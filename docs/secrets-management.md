# Secrets Management

Where each credential on the AWS dev platform actually lives, and how to rotate it. `${cluster}` is the cluster name (default `mlops-platform-dev`).

## Overview

Four mechanisms are in use, each for a specific secret:

1. **RDS-managed master secret** for the MLflow database (`manage_master_user_password = true`).
2. **SSM Parameter Store** (SecureString) for the Grafana admin password.
3. **Secrets Manager + External Secrets Operator** (`ClusterSecretStore aws-sm`) for the optional integrations.
4. **IRSA** for AWS API access from pods: no static AWS credentials ([IRSA access matrix](irsa-access-matrix.md)).

## Secret Types

| Secret | Storage | Consumed by | Source |
|--------|---------|-------------|--------|
| MLflow DB password | RDS-managed master secret in Secrets Manager | Terraform copies it into the K8s secret `mlflow/mlflow-postgres`, which the MLflow chart reads (`existingDatabaseSecret`) | `modules/eks/database.tf`, `modules/aws-platform/namespaces.tf`, `helm/aws/mlflow-values.yaml` |
| Grafana admin password | SSM SecureString `/${cluster}/grafana/admin-password` | Passed to the chart as the Helm value `grafana.adminPassword`; no ESO | `modules/aws-platform/monitoring.tf` |
| ArgoCD admin login | K8s secret `argocd/argocd-initial-admin-secret` (chart default) | `make port-forward-argocd` prints it | Argo CD chart |
| Slack webhook (optional) | Secrets Manager `${cluster}/alertmanager/slack-webhook-url` | ESO to `monitoring/alertmanager-slack-webhook` when `slack_notifications_enabled` | `environments/aws/dev/secrets.tf`, `modules/aws-platform/external-secrets.tf` |
| HF Hub token (optional) | Secrets Manager `${cluster}/huggingface/token` (created by hand) | ESO to `argo/huggingface-hub-token` when `enable_huggingface_hub_token` | `modules/aws-platform/external-secrets.tf` |
| Grafana Cloud remote write (optional) | Secrets Manager `${cluster}/grafana-cloud/remote-write` (created by hand) | ESO to `monitoring/grafana-cloud-remote-write` when `enable_grafana_cloud_remote_write` | `modules/aws-platform/monitoring.tf` |
| AWS credentials | IRSA | Pod service accounts | `modules/eks/iam.tf`, `modules/aws-platform/*-irsa.tf` |

### Retrieval

`make secrets-aws` prints all three logins from where each one lives. It reads the ArgoCD and MLflow entries through a temporary kubeconfig for this cluster, never the current kubectl context. By hand:

```bash
# Grafana
aws ssm get-parameter --name "/${CLUSTER}/grafana/admin-password" --with-decryption --query Parameter.Value --output text
# ArgoCD (user: admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
# MLflow DB (RDS-managed)
kubectl -n mlflow get secret mlflow-postgres -o jsonpath='{.data.password}' | base64 --decode
```

## Secret Rotation

### MLflow database password

The password is owned by RDS. Do not run `ALTER USER` or `modify-db-instance --master-user-password`: that desyncs the RDS-managed secret from `mlflow-postgres` and breaks MLflow.

1. Rotate through RDS:
   ```bash
   aws rds modify-db-instance --db-instance-identifier <mlflow-db-id> \
     --rotate-master-user-password --apply-immediately
   ```
2. Refresh the K8s copy: `terraform apply` (re-reads the secret into `mlflow-postgres`).
3. Restart MLflow: `kubectl rollout restart deployment mlflow -n mlflow`.

### Grafana, ArgoCD

This is a dev cluster that is destroyed after each session, and these passwords are regenerated on every fresh deploy. Rotation is a redeploy.

## Monitoring Secret Expiry

`infrastructure/kubernetes/monitoring.yaml` defines `TLSCertificateExpiringSoon` on `certmanager_certificate_expiration_timestamp_seconds`.

## Security Best Practices

1. **Never commit secrets** to version control.
2. **Prefer External Secrets Operator** over hand-created Kubernetes secrets.
3. **Implement least privilege**: pods only access secrets they need.
4. **Use IRSA**: avoid static cloud credentials.
