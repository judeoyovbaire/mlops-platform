# Operational Notes

Production deployment guidance and known considerations from the infrastructure review.

## Terraform State & Secrets (F4)

`random_password` resources (MinIO, Grafana, ArgoCD, MLflow DB) produce values that
appear in Terraform state on the first `terraform apply`. Mitigations in place:

- **AWS**: Passwords stored in Secrets Manager; ExternalSecret Operator syncs to K8s.
  State is encrypted at rest via S3 + DynamoDB with KMS.
- **Azure**: Passwords stored in Key Vault; ExternalSecret Operator syncs to K8s.
  State backend uses Azure Storage with encryption.
- **GCP**: Passwords stored in Secret Manager; ExternalSecret Operator syncs to K8s.
  State backend uses GCS with encryption.

For maximum security, rotate passwords after initial provisioning using the respective
cloud secret manager CLI, then run `terraform apply -refresh-only` to sync state.

## CI/CD Pipeline Hardening (F8)

GitHub Actions workflows pin major versions (e.g. `actions/checkout@v4`). For
supply-chain hardening in production:

- Pin to exact commit SHAs instead of version tags:
  `actions/checkout@<full-sha>` (use Dependabot or Renovate to auto-update)
- Enable GitHub's artifact attestation for published container images
- Consider adding SLSA provenance generation to the build pipeline

## GKE Cluster Topology (F9)

GKE clusters are configured as **zonal** (`zones` variable) for cost efficiency in
dev environments. For production:

- Use **regional** clusters (`location = var.region`) for control plane HA
- Regional clusters provide 99.95% SLA vs 99.5% for zonal
- Trade-off: Regional clusters cost ~3x for the control plane
- GPU node pools should remain zonal (pinned to zones with GPU availability)

## Observability Storage (F11)

Loki and Tempo use **local filesystem storage** (`SingleBinary` mode) suitable for
development. For production:

### Loki
- Switch to `distributed` deployment mode
- Use cloud object storage: S3 (AWS), Blob Storage (Azure), GCS (GCP)
- Configure retention policies and compaction
- Set `loki.storage.type: s3|azure|gcs` in values

### Tempo
- Switch to distributed mode with cloud object storage backend
- Configure `storage.trace.backend: s3|azure|gcs`
- Set appropriate retention (default 14 days for traces)

## GPU Autoscaling (F21)

GPU node scaling capabilities differ by cloud provider:

| Provider | Mechanism | Scale-to-Zero | Notes |
|----------|-----------|---------------|-------|
| AWS (EKS) | Karpenter | Yes | Fastest provisioning; supports mixed instance types |
| Azure (AKS) | Cluster Autoscaler | Yes (with `min_count=0`) | NC-series for training, ND-series for inference |
| GCP (GKE) | Node Auto-Provisioning (NAP) | Yes | Automatically selects GPU type based on pod requests |

All environments include GPU node pools with spot/preemptible pricing. Karpenter
(AWS) provides the most flexible scaling; AKS and GKE use standard cluster autoscaler
with node pool definitions.

## Backup & Disaster Recovery (F22)

The platform does not currently include a cluster-level backup solution. For production:

- Deploy **Velero** with cloud storage backend for:
  - Cluster resource backup (CRDs, ConfigMaps, Secrets)
  - PV snapshot integration (EBS/Managed Disk/PD snapshots)
  - Scheduled backups with retention policies
- MLflow artifacts are already persisted in cloud object storage (S3/Blob/GCS)
- Terraform state is backed up via the CI/CD pipeline (state pull before apply)
- See `docs/disaster-recovery.md` for the full DR runbook

## Cloud Cost Management (F23)

Budget alerts and cost controls should be configured per cloud account:

- **AWS**: Create AWS Budgets with SNS notifications for monthly spend thresholds
- **Azure**: Use Cost Management + Budgets with action groups for alerts
- **GCP**: Set up Billing Budgets with Pub/Sub notifications

The platform includes a Grafana **Cloud Cost Dashboard** for visibility into
resource utilization. Spot/preemptible instances are used for training and GPU
workloads to reduce costs by 60-90%.

Recommended budget thresholds:
- Dev: Alert at 80% and 100% of expected monthly cost
- Prod: Alert at 50%, 80%, and 100%; auto-notify on-call at 100%
