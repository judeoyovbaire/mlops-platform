# =============================================================================
# Auto-generated Secrets - Stored in Azure Key Vault
# =============================================================================

# =============================================================================
# Random Passwords
# =============================================================================

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "random_password" "argocd_admin" {
  length  = 24
  special = false
}

# =============================================================================
# Wait for RBAC propagation
# =============================================================================

# Azure RBAC assignments can take up to 10 minutes to propagate
# Wait before creating secrets to ensure permissions are available
resource "time_sleep" "wait_for_keyvault_rbac" {
  depends_on = [module.aks]

  create_duration = "60s"
}

# =============================================================================
# Store Secrets in Key Vault
# =============================================================================

resource "azurerm_key_vault_secret" "grafana_admin" {
  name         = "grafana-admin-password"
  value        = random_password.grafana_admin.result
  key_vault_id = module.aks.key_vault_id

  depends_on = [time_sleep.wait_for_keyvault_rbac]
}

resource "azurerm_key_vault_secret" "argocd_admin" {
  name         = "argocd-admin-password"
  value        = random_password.argocd_admin.result
  key_vault_id = module.aks.key_vault_id

  depends_on = [time_sleep.wait_for_keyvault_rbac]
}

resource "azurerm_key_vault_secret" "minio_root" {
  name         = "minio-root-password"
  value        = random_password.minio.result
  key_vault_id = module.aks.key_vault_id

  depends_on = [time_sleep.wait_for_keyvault_rbac]
}