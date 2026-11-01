# Deployment Scripts

Shell scripts for deploying and destroying the MLOps platform infrastructure.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `deploy-aws.sh` | Deploy MLOps platform to AWS EKS |
| `destroy-aws.sh` | Tear down AWS infrastructure |

## Prerequisites

All scripts check for required tools before running:

| Cloud | Required Tools |
|-------|---------------|
| AWS | `aws`, `terraform`, `kubectl`, `helm` |

## Usage

### Deploy

```bash
# AWS
./scripts/deploy-aws.sh
```

### Destroy

**Warning**: Destroy scripts will delete all infrastructure including data!

```bash
# AWS - prompts for confirmation
./scripts/destroy-aws.sh
```

Type `destroy` when prompted to confirm.

## What the Scripts Do

### Deploy Scripts

1. **Prerequisite Checks**
   - Verify required CLI tools are installed
   - Check cloud authentication
   - Validate environment variables

2. **Terraform Execution**
   - Initialize Terraform
   - Run `terraform plan`
   - Apply infrastructure changes

3. **Kubernetes Configuration**
   - Configure kubectl context
   - Wait for cluster to be ready

4. **Post-Deployment**
   - Display access information
   - Show port-forward commands

### Destroy Scripts

1. **Confirmation**
   - Require explicit "destroy" confirmation

2. **Kubernetes Cleanup**
   - Remove webhooks that can block deletion
   - Delete Kyverno policies
   - Remove LoadBalancer services

3. **Terraform Destroy**
   - Run `terraform destroy -auto-approve`

4. **Orphan Cleanup**
   - Delete orphaned cloud resources (disks, IPs, etc.)

5. **Verification**
   - Confirm resources are deleted

## Environment Variables

Scripts use these environment variables (with sensible defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `mlops-platform-dev` | Kubernetes cluster name |
| `AWS_REGION` | `eu-west-1` | AWS region |

## Troubleshooting

### Script Fails on Prerequisites

Ensure you're authenticated to the cloud provider:

```bash
# AWS
aws sts get-caller-identity
```

### Terraform State Issues

If Terraform state is corrupted, you may need to:
1. Back up the state file
2. Remove problematic resources from state
3. Re-import or recreate resources

### Destroy Hangs

If destroy hangs on a resource:
1. Check for finalizers on Kubernetes resources
2. Manually delete blocking resources
3. Re-run the destroy script