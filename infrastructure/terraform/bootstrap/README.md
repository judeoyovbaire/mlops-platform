# Terraform Bootstrap

This module creates the foundational AWS resources required **before** deploying the main MLOps platform.

## What It Creates

| Resource | Purpose |
|----------|---------|
| S3 Bucket | Terraform state storage with versioning and encryption |
| DynamoDB Table | State locking to prevent concurrent modifications |
| GitHub OIDC Provider | Allows GitHub Actions to authenticate without static credentials |
| IAM Role | Permissions for GitHub Actions to deploy infrastructure |

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform 1.0+

## Usage

### 1. Initialize and Apply

```bash
cd infrastructure/terraform/bootstrap
terraform init
terraform plan
terraform apply
```

### 2. Note the Outputs

After applying, Terraform will output:
- `terraform_state_bucket` - S3 bucket name for state
- `terraform_locks_table` - DynamoDB table for locking
- `github_actions_role_arn` - IAM role ARN for CI/CD
- `backend_config` - Ready-to-use backend configuration

### 3. Update Dev Environment

Copy the backend configuration from the output and update `environments/dev/main.tf`:

```hcl
terraform {
  # ... existing config ...

  backend "s3" {
    bucket         = "mlops-platform-tfstate-<account-id>"
    key            = "mlops-platform/dev/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "mlops-platform-terraform-locks"
  }
}
```

### 4. Migrate Existing State (if applicable)

If you have existing local state:

```bash
cd infrastructure/terraform/environments/dev
terraform init -migrate-state
```

### 5. Add GitHub Secrets

Add the following to your GitHub repository secrets:
- `AWS_ROLE_ARN` - The `github_actions_role_arn` output value

## GitHub Actions Configuration

The workflow should use OIDC authentication:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-west-1
```

## Security Features

- **S3 Encryption**: AES-256 server-side encryption enabled
- **S3 Versioning**: All state versions retained for 90 days
- **Public Access Blocked**: No public access to state bucket
- **OIDC Authentication**: No static AWS credentials in GitHub
- **Least Privilege**: IAM role scoped to required permissions only
- **State Locking**: DynamoDB prevents concurrent modifications

## Cost

Minimal - approximately $1-2/month:
- S3: Pay per GB stored (state files are tiny)
- DynamoDB: PAY_PER_REQUEST (minimal for state operations)

## Destroying

**Warning**: Destroying this module will delete your Terraform state!

If you need to destroy:
1. First, destroy all infrastructure managed by this state
2. Empty the S3 bucket manually
3. Run `terraform destroy` in this directory

```bash
# Empty bucket first
aws s3 rm s3://mlops-platform-tfstate-<account-id> --recursive

# Then destroy
terraform destroy
```