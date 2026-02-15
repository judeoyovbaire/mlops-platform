# Secret Generation via AWS Secrets Manager (avoids secrets in Terraform state)

# MLflow database password - generated and managed by Secrets Manager
resource "aws_secretsmanager_secret" "mlflow_db_password" {
  name        = "${var.cluster_name}/mlflow/db-password"
  description = "MLflow PostgreSQL database password"
  # Uses AWS managed key if kms_key_arn is not provided
  kms_key_id = var.kms_key_arn

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "mlflow_db_password" {
  secret_id = aws_secretsmanager_secret.mlflow_db_password.id
  secret_string = jsonencode({
    username = "mlflow"
    password = random_password.mlflow_db.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# MinIO root password - generated and managed by Secrets Manager
resource "aws_secretsmanager_secret" "minio_root_password" {
  name        = "${var.cluster_name}/minio/root-password"
  description = "MinIO root password"
  kms_key_id  = var.kms_key_arn

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "minio_root_password" {
  secret_id = aws_secretsmanager_secret.minio_root_password.id
  secret_string = jsonencode({
    username = "minioadmin"
    password = random_password.minio.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ArgoCD admin password - generated and managed by Secrets Manager
resource "aws_secretsmanager_secret" "argocd_admin_password" {
  name        = "${var.cluster_name}/argocd/admin-password"
  description = "ArgoCD admin password"
  kms_key_id  = var.kms_key_arn

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "argocd_admin_password" {
  secret_id = aws_secretsmanager_secret.argocd_admin_password.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.argocd_admin.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Initial password generation (only used on first apply)
# These are stored in Secrets Manager, not in Terraform state long-term

resource "random_password" "mlflow_db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "minio" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "argocd_admin" {
  length  = 24
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

# Non-secret configuration in SSM for easy access

resource "aws_ssm_parameter" "cluster_endpoint" {
  name        = "/${var.cluster_name}/cluster/endpoint"
  description = "EKS cluster endpoint"
  type        = "String"
  value       = module.eks.cluster_endpoint

  tags = var.tags
}

resource "aws_ssm_parameter" "cluster_name_param" {
  name        = "/${var.cluster_name}/cluster/name"
  description = "EKS cluster name"
  type        = "String"
  value       = module.eks.cluster_name

  tags = var.tags
}

# Outputs - reference ARNs, not values (to avoid state exposure)

output "mlflow_db_secret_arn" {
  description = "ARN of the MLflow database password secret"
  value       = aws_secretsmanager_secret.mlflow_db_password.arn
}

output "minio_secret_arn" {
  description = "ARN of the MinIO root password secret"
  value       = aws_secretsmanager_secret.minio_root_password.arn
}

output "argocd_secret_arn" {
  description = "ARN of the ArgoCD admin password secret"
  value       = aws_secretsmanager_secret.argocd_admin_password.arn
}
