# Database Restore Procedures

This runbook provides step-by-step procedures for restoring MLflow database backups across AWS, Azure, and GCP.

## Prerequisites

- Cloud provider CLI tools installed and authenticated
- Appropriate IAM permissions for database restore operations
- Backup verification completed (run `scripts/backup/verify-backups.sh`)

## AWS RDS Restore

### From Automated Backup (Point-in-Time Recovery)

```bash
# Restore to a specific point in time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier mlops-platform-prod-mlflow \
  --target-db-instance-identifier mlops-platform-prod-mlflow-restored \
  --restore-time 2024-01-15T10:00:00Z \
  --db-instance-class db.t3.small

# Wait for restore to complete
aws rds wait db-instance-available \
  --db-instance-identifier mlops-platform-prod-mlflow-restored

# Update MLflow to use restored database
kubectl set env deployment/mlflow \
  -n mlflow \
  MLFLOW_BACKEND_STORE_URI="postgresql://mlflow:${PASSWORD}@mlops-platform-prod-mlflow-restored.xxxxx.rds.amazonaws.com:5432/mlflow"
```

### From Manual Snapshot

```bash
# List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier mlops-platform-prod-mlflow \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier mlops-platform-prod-mlflow-restored \
  --db-snapshot-identifier mlops-platform-prod-mlflow-snapshot-20240115

# Wait for restore
aws rds wait db-instance-available \
  --db-instance-identifier mlops-platform-prod-mlflow-restored
```

### From AWS Backup

```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name mlops-platform-prod-mlops-backup-vault \
  --resource-arn arn:aws:rds:region:account:db:mlops-platform-prod-mlflow

# Restore from recovery point
aws backup start-restore-job \
  --recovery-point-arn arn:aws:rds:region:account:snapshot:recovery-point-id \
  --iam-role-arn arn:aws:iam::account:role/backup-role \
  --resource-type RDS \
  --metadata dbInstanceIdentifier=mlops-platform-prod-mlflow-restored
```

## Azure PostgreSQL Restore

### From Point-in-Time Backup

```bash
RESOURCE_GROUP="mlops-platform-prod-rg"
SOURCE_SERVER="mlops-platform-prod-mlflow-pg"
TARGET_SERVER="mlops-platform-prod-mlflow-restored"
RESTORE_TIME="2024-01-15T10:00:00Z"

# Restore to point in time
az postgres flexible-server restore \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${TARGET_SERVER}" \
  --source-server "${SOURCE_SERVER}" \
  --restore-time "${RESTORE_TIME}"

# Wait for restore
az postgres flexible-server wait \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${TARGET_SERVER}" \
  --created

# Update MLflow connection string
kubectl set env deployment/mlflow \
  -n mlflow \
  MLFLOW_BACKEND_STORE_URI="postgresql://mlflow:${PASSWORD}@${TARGET_SERVER}.postgres.database.azure.com:5432/mlflow"
```

### From Backup

```bash
# List available backups
az postgres flexible-server backup list \
  --resource-group "${RESOURCE_GROUP}" \
  --server-name "${SOURCE_SERVER}"

# Restore from backup
az postgres flexible-server restore \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${TARGET_SERVER}" \
  --source-server "${SOURCE_SERVER}" \
  --backup-name "backup-name"
```

## GCP Cloud SQL Restore

### From Point-in-Time Backup

```bash
INSTANCE_NAME="mlops-platform-prod-mlflow-xxxx"
RESTORE_INSTANCE="mlops-platform-prod-mlflow-restored"
RESTORE_TIME="2024-01-15T10:00:00Z"

# Restore to point in time
gcloud sql backups restore "${BACKUP_ID}" \
  --backup-instance="${INSTANCE_NAME}" \
  --restore-instance="${RESTORE_INSTANCE}"

# Or restore to specific time
gcloud sql instances clone "${INSTANCE_NAME}" "${RESTORE_INSTANCE}" \
  --point-in-time="${RESTORE_TIME}"

# Wait for restore
gcloud sql operations wait \
  --project="${PROJECT_ID}" \
  $(gcloud sql operations list \
    --instance="${RESTORE_INSTANCE}" \
    --limit=1 \
    --format="value(name)")

# Update MLflow connection
kubectl set env deployment/mlflow \
  -n mlflow \
  MLFLOW_BACKEND_STORE_URI="postgresql://mlflow:${PASSWORD}@${RESTORE_INSTANCE_IP}:5432/mlflow"
```

### From Backup

```bash
# List backups
gcloud sql backups list \
  --instance="${INSTANCE_NAME}"

# Restore from backup
gcloud sql backups restore "${BACKUP_ID}" \
  --backup-instance="${INSTANCE_NAME}" \
  --restore-instance="${RESTORE_INSTANCE}"
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
| Azure PostgreSQL | < 20 minutes | 10-15 minutes (automated), 15-30 minutes (manual) |
| GCP Cloud SQL | < 15 minutes | 5-10 minutes (automated), 10-25 minutes (manual) |

## Recovery Point Objectives (RPO)

| Cloud Provider | RPO Target | Actual Capability |
|----------------|------------|-------------------|
| AWS RDS | < 5 minutes | 1-5 minutes (point-in-time recovery) |
| Azure PostgreSQL | < 5 minutes | 1-5 minutes (point-in-time recovery) |
| GCP Cloud SQL | < 5 minutes | 1-5 minutes (point-in-time recovery) |

## Testing Restores

Run restore tests quarterly:

```bash
# Create test restore
./scripts/backup/test-restore.sh aws prod

# Verify data integrity
./scripts/backup/verify-restore.sh aws prod

# Clean up test instance
./scripts/backup/cleanup-test-restore.sh aws prod
```

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
