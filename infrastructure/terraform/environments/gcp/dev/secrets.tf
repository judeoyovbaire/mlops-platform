# Kubernetes Secrets Configuration
# Creates Kubernetes secrets for components that don't use External Secrets

# MLflow database credentials (username component)
# Password is synced via External Secrets, but we need username too
resource "kubernetes_secret" "mlflow_db_username" {
  metadata {
    name      = "mlflow-db-username"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  data = {
    username = "mlflow"
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# Grafana admin username (password synced via External Secrets)
resource "kubernetes_secret" "grafana_admin_username" {
  metadata {
    name      = "grafana-admin-username"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    username = "admin"
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# MinIO root user (password synced via External Secrets)
resource "kubernetes_secret" "minio_root_user" {
  metadata {
    name      = "minio-root-user"
    namespace = kubernetes_namespace.argo.metadata[0].name
  }

  data = {
    accesskey = "minioadmin"
  }

  depends_on = [kubernetes_namespace.argo]
}

# ConfigMaps for Platform Configuration

# MLflow configuration
resource "kubernetes_config_map" "mlflow_config" {
  metadata {
    name      = "mlflow-config"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  data = {
    MLFLOW_TRACKING_URI  = "http://mlflow.mlflow.svc.cluster.local:5000"
    MLFLOW_ARTIFACT_ROOT = "gs://${module.gke.mlflow_artifacts_bucket}"
    GOOGLE_CLOUD_PROJECT = var.project_id
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# Argo Workflows configuration
resource "kubernetes_config_map" "argo_config" {
  metadata {
    name      = "argo-config"
    namespace = kubernetes_namespace.argo.metadata[0].name
  }

  data = {
    ARGO_SERVER = "argo-workflows-server.argo.svc.cluster.local:2746"
  }

  depends_on = [kubernetes_namespace.argo]
}

# KServe configuration
resource "kubernetes_config_map" "kserve_config" {
  metadata {
    name      = "kserve-config"
    namespace = kubernetes_namespace.mlops.metadata[0].name
  }

  data = {
    MODEL_REGISTRY_URL = "gs://${module.gke.mlflow_artifacts_bucket}/models"
    ARTIFACT_REGISTRY  = module.gke.artifact_registry_url
  }

  depends_on = [kubernetes_namespace.mlops]
}
