# =============================================================================
# Production Environment - AWS EKS
# =============================================================================
# High availability configuration with:
# - Multi-AZ EKS cluster
# - Multi-AZ RDS with automated backups
# - Multiple NAT Gateways (one per AZ)
# - Private cluster endpoint (no public access)
# - Enhanced monitoring and logging

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Production backend configuration
  backend "s3" {
    bucket         = "mlops-platform-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "mlops-platform-terraform-locks"
  }
}

# =============================================================================
# Providers
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# Kubernetes provider configured after EKS creation
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# =============================================================================
# EKS Module - Production Configuration
# =============================================================================

module "eks" {
  source = "../../../modules/eks"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.kubernetes_version

  # Production: Private endpoint only
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access

  # VPC Configuration
  vpc_cidr           = var.vpc_cidr
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # Node Groups - Production sizing
  general_node_group  = var.general_node_group
  training_node_group = var.training_node_group
  gpu_node_group      = var.gpu_node_group

  # RDS - Production HA
  rds_instance_class          = var.rds_instance_class
  rds_multi_az                = var.rds_multi_az
  rds_backup_retention_period = var.rds_backup_retention_period
  rds_deletion_protection     = var.rds_deletion_protection

  # Monitoring
  enable_container_insights = var.enable_container_insights
  log_retention_days        = var.log_retention_days

  tags = var.tags
}

# =============================================================================
# Outputs
# =============================================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID for the cluster"
  value       = module.eks.cluster_security_group_id
}

output "rds_endpoint" {
  description = "RDS endpoint for MLflow"
  value       = module.eks.rds_endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket for MLflow artifacts"
  value       = module.eks.s3_bucket_name
}