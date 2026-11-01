# Terraform Modules

Reusable Terraform modules for deploying Kubernetes clusters with MLOps platform components.

## Available Modules

| Module | Cloud | Description |
|--------|-------|-------------|
| `eks/` | AWS | Amazon EKS cluster with VPC, RDS, S3, and IRSA |

## Module Structure

Two modules, split by layer (see ADR-015):

```
modules/eks/           # Cluster layer: VPC, EKS, node groups, IRSA roles, RDS, S3, KMS, backup
modules/aws-platform/  # Platform layer on the cluster: Helm releases, namespaces, policies, Karpenter pools
```

## Usage

Modules are consumed by environment configurations in `environments/<cloud>/dev/`:

```hcl
module "eks" {
  source = "../../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  environment     = "dev"
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

## Extending Modules

To add new functionality:

1. Add resources to the appropriate module's `main.tf`
2. Expose configuration via `variables.tf`
3. Export values via `outputs.tf`
4. Update environment configurations to use new features
