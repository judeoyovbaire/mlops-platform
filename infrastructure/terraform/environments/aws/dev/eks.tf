# EKS Cluster
module "eks" {
  source = "../../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  ami_release     = var.eks_ami_release
  environment     = "dev"

  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Public endpoint access - parameterized for flexibility
  # Restrict to your organization's IP ranges for production-grade security
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cost optimization for dev: single NAT gateway
  single_nat_gateway = true

  # Three, not two: the platform baseline alone fills two t3.large to 98 %
  # CPU requests, Karpenter then adds on-demand c6a.large nodes for the first
  # workload pod and one Alloy pod cannot schedule (session 2, 2026-11-21,
  # JDH-431). About 0.09 USD/h more in eu-west-1.
  general_instance_types = ["t3.large"]
  general_min_size       = 3
  general_max_size       = 4
  general_desired_size   = 3

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

  mlflow_db_instance_class      = "db.t3.small"
  mlflow_db_skip_final_snapshot = true  # Dev doesn't need final snapshots
  mlflow_db_deletion_protection = false # Dev can be freely torn down

  # Cluster admins: the GitHub Actions deploy role plus var.human_admin_role_arns
  # (the IAM Identity Center role used for local kubectl and the EKS console).
  # An access entry for ":root" only covers the root user, so it is not listed.
  cluster_admin_arns = concat(
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/mlops-platform-github-actions"],
    var.human_admin_role_arns,
  )

  # Disable dynamic cluster creator permissions - use explicit ARNs only
  enable_cluster_creator_admin_permissions = false

  tags = var.tags
}
