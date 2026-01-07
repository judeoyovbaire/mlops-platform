# GKE Module Outputs
#
# Exports cluster, networking, storage, and identity information
# for use in the environment configuration layer.

# =============================================================================
# Cluster Information
# =============================================================================

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.main.location
}

output "cluster_master_version" {
  description = "GKE cluster master version"
  value       = google_container_cluster.main.master_version
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.project_id}.svc.id.goog"
}

# =============================================================================
# Network Information
# =============================================================================

output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.main.id
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "subnet_id" {
  description = "GKE subnet ID"
  value       = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  description = "GKE subnet name"
  value       = google_compute_subnetwork.gke.name
}

# =============================================================================
# Storage Information
# =============================================================================

output "mlflow_artifacts_bucket" {
  description = "GCS bucket name for MLflow artifacts"
  value       = google_storage_bucket.mlflow_artifacts.name
}

output "mlflow_artifacts_bucket_url" {
  description = "GCS bucket URL for MLflow artifacts"
  value       = google_storage_bucket.mlflow_artifacts.url
}

# =============================================================================
# Cloud SQL Information
# =============================================================================

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.mlflow.name
}

output "cloudsql_connection_name" {
  description = "Cloud SQL connection name for Cloud SQL Proxy"
  value       = google_sql_database_instance.mlflow.connection_name
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = google_sql_database_instance.mlflow.private_ip_address
}

output "cloudsql_database_name" {
  description = "Cloud SQL database name"
  value       = google_sql_database.mlflow.name
}

output "cloudsql_user" {
  description = "Cloud SQL username"
  value       = google_sql_user.mlflow.name
}

# =============================================================================
# Artifact Registry Information
# =============================================================================

output "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  value       = google_artifact_registry_repository.models.name
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.models.name}"
}

# =============================================================================
# Secret Manager Information
# =============================================================================

output "mlflow_db_password_secret" {
  description = "Secret Manager secret ID for MLflow DB password"
  value       = google_secret_manager_secret.mlflow_db_password.secret_id
}

output "minio_root_password_secret" {
  description = "Secret Manager secret ID for MinIO root password"
  value       = google_secret_manager_secret.minio_root_password.secret_id
}

output "argocd_admin_password_secret" {
  description = "Secret Manager secret ID for ArgoCD admin password"
  value       = google_secret_manager_secret.argocd_admin_password.secret_id
}

output "grafana_admin_password_secret" {
  description = "Secret Manager secret ID for Grafana admin password"
  value       = google_secret_manager_secret.grafana_admin_password.secret_id
}

# =============================================================================
# Service Account Information (Workload Identity)
# =============================================================================

output "mlflow_service_account_email" {
  description = "MLflow service account email"
  value       = google_service_account.mlflow.email
}

output "external_secrets_service_account_email" {
  description = "External Secrets service account email"
  value       = google_service_account.external_secrets.email
}

output "argo_workflows_service_account_email" {
  description = "Argo Workflows service account email"
  value       = google_service_account.argo_workflows.email
}

output "argocd_service_account_email" {
  description = "ArgoCD service account email"
  value       = google_service_account.argocd.email
}

output "kserve_service_account_email" {
  description = "KServe service account email"
  value       = google_service_account.kserve.email
}

output "prometheus_service_account_email" {
  description = "Prometheus service account email"
  value       = google_service_account.prometheus.email
}

output "node_pool_service_account_email" {
  description = "Node pool service account email"
  value       = google_service_account.node_pool.email
}

# =============================================================================
# Project Information
# =============================================================================

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "project_number" {
  description = "GCP project number"
  value       = data.google_project.current.number
}

output "region" {
  description = "GCP region"
  value       = var.region
}

# =============================================================================
# kubectl Configuration
# =============================================================================

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --zone ${google_container_cluster.main.location} --project ${var.project_id}"
}

# =============================================================================
# Access Information
# =============================================================================

output "access_info" {
  description = "Access information for deployed services"
  value       = <<-EOT
    ============================================================
    GKE Cluster Access Information
    ============================================================

    Cluster Name: ${google_container_cluster.main.name}
    Location: ${google_container_cluster.main.location}
    Kubernetes Version: ${google_container_cluster.main.master_version}

    Configure kubectl:
      gcloud container clusters get-credentials ${google_container_cluster.main.name} \
        --zone ${google_container_cluster.main.location} \
        --project ${var.project_id}

    Retrieve Secrets:
      # MLflow DB Password
      gcloud secrets versions access latest --secret="${google_secret_manager_secret.mlflow_db_password.secret_id}"

      # ArgoCD Admin Password
      gcloud secrets versions access latest --secret="${google_secret_manager_secret.argocd_admin_password.secret_id}"

      # Grafana Admin Password
      gcloud secrets versions access latest --secret="${google_secret_manager_secret.grafana_admin_password.secret_id}"

    Cloud SQL Connection:
      Host: ${google_sql_database_instance.mlflow.private_ip_address}
      Database: ${google_sql_database.mlflow.name}
      User: ${google_sql_user.mlflow.name}

    GCS Bucket: ${google_storage_bucket.mlflow_artifacts.name}
    Artifact Registry: ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.models.name}
    ============================================================
  EOT
}
