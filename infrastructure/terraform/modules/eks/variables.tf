# EKS Module Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
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
}

variable "mlflow_db_password" {
  description = "Password for MLflow database"
  type        = string
  sensitive   = true
}

# Cluster access
variable "cluster_admin_arns" {
  description = "List of IAM ARNs to grant cluster admin access"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}