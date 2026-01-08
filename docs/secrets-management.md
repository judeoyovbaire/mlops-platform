# Secrets Management

This document describes the secrets management strategy for the MLOps platform.

## Overview

The platform uses a multi-layered approach to secrets management:

1. **Cloud Secret Stores**: AWS SSM Parameter Store, Azure Key Vault, GCP Secret Manager
2. **External Secrets Operator**: Syncs cloud secrets to Kubernetes
3. **Auto-generated Secrets**: Passwords generated at deployment time
4. **IRSA/Workload Identity**: No static credentials for cloud access

## Secret Types

| Secret | Storage | Rotation | Notes |
|--------|---------|----------|-------|
| MLflow DB Password | SSM/Key Vault/Secret Manager | Manual | Auto-generated at deploy |
| MinIO Root Password | SSM/Key Vault/Secret Manager | Manual | Auto-generated at deploy |
| ArgoCD Admin Password | SSM/Key Vault/Secret Manager | Manual | Bcrypt hashed |
| Grafana Admin Password | External Secrets | Manual | Via cloud secret store |
| AWS/Azure/GCP Credentials | IRSA/Workload Identity | Automatic | No static credentials |

## Secret Rotation

### Database Passwords (MLflow PostgreSQL)

**Rotation Steps:**

1. Generate new password:
   ```bash
   NEW_PASSWORD=$(openssl rand -base64 32)
   ```

2. Update cloud secret store:
   ```bash
   # AWS
   aws ssm put-parameter \
     --name "/mlops-platform-dev/mlflow/db-password" \
     --value "$NEW_PASSWORD" \
     --type SecureString \
     --overwrite

   # Azure
   az keyvault secret set \
     --vault-name mlops-platform-kv \
     --name mlflow-db-password \
     --value "$NEW_PASSWORD"

   # GCP
   echo -n "$NEW_PASSWORD" | gcloud secrets versions add mlflow-db-password --data-file=-
   ```

3. Update database password:
   ```sql
   ALTER USER mlflow WITH PASSWORD 'new_password';
   ```

4. Trigger External Secrets sync:
   ```bash
   kubectl annotate externalsecret mlflow-db-secret \
     -n mlflow \
     force-sync=$(date +%s) \
     --overwrite
   ```

5. Restart MLflow to pick up new credentials:
   ```bash
   kubectl rollout restart deployment mlflow -n mlflow
   ```

### ArgoCD Admin Password

**Rotation Steps:**

1. Generate bcrypt hash:
   ```bash
   NEW_PASSWORD=$(openssl rand -base64 16)
   BCRYPT_HASH=$(htpasswd -nbBC 10 "" "$NEW_PASSWORD" | tr -d ':\n' | sed 's/$2y/$2a/')
   ```

2. Update ArgoCD secret:
   ```bash
   kubectl patch secret argocd-secret -n argocd \
     -p "{\"stringData\": {\"admin.password\": \"$BCRYPT_HASH\"}}"
   ```

3. Store new password in secret manager for reference.

### Grafana Admin Password

1. Update in cloud secret store (External Secrets will sync automatically)
2. Restart Grafana pod to pick up new credentials

## Rotation Schedule (Production Recommendations)

| Secret Type | Rotation Frequency | Method |
|-------------|-------------------|--------|
| Database Passwords | 90 days | Manual with script |
| ArgoCD Admin | 90 days | Manual |
| TLS Certificates | Auto-renewed | cert-manager |
| Cloud Credentials | Automatic | IRSA/Workload Identity |

## Monitoring Secret Expiry

Add Prometheus alerts for certificate expiration:

```yaml
- alert: TLSCertificateExpiringSoon
  expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "TLS certificate expiring within 7 days"
```

## Security Best Practices

1. **Never commit secrets** to version control
2. **Use External Secrets Operator** instead of Kubernetes secrets directly
3. **Enable audit logging** for secret access in cloud providers
4. **Implement least privilege** - pods only access secrets they need
5. **Use IRSA/Workload Identity** - avoid static cloud credentials
6. **Rotate secrets on breach** - have a documented incident response

## Automated Rotation (Future Enhancement)

For fully automated rotation, consider:

- AWS Secrets Manager with Lambda rotation
- Azure Key Vault with automatic rotation
- HashiCorp Vault with dynamic secrets
