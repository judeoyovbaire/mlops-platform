# EKS Module Outputs

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the cluster"
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

# VPC outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

# MLflow outputs
output "mlflow_s3_bucket" {
  description = "S3 bucket for MLflow artifacts"
  value       = aws_s3_bucket.mlflow_artifacts.id
}

output "mlflow_irsa_role_arn" {
  description = "IAM role ARN for MLflow IRSA"
  value       = module.mlflow_irsa.arn
}

output "aws_lb_controller_irsa_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller IRSA"
  value       = module.aws_lb_controller_irsa.arn
}

output "mlflow_db_endpoint" {
  description = "Endpoint for MLflow RDS database"
  value       = aws_db_instance.mlflow.endpoint
}

output "mlflow_db_name" {
  description = "Database name for MLflow"
  value       = aws_db_instance.mlflow.db_name
}

# Kubeconfig command
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks.cluster_name}"
}

# Karpenter outputs
output "karpenter_irsa_role_arn" {
  description = "IAM role ARN for Karpenter IRSA"
  value       = module.karpenter_irsa.arn
}

output "karpenter_node_role_name" {
  description = "IAM role name for Karpenter nodes"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name for Karpenter nodes"
  value       = aws_iam_instance_profile.karpenter_node.name
}

# ECR outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository for ML model images"
  value       = aws_ecr_repository.models.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository for ML model images"
  value       = aws_ecr_repository.models.arn
}