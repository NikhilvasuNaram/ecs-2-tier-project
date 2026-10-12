#### ECS CLUSTER ####

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.cluster_name
}

### ECS TASK DEFINITION ####
resource "aws_ecs_task_definition" "service" {
  family                   = "2tier-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  container_definitions = jsonencode([
    {
      name      = var.ecs_cnt_name
      image     = "${data.aws_ecr_repository.ecr_repo.repository_url}:latest"
      essential = true
      environment = [
        {
          name  = "DB_LINK"
          value = aws_secretsmanager_secret_version.rds_password.secret_string
        }
      ]
      portMappings = [
        {
          containerPort = var.ecs_cont_port
          hostPort      = var.ecs_cont_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          # FIX: use the log group that Terraform actually creates
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
}


# ecs service
resource "aws_ecs_service" "app_service" {
  name            = var.ecs_service
  cluster         = aws_ecs_cluster.ecs_cluster.id
  desired_count   = 2
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.service.arn

  load_balancer {
    target_group_arn = aws_alb_target_group.april_alb_tg.arn
    container_name   = var.ecs_cnt_name
    container_port   = var.ecs_cont_port
  }

  network_configuration {
    subnets          = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  depends_on = [aws_alb_listener.http]
}

resource "aws_appautoscaling_target" "ecs_scaling_target" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.app_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "cpu-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 50.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "memory-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
