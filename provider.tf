provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = "test"
      Terraform   = "true"
      repo        = "lvngdevops/2tier"
    }
  }
}