# EKS Module Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.(2[89]|3[0-4])$", var.cluster_version))
    error_message = "Cluster version must be a supported EKS version (1.28-1.34)."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint. Set to false for production environments with VPN/bastion access."
  type        = bool
  default     = false # Secure by default - enable only if needed
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the EKS public endpoint. Only used when cluster_endpoint_public_access is true. Restrict to your organization's IP ranges."
  type        = list(string)
  default     = [] # Empty by default - must be explicitly configured if public access is enabled
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "enable_kms_encryption" {
  description = "Enable customer-managed KMS encryption for S3, RDS, and SSM"
  type        = bool
  default     = true
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for cost savings"
  type        = bool
  default     = true
}

# General node group
variable "general_instance_types" {
  description = "Instance types for general node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "general_min_size" {
  description = "Minimum size of general node group"
  type        = number
  default     = 2
}

variable "general_max_size" {
  description = "Maximum size of general node group"
  type        = number
  default     = 5
}

variable "general_desired_size" {
  description = "Desired size of general node group"
  type        = number
  default     = 2
}

# Training node group
variable "training_instance_types" {
  description = "Instance types for training node group"
  type        = list(string)
  default     = ["c5.2xlarge"]
}

variable "training_capacity_type" {
  description = "Capacity type for training nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "SPOT"
}

variable "training_min_size" {
  description = "Minimum size of training node group"
  type        = number
  default     = 0
}

variable "training_max_size" {
  description = "Maximum size of training node group"
  type        = number
  default     = 10
}

variable "training_desired_size" {
  description = "Desired size of training node group"
  type        = number
  default     = 0
}

variable "training_taints" {
  description = "Taints for training node group"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = [
    {
      key    = "workload"
      value  = "training"
      effect = "NO_SCHEDULE"
    }
  ]
}

# GPU node group
variable "gpu_instance_types" {
  description = "Instance types for GPU node group"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_capacity_type" {
  description = "Capacity type for GPU nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "SPOT"
}

variable "gpu_min_size" {
  description = "Minimum size of GPU node group"
  type        = number
  default     = 0
}

variable "gpu_max_size" {
  description = "Maximum size of GPU node group"
  type        = number
  default     = 4
}

variable "gpu_desired_size" {
  description = "Desired size of GPU node group"
  type        = number
  default     = 0
}

# MLflow database
variable "mlflow_db_instance_class" {
  description = "Instance class for MLflow RDS"
  type        = string
  default     = "db.t3.small"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.mlflow_db_instance_class))
    error_message = "Must be a valid RDS instance class (e.g., db.t3.small, db.r5.large)."
  }
}

variable "mlflow_db_password" {
  description = "Password for MLflow database"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.mlflow_db_password) >= 16
    error_message = "Database password must be at least 16 characters long for security."
  }
}

variable "mlflow_db_allocated_storage" {
  description = "Allocated storage for MLflow RDS in GB"
  type        = number
  default     = 20
}

variable "mlflow_db_max_allocated_storage" {
  description = "Maximum allocated storage for MLflow RDS autoscaling in GB"
  type        = number
  default     = 100
}

variable "mlflow_db_engine_version" {
  description = "PostgreSQL engine version for MLflow RDS"
  type        = string
  default     = "15"
}

variable "mlflow_db_skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS (set to false for production)"
  type        = bool
  default     = true
}

variable "mlflow_db_backup_retention_period" {
  description = "Number of days to retain automated backups (0 to disable, 7+ recommended for production)"
  type        = number
  default     = 7

  validation {
    condition     = var.mlflow_db_backup_retention_period >= 0 && var.mlflow_db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "mlflow_db_deletion_protection" {
  description = "Enable deletion protection for RDS (recommended for production)"
  type        = bool
  default     = false
}

variable "mlflow_db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS high availability"
  type        = bool
  default     = false
}

# Cluster access
variable "cluster_admin_arns" {
  description = "List of IAM ARNs to grant cluster admin access"
  type        = list(string)
  default     = []
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable cluster admin permissions for the identity that creates the cluster"
  type        = bool
  default     = true
}

# AWS Backup
variable "enable_aws_backup" {
  description = "Enable AWS Backup for RDS and other resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups in AWS Backup"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# VPC Flow Logs
variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network troubleshooting"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC Flow Logs in CloudWatch"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention days must be a valid CloudWatch Logs retention value."
  }
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}