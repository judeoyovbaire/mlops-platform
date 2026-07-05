# aws-platform module inputs.
#
# This module owns the Kubernetes platform layer that is common to every AWS
# environment (Karpenter pools, core Helm releases, Kyverno/Tetragon security,
# monitoring stack, namespaces, storage classes, multi-tenancy quotas). It
# exists to eliminate the dev/prod copy-paste that once shipped prod GPU nodes
# tagged Environment: dev — environment differences are explicit inputs here,
# not divergent file copies.

variable "environment" {
  description = "Environment name (dev | prod) — used for tagging and labels"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "eks" {
  description = <<-EOT
    Outputs object of the environment's EKS module (pass `eks = module.eks`).
    Consumed attributes: cluster_name, cluster_endpoint, oidc_provider_arn,
    vpc_id, karpenter_irsa_role_arn, karpenter_node_role_name,
    aws_lb_controller_irsa_role_arn, loki/mlflow/tempo IRSA role ARNs and
    S3 bucket ids, mlflow_db_endpoint/name/secret_arn.
  EOT
  type        = any
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for ingress TLS"
  type        = string
  default     = ""
}

variable "kserve_ingress_domain" {
  description = "Ingress domain for KServe inference services"
  type        = string
}

variable "slack_notifications_enabled" {
  description = "Enable Slack alert notifications"
  type        = bool
  default     = false
}

variable "slack_channel" {
  description = "Slack channel for alerts"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}

variable "argocd_extra_values_files" {
  description = <<-EOT
    Extra ArgoCD Helm values files layered on top of the base values
    (absolute paths — build with abspath()/path.module in the caller).
    Prod passes the HA overlay here.
  EOT
  type        = list(string)
  default     = []
}

variable "minio" {
  description = <<-EOT
    MinIO sizing: dev = standalone/small (defaults), prod = distributed/HA.
    Limits are always rendered - the platform's own Kyverno
    require-resource-limits policy (Enforce, argo namespace in scope)
    admission-blocks limit-less pods.
  EOT
  type = object({
    mode           = optional(string, "standalone")
    replicas       = optional(number, 1)
    storage_size   = optional(string, "10Gi")
    memory_request = optional(string, "512Mi")
    cpu_request    = optional(string, "250m")
    memory_limit   = optional(string, "1Gi")
    cpu_limit      = optional(string, "500m")
  })
  default = {}
}

# --- Helm chart versions (single source: helm-versions.auto.tfvars at root,
# --- passed through by the calling environment) ---

variable "helm_alloy_version" { type = string }
variable "helm_argo_events_version" { type = string }
variable "helm_argo_rollouts_version" { type = string }
variable "helm_argo_workflows_version" { type = string }
variable "helm_argocd_version" { type = string }
variable "helm_aws_lb_controller_version" { type = string }
variable "helm_cert_manager_version" { type = string }
variable "helm_dcgm_exporter_version" { type = string }
variable "helm_external_secrets_version" { type = string }
variable "helm_karpenter_version" { type = string }
variable "helm_kserve_version" { type = string }
variable "helm_kyverno_version" { type = string }
variable "helm_loki_version" { type = string }
variable "helm_minio_version" { type = string }
variable "helm_mlflow_version" { type = string }
variable "helm_opencost_version" { type = string }
variable "helm_otel_collector_version" { type = string }
variable "helm_prometheus_stack_version" { type = string }
variable "helm_tempo_version" { type = string }
variable "helm_tetragon_version" { type = string }

variable "grafana_admin_password" {
  description = "Grafana admin password (generated in the environment's secrets.tf)"
  type        = string
  sensitive   = true
}
