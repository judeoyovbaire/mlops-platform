# Azure Terraform Bootstrap

This module creates the foundational Azure resources required **before** deploying the main MLOps platform.

## What It Creates

| Resource | Purpose |
|----------|---------|
| Resource Group | Container for bootstrap resources |
| Storage Account | Terraform state storage with GRS replication and versioning |
| Azure AD Application | Identity for GitHub Actions |
| Service Principal | Execution identity for deployments |
| Federated Credentials | OIDC authentication for GitHub Actions (no static secrets) |
| Role Assignments | Permissions for infrastructure deployment |

## Prerequisites

- Azure CLI configured (`az login`)
- Terraform 1.0+
- Permissions to create Azure AD applications and role assignments

## Usage

### 1. Initialize and Apply

```bash
cd infrastructure/terraform/bootstrap/azure
terraform init
terraform plan -var="github_org=your-org" -var="github_repo=your-repo"
terraform apply -var="github_org=your-org" -var="github_repo=your-repo"
```

### 2. Note the Outputs

After applying, Terraform will output:
- `storage_account_name` - Storage account for Terraform state
- `container_name` - Blob container for state files
- `client_id` - Azure AD Application Client ID
- `subscription_id` - Azure Subscription ID
- `tenant_id` - Azure AD Tenant ID

### 3. Update Dev Environment

Update `environments/azure/dev/providers.tf` with the backend configuration:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "mlops-platform-bootstrap"
    storage_account_name = "<storage_account_name>"
    container_name       = "tfstate"
    key                  = "mlops-platform/dev/terraform.tfstate"
  }
}
```

### 4. Add GitHub Secrets

Add the following to your GitHub repository secrets:
- `AZURE_CLIENT_ID` - The client_id output value
- `AZURE_SUBSCRIPTION_ID` - The subscription_id output value
- `AZURE_TENANT_ID` - The tenant_id output value

## GitHub Actions Configuration

The workflow uses OIDC authentication (no static credentials):

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

## Security Features

- **GRS Replication**: Geo-redundant storage for state protection
- **Blob Versioning**: All state versions retained for 30 days
- **Soft Delete**: 30-day retention for deleted blobs
- **OIDC Authentication**: No static Azure credentials in GitHub
- **Least Privilege**: Role assignments scoped to required permissions
- **TLS 1.2**: Minimum TLS version enforced

## Federated Credentials

Three federated credentials are created for different scenarios:
- `github-actions-main` - Deployments from main branch
- `github-actions-pr` - Pull request validation
- `github-actions-production` - Production environment deployments

## Cost

Minimal - approximately $1-3/month:
- Storage Account: Pay per GB stored (state files are tiny)
- GRS replication adds minimal cost for redundancy

## Destroying

**Warning**: Destroying this module will delete your Terraform state!

If you need to destroy:
1. First, destroy all infrastructure managed by this state
2. Run `terraform destroy` in this directory

```bash
terraform destroy -var="github_org=your-org" -var="github_repo=your-repo"
```