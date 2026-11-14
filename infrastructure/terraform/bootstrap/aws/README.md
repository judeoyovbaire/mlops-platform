# Terraform Bootstrap

This module creates the foundational AWS resources required **before** deploying the main MLOps platform.

## What It Creates

| Resource | Purpose |
|----------|---------|
| S3 Bucket | Terraform state storage with versioning and encryption |
| KMS Key | Customer-managed key for state encryption |
| DynamoDB Table | State locking to prevent concurrent modifications |
| GitHub OIDC Provider | Allows GitHub Actions to authenticate without static credentials |
| IAM Role | Permissions for GitHub Actions to deploy infrastructure |
| EC2 Spot service-linked role | Required for Spot launches; Karpenter cannot create it |

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.7 (CI uses 1.17.1)

## Usage

### 1. Initialize and Apply

```bash
cd infrastructure/terraform/bootstrap/aws
terraform init -backend-config=...   # partial S3 backend; flags in the comment in main.tf
terraform plan
terraform apply
```

The bootstrap state lives in the bucket it creates. For the first-ever creation in a fresh account, comment out `backend "s3" {}`, apply with local state, restore the block and re-init with `-migrate-state` (see `main.tf`).

`imports.tf` adopts resources that already exist in the author's account (183590992229). In any other account, delete it before the first plan, or the import blocks fail with "Cannot import non-existent remote object".

### 2. Note the Outputs

After applying, Terraform will output:
- `terraform_state_bucket` - S3 bucket name for state
- `terraform_locks_table` - DynamoDB table for locking
- `github_actions_role_arn` - IAM role ARN for CI/CD
- `backend_config` - Ready-to-use backend configuration

### 3. Update Dev Environment

`environments/aws/dev/providers.tf` uses a partial backend (`backend "s3" {}`). Create `environments/aws/dev/backend.conf` from `backend.conf.example` using the outputs:

```hcl
bucket         = "mlops-platform-tfstate-<account-id>"
key            = "mlops-platform/dev/terraform.tfstate"
region         = "eu-west-1"
encrypt        = true
dynamodb_table = "mlops-platform-terraform-locks"
```

Then initialize with `terraform init -backend-config=backend.conf`.

### 4. Migrate Existing State (if applicable)

If you have existing local state:

```bash
cd infrastructure/terraform/environments/aws/dev
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

- **S3 Encryption**: SSE-KMS with a customer-managed key, bucket key enabled, SSE-C blocked
- **S3 Versioning**: Noncurrent versions move to STANDARD_IA at 30 days and expire at 90
- **Public Access Blocked**: No public access to state bucket
- **OIDC Authentication**: No static AWS credentials in GitHub
- **Least Privilege**: IAM role scoped to required permissions only
- **State Locking**: DynamoDB prevents concurrent modifications

The OIDC trust `sub` is bound to `repo:judeoyovbaire/mlops-platform` (`var.github_org`, `var.github_repo`). The repository rename (JDH-411) must update it in the same change, or CI cannot assume the role.

## Cost

Minimal - approximately $2-3/month:
- KMS key: ~$1/month
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
