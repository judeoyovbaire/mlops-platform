# Core Helm Releases

# AWS Load Balancer Controller for ALB Ingress
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.helm_aws_lb_controller_version
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

# Wait for ALB Controller webhook to be ready
# This prevents race conditions where other helm releases try to create
# Services before the ALB Controller's MutatingWebhookConfiguration is serving
resource "time_sleep" "alb_controller_ready" {
  depends_on      = [helm_release.aws_load_balancer_controller]
  create_duration = "60s"
}

# cert-manager (required by KServe)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.helm_cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [time_sleep.alb_controller_ready]
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.helm_argocd_version
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/../../../../helm/aws/argocd-values.yaml")]

  depends_on = [time_sleep.alb_controller_ready]
}

# KServe CRDs
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = var.helm_kserve_version # Note: KServe OCI charts require 'v' prefix
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  depends_on = [helm_release.cert_manager]
}

# KServe Controller
resource "helm_release" "kserve_controller" {
  name       = "kserve-controller"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve"
  version    = var.helm_kserve_version # Note: KServe OCI charts require 'v' prefix
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  set {
    name  = "kserve.controller.deploymentMode"
    value = "RawDeployment"
  }

  # Disable KServe's built-in ingress creation - we manage Ingress separately via ALB
  set {
    name  = "kserve.controller.gateway.disableIngressCreation"
    value = "true"
  }

  set {
    name  = "kserve.controller.gateway.disableIstioVirtualHost"
    value = "true"
  }

  # Configure ingress gateway settings
  set {
    name  = "kserve.controller.gateway.ingressGateway.gateway"
    value = "kserve/kserve-ingress-gateway"
  }

  set {
    name  = "kserve.controller.gateway.ingressGateway.className"
    value = "alb"
  }

  set {
    name  = "kserve.controller.gateway.domain"
    value = var.kserve_ingress_domain
  }

  depends_on = [helm_release.kserve]
}

# MLflow
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = var.helm_mlflow_version
  namespace  = kubernetes_namespace.mlflow.metadata[0].name

  values = [
    templatefile("${path.module}/../../../../helm/aws/mlflow-values.yaml", {
      db_host             = split(":", module.eks.mlflow_db_endpoint)[0]
      db_name             = module.eks.mlflow_db_name
      s3_bucket           = module.eks.mlflow_s3_bucket
      aws_region          = var.aws_region
      acm_certificate_arn = var.acm_certificate_arn
    })
  ]

  depends_on = [
    kubernetes_service_account.mlflow,
    kubernetes_secret.mlflow_postgres,
    time_sleep.alb_controller_ready
  ]
}

# Argo Workflows - ML Pipeline Orchestration
resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = var.helm_argo_workflows_version
  namespace  = kubernetes_namespace.argo.metadata[0].name

  # Increase timeout for CRD installation
  timeout = 600

  values = [file("${path.module}/../../../../helm/aws/argo-workflows-values.yaml")]

  depends_on = [time_sleep.alb_controller_ready]
}

# MinIO for pipeline artifact storage (lightweight S3-compatible storage)
resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = var.helm_minio_version
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

  # Use ExternalSecret-managed credentials (avoids secrets in Helm release metadata)
  set {
    name  = "existingSecret"
    value = "minio-credentials"
  }

  set {
    name  = "buckets[0].name"
    value = "mlpipeline"
  }

  set {
    name  = "buckets[0].policy"
    value = "none"
  }

  depends_on = [time_sleep.alb_controller_ready]
}
