# ---------------------------------
# AWS ECR Repository
# ---------------------------------

resource "aws_ecr_repository" "hydroserver" {
  name                 = "hs-${var.environment}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_lifecycle_policy" "hydroserver" {
  repository = aws_ecr_repository.hydroserver.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the 10 most recent tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "null_resource" "ghcr_to_ecr" {
  depends_on = [aws_ecr_repository.hydroserver]

  triggers = {
    hydroserver_version = var.hydroserver_version
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      set -euo pipefail

      REGION="${var.aws_region}"
      REPO="${aws_ecr_repository.hydroserver.repository_url}"
      HS_VERSION=${var.hydroserver_version}
      GHCR_IMAGE="ghcr.io/hydroserver2/hydroserver:${var.hydroserver_version}"

      # ECR Authentication
      aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$${REPO%%/*}"

      # Mirror HydroServer GHCR image to ECR
      docker pull --platform linux/amd64 $GHCR_IMAGE
      docker tag $GHCR_IMAGE $REPO:$HS_VERSION
      docker push $REPO:$HS_VERSION
    EOT
  }
}
