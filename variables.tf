variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "ecs_cnt_name" {
  type    = string
  default = "april-2-tier-cont"
}

variable "ecs_cont_port" {
  type    = number
  default = 8000
}

variable "app_image" {
  type    = string
  default = "naramnikhil/2tier-app:latest"
}

variable "cluster_name" {
  type    = string
  default = "april-2-tier"
}

variable "ecs_task_def" {
  type    = string
  default = "april-task-def"
}

variable "domain_name" {
  type    = string
  default = "nikhilvasunaram.xyz"
}

variable "ecs_service" {
  type    = string
  default = "april-2-tier-service"
}

variable "alb_apsouth1_zoneid" {
  type    = string
  default = "Z11ORPS3UI2S3F"
}