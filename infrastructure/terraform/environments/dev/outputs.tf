# Development Environment Outputs

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "mlflow_s3_bucket" {
  description = "S3 bucket for MLflow artifacts"
  value       = module.eks.mlflow_s3_bucket
}

output "mlflow_db_endpoint" {
  description = "RDS endpoint for MLflow"
  value       = module.eks.mlflow_db_endpoint
}

output "mlflow_irsa_role_arn" {
  description = "IAM role ARN for MLflow service account"
  value       = module.eks.mlflow_irsa_role_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.eks.vpc_id
}

# =============================================================================
# SSM Parameter Store - Secret Locations
# =============================================================================

output "ssm_mlflow_db_password" {
  description = "SSM parameter path for MLflow DB password"
  value       = aws_ssm_parameter.mlflow_db_password.name
}

output "ssm_minio_password" {
  description = "SSM parameter path for MinIO root password"
  value       = aws_ssm_parameter.minio_root_password.name
}

output "ssm_argocd_password" {
  description = "SSM parameter path for ArgoCD admin password"
  value       = aws_ssm_parameter.argocd_admin_password.name
}

# =============================================================================
# Access Information
# =============================================================================

output "access_info" {
  description = "Access information for deployed services"
  value       = <<-EOT

  ============================================================
  MLOps Platform - AWS EKS Deployment
  ============================================================

  Configure kubectl:
    ${module.eks.configure_kubectl}

  Services (get ALB URLs after deployment):
    kubectl get ingress -A

  ============================================================
  Secrets (stored in AWS SSM Parameter Store)
  ============================================================

  All secrets are auto-generated and stored securely in SSM.
  Retrieve with:

    # MLflow DB password
    aws ssm get-parameter --name "/${var.cluster_name}/mlflow/db-password" --with-decryption --query 'Parameter.Value' --output text

    # MinIO root password
    aws ssm get-parameter --name "/${var.cluster_name}/minio/root-password" --with-decryption --query 'Parameter.Value' --output text

    # ArgoCD admin password
    aws ssm get-parameter --name "/${var.cluster_name}/argocd/admin-password" --with-decryption --query 'Parameter.Value' --output text

  ============================================================
  Service Details
  ============================================================

  MLflow:
    S3 Bucket: ${module.eks.mlflow_s3_bucket}
    RDS Endpoint: ${module.eks.mlflow_db_endpoint}

  External Secrets:
    ClusterSecretStore: aws-ssm
    Secrets auto-sync from SSM to Kubernetes every 1h

  Verify deployment:
    kubectl get pods -A
    kubectl get externalsecrets -A

  ============================================================
  EOT
}