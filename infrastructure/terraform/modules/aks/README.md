# AKS Module

Provisions an Azure AKS cluster with Virtual Network, system/training/GPU node pools, PostgreSQL Flexible Server for MLflow metadata, Blob Storage for artifacts, Azure Key Vault, Azure Container Registry, Workload Identities, NSG Flow Logs with Traffic Analytics, and Azure Monitor integration.

## Usage

```hcl
module "aks" {
  source = "../../modules/aks"

  cluster_name       = "mlops-platform-dev"
  environment        = "dev"
  azure_location     = "northeurope"
  kubernetes_version = "1.29"

  tags = {
    Project    = "mlops-platform"
    managed_by = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the AKS cluster | `string` | n/a | yes |
| azure_location | Azure region for resources | `string` | `"westeurope"` | no |
| kubernetes_version | Kubernetes version for AKS | `string` | `"1.29"` | no |
| environment | Deployment environment | `string` | `"dev"` | no |
| tags | Tags to apply to all resources | `map(string)` | `{ project = "mlops-platform", managed_by = "terraform" }` | no |
| vnet_cidr | CIDR block for the virtual network | `string` | `"10.1.0.0/16"` | no |
| aks_subnet_cidr | CIDR block for the AKS subnet | `string` | `"10.1.0.0/18"` | no |
| postgresql_subnet_cidr | CIDR block for the PostgreSQL subnet | `string` | `"10.1.64.0/24"` | no |
| service_cidr | CIDR block for Kubernetes services | `string` | `"10.2.0.0/16"` | no |
| dns_service_ip | IP address for Kubernetes DNS service | `string` | `"10.2.0.10"` | no |
| api_server_authorized_ip_ranges | List of CIDR blocks authorized to access the AKS API server | `list(string)` | `[]` | no |
| keyvault_allowed_ip_ranges | List of IP addresses/CIDR blocks allowed to access Key Vault | `list(string)` | `[]` | no |
| system_vm_size | VM size for system node pool | `string` | `"Standard_D2s_v3"` | no |
| system_min_count | Minimum number of nodes in system pool | `number` | `2` | no |
| system_max_count | Maximum number of nodes in system pool | `number` | `4` | no |
| training_vm_size | VM size for training node pool | `string` | `"Standard_D8s_v3"` | no |
| training_min_count | Minimum number of nodes in training pool | `number` | `0` | no |
| training_max_count | Maximum number of nodes in training pool | `number` | `10` | no |
| gpu_vm_size | VM size for GPU node pool | `string` | `"Standard_NC6s_v3"` | no |
| gpu_min_count | Minimum number of nodes in GPU pool | `number` | `0` | no |
| gpu_max_count | Maximum number of nodes in GPU pool | `number` | `4` | no |
| gpu_use_spot | Use Spot instances for GPU node pool | `bool` | `true` | no |
| postgresql_sku | SKU for PostgreSQL Flexible Server | `string` | `"B_Standard_B1ms"` | no |
| postgresql_storage_mb | Storage size for PostgreSQL in MB | `number` | `32768` | no |
| postgresql_backup_retention_days | Backup retention period in days | `number` | `7` | no |
| postgresql_ha_enabled | Enable high availability for PostgreSQL | `bool` | `false` | no |
| acr_sku | SKU for Azure Container Registry | `string` | `"Basic"` | no |
| acr_georeplications | List of regions for ACR geo-replication (Premium SKU only) | `list(string)` | `[]` | no |
| enable_azure_monitor | Enable Azure Monitor integration | `bool` | `false` | no |
| log_retention_days | Number of days to retain logs in Log Analytics Workspace | `number` | `30` | no |
| enable_nsg_flow_logs | Enable NSG Flow Logs for network troubleshooting | `bool` | `true` | no |
| flow_logs_retention_days | Number of days to retain NSG Flow Logs | `number` | `30` | no |
| enable_traffic_analytics | Enable Traffic Analytics for NSG Flow Logs | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | Name of the AKS cluster |
| cluster_id | ID of the AKS cluster |
| cluster_endpoint | Endpoint for the AKS cluster API server |
| cluster_ca_certificate | Base64 encoded CA certificate for the cluster |
| client_certificate | Base64 encoded client certificate for admin access |
| client_key | Base64 encoded client key for admin access |
| oidc_issuer_url | OIDC issuer URL for Workload Identity |
| kubelet_identity_object_id | Object ID of the kubelet identity |
| configure_kubectl | Command to configure kubectl |
| resource_group_name | Name of the resource group |
| resource_group_location | Location of the resource group |
| vnet_id | ID of the virtual network |
| aks_subnet_id | ID of the AKS subnet |
| storage_account_name | Name of the MLflow storage account |
| storage_account_primary_blob_endpoint | Primary blob endpoint for the storage account |
| mlflow_artifacts_container | Name of the MLflow artifacts container |
| loki_blob_container | Name of the Loki logs container |
| tempo_blob_container | Name of the Tempo traces container |
| key_vault_id | ID of the Key Vault |
| key_vault_uri | URI of the Key Vault |
| key_vault_name | Name of the Key Vault |
| postgresql_fqdn | FQDN of the PostgreSQL server |
| postgresql_database_name | Name of the MLflow database |
| postgresql_admin_login | Admin username for PostgreSQL |
| acr_login_server | Login server for the Azure Container Registry |
| acr_id | ID of the Azure Container Registry |
| mlflow_identity_client_id | Client ID of the MLflow managed identity |
| external_secrets_identity_client_id | Client ID of the External Secrets managed identity |
| argo_workflows_identity_client_id | Client ID of the Argo Workflows managed identity |
| keda_identity_client_id | Client ID of the KEDA managed identity |
| loki_identity_client_id | Client ID of the Loki managed identity |
| tempo_identity_client_id | Client ID of the Tempo managed identity |
| tenant_id | Azure AD tenant ID |
| subscription_id | Azure subscription ID |
