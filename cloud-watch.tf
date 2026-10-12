### cloud watch log group
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${var.ecs_cnt_name}"
  retention_in_days = 7
  tags = {
    Name = "/ecs/${var.ecs_cnt_name}"
  }
}