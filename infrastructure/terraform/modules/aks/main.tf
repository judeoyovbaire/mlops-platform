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
      version = "~> 3.7"
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

  # API Server access configuration - restrict to authorized IPs
  # Only enable when specific IP ranges are provided (empty = public access)
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # Explicitly enable RBAC (Azure default, but makes intent clear)
  role_based_access_control_enabled = true

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

# Log Analytics Workspace (required for flow logs and monitoring)
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_azure_monitor || var.enable_nsg_flow_logs ? 1 : 0
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

# NSG Flow Logs
resource "azurerm_network_watcher" "main" {
  count               = var.enable_nsg_flow_logs ? 1 : 0
  name                = "${var.cluster_name}-network-watcher"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_storage_account" "flow_logs" {
  count                    = var.enable_nsg_flow_logs ? 1 : 0
  name                     = "flowlogs${replace(var.cluster_name, "-", "")}${substr(md5(azurerm_resource_group.main.id), 0, 8)}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# NSG for AKS subnet (needed for flow logs)
resource "azurerm_network_security_group" "aks" {
  count               = var.enable_nsg_flow_logs ? 1 : 0
  name                = "${var.cluster_name}-aks-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  count                     = var.enable_nsg_flow_logs ? 1 : 0
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks[0].id
}

resource "azurerm_network_watcher_flow_log" "aks" {
  count                = var.enable_nsg_flow_logs ? 1 : 0
  name                 = "${var.cluster_name}-aks-flow-log"
  network_watcher_name = azurerm_network_watcher.main[0].name
  resource_group_name  = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location

  network_security_group_id = azurerm_network_security_group.aks[0].id
  storage_account_id        = azurerm_storage_account.flow_logs[0].id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.flow_logs_retention_days
  }

  traffic_analytics {
    enabled               = var.enable_traffic_analytics
    workspace_id          = azurerm_log_analytics_workspace.main[0].workspace_id
    workspace_region      = azurerm_log_analytics_workspace.main[0].location
    workspace_resource_id = azurerm_log_analytics_workspace.main[0].id
    interval_in_minutes   = 10
  }

  tags = var.tags
}
