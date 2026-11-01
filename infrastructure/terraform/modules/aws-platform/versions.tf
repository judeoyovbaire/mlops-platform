terraform {
  required_version = ">= 1.5"

  # Constraints mirror environments/aws/*/providers.tf. The helm bound matters:
  # helm provider 3.x replaced `set {}` blocks with a list attribute, so an
  # unconstrained standalone init (CI validate, tflint) resolved 3.x and every
  # helm_release in this module failed to parse.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
      source  = "gavinbunney/kubectl"
      version = "~> 1.18"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
