# EKS Cluster Module
# Creates an EKS cluster with managed node groups for MLOps workloads

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Data sources
# Pinned by zone name (CKV_AWS_394): an unfiltered lookup would grow when
# AWS adds an Availability Zone or shift when one drops out, and the VPC
# subnets follow this list.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  filter {
    name   = "zone-name"
    values = [for suffix in var.availability_zone_suffixes : "${data.aws_region.current.region}${suffix}"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# VPC for EKS
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3))
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  tags = var.tags
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster access - grant admin permissions to creator and additional ARNs
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  access_entries = {
    for idx, arn in var.cluster_admin_arns : "admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Tag node security group for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  # Cluster addons - versions PINNED (was most_recent = true, which made
  # every apply a potential surprise upgrade and defeated plan review).
  # Discovered for Kubernetes ${var.cluster_version} via:
  #   aws eks describe-addon-versions --kubernetes-version 1.37 \
  #     --addon-name <name> --query 'addons[0].addonVersions[0].addonVersion'
  # Bump deliberately alongside cluster_version upgrades. On 1.36 every build
  # below is also valid except kube-proxy (use v1.36.0-eksbuild.58).
  addons = {
    eks-pod-identity-agent = {
      addon_version               = "v1.4.1-eksbuild.3"
      resolve_conflicts_on_create = "OVERWRITE"
      before_compute              = true
    }
    coredns = {
      addon_version               = "v1.14.7-eksbuild.22"
      resolve_conflicts_on_create = "OVERWRITE"
    }
    kube-proxy = {
      addon_version               = "v1.37.0-eksbuild.32"
      resolve_conflicts_on_create = "OVERWRITE"
    }
    vpc-cni = {
      addon_version               = "v1.23.2-eksbuild.8"
      resolve_conflicts_on_create = "OVERWRITE"
      before_compute              = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      addon_version               = "v1.67.2-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      service_account_role_arn    = module.ebs_csi_irsa.arn
    }
  }

  eks_managed_node_groups = {
    # General purpose nodes for platform services
    general = {
      name           = "general"
      instance_types = var.general_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.general_min_size
      max_size     = var.general_max_size
      desired_size = var.general_desired_size

      labels = {
        role = "general"
      }

      tags = var.tags
    }

    # CPU nodes for training workloads
    training = {
      name           = "training"
      instance_types = var.training_instance_types
      capacity_type  = var.training_capacity_type

      min_size     = var.training_min_size
      max_size     = var.training_max_size
      desired_size = var.training_desired_size

      labels = {
        role = "training"
      }

      taints = var.training_taints

      tags = var.tags
    }

    # GPU nodes for ML workloads (optional)
    gpu = {
      name           = "gpu"
      instance_types = var.gpu_instance_types
      capacity_type  = var.gpu_capacity_type
      ami_type       = "AL2023_x86_64_NVIDIA" # AL2 AMIs stop at EKS 1.32; AL2023 is the only option here

      min_size     = var.gpu_min_size
      max_size     = var.gpu_max_size
      desired_size = var.gpu_desired_size

      labels = {
        role                     = "gpu"
        "nvidia.com/gpu.present" = "true"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      tags = var.tags
    }
  }

  tags = var.tags
}
