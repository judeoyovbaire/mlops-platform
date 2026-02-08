# Kubernetes Namespaces with Pod Security Admission
# Enforcement strategy:
# - mlops, kserve: restricted (inference workloads should be hardened)
# - mlflow: restricted (tracking server is stateless)
# - keda, monitoring: baseline/privileged (system components)

# MLOps namespace for inference services
resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"

    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [module.aks]
}

# MLflow namespace
resource "kubernetes_namespace" "mlflow" {
  metadata {
    name = "mlflow"

    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [module.aks]
}

# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "privileged" # Required for node-exporter
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }

  depends_on = [module.aks]
}

# KEDA namespace
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"

    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [module.aks]
}