# Bootstrap Infrastructure for MLOps Platform (GCP)
#
# This module creates the foundational GCP resources required BEFORE
# deploying the main MLOps platform:
#   - GCS bucket for Terraform state
#   - Workload Identity Pool for GitHub Actions OIDC
#   - Workload Identity Provider for GitHub
#   - Service Account for GitHub Actions
#   - IAM bindings for Terraform operations
#
# Usage:
#   cd infrastructure/terraform/bootstrap/gcp
#   terraform init
#   terraform apply -var="project_id=your-project-id"
#
# After applying, update the backend configuration in environments/gcp/dev/providers.tf

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.14"
    }
  }

  # Bootstrap uses local state (chicken-and-egg problem)
  # After creation, you could migrate this to GCS if desired
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# Data Sources
# =============================================================================

data "google_project" "current" {}

# =============================================================================
# GCS Bucket for Terraform State
# =============================================================================

resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_name}-tfstate-${var.project_id}"
  location      = var.region
  force_destroy = false

  # Enable versioning for state history
  versioning {
    enabled = true
  }

  # Uniform bucket-level access (recommended)
  uniform_bucket_level_access = true

  # Lifecycle rule to clean up old versions
  lifecycle_rule {
    condition {
      age                   = 90
      num_newer_versions    = 3
      with_state            = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Workload Identity Pool for GitHub Actions
# =============================================================================

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.project_name}-github-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions CI/CD"
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions Provider"
  description                        = "OIDC provider for GitHub Actions"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# =============================================================================
# Service Account for GitHub Actions
# =============================================================================

resource "google_service_account" "github_actions" {
  account_id   = "${var.project_name}-github-actions"
  display_name = "GitHub Actions Service Account"
  description  = "Service account for GitHub Actions CI/CD"
}

# Allow GitHub Actions to impersonate this service account
resource "google_service_account_iam_member" "github_actions_workload_identity" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# =============================================================================
# IAM Bindings for GitHub Actions Service Account
# =============================================================================

# Terraform state bucket access
resource "google_storage_bucket_iam_member" "terraform_state_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.github_actions.email}"
}

# GKE cluster management
resource "google_project_iam_member" "container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Compute resources (VPC, subnets, firewall)
resource "google_project_iam_member" "compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Service account management
resource "google_project_iam_member" "service_account_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Service account token creation (for Workload Identity)
resource "google_project_iam_member" "service_account_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Workload Identity Pool admin
resource "google_project_iam_member" "workload_identity_pool_admin" {
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# GCS bucket management
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Cloud SQL management
resource "google_project_iam_member" "cloudsql_admin" {
  project = var.project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Artifact Registry management
resource "google_project_iam_member" "artifactregistry_admin" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Secret Manager management
resource "google_project_iam_member" "secretmanager_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Service Usage (to enable APIs)
resource "google_project_iam_member" "service_usage_admin" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Project IAM Admin (for creating IAM bindings)
resource "google_project_iam_member" "project_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# =============================================================================
# Enable Required APIs
# =============================================================================

resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",          # GKE
    "compute.googleapis.com",             # Compute Engine (VPC, etc.)
    "sqladmin.googleapis.com",            # Cloud SQL
    "secretmanager.googleapis.com",       # Secret Manager
    "artifactregistry.googleapis.com",    # Artifact Registry
    "iam.googleapis.com",                 # IAM
    "iamcredentials.googleapis.com",      # IAM Credentials
    "cloudresourcemanager.googleapis.com", # Resource Manager
    "servicenetworking.googleapis.com",   # Service Networking (Private Service Access)
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}
