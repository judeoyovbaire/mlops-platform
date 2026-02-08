# GKE Module Instantiation

module "gke" {
  source = "../../../modules/gke"

  # General
  project_id         = var.project_id
  cluster_name       = var.cluster_name
  region             = var.region
  zones              = var.zones
  kubernetes_version = var.kubernetes_version
  release_channel    = var.release_channel
  labels             = var.labels

  # Networking
  vpc_cidr      = var.vpc_cidr
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
  master_cidr   = var.master_cidr

  # Master authorized networks - restrict API server access
  master_authorized_networks = var.master_authorized_networks

  # System node pool
  system_machine_type = var.system_machine_type
  system_min_count    = var.system_min_count
  system_max_count    = var.system_max_count

  # Training node pool
  training_machine_type = var.training_machine_type
  training_min_count    = var.training_min_count
  training_max_count    = var.training_max_count
  training_use_spot     = var.training_use_spot

  # GPU node pool
  gpu_machine_type      = var.gpu_machine_type
  gpu_accelerator_type  = var.gpu_accelerator_type
  gpu_accelerator_count = var.gpu_accelerator_count
  gpu_min_count         = var.gpu_min_count
  gpu_max_count         = var.gpu_max_count
  gpu_use_spot          = var.gpu_use_spot

  # Cloud SQL
  cloudsql_tier              = var.cloudsql_tier
  cloudsql_disk_size         = var.cloudsql_disk_size
  cloudsql_backup_enabled    = var.cloudsql_backup_enabled
  cloudsql_high_availability = var.cloudsql_high_availability
}
