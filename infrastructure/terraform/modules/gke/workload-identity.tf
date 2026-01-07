# GKE Module - Workload Identity Configuration
#
# Creates Google Service Accounts and binds them to Kubernetes Service Accounts
# using GKE Workload Identity Federation for secure pod authentication.

# =============================================================================
# MLflow Service Account
# =============================================================================

resource "google_service_account" "mlflow" {
  account_id   = "${var.cluster_name}-mlflow"
  display_name = "MLflow Service Account"
  description  = "Service account for MLflow to access GCS and Cloud SQL"
  project      = var.project_id
}

# Allow Kubernetes SA to use this Google SA
# Note: depends_on cluster because the workload identity pool is created with the cluster
resource "google_service_account_iam_member" "mlflow_workload_identity" {
  service_account_id = google_service_account.mlflow.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[mlflow/mlflow]"

  depends_on = [google_container_cluster.main]
}

# GCS access for MLflow artifacts
resource "google_storage_bucket_iam_member" "mlflow_gcs" {
  bucket = google_storage_bucket.mlflow_artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mlflow.email}"
}

# Cloud SQL client access
resource "google_project_iam_member" "mlflow_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.mlflow.email}"
}

# =============================================================================
# External Secrets Operator Service Account
# =============================================================================

resource "google_service_account" "external_secrets" {
  account_id   = "${var.cluster_name}-eso"
  display_name = "External Secrets Operator Service Account"
  description  = "Service account for ESO to access Secret Manager"
  project      = var.project_id
}

# Allow Kubernetes SA to use this Google SA
resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"

  depends_on = [google_container_cluster.main]
}

# Secret Manager access for ESO
resource "google_project_iam_member" "external_secrets_secretmanager" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

# =============================================================================
# Argo Workflows Service Account
# =============================================================================

resource "google_service_account" "argo_workflows" {
  account_id   = "${var.cluster_name}-argo"
  display_name = "Argo Workflows Service Account"
  description  = "Service account for Argo Workflows to access GCS artifacts"
  project      = var.project_id
}

# Allow Kubernetes SA (server) to use this Google SA
resource "google_service_account_iam_member" "argo_server_workload_identity" {
  service_account_id = google_service_account.argo_workflows.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argo/argo-workflows-server]"

  depends_on = [google_container_cluster.main]
}

# Allow Kubernetes SA (controller) to use this Google SA
resource "google_service_account_iam_member" "argo_controller_workload_identity" {
  service_account_id = google_service_account.argo_workflows.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argo/argo-workflows-workflow-controller]"

  depends_on = [google_container_cluster.main]
}

# GCS access for Argo artifacts (using MLflow artifacts bucket for simplicity)
resource "google_storage_bucket_iam_member" "argo_gcs" {
  bucket = google_storage_bucket.mlflow_artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.argo_workflows.email}"
}

# =============================================================================
# ArgoCD Service Account
# =============================================================================

resource "google_service_account" "argocd" {
  account_id   = "${var.cluster_name}-argocd"
  display_name = "ArgoCD Service Account"
  description  = "Service account for ArgoCD"
  project      = var.project_id
}

# Allow Kubernetes SA to use this Google SA
resource "google_service_account_iam_member" "argocd_server_workload_identity" {
  service_account_id = google_service_account.argocd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-server]"

  depends_on = [google_container_cluster.main]
}

resource "google_service_account_iam_member" "argocd_controller_workload_identity" {
  service_account_id = google_service_account.argocd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-application-controller]"

  depends_on = [google_container_cluster.main]
}

# =============================================================================
# KServe Service Account
# =============================================================================

resource "google_service_account" "kserve" {
  account_id   = "${var.cluster_name}-kserve"
  display_name = "KServe Service Account"
  description  = "Service account for KServe inference services"
  project      = var.project_id
}

# Allow Kubernetes SA to use this Google SA
resource "google_service_account_iam_member" "kserve_workload_identity" {
  service_account_id = google_service_account.kserve.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[kserve/kserve-controller-manager]"

  depends_on = [google_container_cluster.main]
}

# Allow inference namespace default SA to use this Google SA
resource "google_service_account_iam_member" "kserve_inference_workload_identity" {
  service_account_id = google_service_account.kserve.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[mlops/default]"

  depends_on = [google_container_cluster.main]
}

# GCS access for model artifacts
resource "google_storage_bucket_iam_member" "kserve_gcs" {
  bucket = google_storage_bucket.mlflow_artifacts.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.kserve.email}"
}

# Artifact Registry access for pulling model images
resource "google_artifact_registry_repository_iam_member" "kserve_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.models.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.kserve.email}"
}

# =============================================================================
# Prometheus Service Account (for GCP monitoring integration)
# =============================================================================

resource "google_service_account" "prometheus" {
  account_id   = "${var.cluster_name}-prometheus"
  display_name = "Prometheus Service Account"
  description  = "Service account for Prometheus"
  project      = var.project_id
}

# Allow Kubernetes SA to use this Google SA
resource "google_service_account_iam_member" "prometheus_workload_identity" {
  service_account_id = google_service_account.prometheus.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[monitoring/prometheus-kube-prometheus-prometheus]"

  depends_on = [google_container_cluster.main]
}

# Monitoring viewer for GCP metrics
resource "google_project_iam_member" "prometheus_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.prometheus.email}"
}
