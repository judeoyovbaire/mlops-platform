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