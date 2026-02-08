# Azure Bootstrap Variables

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "mlops-platform"
}

variable "azure_location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "mlops-platform"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "mlops-platform"
    Environment = "bootstrap"
    ManagedBy   = "terraform"
  }
}