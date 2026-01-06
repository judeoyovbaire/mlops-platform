# AKS Module - Azure Kubernetes Service for MLOps Platform
# Creates: Resource Group, VNet, AKS Cluster with Workload Identity,
# Node Pools (System, Training/Spot, GPU/Spot), Azure CNI + Calico

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Data Sources
data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.cluster_name}-rg"
  location = var.azure_location

  tags = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

# AKS Subnet - Large enough for nodes and pods
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# PostgreSQL Subnet - With delegation for Flexible Server
resource "azurerm_subnet" "postgresql" {
  name                 = "postgresql-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.postgresql_subnet_cidr]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # System node pool (required default pool)
  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_vm_size
    min_count                   = var.system_min_count
    max_count                   = var.system_max_count
    max_pods                    = 110 # Increased from default 30 for Azure CNI
    vnet_subnet_id              = azurerm_subnet.aks.id
    enable_auto_scaling         = true
    os_disk_size_gb             = 100
    temporary_name_for_rotation = "systemtmp"

    node_labels = {
      "role" = "system"
    }

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # System-assigned managed identity for cluster
  identity {
    type = "SystemAssigned"
  }

  # Enable OIDC issuer for Workload Identity
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Azure CNI with Calico network policy
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  # Azure Key Vault secrets provider (CSI driver)
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Azure Monitor (optional)
  dynamic "oms_agent" {
    for_each = var.enable_azure_monitor ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
    }
  }

  # Auto-upgrade channel
  automatic_channel_upgrade = "patch"

  # Maintenance window
  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "03:00"
    utc_offset  = "+00:00"
  }

  tags = var.tags
}

# Additional Node Pools

# Training Node Pool - CPU workloads with Spot instances
resource "azurerm_kubernetes_cluster_node_pool" "training" {
  name                  = "training"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.training_vm_size
  min_count             = var.training_min_count
  max_count             = var.training_max_count
  enable_auto_scaling   = true
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1 # Pay market price
  vnet_subnet_id        = azurerm_subnet.aks.id
  os_disk_size_gb       = 100

  node_labels = {
    "role"                                  = "training"
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  node_taints = [
    "workload=training:NoSchedule",
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = var.tags
}

# GPU Node Pool - ML inference and training
resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.gpu_vm_size
  min_count             = var.gpu_min_count
  max_count             = var.gpu_max_count
  enable_auto_scaling   = true
  priority              = var.gpu_use_spot ? "Spot" : "Regular"
  eviction_policy       = var.gpu_use_spot ? "Delete" : null
  spot_max_price        = var.gpu_use_spot ? -1 : null
  vnet_subnet_id        = azurerm_subnet.aks.id
  os_disk_size_gb       = 200

  node_labels = {
    "role"                   = "gpu"
    "nvidia.com/gpu.present" = "true"
  }

  node_taints = [
    "nvidia.com/gpu=true:NoSchedule"
  ]

  tags = var.tags
}

# Log Analytics Workspace (optional)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_azure_monitor ? 1 : 0
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}
