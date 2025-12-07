# Development Environment Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "mlops-platform-dev"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# Note: Database passwords are now auto-generated and stored in AWS SSM Parameter Store
# See main.tf for:
#   - random_password resources (auto-generation)
#   - aws_ssm_parameter resources (secure storage)
#   - External Secrets Operator (K8s sync)
#
# To retrieve passwords after deployment:
#   aws ssm get-parameter --name "/${cluster_name}/mlflow/db-password" --with-decryption
#   aws ssm get-parameter --name "/${cluster_name}/kubeflow/db-password" --with-decryption
#   aws ssm get-parameter --name "/${cluster_name}/minio/root-password" --with-decryption

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "mlops-platform"
  }
}