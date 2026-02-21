#!/bin/bash
# Verify database backups across all cloud providers
# Usage: ./verify-backups.sh [aws|azure|gcp] [dev|prod]

set -euo pipefail

CLOUD="${1:-aws}"
ENV="${2:-dev}"
CLUSTER_NAME="mlops-platform-${ENV}"

echo "Verifying backups for ${CLOUD} ${ENV} environment..."

case "${CLOUD}" in
  aws)
    echo "Checking AWS RDS backups..."
    
    # Get RDS instance identifier
    DB_INSTANCE="${CLUSTER_NAME}-mlflow"
    
    # Check latest backup
    LATEST_BACKUP=$(aws rds describe-db-snapshots \
      --db-instance-identifier "${DB_INSTANCE}" \
      --query 'DBSnapshots[0].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
      --output text 2>/dev/null || echo "NONE")
    
    if [ "${LATEST_BACKUP}" = "NONE" ]; then
      echo "❌ No manual snapshots found"
    else
      echo "✅ Latest snapshot: ${LATEST_BACKUP}"
    fi
    
    # Check automated backups
    AUTOMATED_BACKUPS=$(aws rds describe-db-instances \
      --db-instance-identifier "${DB_INSTANCE}" \
      --query 'DBInstances[0].BackupRetentionPeriod' \
      --output text 2>/dev/null || echo "0")
    
    if [ "${AUTOMATED_BACKUPS}" -gt 0 ]; then
      echo "✅ Automated backups enabled (retention: ${AUTOMATED_BACKUPS} days)"
    else
      echo "⚠️  Automated backups not enabled"
    fi
    
    # Check AWS Backup (if enabled)
    BACKUP_PLAN=$(aws backup list-backup-plans \
      --query "BackupPlansList[?BackupPlanName=='${CLUSTER_NAME}-mlops-backup-plan'].BackupPlanId" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "${BACKUP_PLAN}" ]; then
      echo "✅ AWS Backup plan configured: ${BACKUP_PLAN}"
      
      # List recent backup jobs
      RECENT_JOBS=$(aws backup list-backup-jobs \
        --by-state COMPLETED \
        --max-results 5 \
        --query "BackupJobs[?ResourceArn=~'${DB_INSTANCE}'].{Id:BackupJobId,State:State,Completed:CompletionDate}" \
        --output table 2>/dev/null || echo "No recent jobs")
      
      echo "Recent backup jobs:"
      echo "${RECENT_JOBS}"
    else
      echo "⚠️  AWS Backup plan not found"
    fi
    ;;
    
  azure)
    echo "Checking Azure PostgreSQL backups..."
    
    RESOURCE_GROUP="${CLUSTER_NAME}-rg"
    DB_SERVER="${CLUSTER_NAME}-mlflow-pg"
    
    # Check backup retention
    BACKUP_RETENTION=$(az postgres flexible-server show \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${DB_SERVER}" \
      --query "backup.backupRetentionDays" \
      --output tsv 2>/dev/null || echo "0")
    
    if [ "${BACKUP_RETENTION}" -gt 0 ]; then
      echo "✅ Backup retention: ${BACKUP_RETENTION} days"
    else
      echo "⚠️  Backup retention not configured"
    fi
    
    # Check geo-redundant backup
    GEO_BACKUP=$(az postgres flexible-server show \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${DB_SERVER}" \
      --query "backup.geoRedundantBackup" \
      --output tsv 2>/dev/null || echo "Disabled")
    
    if [ "${GEO_BACKUP}" = "Enabled" ]; then
      echo "✅ Geo-redundant backup enabled"
    else
      echo "⚠️  Geo-redundant backup disabled"
    fi
    
    # List recent backups
    echo "Recent backups:"
    az postgres flexible-server backup list \
      --resource-group "${RESOURCE_GROUP}" \
      --server-name "${DB_SERVER}" \
      --output table 2>/dev/null || echo "Unable to list backups"
    ;;
    
  gcp)
    echo "Checking GCP Cloud SQL backups..."
    
    PROJECT_ID=$(gcloud config get-value project)
    DB_INSTANCE="${CLUSTER_NAME}-mlflow-*"
    
    # Find the actual instance name
    INSTANCE_NAME=$(gcloud sql instances list \
      --filter="name~${DB_INSTANCE}" \
      --format="value(name)" \
      --limit=1 2>/dev/null || echo "")
    
    if [ -z "${INSTANCE_NAME}" ]; then
      echo "❌ Database instance not found"
      exit 1
    fi
    
    # Check backup configuration
    BACKUP_ENABLED=$(gcloud sql instances describe "${INSTANCE_NAME}" \
      --format="value(settings.backupConfiguration.enabled)" 2>/dev/null || echo "False")
    
    if [ "${BACKUP_ENABLED}" = "True" ]; then
      echo "✅ Automated backups enabled"
      
      BACKUP_RETENTION=$(gcloud sql instances describe "${INSTANCE_NAME}" \
        --format="value(settings.backupConfiguration.backupRetentionSettings.retainedBackups)" 2>/dev/null || echo "0")
      
      echo "✅ Backup retention: ${BACKUP_RETENTION} backups"
      
      PITR_ENABLED=$(gcloud sql instances describe "${INSTANCE_NAME}" \
        --format="value(settings.backupConfiguration.pointInTimeRecoveryEnabled)" 2>/dev/null || echo "False")
      
      if [ "${PITR_ENABLED}" = "True" ]; then
        echo "✅ Point-in-time recovery enabled"
      fi
    else
      echo "⚠️  Automated backups disabled"
    fi
    
    # List recent backups
    echo "Recent backups:"
    gcloud sql backups list \
      --instance="${INSTANCE_NAME}" \
      --limit=5 \
      --format="table(id,windowStartTime,status)" 2>/dev/null || echo "Unable to list backups"
    ;;
    
  *)
    echo "❌ Unknown cloud provider: ${CLOUD}"
    echo "Usage: $0 [aws|azure|gcp] [dev|prod]"
    exit 1
    ;;
esac

echo ""
echo "✅ Backup verification complete"
