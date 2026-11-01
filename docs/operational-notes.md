# Operational Notes

Production deployment guidance and known considerations from the infrastructure review.

## Terraform State & Secrets (F4)

`random_password` resources (MinIO, Grafana, ArgoCD, MLflow DB) produce values that
appear in Terraform state on the first `terraform apply`. Mitigations in place:

- **AWS**: Passwords stored in Secrets Manager; ExternalSecret Operator syncs to K8s.
  State is encrypted at rest via S3 + DynamoDB with KMS.

For maximum security, rotate passwords after initial provisioning using the AWS
Secrets Manager CLI, then run `terraform apply -refresh-only` to sync state.

## CI/CD Pipeline Hardening (F8)

GitHub Actions workflows pin major versions (e.g. `actions/checkout@v4`). Python
linting tools are pinned to exact versions (`ruff==0.9.7`, `bandit==1.8.3`) for
reproducible builds. Binary downloads include SHA256 checksum
verification. For additional supply-chain hardening in production:

- Pin to exact commit SHAs instead of version tags:
  `actions/checkout@<full-sha>` (use Dependabot or Renovate to auto-update)
- Container images already carry GitHub artifact attestations (SLSA v1
  Build L2) and keyless signatures verified by digest; see ADR-008

## Observability Storage (F11)

Loki and Tempo use **local filesystem storage** (`SingleBinary` mode) suitable for
development. For production:

### Loki
- Switch to `distributed` deployment mode
- Use S3 object storage
- Configure retention policies and compaction
- Set `loki.storage.type: s3` in values

### Tempo
- Switch to distributed mode with cloud object storage backend
- Configure `storage.trace.backend: s3`
- Set appropriate retention (default 14 days for traces)

## GPU Autoscaling (F21)

GPU node scaling on EKS:

| Provider | Mechanism | Scale-to-Zero | Notes |
|----------|-----------|---------------|-------|
| AWS (EKS) | Karpenter | Yes | Fastest provisioning; supports mixed instance types |

GPU nodes use spot pricing.

## Backup & Disaster Recovery (F22)

The platform does not currently include a cluster-level backup solution. For production:

- Deploy **Velero** with cloud storage backend for:
  - Cluster resource backup (CRDs, ConfigMaps, Secrets)
  - PV snapshot integration (EBS snapshots)
  - Scheduled backups with retention policies
- MLflow artifacts are already persisted in cloud object storage (S3)
- Terraform state is backed up via the CI/CD pipeline (state pull before apply)
- See `docs/disaster-recovery.md` for the full DR runbook

## Cloud Cost Management (F23)

Budget alerts and cost controls should be configured on the AWS account:

- **AWS**: Create AWS Budgets with SNS notifications for monthly spend thresholds

The platform includes a Grafana **Cloud Cost Dashboard** for visibility into
resource utilization. Spot/preemptible instances are used for training and GPU
workloads to reduce costs by 60-90%.

Recommended budget thresholds:
- Dev: Alert at 80% and 100% of expected monthly cost
