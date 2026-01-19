# =============================================================================
# Kubernetes Namespaces - Production
# =============================================================================
# Creates namespaces with Pod Security Admission (PSA) labels
# https://kubernetes.io/docs/concepts/security/pod-security-standards/
#
# Enforcement strategy:
# - mlops, kserve, mlflow: restricted (workloads should be hardened)
# - argo, argocd: baseline (workflow executors need elevated permissions)
# - monitoring: privileged (node-exporter requires host access)

# MLOps namespace - for model serving and inference
resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }

  depends_on = [module.gke]
}

# MLflow namespace - for experiment tracking
resource "kubernetes_namespace" "mlflow" {
  metadata {
    name = "mlflow"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }

  depends_on = [module.gke]
}

# Argo namespace - for workflow orchestration
resource "kubernetes_namespace" "argo" {
  metadata {
    name = "argo"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }

  depends_on = [module.gke]
}

# KServe namespace - for model serving controller
resource "kubernetes_namespace" "kserve" {
  metadata {
    name = "kserve"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }

  depends_on = [module.gke]
}

# Monitoring namespace - for Prometheus/Grafana
# Using privileged due to node-exporter requirements
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
    }
  }

  depends_on = [module.gke]
}

# ArgoCD namespace - for GitOps
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }

  depends_on = [module.gke]
}

# =============================================================================
# Service Accounts with Workload Identity
# =============================================================================

# Note: MLflow ServiceAccount is managed by the Helm chart (helm-core.tf)
# with Workload Identity annotation set in mlflow-values.yaml

# KServe inference service account
resource "kubernetes_service_account" "kserve_inference" {
  metadata {
    name      = "kserve-inference"
    namespace = kubernetes_namespace.mlops.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = module.gke.kserve_service_account_email
    }
  }

  depends_on = [kubernetes_namespace.mlops]
}
