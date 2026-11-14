# Terraform Configuration and Providers

terraform {
  # >= 1.11 for S3 native state locking (use_lockfile in backend.conf, GA in
  # 1.11); modules/aws-platform/moved.tf needs 1.8 on its own.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    kubectl = {
      # alekc/kubectl: maintained fork of gavinbunney/kubectl (no release
      # since 2025-01). 2.x is schema-compatible for kubectl_manifest; it
      # fails at configure on an unknown host unless lazy_load is set (root
      # providers.tf). 3.x (plugin framework) is a separate upgrade.
      source  = "alekc/kubectl"
      version = "~> 2.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
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

  # Remote state backend - partial configuration
  # Run 'terraform init -backend-config=backend.conf'
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "mlops-platform"
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# helm provider 3.x: kubernetes and exec are nested objects, not blocks.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# kubectl provider for CRD-based resources. lazy_load keeps a fresh plan
# working while module.eks outputs are still unknown: alekc/kubectl >= 2.3
# fails at provider configure otherwise (gavinbunney fell back to an empty
# config), which breaks the single-pass plan in scripts/deploy-aws.sh.
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  lazy_load              = true

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
