# Azure Storage Resources - Data Services for MLOps Platform
# Creates: Storage Account, Key Vault, PostgreSQL Flexible Server, ACR

# Storage Account for MLflow Artifacts
resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "mlflow" {
  # Azure storage account names: 3-24 chars, lowercase + numbers only
  name                     = "mlops${random_string.storage_suffix.result}mlf"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # Use GRS for production
  min_tls_version          = "TLS1_2"

  # Enable blob versioning for model artifacts
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  # Block public access
  public_network_access_enabled   = true # Required for AKS access
  allow_nested_items_to_be_public = false

  tags = var.tags
}

resource "azurerm_storage_container" "mlflow_artifacts" {
  name                  = "mlflow-artifacts"
  storage_account_name  = azurerm_storage_account.mlflow.name
  container_access_type = "private"
}

# Azure Key Vault
resource "azurerm_key_vault" "main" {
  # Azure Key Vault names: 3-24 chars, alphanumeric and dashes only
  name                = "mlops-kv-${random_string.storage_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Use RBAC for access control (recommended)
  enable_rbac_authorization = true

  # Soft delete protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Set true for production

  # Network rules - allow AKS access
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# Allow current user to manage secrets during setup
resource "azurerm_role_assignment" "keyvault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgresql" {
  name                = "${var.cluster_name}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = "postgresql-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}

# Azure Database for PostgreSQL Flexible Server
resource "random_password" "postgresql" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_postgresql_flexible_server" "mlflow" {
  name                   = "${var.cluster_name}-mlflow-pg"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "15"
  delegated_subnet_id    = azurerm_subnet.postgresql.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgresql.id
  administrator_login    = "mlflow"
  administrator_password = random_password.postgresql.result
  zone                   = "1"
  storage_mb             = var.postgresql_storage_mb
  sku_name               = var.postgresql_sku

  # Disable public access when using VNet integration
  public_network_access_enabled = false

  backup_retention_days        = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled = false # Enable for production

  # High availability (optional, increases cost)
  dynamic "high_availability" {
    for_each = var.postgresql_ha_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

resource "azurerm_postgresql_flexible_server_database" "mlflow" {
  name      = "mlflow"
  server_id = azurerm_postgresql_flexible_server.mlflow.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Allow non-SSL connections from VNet (MLflow chart doesn't support sslmode config)
resource "azurerm_postgresql_flexible_server_configuration" "ssl_off" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.mlflow.id
  value     = "OFF"
}

# Store PostgreSQL credentials in Key Vault
resource "azurerm_key_vault_secret" "postgresql_username" {
  name         = "mlflow-db-username"
  value        = azurerm_postgresql_flexible_server.mlflow.administrator_login
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

resource "azurerm_key_vault_secret" "postgresql_password" {
  name         = "mlflow-db-password"
  value        = random_password.postgresql.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.keyvault_admin]
}

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  # ACR names: 5-50 chars, alphanumeric only
  name                = "mlopsacr${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false

  # Geo-replication for Premium SKU
  dynamic "georeplications" {
    for_each = var.acr_sku == "Premium" ? var.acr_georeplications : []
    content {
      location                = georeplications.value
      zone_redundancy_enabled = true
    }
  }

  tags = var.tags
}

# Grant AKS pull access to ACR
resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}