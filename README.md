# ecs-2-tier-project
using aws services through terraform we are going to deploy a simple 2-tier app on ecs


# 2-Tier Web App on AWS (ECS Fargate + RDS) with Terraform

A Flask web application running as containers on **AWS ECS Fargate**, served over **HTTPS** through an **Application Load Balancer**, backed by a **PostgreSQL RDS** database, on a custom domain. All AWS infrastructure is defined with **Terraform**.

> **Who this is for:** engineers new to the project. After reading this file you should understand what is deployed, how a request flows through it, how to deploy it yourself, and where to look when something breaks.

---

## Table of contents

1. [What this project does](#1-what-this-project-does)
2. [Architecture](#2-architecture)
3. [How a request flows](#3-how-a-request-flows)
4. [Components explained](#4-components-explained)
5. [Repository layout](#5-repository-layout)
6. [Prerequisites](#6-prerequisites)
7. [Deploy from scratch](#7-deploy-from-scratch)
8. [Configuration (variables)](#8-configuration-variables)
9. [Run the app locally](#9-run-the-app-locally)
10. [Day-2 operations](#10-day-2-operations)
11. [Troubleshooting](#11-troubleshooting)
12. [Cost and cleanup](#12-cost-and-cleanup)
13. [Known limitations and roadmap](#13-known-limitations-and-roadmap)

---

## 1. What this project does

- Runs a **Flask** app (served by **gunicorn** on port `8000`) with a login page backed by a PostgreSQL database.
- Packages the app as a **Docker image** and stores it in **Amazon ECR**.
- Runs **2 to 4 copies** (tasks) of the container on **ECS Fargate**, so there are no servers to manage. It scales automatically with CPU and memory use.
- Exposes the app on **`https://<your-domain>`** using an **ALB** with a free **ACM** certificate and a **Route 53** DNS record.
- Keeps the containers and the database in **private subnets**, so they are not reachable directly from the internet.
- Creates **everything** (network, load balancer, database, DNS, IAM, logs) with **Terraform**, and keeps Terraform state in **S3**.

---

## 2. Architecture

```mermaid
flowchart TB
    U[User / Browser] -->|1. DNS lookup| R53[Route 53 hosted zone]
    GD[GoDaddy domain registrar] -. nameservers point to .-> R53
    U -->|2. HTTPS 443| IGW[Internet Gateway]

    subgraph VPC["VPC 10.0.0.0/16 (ap-south-1)"]
        IGW --> ALB[Application Load Balancer<br/>public subnets]
        NAT[NAT Gateway<br/>public subnet]
        subgraph PRIV["Private subnets"]
            T1[ECS Fargate task<br/>Flask :8000]
            T2[ECS Fargate task<br/>Flask :8000]
        end
        subgraph DB["DB subnets"]
            RDS[(RDS PostgreSQL :5432)]
        end
        ALB -->|3. HTTP 8000| T1
        ALB -->|3. HTTP 8000| T2
        T1 -->|4. SQL| RDS
        T2 -->|4. SQL| RDS
        T1 -. outbound .-> NAT
        T2 -. outbound .-> NAT
    end

    ACM[ACM certificate] -. attached to .-> ALB
    NAT -. pulls image .-> ECR[ECR repository]
    T1 -. logs .-> CW[CloudWatch Logs]
    T2 -. logs .-> CW
    SM[Secrets Manager<br/>DB URL] -. stored by Terraform .- RDS
    S3[(S3 bucket<br/>Terraform state)]
```

---

## 3. How a request flows

1. You type the domain in your browser. **Route 53** answers the DNS query (the domain's nameservers at GoDaddy point to the Route 53 hosted zone). An **A (alias) record** returns the ALB's address.
2. The browser connects to the **ALB** over HTTPS (port 443). The ALB uses the **ACM certificate** to terminate TLS. Port 80 is also open.
3. The ALB forwards the request over plain HTTP to one of the **healthy ECS tasks** on port `8000`. It only sends traffic to tasks that pass the health check (`GET /login` must return `200`).
4. The Flask app handles the request. When it needs data (for example, a login), it connects to **RDS PostgreSQL** using the connection string in the `DB_LINK` environment variable.
5. Container logs go to **CloudWatch Logs**. If the task needs to reach the internet (for example, to pull the image from ECR), it goes out through the **NAT Gateway**.

---

## 4. Components explained

### 4.1 Application (Flask + gunicorn)

| Item | Detail |
|---|---|
| Framework | Flask, Flask-SQLAlchemy, Flask-Login |
| Server | gunicorn, listening on `0.0.0.0:8000` |
| DB driver | `psycopg[binary]` (psycopg v3). It must be in `requirements.txt` or the app fails to boot with `No module named 'psycopg'` |
| Config | `config.py` reads the database URL from the **`DB_LINK`** environment variable |
| Startup | `run.py` calls `db.create_all()`, which creates missing tables. If the DB is unreachable, it logs a warning and the app still starts |
| Health endpoint | `/login` returns `200`. Note that `/` returns `302` (redirect to login), so it is **not** used for health checks |

Important behaviour: `create_all()` creates **tables**, not the **database**. The database `mydb` is created by RDS (see 4.7).

### 4.2 Docker image

The `Dockerfile` builds the app image from `python:3.12-slim`. It installs `requirements.txt`, copies `app/`, `run.py` and `config.py`, and starts gunicorn. A multi-stage version with a non-root user is recommended for production.

### 4.3 Amazon ECR (`ecr.tf`)

The private repository **`lvngdevops/2tier`** stores the image. Terraform does **not** create it. It only looks it up (`data "aws_ecr_repository"`), so **create the repository and push an image before deploying** (see section 7). ECS pulls `<repo-url>:latest`.

### 4.4 Network (`vpc.tf`)

| Resource | CIDR / Detail |
|---|---|
| VPC | `10.0.0.0/16`, DNS support and hostnames enabled |
| Public subnets | `10.0.1.0/24` (AZ a), `10.0.2.0/24` (AZ b). Hold the ALB and the NAT Gateway |
| Private subnets | `10.0.3.0/24`, `10.0.4.0/24`. Hold the ECS tasks |
| DB subnets | `10.0.5.0/24` (AZ a), `10.0.6.0/24` (AZ b). Hold RDS |
| Internet Gateway | Public route table sends `0.0.0.0/0` here |
| NAT Gateway (+ Elastic IP) | Private route table sends `0.0.0.0/0` here, so tasks can pull images and send logs without being public |

### 4.5 Security groups (`sg.tf`)

Traffic is locked down in a chain. Each layer only accepts traffic from the layer before it:

| Security group | Allows inbound | From |
|---|---|---|
| `april-alb-sg` | TCP 80 and 443 | Anywhere (`0.0.0.0/0`) |
| `april-ecs-sg` | TCP 8000 | Only the ALB security group |
| `april-rds-sg` | TCP 5432 | Only the ECS security group |

### 4.6 Application Load Balancer (`alb.tf`)

- Internet-facing ALB in the two public subnets.
- **Target group** (`target_type = "ip"`, port 8000) with health check `GET /login`, expecting `200`, every 30 s.
- **Listeners:** port 80 (HTTP) and port 443 (HTTPS). Both forward to the target group. The HTTPS listener uses the validated ACM certificate.

### 4.7 Database (`rds.tf`)

| Item | Value |
|---|---|
| Engine | PostgreSQL 15, `db.t3.micro`, 20 GB gp2 |
| Database name / user | `mydb` / `postgres` |
| Password | Generated by Terraform (`random_password`, 16 characters). Nobody types it |
| Network | DB subnet group, `publicly_accessible = false`, protected by `april-rds-sg` |
| Secret | The full connection URL (`postgresql://user:pass@host:5432/mydb`) is stored in **Secrets Manager** as `april-rds-password` and passed to the container as `DB_LINK` |

### 4.8 ECS on Fargate (`ecs.tf`)

| Item | Value |
|---|---|
| Cluster | `april-2-tier` |
| Task definition | Fargate, 1 vCPU (1024), 2 GB memory, `awsvpc` networking |
| Container | Image from ECR, port 8000, env var `DB_LINK`, logs to CloudWatch |
| Service | `april-2-tier-service`, desired count 2, in private subnets, no public IP, registered with the ALB target group |
| Autoscaling | Min 2, max 4 tasks. Scales on average CPU (target 50%) and memory (target 70%) |

### 4.9 DNS and HTTPS (`route53.tf`)

- Looks up the **existing** Route 53 hosted zone for your domain.
- Creates an **A (alias) record** pointing the domain to the ALB.
- Requests **one ACM certificate** for the domain with **DNS validation**, creates the validation CNAME record, and then **waits** (`aws_acm_certificate_validation`) until AWS confirms it. The HTTPS listener depends on this.

### 4.10 IAM (`iam.tf`)

The **task execution role** lets ECS itself (not your app code) pull the image from ECR and write to the CloudWatch log group. It has permissions for `ecr:*` pull actions and for `logs:CreateLogStream` / `logs:PutLogEvents` on the log group.

### 4.11 Logging (`cloud-watch.tf`)

Log group `/ecs/<container-name>` with 7-day retention. The task definition **must** reference this exact log group (it uses the Terraform resource, not a typed name).

### 4.12 Terraform state (`version-provider.tf`)

State is stored remotely in the S3 bucket `terraform-state-lvngdevops` (key `april26/ecs/terraform.tfstate`) with encryption and **S3 native locking** (`use_lockfile = true`), so two people cannot apply at once. The Terraform version and provider versions are pinned in the same file.

> **Never commit state files.** `terraform.tfstate` contains secrets (including the DB password) in plain text.

---

## 5. Repository layout

```
.
├── app/                    # Flask application package
├── run.py                  # App entrypoint (gunicorn runs run:app)
├── config.py               # Reads DB_LINK
├── requirements.txt        # Python dependencies (incl. psycopg[binary])
├── Dockerfile              # Container image build
├── .dockerignore
│
├── version-provider.tf     # Terraform + provider versions, S3 backend
├── provider.tf             # AWS provider, region, default tags
├── variables.tf            # Input variables
├── vpc.tf                  # VPC, subnets, route tables, IGW, NAT
├── sg.tf                   # Security groups
├── alb.tf                  # Load balancer, target group, listeners
├── route53.tf              # DNS record, ACM certificate + validation
├── ecr.tf                  # Looks up the existing ECR repository
├── ecs.tf                  # Cluster, task definition, service, autoscaling
├── rds.tf                  # Database, random password, Secrets Manager
├── iam.tf                  # ECS task execution role and policy
├── cloud-watch.tf          # Log group
└── .terraform.lock.hcl     # Provider version lock (commit this)
```

Adjust this tree if your folders differ.

---

## 6. Prerequisites

You need:

- An **AWS account** and credentials configured locally (`aws configure` or SSO) with permission to create the resources above.
- **Terraform** at the version pinned in `version-provider.tf`.
- **AWS CLI v2** and **Docker**.
- A **domain name** you own. Its registrar can be GoDaddy or any other.
- These **pre-existing** resources (Terraform only reads them, it does not create them):
  1. **S3 bucket** for Terraform state (`terraform-state-lvngdevops`, or change the name in `version-provider.tf`).
  2. **Route 53 hosted zone** for your domain, with the registrar's nameservers set to the four NS values of that zone. Without this, certificate validation never completes.
  3. **ECR repository** `lvngdevops/2tier`.

---

## 7. Deploy from scratch

### Step 1: Create the ECR repository (once)

```bash
aws ecr create-repository --repository-name lvngdevops/2tier --region ap-south-1
```

### Step 2: Build and push the image

```bash
ACCOUNT_ID=<your-aws-account-id>
REGION=ap-south-1
REPO=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/lvngdevops/2tier

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
docker build --platform linux/amd64 -t $REPO:latest .
docker push $REPO:latest
```

Confirm the `latest` tag exists:

```bash
aws ecr describe-images --repository-name lvngdevops/2tier --region $REGION
```

### Step 3: Set your domain

In `variables.tf`, set `domain_name` to your domain (or pass `-var domain_name=example.com`).

### Step 4: Apply Terraform

```bash
terraform init
terraform plan
terraform apply
```

The first apply takes several minutes. The ACM certificate validation and the RDS instance are the slowest parts.

### Step 5: Verify

1. **ECS console, cluster `april-2-tier`, service `april-2-tier-service`:** 2 running tasks.
2. **EC2 console, Target Groups, `april-alb-tg`, Targets:** status `healthy`.
3. Open **`https://<your-domain>`**. You should see the login page.

If the tasks started before the image existed, force a new deployment:

```bash
aws ecs update-service --cluster april-2-tier --service april-2-tier-service --force-new-deployment --region ap-south-1
```

---

## 8. Configuration (variables)

Defined in `variables.tf`. Override with `-var` or a `terraform.tfvars` file.

| Variable | Default | Purpose |
|---|---|---|
| `aws_region` | `ap-south-1` | Region for all resources |
| `domain_name` | `nikhilvasunaram.xyz` | Domain served by the ALB (must have a Route 53 hosted zone) |
| `cluster_name` | `april-2-tier` | ECS cluster name |
| `ecs_service` | `april-2-tier-service` | ECS service name |
| `ecs_task_def` | `april-task-def` | Used for IAM role and policy names |
| `ecs_cnt_name` | `april-2-tier-cont` | Container name, also names the log group |
| `ecs_cont_port` | `8000` | Container port and target group port |
| `app_image` | `naramnikhil/2tier-app:latest` | Currently **unused**. The image comes from ECR (`ecr.tf`) |
| `alb_apsouth1_zoneid` | `Z11ORPS3UI2S3F` | Currently unused. The alias record reads the zone ID from the ALB resource |

The `DB_LINK` connection string is **not** a variable. Terraform builds it from the RDS resource and the generated password.

---

## 9. Run the app locally

Without a database (UI loads, login fails):

```bash
docker build -t app:local .
docker run -it --rm -p 8000:8000 app:local
# open http://localhost:8000
```

With a Postgres database:

```bash
docker run -it --rm -p 8000:8000 \
  -e DB_LINK="postgresql+psycopg://user:password@host.docker.internal:5432/mydb" \
  app:local
```

Notes:

- Inside a container, `localhost` means the container itself. Use `host.docker.internal` for a DB on your machine.
- URL-encode special characters in passwords (`@` becomes `%40`).
- The database (`mydb`) must exist. The app creates the tables.

---

## 10. Day-2 operations

| Task | How |
|---|---|
| Release a new app version | Build and push `:latest` to ECR, then run the `update-service --force-new-deployment` command above |
| View application logs | CloudWatch Logs, group `/ecs/april-2-tier-cont` |
| Why did a task stop? | ECS console, service, Tasks tab, Stopped, open the task, read **Stopped reason** |
| Check target health | EC2 console, Target Groups, `april-alb-tg`, Targets |
| Change instance count or scaling | Edit `desired_count` / autoscaling in `ecs.tf`, then `terraform apply` |
| Change infrastructure | Edit the `.tf` files, run `terraform plan`, review, then `terraform apply` |

---

## 11. Troubleshooting

These are the problems hit while building this project, with their fixes.

| Symptom | Cause | Fix |
|---|---|---|
| **503 Service Unavailable** from the domain | ALB has no healthy targets | Check target health and the ECS stopped-task reason (below) |
| Targets all `unhealthy` | Health check expects `200` but the path returns `302` | Health check path must be `/login` (not `/`) |
| Task stops: `AccessDeniedException ... logs:CreateLogStream` | Task logs to a log group that the IAM policy does not allow or that does not exist | Task definition must use `aws_cloudwatch_log_group.ecs_log_group.name` |
| Task stops: `CannotPullContainerError ... :latest: not found` | No `latest` tag in ECR | Push the image (Step 2), then force a new deployment |
| Container exits: `ModuleNotFoundError: No module named 'config'` | `config.py` not copied into the image | Add `COPY config.py .` to the Dockerfile and rebuild |
| Container exits: `No module named 'psycopg'` | Missing Postgres driver | Add `psycopg[binary]` to `requirements.txt` and rebuild |
| Edited Dockerfile but the build ignores it | File not saved, or an old image tag is being run | Save, rebuild with a new tag, and check the build step count |
| HTTPS listener fails / certificate stuck `Pending validation` | Only one certificate should exist, and its DNS validation record must resolve | Use the single certificate in `route53.tf` and confirm registrar nameservers match the Route 53 zone |
| Login returns 500 | App cannot reach the DB | Check `docker logs` or CloudWatch for `OperationalError`, the DB status, and security group rules |
| Warning `DB not available, skipping create_all` | DB unreachable at startup | Expected without a DB. With RDS, wait a few minutes after creation, then restart tasks |

First stop for any outage: **ECS service Events**, the **stopped task reason**, then **CloudWatch logs**.

---

## 12. Cost and cleanup

Some resources bill while they exist, even with no traffic:

- **NAT Gateway** (hourly charge plus data processing)
- **Application Load Balancer** (hourly charge)
- **RDS instance** and its storage
- **ECS Fargate tasks** (per second while running)
- ECR storage (very small for this image)

If this is a learning or test environment, destroy it when you are done:

```bash
terraform destroy
```

Warning: RDS is configured with `skip_final_snapshot = true`, so destroying it **deletes the data with no backup**. The ECR repository, hosted zone and state bucket are not managed by this Terraform, so they stay.

---

## 13. Known limitations and roadmap

Be aware of these before using this for anything beyond testing:

- **DB URL in plain environment variable.** The connection string, including the password, is injected as a normal env var in the task definition. Anyone who can view the task definition or Terraform state can read it. Planned fix: use the task definition `secrets` block to pull from Secrets Manager (requires adding `secretsmanager:GetSecretValue` to the execution role).
- **Both private subnets are in AZ `a`.** The tasks are not spread across two availability zones. Change `private_subnet_2` to use AZ `b`.
- **Single NAT Gateway** (in one AZ) and **single-AZ RDS**. This is a cost trade-off, and it is a single point of failure.
- **`:latest` image tag.** Deployments are not tied to a specific version. Use immutable tags (for example the git commit SHA).
- **HTTP is not redirected to HTTPS.** Port 80 forwards to the app directly.
- **No CI/CD.** Image build, push and deployment are manual.
- **Unused variables** (`app_image`, `alb_apsouth1_zoneid`) can be removed.
- **Terraform state contains secrets.** Keep the S3 bucket private and encrypted, and never commit local state files.

Ideas for next steps: GitHub Actions pipeline (build, push, deploy), HTTP to HTTPS redirect, ECS `secrets` for the DB URL, Multi-AZ RDS, CloudWatch alarms, and a WAF in front of the ALB.

---

## Maintainer notes

- Default resource tags: `Environment = test`, `Terraform = true`, `repo = lvngdevops/2tier`.
- Commit `.terraform.lock.hcl`. Do **not** commit `.terraform/` or any `*.tfstate*` files. Suggested `.gitignore`:

```
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
.env
```
