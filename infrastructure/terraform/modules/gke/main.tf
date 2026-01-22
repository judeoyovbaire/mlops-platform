# GKE Module - Google Kubernetes Engine for MLOps Platform
#
# Creates: VPC, GKE Cluster with Workload Identity, Node Pools (System, Training/Spot, GPU/Spot)
# Uses GKE Standard mode with Node Auto-provisioning for dynamic scaling

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.14"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Data Sources
data "google_project" "current" {
  project_id = var.project_id
}

data "google_client_config" "default" {}

# VPC Network
resource "google_compute_network" "main" {
  name                    = "${var.cluster_name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  name          = "${var.cluster_name}-gke-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.subnet_cidr

  # Secondary ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true

  # VPC Flow Logs
  dynamic "log_config" {
    for_each = var.enable_vpc_flow_logs ? [1] : []
    content {
      aggregation_interval = var.flow_logs_aggregation_interval
      flow_sampling        = var.flow_logs_sampling_rate
      metadata             = "INCLUDE_ALL_METADATA"
      filter_expr          = "true"
    }
  }
}

# Cloud NAT for private nodes to access internet
resource "google_compute_router" "main" {
  name    = "${var.cluster_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.cluster_name}-nat"
  project                            = var.project_id
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# GKE Cluster
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zones[0] # Zonal cluster for dev (cheaper)

  # Use a minimal default node pool and remove it
  # We'll create separate node pools with specific configurations
  remove_default_node_pool = true
  initial_node_count       = 1

  # Kubernetes version and release channel
  min_master_version = var.kubernetes_version
  release_channel {
    channel = var.release_channel
  }

  # Network configuration
  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.gke.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_cidr
  }

  # Master authorized networks
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Node Auto-provisioning (NAP)
  dynamic "cluster_autoscaling" {
    for_each = var.enable_node_autoprovisioning ? [1] : []
    content {
      enabled = true

      resource_limits {
        resource_type = "cpu"
        minimum       = var.nap_min_cpu
        maximum       = var.nap_max_cpu
      }

      resource_limits {
        resource_type = "memory"
        minimum       = var.nap_min_memory_gb
        maximum       = var.nap_max_memory_gb
      }

      resource_limits {
        resource_type = "nvidia-tesla-t4"
        minimum       = 0
        maximum       = var.nap_max_gpus
      }

      auto_provisioning_defaults {
        oauth_scopes = [
          "https://www.googleapis.com/auth/cloud-platform"
        ]
        service_account = google_service_account.node_pool.email

        management {
          auto_upgrade = true
          auto_repair  = true
        }

        disk_size = 100
        disk_type = "pd-balanced"
      }
    }
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # Maintenance window - daily 03:00-07:00 UTC (GKE requires 48h availability per 32 days)
  # RFC 3339 format requires a date, but GKE only uses the time portion for recurring windows
  maintenance_policy {
    recurring_window {
      start_time = "1970-01-01T03:00:00Z"
      end_time   = "1970-01-01T07:00:00Z"
      recurrence = "FREQ=DAILY"
    }
  }

  # Binary Authorization (optional)
  binary_authorization {
    evaluation_mode = "DISABLED"
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false # We use our own Prometheus stack
    }
  }

  # Security
  enable_shielded_nodes = true

  resource_labels = var.labels

  # Deletion protection
  deletion_protection = false

  depends_on = [
    google_compute_subnetwork.gke,
    google_service_account.node_pool
  ]
}

# Node Pool Service Account
resource "google_service_account" "node_pool" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE Node Pool Service Account"
  project      = var.project_id
}

# Minimal permissions for node pools
resource "google_project_iam_member" "node_pool_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_stackdriver_writer" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

# Node Pools - System (on-demand, always running)
resource "google_container_node_pool" "system" {
  name     = "system"
  project  = var.project_id
  location = var.zones[0]
  cluster  = google_container_cluster.main.name

  initial_node_count = var.system_min_count

  autoscaling {
    min_node_count = var.system_min_count
    max_node_count = var.system_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.system_machine_type
    disk_size_gb    = var.system_disk_size_gb
    disk_type       = "pd-balanced"
    service_account = google_service_account.node_pool.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = merge(var.labels, {
      role = "system"
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Training Node Pool - Spot instances, scale to zero
resource "google_container_node_pool" "training" {
  name     = "training"
  project  = var.project_id
  location = var.zones[0]
  cluster  = google_container_cluster.main.name

  initial_node_count = 0

  autoscaling {
    min_node_count = var.training_min_count
    max_node_count = var.training_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.training_machine_type
    disk_size_gb    = var.training_disk_size_gb
    disk_type       = "pd-balanced"
    service_account = google_service_account.node_pool.email
    spot            = var.training_use_spot

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = merge(var.labels, {
      role = "training"
    })

    taint {
      key    = "workload"
      value  = "training"
      effect = "NO_SCHEDULE"
    }

    dynamic "taint" {
      for_each = var.training_use_spot ? [1] : []
      content {
        key    = "cloud.google.com/gke-spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# GPU Node Pool - Spot instances, scale to zero
resource "google_container_node_pool" "gpu" {
  name     = "gpu"
  project  = var.project_id
  location = var.zones[0]
  cluster  = google_container_cluster.main.name

  initial_node_count = 0

  autoscaling {
    min_node_count = var.gpu_min_count
    max_node_count = var.gpu_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.gpu_machine_type
    disk_size_gb    = var.gpu_disk_size_gb
    disk_type       = "pd-balanced"
    service_account = google_service_account.node_pool.email
    spot            = var.gpu_use_spot

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    guest_accelerator {
      type  = var.gpu_accelerator_type
      count = var.gpu_accelerator_count
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    labels = merge(var.labels, {
      role                     = "gpu"
      "nvidia.com/gpu.present" = "true"
    })

    # Note: nvidia.com/gpu taint is automatically applied by GKE for GPU nodes
    # Only add the spot taint if using spot instances
    dynamic "taint" {
      for_each = var.gpu_use_spot ? [1] : []
      content {
        key    = "cloud.google.com/gke-spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Firewall Rules - internal communication
resource "google_compute_firewall" "internal" {
  name    = "${var.cluster_name}-allow-internal"
  project = var.project_id
  network = google_compute_network.main.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

# Allow health checks from GCP load balancers
resource "google_compute_firewall" "health_check" {
  name    = "${var.cluster_name}-allow-health-check"
  project = var.project_id
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
  }

  # GCP health check IP ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["gke-${var.cluster_name}"]
}
