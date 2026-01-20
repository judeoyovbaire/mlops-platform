# =============================================================================
# Core Helm Releases - Production
# =============================================================================
# Deploys essential platform components with production configurations

# =============================================================================
# NGINX Ingress Controller
# =============================================================================

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.helm_nginx_ingress_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    file("${path.module}/../../../../helm/gcp/nginx-ingress-values.yaml")
  ]

  depends_on = [module.gke]
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

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  # Production: Higher replica count for HA
  set {
    name  = "replicaCount"
    value = "2"
  }

  depends_on = [module.gke]
}

# =============================================================================
# ArgoCD - Production HA Configuration
# =============================================================================

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.helm_argocd_version
  namespace        = "argocd"
  create_namespace = false

  # Layer HA values on top of base values for production
  values = [
    templatefile("${path.module}/../../../../helm/gcp/argocd-values.yaml", {
      argocd_service_account_email = module.gke.argocd_service_account_email
    }),
    file("${path.module}/../../../../helm/gcp/argocd-values-prod.yaml"),
  ]

  depends_on = [
    helm_release.nginx_ingress,
    kubectl_manifest.argocd_admin_credentials
  ]
}

# =============================================================================
# KServe
# =============================================================================

# Install KServe CRDs first
resource "helm_release" "kserve_crds" {
  name       = "kserve-crds"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = var.helm_kserve_version
  namespace  = "kserve"

  depends_on = [kubernetes_namespace.kserve]
}

# Install KServe controller
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve"
  version    = var.helm_kserve_version
  namespace  = "kserve"

  values = [
    templatefile("${path.module}/../../../../helm/gcp/kserve-values.yaml", {
      kserve_service_account_email = module.gke.kserve_service_account_email
    })
  ]

  depends_on = [
    helm_release.kserve_crds,
    helm_release.nginx_ingress
  ]
}

# =============================================================================
# MLflow
# =============================================================================

resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = var.helm_mlflow_version
  namespace  = "mlflow"

  values = [
    templatefile("${path.module}/../../../../helm/gcp/mlflow-values.yaml", {
      mlflow_service_account_email = module.gke.mlflow_service_account_email
      cloudsql_private_ip          = module.gke.cloudsql_private_ip
      gcs_bucket_name              = module.gke.mlflow_artifacts_bucket
      project_id                   = var.project_id
    })
  ]

  depends_on = [
    kubernetes_namespace.mlflow,
    helm_release.nginx_ingress,
    kubectl_manifest.mlflow_db_credentials
  ]
}

# =============================================================================
# Argo Workflows
# =============================================================================

resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = var.helm_argo_workflows_version
  namespace  = "argo"

  # Increase timeout for CRD installation
  timeout = 600

  values = [
    templatefile("${path.module}/../../../../helm/gcp/argo-workflows-values.yaml", {
      argo_workflows_service_account_email = module.gke.argo_workflows_service_account_email
    })
  ]

  depends_on = [
    kubernetes_namespace.argo,
    helm_release.nginx_ingress
  ]
}

# =============================================================================
# MinIO (S3-compatible storage for Argo artifacts) - Production: Distributed
# =============================================================================

resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io"
  chart      = "minio"
  version    = var.helm_minio_version
  namespace  = "argo"

  # Production: Distributed mode for high availability
  set {
    name  = "mode"
    value = "distributed"
  }

  set {
    name  = "replicas"
    value = "4" # Minimum for distributed mode
  }

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = "100Gi" # Larger storage for production
  }

  set {
    name  = "persistence.storageClass"
    value = "standard-rwo"
  }

  set {
    name  = "resources.requests.cpu"
    value = "500m"
  }

  set {
    name  = "resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "resources.limits.memory"
    value = "2Gi"
  }

  set {
    name  = "buckets[0].name"
    value = "argo-artifacts"
  }

  set {
    name  = "buckets[0].policy"
    value = "none"
  }

  set {
    name  = "existingSecret"
    value = "minio-credentials"
  }

  # Security context - disable privileged mode for Kyverno compliance
  set {
    name  = "securityContext.enabled"
    value = "true"
  }

  set {
    name  = "securityContext.runAsUser"
    value = "1000"
  }

  set {
    name  = "securityContext.runAsGroup"
    value = "1000"
  }

  set {
    name  = "securityContext.fsGroup"
    value = "1000"
  }

  set {
    name  = "containerSecurityContext.enabled"
    value = "true"
  }

  set {
    name  = "containerSecurityContext.runAsNonRoot"
    value = "true"
  }

  set {
    name  = "containerSecurityContext.privileged"
    value = "false"
  }

  set {
    name  = "containerSecurityContext.allowPrivilegeEscalation"
    value = "false"
  }

  # Post-job security context for Kyverno compliance
  set {
    name  = "postJob.securityContext.enabled"
    value = "true"
  }

  set {
    name  = "postJob.securityContext.runAsUser"
    value = "1000"
  }

  set {
    name  = "postJob.securityContext.runAsGroup"
    value = "1000"
  }

  set {
    name  = "postJob.securityContext.fsGroup"
    value = "1000"
  }

  set {
    name  = "postJob.containerSecurityContext.enabled"
    value = "true"
  }

  set {
    name  = "postJob.containerSecurityContext.runAsNonRoot"
    value = "true"
  }

  set {
    name  = "postJob.containerSecurityContext.privileged"
    value = "false"
  }

  set {
    name  = "postJob.containerSecurityContext.allowPrivilegeEscalation"
    value = "false"
  }

  set {
    name  = "postJob.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "postJob.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "postJob.resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "postJob.resources.limits.memory"
    value = "128Mi"
  }

  depends_on = [
    kubernetes_namespace.argo,
    kubectl_manifest.minio_credentials
  ]
}
