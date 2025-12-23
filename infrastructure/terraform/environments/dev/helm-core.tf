# =============================================================================
# Core Helm Releases
# =============================================================================

# AWS Load Balancer Controller for ALB Ingress
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.16.0"
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
  version          = "v1.19.1"
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
  version          = "7.9.0"
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
  version    = "v0.16.0" # Note: KServe OCI charts require 'v' prefix
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  depends_on = [helm_release.cert_manager]
}

# KServe Controller
resource "helm_release" "kserve_controller" {
  name       = "kserve-controller"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve"
  version    = "v0.16.0" # Note: KServe OCI charts require 'v' prefix
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  set {
    name  = "kserve.controller.deploymentMode"
    value = "RawDeployment"
  }

  # Disable KServe's built-in ingress creation - we manage Ingress separately
  set {
    name  = "kserve.controller.ingress.disableIngressCreation"
    value = "true"
  }

  set {
    name  = "kserve.controller.ingress.disableIstioVirtualHost"
    value = "true"
  }

  depends_on = [helm_release.kserve]
}

# MLflow
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = "1.8.1" # Upgraded: supports existingDatabaseSecret
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

# =============================================================================
# Argo Workflows - ML Pipeline Orchestration
# =============================================================================

# Argo Workflows for ML pipeline orchestration
resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = "0.46.1"
  namespace  = kubernetes_namespace.argo.metadata[0].name

  # Increase timeout for CRD installation
  timeout = 600

  values = [file("${path.module}/../../../helm/aws/argo-workflows-values.yaml")]

  depends_on = [module.eks]
}

# MinIO for pipeline artifact storage (lightweight S3-compatible storage)
resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.4.0"
  namespace  = kubernetes_namespace.argo.metadata[0].name

  set {
    name  = "mode"
    value = "standalone"
  }

  set {
    name  = "replicas"
    value = "1"
  }

  set {
    name  = "persistence.size"
    value = "10Gi"
  }

  set {
    name  = "persistence.storageClass"
    value = "gp3"
  }

  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "rootUser"
    value = "minio"
  }

  # Use generated password from SSM
  set {
    name  = "rootPassword"
    value = random_password.minio.result
  }

  set {
    name  = "buckets[0].name"
    value = "mlpipeline"
  }

  set {
    name  = "buckets[0].policy"
    value = "none"
  }

  depends_on = [module.eks]
}
