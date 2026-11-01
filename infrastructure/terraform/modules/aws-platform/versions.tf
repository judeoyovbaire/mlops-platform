terraform {
  # >= 1.8: moved.tf moves resources across types (kubernetes_namespace to _v1).
  required_version = ">= 1.8"

  # Constraints mirror environments/aws/*/providers.tf. The helm bound matters:
  # this module uses the helm provider 3.x syntax (`set = [...]` lists, and
  # `kubernetes = {}` in the root provider), which 2.x cannot parse. Keep
  # `~> 3.3` in step with the root providers.tf.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
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
