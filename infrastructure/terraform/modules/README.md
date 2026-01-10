# Terraform Modules

Reusable Terraform modules for deploying Kubernetes clusters with MLOps platform components.

## Available Modules

| Module | Cloud | Description |
|--------|-------|-------------|
| `eks/` | AWS | Amazon EKS cluster with VPC, RDS, S3, and IRSA |
| `aks/` | Azure | Azure AKS cluster with VNet, PostgreSQL, Blob, and Workload Identity |
| `gke/` | GCP | Google GKE cluster with VPC, Cloud SQL, GCS, and Workload Identity |

## Module Structure

Each module follows the same pattern:

```
modules/<cloud>/
  main.tf           # Core resources (cluster, networking)
  variables.tf      # Input variables
  outputs.tf        # Output values
  workload-identity.tf  # Pod identity configuration (if applicable)
```

## Usage

Modules are consumed by environment configurations in `environments/<cloud>/dev/`:

```hcl
module "gke" {
  source = "../../modules/gke"

  project_name = "mlops-platform"
  environment  = "dev"
  region       = "europe-west4"
  zone         = "europe-west4-a"
}
```

## Common Inputs

All modules accept these standard variables:

| Variable | Type | Description |
|----------|------|-------------|
| `project_name` | string | Project identifier (used in resource names) |
| `environment` | string | Environment name (dev, staging, prod) |
| `tags` / `labels` | map | Resource tags/labels |

## Common Outputs

All modules provide these outputs:

| Output | Description |
|--------|-------------|
| `cluster_name` | Kubernetes cluster name |
| `cluster_endpoint` | API server endpoint |
| `cluster_ca_certificate` | Cluster CA certificate (base64) |

## EKS Module (AWS)

### Key Resources
- VPC with public/private subnets (3 AZs)
- EKS cluster with managed node groups
- S3 bucket for MLflow artifacts
- RDS PostgreSQL for MLflow metadata
- IAM roles with IRSA
- VPC Flow Logs with CloudWatch integration
- AWS Backup vault with daily/weekly backup plans

### Inputs
| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `eu-west-1` | AWS region |
| `kubernetes_version` | `1.32` | EKS version |
| `node_instance_type` | `t3.large` | Default node type |
| `enable_vpc_flow_logs` | `true` | Enable VPC Flow Logs |
| `flow_logs_retention_days` | `30` | Flow logs retention in CloudWatch |
| `enable_aws_backup` | `true` | Enable AWS Backup for RDS |
| `backup_retention_days` | `30` | Daily backup retention period |

## AKS Module (Azure)

### Key Resources
- Virtual Network with subnets
- AKS cluster with node pools
- Storage Account for MLflow artifacts
- PostgreSQL Flexible Server
- Azure Key Vault
- Managed Identities with Workload Identity
- NSG Flow Logs with Traffic Analytics
- Network Watcher for diagnostics

### Inputs
| Variable | Default | Description |
|----------|---------|-------------|
| `location` | `westeurope` | Azure region |
| `kubernetes_version` | `1.32` | AKS version |
| `node_vm_size` | `Standard_D4s_v3` | Default node size |
| `enable_nsg_flow_logs` | `true` | Enable NSG Flow Logs |
| `flow_logs_retention_days` | `30` | Flow logs retention period |
| `enable_traffic_analytics` | `true` | Enable Traffic Analytics |

## GKE Module (GCP)

### Key Resources
- VPC with subnets
- GKE cluster with node pools
- GCS bucket for MLflow artifacts
- Cloud SQL PostgreSQL
- Secret Manager secrets
- Service Accounts with Workload Identity
- VPC Flow Logs on subnets

### Inputs
| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `europe-west4` | GCP region |
| `zone` | `europe-west4-a` | GCP zone |
| `kubernetes_version` | `1.32` | GKE version |
| `node_machine_type` | `e2-standard-4` | Default machine type |
| `enable_vpc_flow_logs` | `true` | Enable VPC Flow Logs |
| `flow_logs_aggregation_interval` | `INTERVAL_5_SEC` | Flow logs aggregation |
| `flow_logs_sampling_rate` | `0.5` | Flow logs sampling rate |

## Extending Modules

To add new functionality:

1. Add resources to the appropriate module's `main.tf`
2. Expose configuration via `variables.tf`
3. Export values via `outputs.tf`
4. Update environment configurations to use new features
