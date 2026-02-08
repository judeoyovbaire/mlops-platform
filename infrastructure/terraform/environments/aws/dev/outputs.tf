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

output "ecr_repository_url" {
  description = "ECR repository URL for ML model images"
  value       = module.eks.ecr_repository_url
}

output "karpenter_irsa_role_arn" {
  description = "IAM role ARN for Karpenter controller"
  value       = module.eks.karpenter_irsa_role_arn
}

output "private_subnet_ids" {
  description = "Private subnet IDs for workload deployment"
  value       = module.eks.private_subnets
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA configuration"
  value       = module.eks.oidc_provider_arn
}

# AWS Secrets Manager - Secret Locations

output "secrets_manager_mlflow_db" {
  description = "Secrets Manager ARN for MLflow DB credentials"
  value       = aws_secretsmanager_secret.mlflow_db_password.arn
}

output "secrets_manager_minio" {
  description = "Secrets Manager ARN for MinIO root credentials"
  value       = aws_secretsmanager_secret.minio_root_password.arn
}

output "secrets_manager_argocd" {
  description = "Secrets Manager ARN for ArgoCD admin credentials"
  value       = aws_secretsmanager_secret.argocd_admin_password.arn
}

# Access Information

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
  Secrets (stored in AWS Secrets Manager)
  ============================================================

  All secrets are auto-generated and stored securely in Secrets Manager.
  Retrieve with:

    # MLflow DB credentials
    aws secretsmanager get-secret-value --secret-id "${var.cluster_name}/mlflow/db-password" --query 'SecretString' --output text | jq .

    # MinIO root credentials
    aws secretsmanager get-secret-value --secret-id "${var.cluster_name}/minio/root-password" --query 'SecretString' --output text | jq .

    # ArgoCD admin credentials
    aws secretsmanager get-secret-value --secret-id "${var.cluster_name}/argocd/admin-password" --query 'SecretString' --output text | jq .

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