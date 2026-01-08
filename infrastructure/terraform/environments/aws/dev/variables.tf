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

# Note: Database passwords are now auto-generated and stored in AWS SSM Parameter Store
# See secrets.tf for:
#   - random_password resources (auto-generation)
#   - aws_ssm_parameter resources (secure storage)
#   - External Secrets Operator (K8s sync)
#
# To retrieve passwords after deployment:
#   aws ssm get-parameter --name "/${cluster_name}/mlflow/db-password" --with-decryption
#   aws ssm get-parameter --name "/${cluster_name}/minio/root-password" --with-decryption
#   aws ssm get-parameter --name "/${cluster_name}/argocd/admin-password" --with-decryption

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "mlops-platform"
  }
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

# =============================================================================
# Helm Chart Versions
# Centralized version management for all Helm releases
# =============================================================================

variable "helm_aws_lb_controller_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.16.0"
}

variable "helm_cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.19.1"
}

variable "helm_argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.9.0"
}

variable "helm_kserve_version" {
  description = "KServe Helm chart version (CRD and controller)"
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
  default     = "0.46.1"
}

variable "helm_minio_version" {
  description = "MinIO Helm chart version"
  type        = string
  default     = "5.4.0"
}

variable "helm_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "72.6.2"
}

variable "helm_karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.0"
}

variable "helm_tetragon_version" {
  description = "Tetragon Helm chart version"
  type        = string
  default     = "1.3.0"
}

variable "helm_kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string
  default     = "3.3.4"
}

variable "helm_external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "1.1.1"
}