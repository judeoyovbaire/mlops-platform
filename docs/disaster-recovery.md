# Disaster Recovery Guide

This document outlines disaster recovery procedures for the MLOps Platform.

## Recovery Objectives

| Metric | Target | Description |
|--------|--------|-------------|
| **RTO** (Recovery Time Objective) | 1 hour | Maximum acceptable downtime |
| **RPO** (Recovery Point Objective) | 15 minutes | Maximum acceptable data loss |

## Critical Components

| Component | Data Criticality | Backup Strategy | Recovery Priority |
|-----------|-----------------|-----------------|-------------------|
| MLflow RDS | High | Automated snapshots | P1 |
| S3 Artifacts | High | Versioning + Cross-region | P1 |
| Terraform State | Critical | S3 versioning | P0 |
| EKS Cluster | Medium | Recreate from Terraform | P2 |
| Kubernetes Manifests | Low | Git repository | P3 |

## Backup Configuration

### RDS Automated Backups

Configured in Terraform:
```hcl
backup_retention_period = 7  # days
backup_window          = "03:00-04:00"  # UTC
```

**Manual Snapshot:**
```bash
aws rds create-db-snapshot \
  --db-instance-identifier mlops-platform-dev-mlflow \
  --db-snapshot-identifier mlops-manual-$(date +%Y%m%d-%H%M%S)
```

### S3 Artifact Versioning

S3 versioning is enabled for all artifact buckets. To list versions:
```bash
aws s3api list-object-versions \
  --bucket mlops-platform-dev-mlflow-artifacts-<account-id> \
  --prefix experiments/
```

### Terraform State

State is stored in S3 with:
- Versioning enabled
- 90-day version retention
- DynamoDB locking

## Disaster Scenarios

### Scenario 1: RDS Database Corruption/Loss

**Symptoms:**
- MLflow returns database errors
- Experiment history unavailable
- Model registry empty

**Recovery Steps:**

1. **Identify last good snapshot:**
   ```bash
   aws rds describe-db-snapshots \
     --db-instance-identifier mlops-platform-dev-mlflow \
     --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Time:SnapshotCreateTime,Status:Status}' \
     --output table
   ```

2. **Restore to new instance:**
   ```bash
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier mlops-platform-dev-mlflow-restored \
     --db-snapshot-identifier <snapshot-id> \
     --db-subnet-group-name mlops-platform-dev-mlflow \
     --vpc-security-group-ids <sg-id>
   ```

3. **Wait for restoration:**
   ```bash
   aws rds wait db-instance-available \
     --db-instance-identifier mlops-platform-dev-mlflow-restored
   ```

4. **Update MLflow configuration:**
   - Update Kubernetes secret with new endpoint
   - Restart MLflow deployment

5. **Verify data integrity:**
   ```bash
   # Connect to restored database
   psql -h <new-endpoint> -U mlflow -d mlflow -c "SELECT COUNT(*) FROM experiments;"
   ```

6. **Swap endpoints:**
   - Delete original instance (after verification)
   - Rename restored instance to original name

**Estimated Recovery Time:** 30-45 minutes

### Scenario 2: S3 Artifact Bucket Deletion

**Symptoms:**
- Model artifacts unavailable
- Training pipeline failures
- Drift detection reports missing

**Recovery Steps:**

1. **If bucket exists but objects deleted:**
   ```bash
   # List deleted objects
   aws s3api list-object-versions \
     --bucket mlops-platform-dev-mlflow-artifacts-<account-id> \
     --query 'DeleteMarkers[*].{Key:Key,VersionId:VersionId}'

   # Restore specific object
   aws s3api delete-object \
     --bucket mlops-platform-dev-mlflow-artifacts-<account-id> \
     --key <object-key> \
     --version-id <delete-marker-version-id>
   ```

2. **If bucket deleted:**
   - Restore from cross-region replica (if configured)
   - Or recreate from Terraform and restore from last backup

3. **Bulk restore script:**
   ```bash
   # Restore all deleted objects from last 24 hours
   aws s3api list-object-versions \
     --bucket mlops-platform-dev-mlflow-artifacts-<account-id> \
     --query "DeleteMarkers[?LastModified>='$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)']" \
     | jq -r '.[] | "\(.Key) \(.VersionId)"' \
     | while read key vid; do
         aws s3api delete-object --bucket $BUCKET --key "$key" --version-id "$vid"
       done
   ```

**Estimated Recovery Time:** 15-30 minutes

### Scenario 3: EKS Cluster Failure

**Symptoms:**
- kubectl commands fail
- All workloads unavailable
- Control plane unreachable

**Recovery Steps:**

1. **Check AWS EKS console** for cluster status

2. **If control plane issue:**
   - AWS typically auto-recovers control plane
   - Wait 15-30 minutes for AWS recovery

3. **If complete cluster loss:**

   a. **Ensure Terraform state is available:**
   ```bash
   cd infrastructure/terraform/environments/dev
   terraform init
   terraform plan  # Verify state
   ```

   b. **Recreate cluster:**
   ```bash
   terraform apply -target=module.eks
   ```

   c. **Restore node groups:**
   ```bash
   terraform apply
   ```

   d. **Verify cluster:**
   ```bash
   aws eks update-kubeconfig --name mlops-platform-dev --region eu-west-1
   kubectl get nodes
   ```

   e. **Redeploy workloads:**
   ```bash
   kubectl apply -k infrastructure/kubernetes/
   kubectl apply -f components/kserve/
   ```

**Estimated Recovery Time:** 45-60 minutes

### Scenario 4: Terraform State Corruption

**Symptoms:**
- `terraform plan` shows unexpected changes
- State file errors
- Resource drift detection fails

**Recovery Steps:**

1. **List state versions:**
   ```bash
   aws s3api list-object-versions \
     --bucket mlops-platform-tfstate-<account-id> \
     --prefix mlops-platform/dev/terraform.tfstate \
     --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified,Size:Size}' \
     --output table
   ```

2. **Download previous version:**
   ```bash
   aws s3api get-object \
     --bucket mlops-platform-tfstate-<account-id> \
     --key mlops-platform/dev/terraform.tfstate \
     --version-id <version-id> \
     terraform.tfstate.backup
   ```

3. **Verify backup state:**
   ```bash
   terraform show terraform.tfstate.backup
   ```

4. **Restore state:**
   ```bash
   # Upload restored state
   aws s3 cp terraform.tfstate.backup \
     s3://mlops-platform-tfstate-<account-id>/mlops-platform/dev/terraform.tfstate
   ```

5. **Verify restoration:**
   ```bash
   terraform init -reconfigure
   terraform plan
   ```

**Estimated Recovery Time:** 15-30 minutes

## Post-Recovery Checklist

- [ ] Verify MLflow UI accessible
- [ ] Run sample training pipeline
- [ ] Check model registry contents
- [ ] Verify inference endpoints responding
- [ ] Review monitoring dashboards
- [ ] Check all alerts cleared
- [ ] Document incident and root cause
- [ ] Update runbooks if needed

## Testing Disaster Recovery

### Monthly DR Drill

1. **Database Recovery Test:**
   - Create manual snapshot
   - Restore to test instance
   - Verify data integrity
   - Delete test instance

2. **S3 Recovery Test:**
   - Delete test object
   - Restore from version
   - Verify object content

3. **Document Results:**
   - Actual recovery time
   - Issues encountered
   - Process improvements

### Quarterly Full DR Test

1. Deploy complete stack to DR region
2. Restore all data
3. Run full test suite
4. Document findings
5. Update recovery procedures

## Emergency Contacts

| Role | Contact | Escalation Time |
|------|---------|-----------------|
| On-Call Engineer | PagerDuty | Immediate |
| Platform Lead | Slack #mlops-platform | 15 minutes |
| AWS Support | Support Console | 30 minutes |

## Related Documents

- [Runbooks](runbooks/README.md)
- [Architecture](architecture.md)
