# Development Environment Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "mlops-platform-dev"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
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

# Note: Database passwords are now auto-generated and stored in AWS Secrets Manager
# See secrets.tf for:
#   - aws_secretsmanager_secret resources (secure storage, not in Terraform state)
#   - External Secrets Operator (K8s sync)
#
# To retrieve passwords after deployment:
#   aws secretsmanager get-secret-value --secret-id "${cluster_name}/mlflow/db-password"
#   aws secretsmanager get-secret-value --secret-id "${cluster_name}/minio/root-password"
#   aws secretsmanager get-secret-value --secret-id "${cluster_name}/argocd/admin-password"

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting secrets. If not provided, uses AWS managed key."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "mlops-platform"
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS ingress. Empty string disables HTTPS redirect."
  type        = string
  default     = ""
}

variable "kserve_ingress_domain" {
  description = "Domain for KServe inference services ingress"
  type        = string
  default     = "inference.mlops.local"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.kserve_ingress_domain))
    error_message = "Domain must be a valid DNS name."
  }
}

# Helm Chart Versions (common defaults in helm-versions.auto.tfvars)
# Cloud-specific versions below; shared versions via symlinked auto.tfvars

variable "helm_aws_lb_controller_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.17.1"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_aws_lb_controller_version))
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
  description = "KServe Helm chart version (CRD and controller)"
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

variable "helm_karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.3"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_karpenter_version))
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

variable "helm_kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_kyverno_version))
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

# -----------------------------------------------------------------------------
# Cluster API Access Control
# -----------------------------------------------------------------------------

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint. Required for CI/CD access from GitHub Actions."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS API public endpoint. Restrict to your organization's IP ranges for production-grade security."
  type        = list(string)
  # Dev default is open: the API server still requires IAM auth + RBAC, and
  # CI (kubectl from GitHub-hosted runners) needs endpoint access from
  # ever-changing runner IPs. Note AWS rejects RFC 1918 ranges in
  # publicAccessCidrs, so "restrict to the VPC" is not expressible here -
  # production uses a private endpoint instead (see prod/variables.tf).
  default = ["0.0.0.0/0"]
}

# Slack Notifications

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
  default     = "2.5.26"

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
variable "helm_nvidia_device_plugin_version" {
  description = "nvidia-device-plugin chart version"
  type        = string
  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.helm_nvidia_device_plugin_version))
    error_message = "Must be a semantic version."
  }
}
