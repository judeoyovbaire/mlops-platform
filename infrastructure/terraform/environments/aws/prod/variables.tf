# Production Environment Variables - AWS

variable "aws_region" {
  description = "AWS region for production deployment"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "mlops-platform-prod"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

# Network Configuration

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.100.0.0/16" # Different from dev to avoid conflicts
}

variable "private_subnets" {
  description = "Private subnet CIDRs (one per AZ for HA)"
  type        = list(string)
  default     = ["10.100.1.0/24", "10.100.2.0/24", "10.100.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs (one per AZ for HA)"
  type        = list(string)
  default     = ["10.100.101.0/24", "10.100.102.0/24", "10.100.103.0/24"]
}

# Cluster Access Control

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
  default     = false # Production: private access only via VPN/bastion
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access public endpoint (if enabled)"
  type        = list(string)
  default     = [] # Set to your organization's IP ranges if public access needed
}

# Tags

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Environment = "prod"
    Project     = "mlops-platform"
    CostCenter  = "ml-infrastructure"
    Criticality = "high"
  }
}

# Inference Domain

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS ingress. Must be set for production."
  type        = string
  default     = ""
}

variable "kserve_ingress_domain" {
  description = "Domain for KServe inference services"
  type        = string
  default     = "inference.mlops.example.com" # Replace with your actual domain

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
}

variable "helm_cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
}

variable "helm_argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
}

variable "helm_kserve_version" {
  description = "KServe Helm chart version"
  type        = string
}

variable "helm_mlflow_version" {
  description = "MLflow Helm chart version"
  type        = string
}

variable "helm_argo_workflows_version" {
  description = "Argo Workflows Helm chart version"
  type        = string
}

variable "helm_minio_version" {
  description = "MinIO Helm chart version"
  type        = string
}

variable "helm_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
}

variable "helm_karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.3"
}

variable "helm_tetragon_version" {
  description = "Tetragon Helm chart version"
  type        = string
}

variable "helm_kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string
}

variable "helm_external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
}

variable "helm_loki_version" {
  description = "Loki Helm chart version"
  type        = string
}

variable "helm_tempo_version" {
  description = "Tempo Helm chart version"
  type        = string
}

variable "helm_otel_collector_version" {
  description = "OpenTelemetry Collector Helm chart version"
  type        = string
}

variable "helm_alloy_version" {
  description = "Grafana Alloy Helm chart version"
  type        = string
}
