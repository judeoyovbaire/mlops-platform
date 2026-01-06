# =============================================================================
# Core Helm Releases - Azure
# =============================================================================

# =============================================================================
# NGINX Ingress Controller (replaces AWS ALB Controller)
# =============================================================================

resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.helm_nginx_ingress_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    file("${path.module}/../../../../helm/azure/nginx-ingress-values.yaml")
  ]

  depends_on = [module.aks]
}

# =============================================================================
# cert-manager
# =============================================================================

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

  depends_on = [module.aks]
}

# =============================================================================
# ArgoCD
# =============================================================================

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.helm_argocd_version
  namespace        = "argocd"
  create_namespace = true

  values = [
    file("${path.module}/../../../../helm/azure/argocd-values.yaml")
  ]

  depends_on = [
    module.aks,
    helm_release.nginx_ingress
  ]
}

# =============================================================================
# KServe (Model Serving)
# =============================================================================

# KServe CRDs
resource "helm_release" "kserve_crd" {
  name             = "kserve-crd"
  repository       = "oci://ghcr.io/kserve/charts"
  chart            = "kserve-crd"
  version          = var.helm_kserve_version
  namespace        = "kserve"
  create_namespace = true

  depends_on = [module.aks]
}

# KServe Controller
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve"
  version    = var.helm_kserve_version
  namespace  = "kserve"

  values = [
    file("${path.module}/../../../../helm/azure/kserve-values.yaml")
  ]

  depends_on = [
    helm_release.kserve_crd,
    helm_release.cert_manager
  ]
}

# =============================================================================
# MLflow
# =============================================================================

resource "helm_release" "mlflow" {
  name             = "mlflow"
  repository       = "https://community-charts.github.io/helm-charts"
  chart            = "mlflow"
  version          = var.helm_mlflow_version
  namespace        = "mlflow"
  create_namespace = true

  values = [
    templatefile("${path.module}/../../../../helm/azure/mlflow-values.yaml", {
      storage_account_name      = module.aks.storage_account_name
      mlflow_identity_client_id = module.aks.mlflow_identity_client_id
      postgresql_host           = module.aks.postgresql_fqdn
      postgresql_database       = module.aks.postgresql_database_name
    })
  ]

  depends_on = [
    module.aks,
    helm_release.nginx_ingress,
    kubectl_manifest.mlflow_db_external_secret
  ]
}

# =============================================================================
# Argo Workflows
# =============================================================================

resource "helm_release" "argo_workflows" {
  name             = "argo-workflows"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  version          = var.helm_argo_workflows_version
  namespace        = "argo"
  create_namespace = true

  values = [
    file("${path.module}/../../../../helm/azure/argo-workflows-values.yaml")
  ]

  # Workload Identity for Argo
  set {
    name  = "server.serviceAccount.annotations.azure\\.workload\\.identity/client-id"
    value = module.aks.argo_workflows_identity_client_id
  }

  set {
    name  = "controller.serviceAccount.annotations.azure\\.workload\\.identity/client-id"
    value = module.aks.argo_workflows_identity_client_id
  }

  depends_on = [
    module.aks,
    helm_release.nginx_ingress
  ]
}

# =============================================================================
# MinIO (S3-compatible storage for Argo Workflows artifacts)
# =============================================================================

resource "helm_release" "minio" {
  name             = "minio"
  repository       = "https://charts.min.io/"
  chart            = "minio"
  version          = var.helm_minio_version
  namespace        = "argo"
  create_namespace = false

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
    value = "20Gi"
  }

  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  set_sensitive {
    name  = "rootUser"
    value = "admin"
  }

  set_sensitive {
    name  = "rootPassword"
    value = random_password.minio.result
  }

  set {
    name  = "buckets[0].name"
    value = "argo-artifacts"
  }

  set {
    name  = "buckets[0].policy"
    value = "none"
  }

  depends_on = [helm_release.argo_workflows]
}

resource "random_password" "minio" {
  length  = 24
  special = false
}