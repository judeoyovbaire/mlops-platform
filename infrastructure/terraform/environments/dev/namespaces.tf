# =============================================================================
# Kubernetes Namespaces with Pod Security Standards (PSA)
# =============================================================================
# PSA enforcement levels:
# - restricted: Highly restricted, follows Pod hardening best practices (mlops, mlflow, kserve)
# - baseline: Minimally restrictive, prevents known privilege escalations (argo, monitoring)
# - privileged: Unrestricted (system namespaces only)
#
# Using "warn" mode initially to identify violations without blocking deployments
# Change to "enforce" after validating all workloads comply

resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"
    labels = {
      "app.kubernetes.io/name"                     = "mlops-platform"
      "app.kubernetes.io/part-of"                  = "mlops-platform"
      "pod-security.kubernetes.io/enforce"         = "baseline"
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
      "app.kubernetes.io/name"                     = "mlops-platform"
      "app.kubernetes.io/part-of"                  = "mlops-platform"
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
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
      "pod-security.kubernetes.io/enforce"         = "baseline"
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
