# GKE Module - Storage Resources
#
# Creates: GCS Bucket (MLflow artifacts), Cloud SQL PostgreSQL,
# Artifact Registry, Secret Manager secrets

# =============================================================================
# GCS Bucket for MLflow Artifacts
# =============================================================================

resource "google_storage_bucket" "mlflow_artifacts" {
  name          = "${var.cluster_name}-mlflow-artifacts-${var.project_id}"
  project       = var.project_id
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
}

# =============================================================================
# Private Service Access for Cloud SQL
# =============================================================================

resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.cluster_name}-private-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# =============================================================================
# Cloud SQL PostgreSQL
# =============================================================================

resource "random_id" "cloudsql_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "mlflow" {
  name                = "${var.cluster_name}-mlflow-${random_id.cloudsql_suffix.hex}"
  project             = var.project_id
  region              = var.region
  database_version    = var.cloudsql_database_version
  deletion_protection = false

  settings {
    tier              = var.cloudsql_tier
    availability_type = var.cloudsql_high_availability ? "REGIONAL" : "ZONAL"
    disk_size         = var.cloudsql_disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = var.cloudsql_backup_enabled
      point_in_time_recovery_enabled = var.cloudsql_backup_enabled
      start_time                     = "03:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    user_labels = var.labels
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "mlflow" {
  name     = "mlflow"
  project  = var.project_id
  instance = google_sql_database_instance.mlflow.name
}

resource "random_password" "mlflow_db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]<>:?"
}

resource "google_sql_user" "mlflow" {
  name     = "mlflow"
  project  = var.project_id
  instance = google_sql_database_instance.mlflow.name
  password = random_password.mlflow_db.result
}

# =============================================================================
# Artifact Registry
# =============================================================================

resource "google_artifact_registry_repository" "models" {
  repository_id = "${var.cluster_name}-models"
  project       = var.project_id
  location      = var.region
  format        = var.artifact_registry_format
  description   = "Container images for ML models"

  docker_config {
    immutable_tags = var.artifact_registry_immutable_tags
  }

  cleanup_policies {
    id     = "keep-last-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      older_than = "604800s" # 7 days
      tag_state  = "UNTAGGED"
    }
  }

  labels = var.labels
}

# =============================================================================
# Secret Manager Secrets
# =============================================================================

# MLflow Database Password
resource "google_secret_manager_secret" "mlflow_db_password" {
  secret_id = "${var.cluster_name}-mlflow-db-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "mlflow_db_password" {
  secret      = google_secret_manager_secret.mlflow_db_password.id
  secret_data = random_password.mlflow_db.result
}

# MinIO Root Password
resource "random_password" "minio_root" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]<>:?"
}

resource "google_secret_manager_secret" "minio_root_password" {
  secret_id = "${var.cluster_name}-minio-root-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "minio_root_password" {
  secret      = google_secret_manager_secret.minio_root_password.id
  secret_data = random_password.minio_root.result
}

# ArgoCD Admin Password
resource "random_password" "argocd_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]<>:?"
}

resource "google_secret_manager_secret" "argocd_admin_password" {
  secret_id = "${var.cluster_name}-argocd-admin-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "argocd_admin_password" {
  secret      = google_secret_manager_secret.argocd_admin_password.id
  secret_data = random_password.argocd_admin.result
}

# Grafana Admin Password
resource "random_password" "grafana_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]<>:?"
}

resource "google_secret_manager_secret" "grafana_admin_password" {
  secret_id = "${var.cluster_name}-grafana-admin-password"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "grafana_admin_password" {
  secret      = google_secret_manager_secret.grafana_admin_password.id
  secret_data = random_password.grafana_admin.result
}
