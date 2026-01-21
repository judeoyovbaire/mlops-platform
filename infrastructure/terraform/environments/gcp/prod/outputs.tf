# =============================================================================
# GCP Production Environment Outputs
# =============================================================================

# =============================================================================
# Cluster Information
# =============================================================================

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = module.gke.cluster_location
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = module.gke.kubectl_config_command
}

# =============================================================================
# Network Information
# =============================================================================

output "vpc_name" {
  description = "VPC network name"
  value       = module.gke.vpc_name
}

output "subnet_name" {
  description = "GKE subnet name"
  value       = module.gke.subnet_name
}

# =============================================================================
# Storage Information
# =============================================================================

output "mlflow_artifacts_bucket" {
  description = "GCS bucket for MLflow artifacts"
  value       = module.gke.mlflow_artifacts_bucket
}

output "artifact_registry_url" {
  description = "Artifact Registry URL"
  value       = module.gke.artifact_registry_url
}

# =============================================================================
# Database Information
# =============================================================================

output "cloudsql_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.gke.cloudsql_instance_name
}

output "cloudsql_connection_name" {
  description = "Cloud SQL connection name"
  value       = module.gke.cloudsql_connection_name
}

output "cloudsql_private_ip" {
  description = "Cloud SQL private IP"
  value       = module.gke.cloudsql_private_ip
  sensitive   = true
}

# =============================================================================
# Secret Manager
# =============================================================================

output "mlflow_db_password_secret" {
  description = "Secret Manager secret for MLflow DB password"
  value       = module.gke.mlflow_db_password_secret
}

output "argocd_admin_password_secret" {
  description = "Secret Manager secret for ArgoCD admin password"
  value       = module.gke.argocd_admin_password_secret
}

output "grafana_admin_password_secret" {
  description = "Secret Manager secret for Grafana admin password"
  value       = module.gke.grafana_admin_password_secret
}

# =============================================================================
# Service Accounts
# =============================================================================

output "mlflow_service_account" {
  description = "MLflow service account email"
  value       = module.gke.mlflow_service_account_email
}

output "external_secrets_service_account" {
  description = "External Secrets service account email"
  value       = module.gke.external_secrets_service_account_email
}

# =============================================================================
# Access Information
# =============================================================================

output "access_info" {
  description = "Access information for deployed services"
  value       = <<-EOT

    ============================================================
    GCP MLOps Platform - Production Environment
    ============================================================

    CLUSTER ACCESS:
      ${module.gke.kubectl_config_command}

    RETRIEVE SECRETS:
      # MLflow DB Password
      gcloud secrets versions access latest --secret="${module.gke.mlflow_db_password_secret}"

      # ArgoCD Admin Password
      gcloud secrets versions access latest --secret="${module.gke.argocd_admin_password_secret}"

      # Grafana Admin Password
      gcloud secrets versions access latest --secret="${module.gke.grafana_admin_password_secret}"

    PORT FORWARDING:
      # MLflow
      kubectl port-forward svc/mlflow 5000:5000 -n mlflow

      # ArgoCD
      kubectl port-forward svc/argocd-server 8080:443 -n argocd

      # Grafana
      kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

      # Argo Workflows
      kubectl port-forward svc/argo-workflows-server 2746:2746 -n argo

    DASHBOARDS (after port-forward):
      - MLflow: http://localhost:5000
      - ArgoCD: https://localhost:8080
      - Grafana: http://localhost:3000 (admin / <grafana-secret>)
      - Argo Workflows: http://localhost:2746

    DEPLOY MODEL:
      kubectl apply -f examples/kserve/inferenceservice-examples.yaml
      kubectl get inferenceservice -n mlops

    PRODUCTION NOTES:
      - Multi-zone deployment for high availability
      - Cloud SQL with regional HA enabled
      - ON_DEMAND instances (no Spot) for reliability
      - Kyverno policies ENFORCED (not just audit)
      - Extended backup retention periods

    ============================================================
  EOT
}
