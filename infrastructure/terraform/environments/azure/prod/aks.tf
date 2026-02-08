# AKS Cluster - Production Configuration
# Zone redundancy, managed identities, HA PostgreSQL with geo-redundant backups

module "aks" {
  source = "../../../modules/aks"

  # General
  cluster_name       = var.cluster_name
  azure_location     = var.azure_location
  kubernetes_version = var.kubernetes_version

  tags = var.tags

  # Networking
  vnet_cidr              = var.vnet_cidr
  aks_subnet_cidr        = var.aks_subnet_cidr
  postgresql_subnet_cidr = var.postgresql_subnet_cidr
  service_cidr           = var.service_cidr
  dns_service_ip         = var.dns_service_ip

  # API Server Access Control (restrict for production)
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges

  # System Node Pool - Production
  system_vm_size   = var.system_vm_size
  system_min_count = var.system_min_count
  system_max_count = var.system_max_count

  # Training Node Pool - Production (Regular instances, not Spot)
  training_vm_size   = var.training_vm_size
  training_min_count = var.training_min_count
  training_max_count = var.training_max_count

  # GPU Node Pool - Production (Regular instances for reliability)
  gpu_vm_size   = var.gpu_vm_size
  gpu_min_count = var.gpu_min_count
  gpu_max_count = var.gpu_max_count
  gpu_use_spot  = var.gpu_use_spot

  # PostgreSQL - Production Grade
  postgresql_sku                   = var.postgresql_sku
  postgresql_storage_mb            = var.postgresql_storage_mb
  postgresql_backup_retention_days = var.postgresql_backup_retention_days
  postgresql_ha_enabled            = var.postgresql_ha_enabled

  # Container Registry - Premium for Production
  acr_sku = var.acr_sku

  # Monitoring - Enabled for Production
  enable_azure_monitor = var.enable_azure_monitor
}
