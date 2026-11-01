# Deployment Scripts

Shell scripts for deploying and destroying the MLOps platform infrastructure.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `deploy-aws.sh` | Deploy MLOps platform to AWS EKS (`deploy`, `status`, `secrets`, `destroy`) |
| `destroy-aws.sh` | Tear down AWS infrastructure |
| `deploy-local.sh` | Deploy the stack to a local Kind cluster |
| `render-slos.sh` | Render the Sloth SLO sources to PrometheusRules (CI diffs the output) |
| `test-policies.sh` | Run the Kyverno policy tests in `tests/policies/` |
| `backup/verify-backups.sh` | Verify RDS and AWS Backup recovery points |
| `benchmark/llm_bench.py` | LLM serving benchmark against an OpenAI-compatible endpoint |
| `demo/` | Rollback demo tooling ([README](demo/README.md)) |
| `cost-optimization/` | Cost report generator and idle-resource scanner |

## Prerequisites

The AWS scripts check for `aws`, `terraform`, `kubectl` and `helm` before running.

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

Answer `yes` when prompted to confirm. `--force` (or `-f`) skips the prompts.

## What the Scripts Do

### Deploy Scripts

1. **Prerequisite Checks**
   - Verify required CLI tools are installed
   - Check cloud authentication

2. **Terraform Execution**
   - Create `terraform.tfvars` if missing
   - Initialize Terraform (uses `backend.conf` if present)
   - Run `terraform plan`
   - Apply infrastructure changes

3. **Kubernetes Configuration**
   - Configure kubectl context

4. **Post-Deployment**
   - Display access information
   - Show port-forward commands

### Destroy Script

See the [teardown runbook](../docs/runbooks/teardown.md) for the phase-by-phase procedure.

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