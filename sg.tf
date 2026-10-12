### ALB SECURITY GROUP
resource "aws_security_group" "alb_sg" {
  name        = "april-alb-sg"
  description = "Security group for alb subnet"
  vpc_id      = aws_vpc.april_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-alb-sg"
  }
}


#### ECS SECURITY GROUP

resource "aws_security_group" "ecs_sg" {
  name        = "april-ecs-sg"
  description = "Security group for ecs pvt subnets"
  vpc_id      = aws_vpc.april_vpc.id

  ingress {
    from_port = 8000
    to_port   = 8000
    protocol  = "tcp"
    # cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-ecs-sg"
  }
}




#### RDS SECURITY GROUP
resource "aws_security_group" "rds_sg" {
  name        = "april-rds-sg"
  description = "Security group for rds subnets"
  vpc_id      = aws_vpc.april_vpc.id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    # cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-rds-sg"
  }
}