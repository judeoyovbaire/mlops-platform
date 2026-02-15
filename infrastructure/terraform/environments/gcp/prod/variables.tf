# Production Environment Variables - GCP

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "mlops-platform-prod-001"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "mlops-platform-prod"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west4"
}

variable "zones" {
  description = "GCP zones for node pools (multi-zone for HA)"
  type        = list(string)
  default     = ["europe-west4-a", "europe-west4-b", "europe-west4-c"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for GKE"
  type        = string
  default     = "1.33"
}

variable "release_channel" {
  description = "GKE release channel"
  type        = string
  default     = "STABLE"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "prod"
    project     = "mlops-platform"
    managed_by  = "terraform"
    criticality = "high"
    cost_center = "ml-infrastructure"
  }
}

# Networking

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.100.0.0/16" # Different from dev
}

variable "subnet_cidr" {
  description = "CIDR block for the GKE subnet"
  type        = string
  default     = "10.100.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR block for pods"
  type        = string
  default     = "10.116.0.0/14"
}

variable "services_cidr" {
  description = "Secondary CIDR block for services"
  type        = string
  default     = "10.120.0.0/20"
}

variable "master_cidr" {
  description = "CIDR block for the GKE master"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the GKE master API server"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "10.100.0.0/8"
      display_name = "Internal networks"
    }
  ]
}

# Node Pools - Production Sizing

variable "system_machine_type" {
  description = "Machine type for system node pool"
  type        = string
  default     = "e2-standard-8" # Larger for production
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

variable "training_machine_type" {
  description = "Machine type for training node pool"
  type        = string
  default     = "c2-standard-16" # Larger for production workloads
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

variable "training_use_spot" {
  description = "Use Spot VMs for training node pool"
  type        = bool
  default     = false # Production: ON_DEMAND for reliability
}

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
  description = "Use Spot VMs for GPU node pool"
  type        = bool
  default     = false # Production: ON_DEMAND for reliability
}

# Cloud SQL - Production Grade

variable "cloudsql_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-4-16384" # 4 vCPU, 16GB RAM for production
}

variable "cloudsql_disk_size" {
  description = "Cloud SQL disk size (GB)"
  type        = number
  default     = 100 # 100GB for production
}

variable "cloudsql_backup_enabled" {
  description = "Enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "cloudsql_high_availability" {
  description = "Enable high availability for Cloud SQL"
  type        = bool
  default     = true # Regional HA for production
}

# Helm Chart Versions (Pinned for production stability)

variable "helm_nginx_ingress_version" {
  description = "NGINX Ingress Controller Helm chart version"
  type        = string
  default     = "4.14.3"
}

variable "helm_cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.19.3"
}

variable "helm_argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.4.2"
}

variable "helm_kserve_version" {
  description = "KServe Helm chart version"
  type        = string
  default     = "v0.16.0"
}

variable "helm_mlflow_version" {
  description = "MLflow Helm chart version"
  type        = string
  default     = "1.8.1"
}

variable "helm_argo_workflows_version" {
  description = "Argo Workflows Helm chart version"
  type        = string
  default     = "0.47.3"
}

variable "helm_minio_version" {
  description = "MinIO Helm chart version"
  type        = string
  default     = "5.4.0"
}

variable "helm_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "81.6.9"
}

variable "helm_kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string
  default     = "3.6.2"
}

variable "helm_tetragon_version" {
  description = "Tetragon Helm chart version"
  type        = string
  default     = "1.6.0"
}

variable "helm_external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "1.2.1"
}

variable "helm_loki_version" {
  description = "Loki Helm chart version"
  type        = string
  default     = "6.24.0"
}

variable "helm_tempo_version" {
  description = "Tempo Helm chart version"
  type        = string
  default     = "1.15.0"
}

variable "helm_otel_collector_version" {
  description = "OpenTelemetry Collector Helm chart version"
  type        = string
  default     = "0.108.0"
}

variable "helm_alloy_version" {
  description = "Grafana Alloy Helm chart version"
  type        = string
  default     = "0.12.0"
}
