# ECR Repository for ML Model Images

resource "aws_ecr_repository" "models" {
  name                 = "${var.cluster_name}/models"
  image_tag_mutability = "IMMUTABLE" # Prevent tag overwriting for security and traceability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.enable_kms_encryption ? "KMS" : "AES256"
    kms_key         = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null
  }

  tags = var.tags
}

# Lifecycle policy to clean up old images
resource "aws_ecr_lifecycle_policy" "models" {
  repository = aws_ecr_repository.models.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
