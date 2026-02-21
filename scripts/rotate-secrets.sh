#!/bin/bash
# Automated secret rotation script for MLOps Platform
# Usage: ./rotate-secrets.sh [aws|azure|gcp] [dev|prod] [secret-type]
# Secret types: mlflow-db, grafana-admin, argocd-admin, minio-root

set -euo pipefail

CLOUD="${1:-aws}"
ENV="${2:-dev}"
SECRET_TYPE="${3:-all}"
CLUSTER_NAME="mlops-platform-${ENV}"

echo "Rotating secrets for ${CLOUD} ${ENV} environment..."

rotate_mlflow_db() {
  echo "Rotating MLflow database password..."
  
  case "${CLOUD}" in
    aws)
      NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
      
      # Update Secrets Manager
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
      
    azure)
      NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
      RESOURCE_GROUP="${CLUSTER_NAME}-rg"
      DB_SERVER="${CLUSTER_NAME}-mlflow-pg"
      
      # Update Key Vault
      az keyvault secret set \
        --vault-name "mlops-kv-*" \
        --name "mlflow-db-password" \
        --value "${NEW_PASSWORD}" \
        --output none
      
      # Update PostgreSQL password
      az postgres flexible-server update \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${DB_SERVER}" \
        --admin-password "${NEW_PASSWORD}" \
        --output none
      
      echo "✅ MLflow DB password rotated"
      ;;
      
    gcp)
      NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
      PROJECT_ID=$(gcloud config get-value project)
      INSTANCE_NAME=$(gcloud sql instances list \
        --filter="name~${CLUSTER_NAME}-mlflow" \
        --format="value(name)" \
        --limit=1)
      
      # Update Secret Manager
      echo -n "${NEW_PASSWORD}" | gcloud secrets versions add mlflow-db-password \
        --data-file=- \
        --project="${PROJECT_ID}"
      
      # Update Cloud SQL password
      gcloud sql users set-password mlflow \
        --instance="${INSTANCE_NAME}" \
        --password="${NEW_PASSWORD}" \
        --quiet
      
      echo "✅ MLflow DB password rotated"
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
    azure)
      az keyvault secret set \
        --vault-name "mlops-kv-*" \
        --name "grafana-admin-password" \
        --value "${NEW_PASSWORD}" \
        --output none
      ;;
    gcp)
      echo -n "${NEW_PASSWORD}" | gcloud secrets versions add grafana-admin-password \
        --data-file=- \
        --project=$(gcloud config get-value project)
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
  
  # Store in cloud secret manager for reference
  case "${CLOUD}" in
    aws)
      aws ssm put-parameter \
        --name "/${CLUSTER_NAME}/argocd/admin-password" \
        --value "{\"username\":\"admin\",\"password\":\"${NEW_PASSWORD}\"}" \
        --type SecureString \
        --overwrite \
        --no-cli-pager
      ;;
    azure)
      az keyvault secret set \
        --vault-name "mlops-kv-*" \
        --name "argocd-admin-password" \
        --value "${NEW_PASSWORD}" \
        --output none
      ;;
    gcp)
      echo -n "${NEW_PASSWORD}" | gcloud secrets versions add argocd-admin-password \
        --data-file=- \
        --project=$(gcloud config get-value project)
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
    echo "Usage: $0 [aws|azure|gcp] [dev|prod] [mlflow-db|grafana-admin|argocd-admin|all]"
    exit 1
    ;;
esac

echo ""
echo "✅ Secret rotation complete for ${SECRET_TYPE}"
