#!/bin/bash
# Automated secret rotation script for MLOps Platform
# Usage: ./rotate-secrets.sh [aws] [dev] [secret-type]
# Secret types: mlflow-db, grafana-admin, argocd-admin, minio-root

set -euo pipefail

CLOUD="${1:-aws}"
if [[ "${CLOUD}" != "aws" ]]; then
  echo "Only aws is supported (ADR-017); got: ${CLOUD}" >&2
  exit 1
fi
ENV="${2:-dev}"
SECRET_TYPE="${3:-all}"
CLUSTER_NAME="mlops-platform-${ENV}"

echo "Rotating secrets for ${CLOUD} ${ENV} environment..."

rotate_mlflow_db() {
  echo "Rotating MLflow database password..."
  
  case "${CLOUD}" in
    aws)
      NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
      
      # WARNING: writes an SSM parameter that nothing reads, then sets the RDS
      # password directly, which desyncs the RDS-managed secret that MLflow
      # uses (mlflow-postgres). Do not use; see docs/secrets-management.md.
      aws ssm put-parameter \
        --name "/${CLUSTER_NAME}/mlflow/db-password" \
        --value "{\"username\":\"mlflow\",\"password\":\"${NEW_PASSWORD}\"}" \
        --type SecureString \
        --overwrite \
        --no-cli-pager
      
      # Update RDS password
      DB_INSTANCE="${CLUSTER_NAME}-mlflow"
      aws rds modify-db-instance \
        --db-instance-identifier "${DB_INSTANCE}" \
        --master-user-password "${NEW_PASSWORD}" \
        --apply-immediately \
        --no-cli-pager
      
      echo "✅ MLflow DB password rotated. Triggering External Secrets sync..."
      ;;

  esac
  
  # Trigger External Secrets sync
  kubectl annotate externalsecret mlflow-db-secret \
    -n mlflow \
    force-sync=$(date +%s) \
    --overwrite || echo "⚠️  ExternalSecret not found, skipping sync"
  
  # Restart MLflow to pick up new credentials
  kubectl rollout restart deployment/mlflow -n mlflow
  kubectl rollout status deployment/mlflow -n mlflow --timeout=300s
}

rotate_grafana_admin() {
  echo "Rotating Grafana admin password..."
  
  NEW_PASSWORD=$(openssl rand -base64 16)
  
  case "${CLOUD}" in
    aws)
      aws ssm put-parameter \
        --name "/${CLUSTER_NAME}/grafana/admin-password" \
        --value "${NEW_PASSWORD}" \
        --type SecureString \
        --overwrite \
        --no-cli-pager
      ;;
  esac
  
  # Update Grafana secret directly (External Secrets will sync)
  kubectl patch secret prometheus-grafana \
    -n monitoring \
    -p "{\"data\":{\"admin-password\":\"$(echo -n ${NEW_PASSWORD} | base64)\"}}" || \
    echo "⚠️  Grafana secret not found, External Secrets will sync"
  
  kubectl rollout restart deployment/prometheus-grafana -n monitoring
  echo "✅ Grafana admin password rotated"
}

rotate_argocd_admin() {
  echo "Rotating ArgoCD admin password..."
  
  NEW_PASSWORD=$(openssl rand -base64 16)
  BCRYPT_HASH=$(htpasswd -nbBC 10 "" "${NEW_PASSWORD}" | tr -d ':\n' | sed 's/$2y/$2a/')
  
  # Update ArgoCD secret
  kubectl patch secret argocd-secret \
    -n argocd \
    -p "{\"stringData\":{\"admin.password\":\"${BCRYPT_HASH}\"}}"
  
  # Store for reference (an SSM parameter that nothing reads)
  case "${CLOUD}" in
    aws)
      aws ssm put-parameter \
        --name "/${CLUSTER_NAME}/argocd/admin-password" \
        --value "{\"username\":\"admin\",\"password\":\"${NEW_PASSWORD}\"}" \
        --type SecureString \
        --overwrite \
        --no-cli-pager
      ;;
  esac
  
  echo "✅ ArgoCD admin password rotated"
  echo "⚠️  New password stored in cloud secret manager for reference"
}

case "${SECRET_TYPE}" in
  mlflow-db)
    rotate_mlflow_db
    ;;
  grafana-admin)
    rotate_grafana_admin
    ;;
  argocd-admin)
    rotate_argocd_admin
    ;;
  all)
    rotate_mlflow_db
    rotate_grafana_admin
    rotate_argocd_admin
    ;;
  *)
    echo "❌ Unknown secret type: ${SECRET_TYPE}"
    echo "Usage: $0 [aws] [dev] [mlflow-db|grafana-admin|argocd-admin|all]"
    exit 1
    ;;
esac

echo ""
echo "✅ Secret rotation complete for ${SECRET_TYPE}"
