# =============================================================================
# EKS Cluster - Production Configuration
# =============================================================================
#
# Production-grade EKS cluster with:
# - High availability (multi-AZ, multiple NAT gateways)
# - Enhanced security (private endpoint, KMS encryption)
# - Production sizing (larger node pools, ON_DEMAND instances)
# - Disaster recovery (deletion protection, extended backups)
# =============================================================================

module "eks" {
  source = "../../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Network configuration
  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Production: NAT gateway per AZ for high availability
  single_nat_gateway = false

  # Production: Restrict public endpoint access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # ============================================================================
  # Node Pool Configuration - Production Sizing
  # ============================================================================

  # General nodes for platform services (Always ON_DEMAND for stability)
  general_instance_types = ["m5.xlarge", "m5.2xlarge"] # Larger instances
  general_min_size       = 3                           # Minimum 3 for HA
  general_max_size       = 10
  general_desired_size   = 3

  # Training nodes - ON_DEMAND for production reliability
  training_instance_types = ["c5.4xlarge", "c5.2xlarge"]
  training_capacity_type  = "ON_DEMAND" # Production: no SPOT for reliability
  training_min_size       = 0
  training_max_size       = 20
  training_desired_size   = 0

  # GPU nodes - ON_DEMAND for production workloads
  gpu_instance_types = ["g4dn.xlarge", "g4dn.2xlarge", "p3.2xlarge"]
  gpu_capacity_type  = "ON_DEMAND" # Production: no SPOT for reliability
  gpu_min_size       = 0
  gpu_max_size       = 10
  gpu_desired_size   = 0

  # ============================================================================
  # Database Configuration - Production Grade
  # ============================================================================

  mlflow_db_instance_class          = "db.r5.large" # Production-grade instance
  mlflow_db_password                = random_password.mlflow_db.result
  mlflow_db_allocated_storage       = 100   # Larger initial storage
  mlflow_db_max_allocated_storage   = 500   # Allow autoscaling to 500GB
  mlflow_db_multi_az                = true  # Multi-AZ for HA
  mlflow_db_deletion_protection     = true  # Prevent accidental deletion
  mlflow_db_backup_retention_period = 30    # 30 days retention
  mlflow_db_skip_final_snapshot     = false # Create final snapshot on delete

  # ============================================================================
  # Security Configuration
  # ============================================================================

  # Enable KMS encryption for S3, RDS, and SSM
  enable_kms_encryption = true

  # Enable VPC Flow Logs for network monitoring
  enable_vpc_flow_logs     = true
  flow_logs_retention_days = 90 # Extended retention for compliance

  # Enable AWS Backup for automated backups
  enable_aws_backup     = true
  backup_retention_days = 90 # Extended retention

  # ============================================================================
  # Access Configuration
  # ============================================================================

  # Grant cluster admin access to specific roles only
  cluster_admin_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mlops-platform-github-actions",
    # Add additional admin roles as needed
    # "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/platform-admins",
  ]

  # Disable dynamic cluster creator permissions - use explicit ARNs only
  enable_cluster_creator_admin_permissions = false

  tags = var.tags
}