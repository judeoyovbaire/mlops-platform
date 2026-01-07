# Bootstrap Variables for GCP MLOps Platform
#
# These variables configure the initial GCP resources needed before
# deploying the main MLOps platform infrastructure.

variable "create_project" {
  description = "Whether to create a new GCP project (true) or use an existing one (false)"
  type        = bool
  default     = true
}

variable "project_id" {
  description = "GCP project ID (will be created if create_project=true)"
  type        = string
}

variable "project_name" {
  description = "Display name for the project (used if create_project=true)"
  type        = string
  default     = "MLOps Platform"
}

variable "billing_account" {
  description = "Billing account ID (required if create_project=true)"
  type        = string
  default     = ""
}

variable "org_id" {
  description = "Organization ID (optional, for org-level project creation)"
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID (optional, for folder-level project creation)"
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west4"
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
  default     = "mlops-platform"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "judeoyovbaire"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "mlops-platform"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project    = "mlops-platform"
    managed_by = "terraform-bootstrap"
  }
}
