# Bootstrap Outputs for GCP MLOps Platform
#
# These outputs provide the information needed to configure:
# - Terraform backend in environments/gcp/dev/providers.tf
# - GitHub Actions secrets for CI/CD

# =============================================================================
# Terraform State
# =============================================================================

output "terraform_state_bucket" {
  description = "GCS bucket name for Terraform state"
  value       = google_storage_bucket.terraform_state.name
}

output "terraform_state_bucket_url" {
  description = "GCS bucket URL for Terraform state"
  value       = google_storage_bucket.terraform_state.url
}

# =============================================================================
# Workload Identity
# =============================================================================

output "workload_identity_pool_name" {
  description = "Workload Identity Pool name"
  value       = google_iam_workload_identity_pool.github.name
}

output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.github.workload_identity_pool_id
}

output "workload_identity_provider" {
  description = "Full Workload Identity Provider name for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

# =============================================================================
# Service Account
# =============================================================================

output "github_actions_service_account" {
  description = "Service account email for GitHub Actions"
  value       = google_service_account.github_actions.email
}

output "github_actions_service_account_id" {
  description = "Service account ID for GitHub Actions"
  value       = google_service_account.github_actions.id
}

# =============================================================================
# Project Information
# =============================================================================

output "project_id" {
  description = "GCP project ID"
  value       = local.project_id
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
# Configuration Outputs
# =============================================================================

# Backend configuration for copy-paste into environments/gcp/dev/providers.tf
output "backend_config" {
  description = "Backend configuration to add to environments/gcp/dev/providers.tf"
  value       = <<-EOT
    # Add this to your terraform block in environments/gcp/dev/providers.tf:
    backend "gcs" {
      bucket = "${google_storage_bucket.terraform_state.name}"
      prefix = "mlops-platform/gcp/dev"
    }
  EOT
}

# GitHub Actions secrets configuration
output "github_actions_secrets" {
  description = "GitHub Actions secrets to configure"
  value       = <<-EOT
    # Add these secrets to your GitHub repository:
    # Settings > Secrets and variables > Actions > New repository secret

    GCP_PROJECT_ID: ${local.project_id}
    GCP_WORKLOAD_IDENTITY_PROVIDER: ${google_iam_workload_identity_pool_provider.github.name}
    GCP_SERVICE_ACCOUNT: ${google_service_account.github_actions.email}
  EOT
}

# GitHub Actions workflow configuration
output "github_actions_config" {
  description = "Configuration for GitHub Actions workflow"
  value       = <<-EOT
    # Add this step to your GitHub Actions workflow:

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${google_iam_workload_identity_pool_provider.github.name}
        service_account: ${google_service_account.github_actions.email}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2
      with:
        project_id: ${local.project_id}
  EOT
}

# JSON output for easy parsing
output "github_secrets_json" {
  description = "GitHub secrets in JSON format for automation"
  value = {
    GCP_PROJECT_ID                 = local.project_id
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_SERVICE_ACCOUNT            = google_service_account.github_actions.email
  }
}
