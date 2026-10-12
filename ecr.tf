# ### ECR REPOSITORY ####
# resource "aws_ecr_repository" "lvngdevops" {
#   name                 = "lvngdevops/2tier"
#   image_tag_mutability = "MUTABLE"

#   #   image_scanning_configuration {
#   #     scan_on_push = true
#   #   }
# }


data "aws_ecr_repository" "ecr_repo" {
  name = "lvngdevops/2tier"
}