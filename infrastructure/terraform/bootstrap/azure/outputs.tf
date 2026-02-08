# Azure Bootstrap Outputs

output "resource_group_name" {
  description = "Name of the bootstrap resource group"
  value       = azurerm_resource_group.bootstrap.name
}

output "storage_account_name" {
  description = "Name of the Terraform state storage account"
  value       = azurerm_storage_account.tfstate.name
}

output "storage_container_name" {
  description = "Name of the Terraform state container"
  value       = azurerm_storage_container.tfstate.name
}

output "client_id" {
  description = "Azure AD Application (client) ID for GitHub Actions"
  value       = azuread_application.github_actions.client_id
}

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_subscription.current.subscription_id
}

output "github_secrets" {
  description = "GitHub secrets to configure for Azure OIDC"
  value       = <<-EOT
    Add these secrets to your GitHub repository:

    AZURE_CLIENT_ID: ${azuread_application.github_actions.client_id}
    AZURE_TENANT_ID: ${data.azurerm_client_config.current.tenant_id}
    AZURE_SUBSCRIPTION_ID: ${data.azurerm_subscription.current.subscription_id}
  EOT
}

output "backend_config" {
  description = "Terraform backend configuration for Azure environments"
  value       = <<-EOT
    Add this backend configuration to your Azure environment providers.tf:

    backend "azurerm" {
      resource_group_name  = "${azurerm_resource_group.bootstrap.name}"
      storage_account_name = "${azurerm_storage_account.tfstate.name}"
      container_name       = "${azurerm_storage_container.tfstate.name}"
      key                  = "mlops-platform/azure/dev/terraform.tfstate"
    }
  EOT
}
