# GKE Module Variables
#
# Variables for configuring the GKE cluster and associated resources
# for the MLOps Platform on Google Cloud.

# =============================================================================
# General Configuration
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "mlops-platform-dev"
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "europe-west4"
}

variable "zones" {
  description = "GCP zones for node pools (leave empty for regional cluster)"
  type        = list(string)
  default     = ["europe-west4-a"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.32"

  validation {
    condition     = can(regex("^1\\.(2[8-9]|3[0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be between 1.28 and 1.39."
  }
}

variable "release_channel" {
  description = "GKE release channel (STABLE, REGULAR, RAPID)"
  type        = string
  default     = "STABLE"

  validation {
    condition     = contains(["STABLE", "REGULAR", "RAPID"], var.release_channel)
    error_message = "Release channel must be STABLE, REGULAR, or RAPID."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "mlops-platform"
    environment = "dev"
    managed_by  = "terraform"
  }
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the GKE subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR block for pods"
  type        = string
  default     = "10.16.0.0/14"
}

variable "services_cidr" {
  description = "Secondary CIDR block for services"
  type        = string
  default     = "10.20.0.0/20"
}

variable "master_cidr" {
  description = "CIDR block for the GKE master (private cluster)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "enable_private_nodes" {
  description = "Enable private nodes (no public IPs)"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint (master not accessible from internet)"
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  ]
}

# =============================================================================
# System Node Pool Configuration
# =============================================================================

variable "system_machine_type" {
  description = "Machine type for system node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "system_min_count" {
  description = "Minimum number of system nodes"
  type        = number
  default     = 2
}

variable "system_max_count" {
  description = "Maximum number of system nodes"
  type        = number
  default     = 5
}

variable "system_disk_size_gb" {
  description = "Disk size for system nodes (GB)"
  type        = number
  default     = 100
}

# =============================================================================
# Training Node Pool Configuration
# =============================================================================

variable "training_machine_type" {
  description = "Machine type for training node pool"
  type        = string
  default     = "c2-standard-8"
}

variable "training_min_count" {
  description = "Minimum number of training nodes"
  type        = number
  default     = 0
}

variable "training_max_count" {
  description = "Maximum number of training nodes"
  type        = number
  default     = 10
}

variable "training_disk_size_gb" {
  description = "Disk size for training nodes (GB)"
  type        = number
  default     = 100
}

variable "training_use_spot" {
  description = "Use Spot VMs for training nodes"
  type        = bool
  default     = true
}

# =============================================================================
# GPU Node Pool Configuration
# =============================================================================

variable "gpu_machine_type" {
  description = "Machine type for GPU node pool"
  type        = string
  default     = "n1-standard-8"
}

variable "gpu_accelerator_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_accelerator_count" {
  description = "Number of GPUs per node"
  type        = number
  default     = 1
}

variable "gpu_min_count" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 0
}

variable "gpu_max_count" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 4
}

variable "gpu_disk_size_gb" {
  description = "Disk size for GPU nodes (GB)"
  type        = number
  default     = 200
}

variable "gpu_use_spot" {
  description = "Use Spot VMs for GPU nodes"
  type        = bool
  default     = true
}

# =============================================================================
# Node Auto-provisioning (NAP) Configuration
# =============================================================================

variable "enable_node_autoprovisioning" {
  description = "Enable cluster autoscaler node auto-provisioning"
  type        = bool
  default     = true
}

variable "nap_min_cpu" {
  description = "Minimum CPU cores for NAP"
  type        = number
  default     = 4
}

variable "nap_max_cpu" {
  description = "Maximum CPU cores for NAP"
  type        = number
  default     = 100
}

variable "nap_min_memory_gb" {
  description = "Minimum memory (GB) for NAP"
  type        = number
  default     = 16
}

variable "nap_max_memory_gb" {
  description = "Maximum memory (GB) for NAP"
  type        = number
  default     = 400
}

variable "nap_max_gpus" {
  description = "Maximum number of GPUs for NAP"
  type        = number
  default     = 8
}

# =============================================================================
# Cloud SQL Configuration
# =============================================================================

variable "cloudsql_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "cloudsql_disk_size" {
  description = "Cloud SQL disk size (GB)"
  type        = number
  default     = 20
}

variable "cloudsql_backup_enabled" {
  description = "Enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "cloudsql_high_availability" {
  description = "Enable high availability for Cloud SQL"
  type        = bool
  default     = false
}

variable "cloudsql_database_version" {
  description = "PostgreSQL version for Cloud SQL"
  type        = string
  default     = "POSTGRES_17"
}

# =============================================================================
# Artifact Registry Configuration
# =============================================================================

variable "artifact_registry_format" {
  description = "Artifact Registry format (DOCKER, MAVEN, NPM, etc.)"
  type        = string
  default     = "DOCKER"
}

variable "artifact_registry_immutable_tags" {
  description = "Enable immutable tags for Artifact Registry"
  type        = bool
  default     = false
}
