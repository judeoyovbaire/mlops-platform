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
      # alekc/kubectl: maintained fork of gavinbunney/kubectl (no release
      # since 2025-01). 2.x is schema-compatible for kubectl_manifest; it
      # fails at configure on an unknown host unless lazy_load is set (root
      # providers.tf). 3.x (plugin framework) is a separate upgrade.
      source  = "alekc/kubectl"
      version = "~> 2.4"
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
