# EKS Module

Provisions an AWS EKS cluster with VPC, managed node groups (general, training, GPU), S3 artifact storage, RDS PostgreSQL for MLflow metadata, IRSA roles, Karpenter support, ECR repository, VPC Flow Logs, and AWS Backup.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name    = "mlops-platform-dev"
  environment     = "dev"
  cluster_version = "1.34"
  vpc_cidr        = "10.0.0.0/16"

  tags = {
    Project    = "mlops-platform"
    managed_by = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| environment | Deployment environment | `string` | `"dev"` | no |
| cluster_version | Kubernetes version for the EKS cluster | `string` | `"1.34"` | no |
| cluster_endpoint_public_access | Enable public access to EKS API endpoint | `bool` | `false` | no |
| cluster_endpoint_public_access_cidrs | List of CIDR blocks allowed to access the EKS public endpoint | `list(string)` | `[]` | no |
| vpc_cidr | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| enable_kms_encryption | Enable customer-managed KMS encryption for S3, RDS, and SSM | `bool` | `true` | no |
| private_subnets | Private subnet CIDR blocks | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]` | no |
| public_subnets | Public subnet CIDR blocks | `list(string)` | `["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]` | no |
| single_nat_gateway | Use a single NAT gateway for cost savings | `bool` | `true` | no |
| general_instance_types | Instance types for general node group | `list(string)` | `["t3.large"]` | no |
| general_min_size | Minimum size of general node group | `number` | `2` | no |
| general_max_size | Maximum size of general node group | `number` | `5` | no |
| general_desired_size | Desired size of general node group | `number` | `2` | no |
| training_instance_types | Instance types for training node group | `list(string)` | `["c5.2xlarge"]` | no |
| training_capacity_type | Capacity type for training nodes (ON_DEMAND or SPOT) | `string` | `"SPOT"` | no |
| training_min_size | Minimum size of training node group | `number` | `0` | no |
| training_max_size | Maximum size of training node group | `number` | `10` | no |
| training_desired_size | Desired size of training node group | `number` | `0` | no |
| training_taints | Taints for training node group | `map(object)` | `{ training = { key = "workload", value = "training", effect = "NO_SCHEDULE" } }` | no |
| gpu_instance_types | Instance types for GPU node group | `list(string)` | `["g4dn.xlarge"]` | no |
| gpu_capacity_type | Capacity type for GPU nodes (ON_DEMAND or SPOT) | `string` | `"SPOT"` | no |
| gpu_min_size | Minimum size of GPU node group | `number` | `0` | no |
| gpu_max_size | Maximum size of GPU node group | `number` | `4` | no |
| gpu_desired_size | Desired size of GPU node group | `number` | `0` | no |
| mlflow_db_instance_class | Instance class for MLflow RDS | `string` | `"db.t3.small"` | no |
| mlflow_db_allocated_storage | Allocated storage for MLflow RDS in GB | `number` | `20` | no |
| mlflow_db_max_allocated_storage | Maximum allocated storage for MLflow RDS autoscaling in GB | `number` | `100` | no |
| mlflow_db_engine_version | PostgreSQL engine version for MLflow RDS | `string` | `"15"` | no |
| mlflow_db_skip_final_snapshot | Skip final snapshot when destroying RDS | `bool` | `false` | no |
| mlflow_db_backup_retention_period | Number of days to retain automated backups | `number` | `7` | no |
| mlflow_db_deletion_protection | Enable deletion protection for RDS | `bool` | `false` | no |
| mlflow_db_multi_az | Enable Multi-AZ deployment for RDS high availability | `bool` | `false` | no |
| cluster_admin_arns | List of IAM ARNs to grant cluster admin access | `list(string)` | `[]` | no |
| enable_cluster_creator_admin_permissions | Enable cluster admin permissions for the cluster creator | `bool` | `true` | no |
| enable_aws_backup | Enable AWS Backup for RDS and other resources | `bool` | `true` | no |
| backup_retention_days | Number of days to retain backups in AWS Backup | `number` | `30` | no |
| enable_vpc_flow_logs | Enable VPC Flow Logs for network troubleshooting | `bool` | `true` | no |
| flow_logs_retention_days | Number of days to retain VPC Flow Logs in CloudWatch | `number` | `30` | no |
| tags | Tags to apply to all resources | `map(string)` | `{ project = "mlops-platform", managed_by = "terraform" }` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | Name of the EKS cluster |
| cluster_endpoint | Endpoint for the EKS cluster API server |
| cluster_certificate_authority_data | Base64 encoded certificate data for the cluster |
| oidc_provider_arn | ARN of the OIDC provider for the cluster |
| cluster_security_group_id | Security group ID attached to the EKS cluster |
| node_security_group_id | Security group ID attached to the EKS nodes |
| vpc_id | ID of the VPC |
| private_subnets | List of private subnet IDs |
| public_subnets | List of public subnet IDs |
| mlflow_s3_bucket | S3 bucket for MLflow artifacts |
| loki_s3_bucket | S3 bucket for Loki logs |
| tempo_s3_bucket | S3 bucket for Tempo traces |
| loki_irsa_role_arn | IAM role ARN for Loki IRSA |
| tempo_irsa_role_arn | IAM role ARN for Tempo IRSA |
| mlflow_irsa_role_arn | IAM role ARN for MLflow IRSA |
| aws_lb_controller_irsa_role_arn | IAM role ARN for AWS Load Balancer Controller IRSA |
| mlflow_db_endpoint | Endpoint for MLflow RDS database |
| mlflow_db_name | Database name for MLflow |
| mlflow_db_secret_arn | ARN of the Secrets Manager secret for MLflow database password |
| configure_kubectl | Command to configure kubectl |
| karpenter_irsa_role_arn | IAM role ARN for Karpenter IRSA |
| karpenter_node_role_name | IAM role name for Karpenter nodes |
| karpenter_node_instance_profile_name | Instance profile name for Karpenter nodes |
| ecr_repository_url | URL of the ECR repository for ML model images |
| ecr_repository_arn | ARN of the ECR repository for ML model images |
| access_info | Access information for deployed services |
