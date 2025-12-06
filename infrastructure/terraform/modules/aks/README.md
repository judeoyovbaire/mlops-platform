# AKS Module (Coming Soon)

This module will deploy the MLOps platform on Azure Kubernetes Service (AKS).

## Architecture Mapping: AWS EKS → Azure AKS

| AWS Component | Azure Equivalent | Notes |
|---------------|------------------|-------|
| EKS | AKS | Azure-managed Kubernetes |
| VPC | Virtual Network (VNet) | Similar concepts |
| NAT Gateway | NAT Gateway | Required for private node egress |
| ALB | Azure Application Gateway | Or use Azure Load Balancer |
| S3 | Azure Blob Storage | For MLflow artifacts |
| RDS PostgreSQL | Azure Database for PostgreSQL | Flexible Server recommended |
| IAM Roles (IRSA) | Workload Identity | AKS pod-level Azure AD integration |
| EBS CSI | Azure Disk CSI | Built into AKS |

## Key Differences from AWS

### Networking
- Azure uses **VNet** with subnets, similar to AWS VPC
- **Private Link** for private access to Azure services
- **Azure CNI** vs **Kubenet** networking modes
- Consider **Azure CNI Overlay** for large clusters (IP conservation)

### GPU Support
- Use **NC-series** (NVIDIA T4), **ND-series** (A100), or **NV-series** VMs
- **NVIDIA GPU Operator** or AKS GPU node pools
- Spot VMs available for cost optimization

### Authentication
- **AKS Workload Identity** (successor to AAD Pod Identity)
- Integrates with Azure Active Directory
- Required for secure access to Blob Storage, PostgreSQL, etc.

### Cost Optimization
- **Spot VMs** for training nodes (up to 90% savings)
- **Azure Reserved Instances** for sustained workloads
- **Cluster autoscaler** with scale-to-zero
- **AKS Free tier** available for dev clusters

## Planned Implementation

```hcl
# infrastructure/terraform/modules/aks/main.tf (planned)

module "aks" {
  source  = "Azure/aks/azurerm"
  version = "~> 9.0"

  resource_group_name = var.resource_group_name
  cluster_name        = var.cluster_name
  location            = var.location

  # Kubernetes version
  kubernetes_version  = "1.29"

  # Network configuration
  vnet_subnet_id      = module.vnet.subnet_ids["aks"]
  network_plugin      = "azure"
  network_policy      = "calico"

  # Default node pool
  default_node_pool = {
    name                = "general"
    vm_size             = "Standard_D4s_v3"
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 4
  }

  # Additional node pools
  node_pools = {
    training = {
      vm_size             = "Standard_F8s_v2"
      enable_auto_scaling = true
      min_count           = 0
      max_count           = 5
      priority            = "Spot"
      eviction_policy     = "Delete"
      spot_max_price      = -1
      node_labels = {
        "role" = "training"
      }
    }
    gpu = {
      vm_size             = "Standard_NC6s_v3"  # NVIDIA V100
      enable_auto_scaling = true
      min_count           = 0
      max_count           = 2
      priority            = "Spot"
      node_taints         = ["nvidia.com/gpu=true:NoSchedule"]
    }
  }

  # Workload Identity
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
}

# Workload Identity for MLflow
resource "azurerm_user_assigned_identity" "mlflow" {
  name                = "${var.cluster_name}-mlflow"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_federated_identity_credential" "mlflow" {
  name                = "mlflow-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.mlflow.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:mlflow:mlflow"
}

# Azure Database for PostgreSQL (Flexible Server)
resource "azurerm_postgresql_flexible_server" "mlflow" {
  name                   = "${var.cluster_name}-mlflow"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "15"
  sku_name               = "B_Standard_B1ms"  # Dev tier
  storage_mb             = 32768
  backup_retention_days  = 7
}

# Azure Blob Storage for artifacts
resource "azurerm_storage_account" "mlflow" {
  name                     = "${replace(var.cluster_name, "-", "")}mlflow"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "artifacts" {
  name                  = "mlflow-artifacts"
  storage_account_name  = azurerm_storage_account.mlflow.name
  container_access_type = "private"
}
```

## Helm Values for Azure

Key differences in Helm configurations:

```yaml
# infrastructure/helm/azure/mlflow-values.yaml (planned)
artifactRoot:
  azureBlob:
    enabled: true
    connectionString: "${storage_connection_string}"
    container: "mlflow-artifacts"

# Use Workload Identity
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "${mlflow_client_id}"

podLabels:
  azure.workload.identity/use: "true"
```

## Azure-Specific Features

### Azure Machine Learning Integration
Consider integrating with Azure ML for:
- **Managed endpoints** as alternative to KServe
- **Azure ML Pipelines** alongside Kubeflow
- **Prompt Flow** for LLM orchestration

### Azure Container Registry (ACR)
```hcl
resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.cluster_name, "-", "")}acr"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
}

# Attach ACR to AKS
resource "azurerm_role_assignment" "aks_acr" {
  principal_id         = module.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}
```

## Timeline

This module is planned for Phase 2 of the multi-cloud expansion. Priority is given to GCP GKE first due to market demand, followed by Azure AKS.

## Contributing

Contributions welcome! If you'd like to help implement this module, please open an issue to discuss the approach.