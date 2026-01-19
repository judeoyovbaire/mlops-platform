# =============================================================================
# Terraform Configuration and Providers - Production
# =============================================================================

terraform {
  required_version = ">= 1.0"

  # GCS Backend for Terraform State
  backend "gcs" {
    bucket = "mlops-platform-tfstate-mlops-platform-prod-001"
    prefix = "mlops-platform/gcp/prod"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.14"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = var.labels
}

provider "google-beta" {
  project = var.project_id
  region  = var.region

  default_labels = var.labels
}

# Data source for GKE cluster auth
data "google_client_config" "default" {}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

# kubectl provider for CRD management
provider "kubectl" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  load_config_file       = false
}
