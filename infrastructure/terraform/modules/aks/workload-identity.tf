# Workload Identity - Azure equivalent of AWS IRSA
# Creates managed identities with federated credentials for K8s ServiceAccounts

# MLflow Identity
resource "azurerm_user_assigned_identity" "mlflow" {
  name                = "${var.cluster_name}-mlflow-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "mlflow" {
  name                = "mlflow-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.mlflow.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:mlflow:mlflow"
}

# MLflow can access Blob Storage
resource "azurerm_role_assignment" "mlflow_blob" {
  scope                = azurerm_storage_account.mlflow.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mlflow.principal_id
}

# External Secrets Identity
resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${var.cluster_name}-external-secrets-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name                = "external-secrets-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.external_secrets.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets"
}

# External Secrets can read Key Vault secrets
resource "azurerm_role_assignment" "external_secrets_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
}

# Argo Workflows Identity
resource "azurerm_user_assigned_identity" "argo_workflows" {
  name                = "${var.cluster_name}-argo-workflows-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "argo_workflows" {
  name                = "argo-workflows-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.argo_workflows.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:argo:argo-workflows-server"
}

# Argo Workflows can access Blob Storage (for artifacts)
resource "azurerm_role_assignment" "argo_workflows_blob" {
  scope                = azurerm_storage_account.mlflow.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.argo_workflows.principal_id
}

# KEDA Identity (for Azure-specific scalers)
resource "azurerm_user_assigned_identity" "keda" {
  name                = "${var.cluster_name}-keda-identity"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "keda" {
  name                = "keda-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.keda.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:keda:keda-operator"
}

# KEDA can read metrics from Azure Monitor (if enabled)
resource "azurerm_role_assignment" "keda_monitoring" {
  count                = var.enable_azure_monitor ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.keda.principal_id
}