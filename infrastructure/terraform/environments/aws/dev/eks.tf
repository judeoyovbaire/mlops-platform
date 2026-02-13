# EKS Cluster
module "eks" {
  source = "../../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Public endpoint access - parameterized for flexibility
  # Restrict to your organization's IP ranges for production-grade security
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cost optimization for dev: single NAT gateway
  single_nat_gateway = true

  general_instance_types = ["t3.large"]
  general_min_size       = 2
  general_max_size       = 4
  general_desired_size   = 2

  training_instance_types = ["c5.2xlarge"]
  training_capacity_type  = "SPOT"
  training_min_size       = 0
  training_max_size       = 5
  training_desired_size   = 0

  gpu_instance_types = ["g4dn.xlarge"]
  gpu_capacity_type  = "SPOT"
  gpu_min_size       = 0
  gpu_max_size       = 2
  gpu_desired_size   = 0

  mlflow_db_instance_class = "db.t3.small"
  mlflow_db_password       = random_password.mlflow_db.result

  # Grant cluster admin access to GitHub Actions role and root account
  # GitHub Actions for CI/CD deployments, root for local access
  cluster_admin_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mlops-platform-github-actions",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]

  # Disable dynamic cluster creator permissions - use explicit ARNs only
  enable_cluster_creator_admin_permissions = false

  tags = var.tags
}
