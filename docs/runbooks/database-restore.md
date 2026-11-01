# Database Restore Procedures

This runbook provides step-by-step procedures for restoring MLflow database backups on AWS.

## Prerequisites

- AWS CLI installed and authenticated
- Appropriate IAM permissions for database restore operations
- Backup verification completed (run `scripts/backup/verify-backups.sh`)

## AWS RDS Restore

### From Automated Backup (Point-in-Time Recovery)

```bash
# Restore to a specific point in time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier mlops-platform-dev-mlflow \
  --target-db-instance-identifier mlops-platform-dev-mlflow-restored \
  --restore-time 2024-01-15T10:00:00Z \
  --db-instance-class db.t3.small

# Wait for restore to complete
aws rds wait db-instance-available \
  --db-instance-identifier mlops-platform-dev-mlflow-restored

# Update MLflow to use restored database
kubectl set env deployment/mlflow \
  -n mlflow \
  MLFLOW_BACKEND_STORE_URI="postgresql://mlflow:${PASSWORD}@mlops-platform-dev-mlflow-restored.xxxxx.rds.amazonaws.com:5432/mlflow"
```

### From Manual Snapshot

```bash
# List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier mlops-platform-dev-mlflow \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier mlops-platform-dev-mlflow-restored \
  --db-snapshot-identifier mlops-platform-dev-mlflow-snapshot-20240115

# Wait for restore
aws rds wait db-instance-available \
  --db-instance-identifier mlops-platform-dev-mlflow-restored
```

### From AWS Backup

```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name mlops-platform-dev-mlops-backup-vault \
  --resource-arn arn:aws:rds:region:account:db:mlops-platform-dev-mlflow

# Restore from recovery point
aws backup start-restore-job \
  --recovery-point-arn arn:aws:rds:region:account:snapshot:recovery-point-id \
  --iam-role-arn arn:aws:iam::account:role/backup-role \
  --resource-type RDS \
  --metadata dbInstanceIdentifier=mlops-platform-dev-mlflow-restored
```

## Post-Restore Steps

1. **Verify database connectivity:**
   ```bash
   kubectl exec -n mlflow deployment/mlflow -- \
     psql "${MLFLOW_BACKEND_STORE_URI}" -c "SELECT COUNT(*) FROM experiments;"
   ```

2. **Verify MLflow UI:**
   ```bash
   kubectl port-forward -n mlflow svc/mlflow 5000:5000
   # Open http://localhost:5000 and verify experiments/models are visible
   ```

3. **Test model serving:**
   ```bash
   # Verify KServe can access models from restored MLflow
   kubectl get inferenceservice -n mlops
   ```

4. **Update DNS/Service endpoints** (if using restored instance permanently)

5. **Clean up temporary restored instance** (after verification)

## Recovery Time Objectives (RTO)

| Cloud Provider | RTO Target | Actual Capability |
|----------------|------------|-------------------|
| AWS RDS | < 15 minutes | 5-10 minutes (automated), 10-30 minutes (manual) |

## Recovery Point Objectives (RPO)

| Cloud Provider | RPO Target | Actual Capability |
|----------------|------------|-------------------|
| AWS RDS | < 5 minutes | 1-5 minutes (point-in-time recovery) |

## Testing Restores

Run restore tests quarterly:

```bash
# Check backup configuration and recent recovery points
./scripts/backup/verify-backups.sh aws dev
```

Then exercise a real restore with the point-in-time steps above against a
scratch instance identifier, verify MLflow can read it, and delete the
scratch instance.

## Troubleshooting

### Restore Fails with "Insufficient Storage"

- Check available storage quota
- Increase disk size before restore
- Clean up old backups if needed

### Restore Takes Too Long

- Large databases (>100GB) may take 30-60 minutes
- Use read replicas for faster access during restore
- Consider database optimization before restore

### Connection Issues After Restore

- Verify security group/firewall rules
- Check DNS resolution
- Verify credentials in Kubernetes secrets
