# GKE Module (Coming Soon)

This module will deploy the MLOps platform on Google Kubernetes Engine (GKE).

## Architecture Mapping: AWS EKS → GCP GKE

| AWS Component | GCP Equivalent | Notes |
|---------------|----------------|-------|
| EKS | GKE Autopilot/Standard | GKE Autopilot recommended for hands-off management |
| VPC | VPC | Similar concepts, different CIDR defaults |
| NAT Gateway | Cloud NAT | Required for private node egress |
| ALB | Cloud Load Balancer | Via GKE Ingress or Gateway API |
| S3 | Cloud Storage (GCS) | For MLflow artifacts |
| RDS PostgreSQL | Cloud SQL | Managed PostgreSQL |
| IAM Roles (IRSA) | Workload Identity | GKE's pod-level IAM |
| EBS CSI | GCE Persistent Disk CSI | Built into GKE |

## Key Differences from AWS

### Networking
- GCP uses **Shared VPC** for multi-project setups
- **Private Google Access** replaces VPC endpoints for GCP services
- GKE **VPC-native clusters** (alias IPs) are the default

### GPU Support
- Use **NVIDIA T4, L4, A100, H100** via GKE node pools
- **GPU time-sharing** available for cost optimization
- Consider **Cloud TPUs** for TensorFlow workloads

### Authentication
- **Workload Identity** is the GKE equivalent of IRSA
- Binds Kubernetes ServiceAccounts to GCP IAM service accounts
- Required for secure access to GCS, Cloud SQL, etc.

### Cost Optimization
- **Spot VMs** (equivalent to AWS SPOT) for training nodes
- **Committed Use Discounts** (CUDs) for sustained workloads
- **GKE Autopilot** for pay-per-pod pricing

## Planned Implementation

```hcl
# infrastructure/terraform/modules/gke/main.tf (planned)

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google"
  version = "~> 31.0"

  project_id        = var.project_id
  name              = var.cluster_name
  region            = var.region

  # Autopilot for simplified management
  enable_autopilot  = true

  # Or Standard for more control
  node_pools = [
    {
      name           = "general"
      machine_type   = "e2-standard-4"
      min_count      = 2
      max_count      = 4
    },
    {
      name           = "gpu"
      machine_type   = "n1-standard-4"
      accelerator_type = "nvidia-tesla-t4"
      accelerator_count = 1
      spot           = true
      min_count      = 0
      max_count      = 2
    }
  ]
}

# Workload Identity for MLflow
module "mlflow_workload_identity" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"

  name       = "mlflow"
  namespace  = "mlflow"
  project_id = var.project_id
  roles      = ["roles/storage.objectAdmin"]
}

# Cloud SQL for MLflow metadata
module "cloudsql" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/postgresql"

  name             = "${var.cluster_name}-mlflow"
  database_version = "POSTGRES_15"
  tier             = "db-f1-micro"  # Dev tier
}

# GCS bucket for artifacts
resource "google_storage_bucket" "mlflow_artifacts" {
  name     = "${var.cluster_name}-mlflow-artifacts"
  location = var.region
}
```

## Helm Values for GCP

Key differences in Helm configurations:

```yaml
# infrastructure/helm/gcp/mlflow-values.yaml (planned)
artifactRoot:
  gcs:
    enabled: true
    bucket: "${gcs_bucket}"

# Use Workload Identity instead of static credentials
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: mlflow@${project_id}.iam.gserviceaccount.com
```

## Timeline

This module is planned for Phase 2 of the multi-cloud expansion. The AWS EKS module serves as the reference implementation, and GKE will follow the same patterns with GCP-native services.

## Contributing

Contributions welcome! If you'd like to help implement this module, please open an issue to discuss the approach.