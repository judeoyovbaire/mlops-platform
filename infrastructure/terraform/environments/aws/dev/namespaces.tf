# =============================================================================
# Kubernetes Namespaces with Pod Security Standards (PSA)
# =============================================================================
# PSA enforcement levels:
# - restricted: Highly restricted, follows Pod hardening best practices
# - baseline: Minimally restrictive, prevents known privilege escalations
# - privileged: Unrestricted (system namespaces only)
#
# Enforcement strategy:
# - mlops, kserve: restricted (inference workloads should be hardened)
# - mlflow: baseline (MLflow chart doesn't set seccompProfile)
# - argo: baseline (workflow executor needs some elevated permissions)
# - monitoring, kyverno, tetragon: privileged (system components)

resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"
    labels = {
      "app.kubernetes.io/name"                     = "mlops-platform"
      "app.kubernetes.io/part-of"                  = "mlops-platform"
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
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
      # MLflow Helm chart doesn't set seccompProfile, requires baseline
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "baseline"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "argo" {
  metadata {
    name = "argo"
    labels = {
      "app.kubernetes.io/name"    = "argo-workflows"
      "app.kubernetes.io/part-of" = "mlops-platform"
      # Argo Workflows needs baseline due to executor requirements
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "baseline"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "kserve" {
  metadata {
    name = "kserve"
    labels = {
      "app.kubernetes.io/name"                     = "mlops-platform"
      "app.kubernetes.io/part-of"                  = "mlops-platform"
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }
  }

  depends_on = [module.eks]
}

# =============================================================================
# Kubernetes Secrets and Service Accounts
# =============================================================================

# MLflow secrets (using generated password)
resource "kubernetes_secret" "mlflow_postgres" {
  metadata {
    name      = "mlflow-postgres"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  data = {
    username = "mlflow"
    password = random_password.mlflow_db.result
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# Note: S3 credentials not needed - MLflow uses IRSA (IAM Roles for Service Accounts)
# The service account below is annotated with the IAM role ARN

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
