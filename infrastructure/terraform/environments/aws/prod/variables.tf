# =============================================================================
# Production Environment Variables for AWS EKS
# =============================================================================
# Production-specific configurations with HA and security hardening

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "mlops-platform"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

# =============================================================================
# EKS Configuration - Production
# =============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.31" # Use stable version for production
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
  default     = false # Private-only for production security
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to EKS API endpoint"
  type        = bool
  default     = true
}

# =============================================================================
# Node Group Configuration - Production (HA)
# =============================================================================

variable "general_node_group" {
  description = "General node group configuration"
  type = object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
  })
  default = {
    instance_types = ["m5.xlarge", "m5.2xlarge"] # Larger instances for production
    capacity_type  = "ON_DEMAND"                  # On-demand for stability
    min_size       = 3                            # HA: minimum 3 nodes
    max_size       = 10
    desired_size   = 3
  }
}

variable "training_node_group" {
  description = "Training node group configuration"
  type = object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
  })
  default = {
    instance_types = ["c5.4xlarge", "c5.2xlarge"]
    capacity_type  = "SPOT"
    min_size       = 0
    max_size       = 20
    desired_size   = 0
  }
}

variable "gpu_node_group" {
  description = "GPU node group configuration"
  type = object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
  })
  default = {
    instance_types = ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge"]
    capacity_type  = "SPOT"
    min_size       = 0
    max_size       = 10
    desired_size   = 0
  }
}

# =============================================================================
# Database Configuration - Production (HA)
# =============================================================================

variable "rds_instance_class" {
  description = "RDS instance class for MLflow backend"
  type        = string
  default     = "db.t3.medium" # Larger for production
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS (HA)"
  type        = bool
  default     = true # Enable for production HA
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention in days"
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = true
}

# =============================================================================
# Networking - Production
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16" # Different CIDR from dev
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway (cost optimization)"
  type        = bool
  default     = false # Use one per AZ for HA in production
}

# =============================================================================
# KServe Configuration
# =============================================================================

variable "kserve_ingress_domain" {
  description = "Domain for KServe inference services"
  type        = string
  default     = "inference.mlops.example.com" # Replace with actual domain

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.kserve_ingress_domain))
    error_message = "Domain must be a valid DNS name."
  }
}

# =============================================================================
# Monitoring - Production
# =============================================================================

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "mlops-platform"
    Environment = "prod"
    ManagedBy   = "terraform"
    CostCenter  = "ml-infrastructure"
  }
}

# =============================================================================
# Helm Chart Versions (pinned for production stability)
# =============================================================================

variable "helm_chart_versions" {
  description = "Helm chart versions for production"
  type        = map(string)
  default = {
    argocd              = "7.9.0"
    argo_workflows      = "0.46.1"
    kserve_crd          = "0.16.0"
    kserve              = "0.16.0"
    mlflow              = "1.8.1"
    prometheus_stack    = "72.6.2"
    cert_manager        = "1.19.1"
    external_secrets    = "1.1.1"
    kyverno             = "3.3.4"
    tetragon            = "1.3.0"
    aws_lb_controller   = "1.16.0"
    karpenter           = "1.8.0"
  }
}