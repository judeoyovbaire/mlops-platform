# Production Environment Variables - Azure

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "mlops-platform-prod"
}

variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "northeurope"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.34.0"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "prod"
    Project     = "mlops-platform"
    ManagedBy   = "terraform"
    Criticality = "high"
    CostCenter  = "ml-infrastructure"
  }
}

# Networking

variable "vnet_cidr" {
  description = "CIDR block for the virtual network"
  type        = string
  default     = "10.101.0.0/16" # Different from dev
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS subnet"
  type        = string
  default     = "10.101.0.0/18"
}

variable "postgresql_subnet_cidr" {
  description = "CIDR block for the PostgreSQL subnet"
  type        = string
  default     = "10.101.64.0/24"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.102.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.102.0.10"
}

# API Server Access Control

variable "api_server_authorized_ip_ranges" {
  description = "CIDR blocks authorized to access AKS API server (set for production)"
  type        = list(string)
  # SECURITY: Set to your organization's CIDR ranges before production deployment.
  # Example: ["203.0.113.0/24", "198.51.100.0/24"]
  # An empty list allows unrestricted access to the API server.
  default = []
}

# Node Pools - Production Sizing

variable "system_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D4s_v3" # Larger for production
}

variable "system_min_count" {
  description = "Minimum number of nodes in system pool"
  type        = number
  default     = 3 # Minimum 3 for HA
}

variable "system_max_count" {
  description = "Maximum number of nodes in system pool"
  type        = number
  default     = 10
}

variable "training_vm_size" {
  description = "VM size for training node pool"
  type        = string
  default     = "Standard_D16s_v3" # Larger for production
}

variable "training_min_count" {
  description = "Minimum number of nodes in training pool"
  type        = number
  default     = 0
}

variable "training_max_count" {
  description = "Maximum number of nodes in training pool"
  type        = number
  default     = 20
}

variable "gpu_vm_size" {
  description = "VM size for GPU node pool"
  type        = string
  default     = "Standard_NC6s_v3"
}

variable "gpu_min_count" {
  description = "Minimum number of nodes in GPU pool"
  type        = number
  default     = 0
}

variable "gpu_max_count" {
  description = "Maximum number of nodes in GPU pool"
  type        = number
  default     = 10
}

variable "gpu_use_spot" {
  description = "Use Spot instances for GPU node pool"
  type        = bool
  default     = false # Production: ON_DEMAND for reliability
}

# PostgreSQL - Production Grade

variable "postgresql_sku" {
  description = "SKU for PostgreSQL Flexible Server"
  type        = string
  default     = "GP_Standard_D4s_v3" # General Purpose for production
}

variable "postgresql_storage_mb" {
  description = "Storage size for PostgreSQL in MB"
  type        = number
  default     = 131072 # 128GB for production
}

variable "postgresql_backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 35 # Maximum retention
}

variable "postgresql_ha_enabled" {
  description = "Enable high availability for PostgreSQL"
  type        = bool
  default     = true # Zone-redundant HA for production
}

# Container Registry

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Premium" # Premium for geo-replication and private endpoints
}

# Monitoring

variable "enable_azure_monitor" {
  description = "Enable Azure Monitor integration"
  type        = bool
  default     = true # Enabled for production
}

# Helm Chart Versions (common defaults in helm-versions.auto.tfvars)
# Cloud-specific versions below; shared versions via symlinked auto.tfvars

variable "helm_nginx_ingress_version" {
  description = "NGINX Ingress Controller Helm chart version"
  type        = string
  default     = "4.14.3"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_nginx_ingress_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_cert_manager_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_argocd_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_kserve_version" {
  description = "KServe Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_kserve_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_mlflow_version" {
  description = "MLflow Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_mlflow_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_argo_workflows_version" {
  description = "Argo Workflows Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_argo_workflows_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_minio_version" {
  description = "MinIO Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_minio_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_prometheus_stack_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_keda_version" {
  description = "KEDA Helm chart version"
  type        = string
  default     = "2.19.0"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_keda_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_kyverno_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_tetragon_version" {
  description = "Tetragon Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_tetragon_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_external_secrets_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_loki_version" {
  description = "Loki Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_loki_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_tempo_version" {
  description = "Tempo Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_tempo_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_otel_collector_version" {
  description = "OpenTelemetry Collector Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_otel_collector_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_alloy_version" {
  description = "Grafana Alloy Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_alloy_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

# Slack Notifications

variable "slack_notifications_enabled" {
  description = "Enable Slack notifications for AlertManager"
  type        = bool
  default     = false
}

variable "slack_channel" {
  description = "Slack channel for AlertManager notifications"
  type        = string
  default     = "#mlops-alerts"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL (stored in cloud secret manager, not in Terraform state)"
  type        = string
  default     = ""
  sensitive   = true
}

# Progressive Delivery & Observability (shared across dev/prod)

variable "helm_argo_rollouts_version" {
  description = "Argo Rollouts Helm chart version"
  type        = string
  default     = "2.39.1"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_argo_rollouts_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_argo_events_version" {
  description = "Argo Events Helm chart version"
  type        = string
  default     = "2.4.14"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_argo_events_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_opencost_version" {
  description = "OpenCost Helm chart version"
  type        = string
  default     = "1.44.0"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_opencost_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}

variable "helm_dcgm_exporter_version" {
  description = "NVIDIA DCGM Exporter Helm chart version"
  type        = string
  default     = "3.6.1"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_dcgm_exporter_version))
    error_message = "Must be a valid semver version, optionally v-prefixed (e.g., 1.2.3 or v1.2.3)."
  }
}
