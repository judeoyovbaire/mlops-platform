#!/bin/bash
# Verify AWS database backups (RDS and AWS Backup)
# Usage: ./verify-backups.sh [aws] [dev|prod]

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

  *)
    echo "❌ Unknown cloud provider: ${CLOUD}"
    echo "Usage: $0 [aws] [dev|prod]"
    exit 1
    ;;
esac

echo ""
echo "✅ Backup verification complete"
