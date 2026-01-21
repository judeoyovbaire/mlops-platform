# =============================================================================
# Production Environment Variables - AWS
# =============================================================================
#
# This file contains production-grade configurations optimized for:
# - High availability (multi-AZ, redundant components)
# - Security (encryption, network isolation, access controls)
# - Performance (appropriate sizing for production workloads)
# - Disaster recovery (backup retention, deletion protection)
#
# IMPORTANT: Review and customize these values for your specific requirements
# before deploying to production.
# =============================================================================

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

# =============================================================================
# Network Configuration
# =============================================================================

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

# =============================================================================
# Cluster Access Control
# =============================================================================

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

# =============================================================================
# Tags
# =============================================================================

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

# =============================================================================
# Inference Domain
# =============================================================================

variable "kserve_ingress_domain" {
  description = "Domain for KServe inference services"
  type        = string
  default     = "inference.mlops.example.com" # Replace with your actual domain

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.kserve_ingress_domain))
    error_message = "Domain must be a valid DNS name."
  }
}

# =============================================================================
# Helm Chart Versions
# Pinned versions for production stability
# =============================================================================

variable "helm_aws_lb_controller_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.17.1"
}

variable "helm_cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.19.2"
}

variable "helm_argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.3.4"
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
  default     = "0.47.1"
}

variable "helm_minio_version" {
  description = "MinIO Helm chart version"
  type        = string
  default     = "5.4.0"
}

variable "helm_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "81.2.0"
}

variable "helm_karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.8.3"
}

variable "helm_tetragon_version" {
  description = "Tetragon Helm chart version"
  type        = string
  default     = "1.6.0"
}

variable "helm_kyverno_version" {
  description = "Kyverno Helm chart version"
  type        = string
  default     = "3.6.2"
}

variable "helm_external_secrets_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "1.2.1"
}
