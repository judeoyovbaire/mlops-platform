# AWS Production Environment

Production-grade MLOps platform deployment on AWS EKS with high availability and security hardening.

## Key Differences from Dev

| Feature | Dev | Production |
|---------|-----|------------|
| **EKS Endpoint** | Public + Private | Private only |
| **Node Count** | 2 (min) | 3 (min) for HA |
| **Instance Types** | t3.large | m5.xlarge/2xlarge |
| **NAT Gateway** | Single | One per AZ |
| **RDS Multi-AZ** | No | Yes |
| **RDS Backups** | 1 day | 7 days |
| **Deletion Protection** | No | Yes |
| **Container Insights** | Optional | Enabled |

## Prerequisites

1. **VPN/Bastion Access**: Since the cluster endpoint is private, you need VPN or bastion host access to the VPC.

2. **Backend Configuration**: Update the S3 backend bucket and DynamoDB table names in `main.tf`:
   ```hcl
   backend "s3" {
     bucket         = "your-terraform-state-bucket"
     key            = "prod/terraform.tfstate"
     region         = "eu-west-1"
     encrypt        = true
     dynamodb_table = "your-terraform-locks"
   }
   ```

3. **Domain Configuration**: Set your production domain:
   ```hcl
   kserve_ingress_domain = "inference.your-domain.com"
   ```

## Deployment

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan -out=tfplan

# Apply (requires approval)
terraform apply tfplan
```

## Cost Estimate

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| EKS Control Plane | Managed | $73 |
| General Nodes | 3x m5.xlarge (ON_DEMAND) | ~$360 |
| Training Nodes | c5.4xlarge (SPOT, scale-to-zero) | ~$50-100 |
| GPU Nodes | g4dn.xlarge (SPOT, scale-to-zero) | ~$50-100 |
| NAT Gateways | 3 (one per AZ) | ~$135 |
| RDS PostgreSQL | db.t3.medium, Multi-AZ | ~$100 |
| S3 + ALB | Production usage | ~$30-50 |
| CloudWatch | Logs + Insights | ~$50-100 |
| **Total** | | **~$850-1000/month** |

## Security Considerations

1. **Private Endpoint**: Cluster API is only accessible from within the VPC
2. **Encryption**: All data at rest is encrypted (RDS, S3, EBS)
3. **Network Isolation**: Private subnets for workloads, public for load balancers only
4. **IRSA**: No static credentials, all pods use IAM roles
5. **PSA Restricted**: Workload namespaces enforce restricted Pod Security Standards

## Disaster Recovery

- **RDS**: Multi-AZ with automatic failover, 7-day backup retention
- **S3**: Versioning enabled for MLflow artifacts
- **EKS**: Control plane is managed by AWS with HA
- **Node Groups**: Spread across 3 AZs

## Monitoring

- CloudWatch Container Insights enabled
- Prometheus + Grafana deployed
- 30-day log retention in CloudWatch

## Maintenance

### Cluster Upgrades

```bash
# Update kubernetes_version in variables.tf
# Then apply with plan review
terraform plan -out=tfplan
terraform apply tfplan
```

### Node Rotation

Managed node groups support rolling updates. To force node rotation:

```bash
aws eks update-nodegroup-config \
  --cluster-name mlops-platform-prod \
  --nodegroup-name general \
  --scaling-config minSize=3,maxSize=10,desiredSize=4
```