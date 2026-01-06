# =============================================================================
# Terraform Configuration and Providers - Azure
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Remote state backend - created by bootstrap module
  # Update these values after running bootstrap/azure
  backend "azurerm" {
    resource_group_name  = "mlops-platform-bootstrap"
    storage_account_name = "mlopstfo9g9kzzx"
    container_name       = "tfstate"
    key                  = "mlops-platform/azure/dev/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "azuread" {}

# Kubernetes provider configuration (after cluster creation)
provider "kubernetes" {
  host                   = module.aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login", "azurecli",
      "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630" # AKS AAD server
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login", "azurecli",
        "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"
      ]
    }
  }
}

# kubectl provider for CRD-based resources
provider "kubectl" {
  host                   = module.aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login", "azurecli",
      "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"
    ]
  }
}
