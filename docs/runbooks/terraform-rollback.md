# Terraform Rollback Procedures

This runbook covers procedures for rolling back Terraform-managed infrastructure changes.

## Overview

Terraform rollbacks can be performed in several ways depending on the situation:

1. **Targeted Resource Rollback** - Revert specific resources
2. **State-Based Rollback** - Restore from a previous state file
3. **Git-Based Rollback** - Revert to a previous code version
4. **Emergency Procedures** - For critical production issues

## Prerequisites

- Terraform CLI installed (matching version in CI/CD)
- Cloud provider credentials configured
- Access to state backend (S3/Azure Storage/GCS)
- Git access to the repository

## 1. Targeted Resource Rollback

Use when a specific resource needs to be reverted without affecting other infrastructure.

### Identify Changed Resources

```bash
# Show recent state changes
terraform show

# List all resources in state
terraform state list

# Show specific resource details
terraform state show <resource_address>
```

### Rollback Specific Resource

```bash
# Option 1: Taint and recreate
terraform taint <resource_address>
terraform apply

# Option 2: Import from backup/existing infrastructure
terraform import <resource_address> <resource_id>

# Option 3: Remove from state and re-apply
terraform state rm <resource_address>
terraform apply
```

## 2. State-Based Rollback

Use when you have a backup of the previous state file.

### Locate State Backup

CI/CD automatically backs up state before each apply. Find backups:

```bash
# AWS S3
aws s3 ls s3://<bucket>/mlops-platform/<env>/backups/

# Azure Storage
az storage blob list --container-name tfstate --prefix "backups/"

# GCP GCS
gsutil ls gs://<bucket>/mlops-platform/<env>/backups/
```

### Restore Previous State

```bash
# Download backup state
aws s3 cp s3://<bucket>/mlops-platform/<env>/backups/terraform.tfstate.backup ./terraform.tfstate

# Push restored state (CAUTION: This overwrites current state)
terraform state push terraform.tfstate

# Verify state
terraform plan
```

## 3. Git-Based Rollback

Use when configuration changes need to be reverted.

### Identify Commit to Revert

```bash
# View recent commits affecting infrastructure
git log --oneline -- infrastructure/terraform/

# Show changes in a specific commit
git show <commit_hash> -- infrastructure/terraform/
```

### Revert Configuration

```bash
# Option 1: Revert a specific commit
git revert <commit_hash>

# Option 2: Reset to a previous commit (for local branches)
git reset --hard <commit_hash>

# Option 3: Checkout specific files from a previous commit
git checkout <commit_hash> -- infrastructure/terraform/environments/<cloud>/<env>/
```

### Apply Reverted Configuration

```bash
cd infrastructure/terraform/environments/<cloud>/<env>
terraform init
terraform plan  # Review changes
terraform apply
```

## 4. Emergency Procedures

For critical production issues requiring immediate action.

### Immediate Mitigation

```bash
# 1. Stop any running Terraform operations
# Kill the process or wait for lock timeout

# 2. Lock the state to prevent concurrent changes
terraform force-unlock <lock_id>  # Only if orphaned lock

# 3. Review current state
terraform refresh
terraform plan
```

### Emergency Rollback Steps

1. **Assess Impact**
   ```bash
   terraform plan -detailed-exitcode
   # Exit code 0 = No changes
   # Exit code 1 = Error
   # Exit code 2 = Changes pending
   ```

2. **Backup Current State**
   ```bash
   terraform state pull > emergency_backup_$(date +%Y%m%d_%H%M%S).tfstate
   ```

3. **Apply Previous Known-Good State**
   ```bash
   # From CI/CD artifacts or manual backup
   terraform state push <known_good_state_file>
   terraform apply -auto-approve
   ```

4. **Verify Services**
   ```bash
   # Check cluster health
   kubectl get nodes
   kubectl get pods -A | grep -v Running

   # Check critical services
   kubectl get svc -n mlflow
   kubectl get svc -n argocd
   ```

### Post-Incident Actions

1. Document the incident and root cause
2. Update runbooks if needed
3. Consider adding preventive measures (e.g., more restrictive plan reviews)

## Cloud-Specific Considerations

### AWS EKS

```bash
# Verify EKS cluster access
aws eks update-kubeconfig --name mlops-platform-<env> --region <region>
kubectl cluster-info
```

### Azure AKS

```bash
# Verify AKS cluster access
az aks get-credentials --resource-group mlops-platform-<env>-rg --name mlops-platform-<env>
kubectl cluster-info
```

### GCP GKE

```bash
# Verify GKE cluster access
gcloud container clusters get-credentials mlops-platform-<env> --zone <zone> --project <project>
kubectl cluster-info
```

## Prevention Best Practices

1. **Always run `terraform plan` before `apply`**
2. **Use CI/CD for all production changes**
3. **Enable state versioning in backend**
4. **Review plan output in PRs**
5. **Use `-target` flag sparingly**
6. **Test changes in dev environment first**

## Related Documents

- [CI/CD Pipeline Documentation](../../.github/workflows/ci-cd.yaml)
- [Infrastructure Architecture](../architecture/)
- [Disaster Recovery Plan](./disaster-recovery.md)