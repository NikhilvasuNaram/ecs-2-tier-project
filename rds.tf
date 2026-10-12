
#### random password for rds instance
resource "random_password" "rand_pass" {
  length           = 16
  special          = true
  override_special = "sdpcjiqewoudcyqe2389r732r19ehudwidck"
}

### RDS SUBNET GROUP ####
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db subnet group"
  subnet_ids = [aws_subnet.rds_subnet_1.id, aws_subnet.rds_subnet_2.id]
  tags = {
    Name = "My DB subnet group"
  }
}

### RDS INSTANCE ####
resource "aws_db_instance" "rds_instance" {
  identifier              = "mydb-instance"
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t3.micro"
  port                    = 5432
  db_name                 = "mydb"
  username                = "postgres"
  password                = random_password.rand_pass.result
  parameter_group_name    = "default.postgres15"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  backup_retention_period = 1
  tags = {
    Name = "mydb-instance"
  }
}

### rds secret manager
resource "aws_secretsmanager_secret" "rds_password" {
  name        = "april-rds-password"
  description = "Password for rds instance"
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  # secret_string = random_password.rand_pass.result
  # secret_string = "postgresql://${aws_db_instance.rds_instance.username}:${random_password.rds_password.result}@${aws_db_instance.rds_instance.address}:${aws_db_instance.rds_instance.port}/${aws_db_instance.rds_instance.db_name}"
  secret_string = "postgresql://${aws_db_instance.rds_instance.username}:${random_password.rand_pass.result}@${aws_db_instance.rds_instance.address}:${aws_db_instance.rds_instance.port}/${aws_db_instance.rds_instance.db_name}"
}