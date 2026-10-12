### CREATE ALB ####

resource "aws_alb" "april_alb" {
  name                       = "april-alb"
  internal                   = false
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  enable_deletion_protection = false

  tags = {
    Name = "april-alb"
  }
}

#### ALB TARGET GROUP ####
resource "aws_alb_target_group" "april_alb_tg" {
  name        = "april-alb-tg"
  port        = var.ecs_cont_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.april_vpc.id
  target_type = "ip"

  health_check {
    timeout  = 5
    interval = 30
    path     = "/login" # FIX: "/" returns 302, so use /login which returns 200
    matcher  = "200"
  }

  tags = {
    Name = "april-alb-tg"
  }
}

### HTTP listener (port 80)
resource "aws_alb_listener" "name" {
  load_balancer_arn = aws_alb.april_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.april_alb_tg.arn
  }
}

### HTTPS listener (port 443)
# FIX: uses the ONE certificate defined in route53.tf, and waits until it is validated
resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.april_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.april_cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.april_alb_tg.arn
  }
}

# FIX: the second certificate (april_cert) was removed from this file.
# The only certificate now lives in route53.tf
