# Development Environment - MLOps Platform on EKS

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  # Uncomment to use S3 backend for state management
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "mlops-platform/dev/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
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

# Kubernetes provider configuration (after cluster creation)
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# EKS Cluster
module "eks" {
  source = "../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Cost optimization for dev: single NAT gateway
  single_nat_gateway = true

  # General nodes for platform services
  general_instance_types = ["t3.large"]
  general_min_size       = 2
  general_max_size       = 4
  general_desired_size   = 2

  # Training nodes (scale to zero when not in use)
  training_instance_types = ["c5.2xlarge"]
  training_capacity_type  = "SPOT"
  training_min_size       = 0
  training_max_size       = 5
  training_desired_size   = 0

  # GPU nodes (scale to zero when not in use)
  gpu_instance_types = ["g4dn.xlarge"]
  gpu_capacity_type  = "SPOT"
  gpu_min_size       = 0
  gpu_max_size       = 2
  gpu_desired_size   = 0

  # MLflow database
  mlflow_db_instance_class = "db.t3.small"
  mlflow_db_password       = var.mlflow_db_password

  tags = var.tags
}

# Kubernetes namespaces
resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "mlflow" {
  metadata {
    name = "mlflow"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "kubeflow" {
  metadata {
    name = "kubeflow"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "kserve" {
  metadata {
    name = "kserve"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

# MLflow secrets
resource "kubernetes_secret" "mlflow_postgres" {
  metadata {
    name      = "mlflow-postgres"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  data = {
    username = "mlflow"
    password = var.mlflow_db_password
  }

  depends_on = [kubernetes_namespace.mlflow]
}

resource "kubernetes_secret" "mlflow_s3" {
  metadata {
    name      = "mlflow-s3"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  # Using IRSA, so no need for static credentials
  # These are placeholders - actual auth uses service account
  data = {
    access-key = "use-irsa"
    secret-key = "use-irsa"
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# Service account for MLflow with IRSA
resource "kubernetes_service_account" "mlflow" {
  metadata {
    name      = "mlflow"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.eks.mlflow_irsa_role_arn
    }
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# =============================================================================
# Helm Releases
# =============================================================================

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.11.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.aws_lb_controller_irsa_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.eks.vpc_id
  }

  depends_on = [module.eks]
}

# cert-manager (required by KServe)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.17.0"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.0"
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/../../../helm/aws/argocd-values.yaml")]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# KServe CRDs
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = "0.15.2"
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  depends_on = [helm_release.cert_manager]
}

# KServe Controller
resource "helm_release" "kserve_controller" {
  name       = "kserve-controller"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve"
  version    = "0.15.2"
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  set {
    name  = "kserve.controller.deploymentMode"
    value = "RawDeployment"
  }

  depends_on = [helm_release.kserve]
}

# MLflow
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = "0.7.19"
  namespace  = kubernetes_namespace.mlflow.metadata[0].name

  values = [
    templatefile("${path.module}/../../../helm/aws/mlflow-values.yaml", {
      db_host    = split(":", module.eks.mlflow_db_endpoint)[0]
      db_name    = module.eks.mlflow_db_name
      s3_bucket  = module.eks.mlflow_s3_bucket
      aws_region = var.aws_region
    })
  ]

  depends_on = [
    kubernetes_service_account.mlflow,
    kubernetes_secret.mlflow_postgres,
    helm_release.aws_load_balancer_controller
  ]
}