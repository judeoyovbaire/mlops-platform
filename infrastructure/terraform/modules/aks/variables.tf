# =============================================================================
# AKS Module Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.29"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vnet_cidr" {
  description = "CIDR block for the virtual network"
  type        = string
  default     = "10.1.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS subnet"
  type        = string
  default     = "10.1.0.0/18" # ~16,000 IPs for nodes and pods
}

variable "postgresql_subnet_cidr" {
  description = "CIDR block for the PostgreSQL subnet"
  type        = string
  default     = "10.1.64.0/24"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.2.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.2.0.10"
}

# -----------------------------------------------------------------------------
# API Server Access Control
# -----------------------------------------------------------------------------

variable "api_server_authorized_ip_ranges" {
  description = "List of CIDR blocks authorized to access the AKS API server. Use your organization's IP ranges for security."
  type        = list(string)
  default     = [] # Empty list allows all IPs - set specific CIDRs in production!

  validation {
    condition     = alltrue([for cidr in var.api_server_authorized_ip_ranges : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid CIDR blocks (e.g., 203.0.113.0/24)."
  }
}

variable "keyvault_allowed_ip_ranges" {
  description = "List of IP addresses/CIDR blocks allowed to access Key Vault (for management access)"
  type        = list(string)
  default     = [] # Empty by default - access restricted to VNet and Azure services
}

# -----------------------------------------------------------------------------
# System Node Pool
# -----------------------------------------------------------------------------

variable "system_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D2s_v3" # 2 vCPUs - fits free tier quota
}

variable "system_min_count" {
  description = "Minimum number of nodes in system pool"
  type        = number
  default     = 2
}

variable "system_max_count" {
  description = "Maximum number of nodes in system pool"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# Training Node Pool
# -----------------------------------------------------------------------------

variable "training_vm_size" {
  description = "VM size for training node pool"
  type        = string
  default     = "Standard_D8s_v3"
}

variable "training_min_count" {
  description = "Minimum number of nodes in training pool"
  type        = number
  default     = 0
}

variable "training_max_count" {
  description = "Maximum number of nodes in training pool"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# GPU Node Pool
# -----------------------------------------------------------------------------

variable "gpu_vm_size" {
  description = "VM size for GPU node pool"
  type        = string
  default     = "Standard_NC6s_v3" # 1x V100 GPU
}

variable "gpu_min_count" {
  description = "Minimum number of nodes in GPU pool"
  type        = number
  default     = 0
}

variable "gpu_max_count" {
  description = "Maximum number of nodes in GPU pool"
  type        = number
  default     = 4
}

variable "gpu_use_spot" {
  description = "Use Spot instances for GPU node pool"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# PostgreSQL
# -----------------------------------------------------------------------------

variable "postgresql_sku" {
  description = "SKU for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms" # Burstable, 1 vCore (dev)
}

variable "postgresql_storage_mb" {
  description = "Storage size for PostgreSQL in MB"
  type        = number
  default     = 32768 # 32 GB
}

variable "postgresql_backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "postgresql_ha_enabled" {
  description = "Enable high availability for PostgreSQL"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Container Registry
# -----------------------------------------------------------------------------

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
}

variable "acr_georeplications" {
  description = "List of regions for ACR geo-replication (Premium SKU only)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

variable "enable_azure_monitor" {
  description = "Enable Azure Monitor integration"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics Workspace"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

# -----------------------------------------------------------------------------
# NSG Flow Logs
# -----------------------------------------------------------------------------

variable "enable_nsg_flow_logs" {
  description = "Enable NSG Flow Logs for network troubleshooting"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain NSG Flow Logs"
  type        = number
  default     = 30

  validation {
    condition     = var.flow_logs_retention_days >= 1 && var.flow_logs_retention_days <= 365
    error_message = "Flow logs retention days must be between 1 and 365."
  }
}

variable "enable_traffic_analytics" {
  description = "Enable Traffic Analytics for NSG Flow Logs"
  type        = bool
  default     = true
}
