# GCP Terraform Bootstrap

This module creates the foundational GCP resources required **before** deploying the main MLOps platform.

## What It Creates

| Resource | Purpose |
|----------|---------|
| GCP Project | (Optional) New project for MLOps resources |
| GCS Bucket | Terraform state storage with versioning |
| Workload Identity Pool | OIDC authentication for GitHub Actions |
| Workload Identity Provider | GitHub Actions identity provider |
| Service Account | Execution identity for deployments |
| IAM Bindings | Permissions for infrastructure deployment |
| API Enablement | Required GCP APIs (GKE, Cloud SQL, etc.) |

## Prerequisites

- Google Cloud CLI configured (`gcloud auth login`)
- Terraform 1.0+
- Project Owner or sufficient permissions
- Billing account (if creating new project)

## Usage

### 1. Initialize and Apply

```bash
cd infrastructure/terraform/bootstrap/gcp

# Using existing project
terraform init
terraform plan \
  -var="project_id=your-project-id" \
  -var="github_org=your-org" \
  -var="github_repo=your-repo"

# Creating new project
terraform plan \
  -var="create_project=true" \
  -var="project_id=mlops-dev-12345" \
  -var="billing_account=XXXXX-XXXXX-XXXXX" \
  -var="github_org=your-org" \
  -var="github_repo=your-repo"
```

### 2. Note the Outputs

After applying, Terraform will output:
- `terraform_state_bucket` - GCS bucket for Terraform state
- `workload_identity_provider` - Full provider path for GitHub Actions
- `service_account_email` - Service account for deployments
- `project_id` - GCP Project ID

### 3. Update Dev Environment

Update `environments/gcp/dev/providers.tf` with the backend configuration:

```hcl
terraform {
  backend "gcs" {
    bucket = "<terraform_state_bucket>"
    prefix = "mlops-platform/dev"
  }
}
```

### 4. Add GitHub Secrets

Add the following to your GitHub repository secrets:
- `GCP_PROJECT_ID` - The project_id output value
- `GCP_WORKLOAD_IDENTITY_PROVIDER` - The workload_identity_provider output
- `GCP_SERVICE_ACCOUNT` - The service_account_email output

## GitHub Actions Configuration

The workflow uses Workload Identity Federation (no static credentials):

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

## Security Features

- **Bucket Versioning**: All state versions retained
- **Uniform Access**: Bucket-level IAM (no ACLs)
- **Lifecycle Rules**: Old versions cleaned up after 90 days
- **Workload Identity**: No static GCP credentials in GitHub
- **Least Privilege**: IAM roles scoped to required permissions
- **Attribute Condition**: Only your GitHub org can authenticate

## APIs Enabled

The bootstrap enables these APIs automatically:
- `container.googleapis.com` - GKE
- `compute.googleapis.com` - VPC, Compute Engine
- `sqladmin.googleapis.com` - Cloud SQL
- `secretmanager.googleapis.com` - Secret Manager
- `artifactregistry.googleapis.com` - Container Registry
- `servicenetworking.googleapis.com` - Private Service Access

## Cost

Minimal - approximately $1-2/month:
- GCS: Pay per GB stored (state files are tiny)
- Workload Identity: Free

## Destroying

**Warning**: Destroying this module will delete your Terraform state!

If you need to destroy:
1. First, destroy all infrastructure managed by this state
2. Run `terraform destroy` in this directory

```bash
terraform destroy \
  -var="project_id=your-project-id" \
  -var="github_org=your-org" \
  -var="github_repo=your-repo"
```