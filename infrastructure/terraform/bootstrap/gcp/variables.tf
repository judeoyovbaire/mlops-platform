# Bootstrap Variables for GCP MLOps Platform
#
# These variables configure the initial GCP resources needed before
# deploying the main MLOps platform infrastructure.

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west4"
}

variable "project_name" {
  description = "Project name used for resource naming"
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
