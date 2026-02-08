# Secret Generation and SSM Parameter Store

# Generate secure random passwords
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

# Store secrets in AWS SSM Parameter Store (SecureString)
resource "aws_ssm_parameter" "mlflow_db_password" {
  name        = "/${var.cluster_name}/mlflow/db-password"
  description = "MLflow PostgreSQL database password"
  type        = "SecureString"
  value       = random_password.mlflow_db.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

resource "aws_ssm_parameter" "minio_root_password" {
  name        = "/${var.cluster_name}/minio/root-password"
  description = "MinIO root password"
  type        = "SecureString"
  value       = random_password.minio.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

resource "aws_ssm_parameter" "argocd_admin_password" {
  name        = "/${var.cluster_name}/argocd/admin-password"
  description = "ArgoCD admin password"
  type        = "SecureString"
  value       = random_password.argocd_admin.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

# Store non-secret configuration in SSM for easy access
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
