# Bootstrap AWS: S3 state bucket, DynamoDB lock table, GitHub OIDC provider, IAM role

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap state lives in the very bucket it manages (chicken-and-egg
  # applies only to FIRST creation - once the bucket exists, keeping this
  # state local is how it got lost in July 2026). Partial config; init with:
  #   terraform init \
  #     -backend-config="bucket=mlops-platform-tfstate-<ACCOUNT_ID>" \
  #     -backend-config="key=bootstrap/aws/terraform.tfstate" \
  #     -backend-config="region=eu-west-1" \
  #     -backend-config="dynamodb_table=mlops-platform-terraform-locks" \
  #     -backend-config="encrypt=true"
  # First-ever creation in a fresh account: comment this out, apply with
  # local state, restore it, re-init with -migrate-state.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "mlops-platform"
      ManagedBy = "terraform-bootstrap"
    }
  }
}

# Variables

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "mlops-platform"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "judeoyovbaire"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "mlops-platform"
}

# Data Sources

data "aws_caller_identity" "current" {}

# KMS Key for Terraform State Encryption

resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-terraform-state-kms"
    Description = "KMS key for Terraform state encryption"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project_name}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# S3 Bucket for Terraform State

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-terraform-state"
    Description = "Terraform state storage for ${var.project_name}"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
    # AWS now returns this on every SSE rule; leaving it undeclared makes
    # the provider see a different rule and plan a perpetual update.
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule to manage old state versions
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {} # Apply to all objects

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
  }
}

# DynamoDB Table for State Locking

# EC2 Spot service-linked role - accounts that have never launched Spot
# lack it, and instance-launching roles (Karpenter) cannot create it:
# first GPU session failed with ServiceLinkedRoleCreationNotPermitted.
resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Enable point-in-time recovery for disaster recovery
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-terraform-locks"
    Description = "Terraform state locking for ${var.project_name}"
  }
}

# GitHub OIDC Provider

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "github-actions-oidc"
    Description = "GitHub Actions OIDC provider for ${var.project_name}"
  }
}

# IAM Role for GitHub Actions

resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions"
  description = "IAM role for GitHub Actions CI/CD"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # Constrain the trust: a bare "repo:org/repo:*" would let ANY ref
          # assume the infrastructure role. Allowed subjects:
          #   - main-branch runs (push / schedule / workflow_dispatch)
          #   - pull_request plan jobs (fork PRs cannot mint OIDC tokens on
          #     pull_request events, so this admits same-repo branches only)
          #   - environment-gated deploy jobs
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
              "repo:${var.github_org}/${var.github_repo}:pull_request",
              "repo:${var.github_org}/${var.github_repo}:environment:*",
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions"
  }
}

# Policy for Terraform state access
resource "aws_iam_policy" "terraform_state_access" {
  name = "${var.project_name}-gha-terraform-state-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        # The state bucket uses SSE-KMS with this CMK; without these the role
        # can list state objects but not read or write them.
        Sid      = "StateKeyUse"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.terraform_state.arn
      },
      {
        Sid    = "DynamoDBLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_state_access" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

# Customer-managed policies attached to the role (6,144 chars each, 10 per
# role by default). These were inline policies until 2026-11-01, when their
# aggregate size reached ~9,000 of the 10,240-char per-role inline limit.
# Policy 1: EKS and EC2/VPC networking
resource "aws_iam_policy" "terraform_eks_ec2" {
  name = "${var.project_name}-gha-terraform-eks-ec2"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSFullAccess"
        Effect = "Allow"
        Action = [
          "eks:CreateCluster", "eks:DeleteCluster", "eks:DescribeCluster",
          "eks:UpdateClusterConfig", "eks:UpdateClusterVersion",
          "eks:TagResource", "eks:UntagResource",
          "eks:ListClusters", "eks:ListTagsForResource",
          "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion",
          "eks:ListNodegroups",
          "eks:CreateAddon", "eks:DeleteAddon", "eks:DescribeAddon",
          "eks:UpdateAddon", "eks:ListAddons",
          "eks:DescribeAddonVersions",
          "eks:AssociateAccessPolicy", "eks:CreateAccessEntry",
          "eks:DeleteAccessEntry", "eks:DescribeAccessEntry",
          "eks:ListAccessEntries", "eks:ListAccessPolicies",
          "eks:ListAssociatedAccessPolicies", "eks:DisassociateAccessPolicy", "eks:UpdateAccessEntry",
          "eks:AssociateIdentityProviderConfig"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkingAccess"
        Effect = "Allow"
        Action = [
          "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*RouteTable*", "ec2:*Route",
          "ec2:*InternetGateway*", "ec2:*NatGateway*", "ec2:*Address*",
          "ec2:*SecurityGroup*", "ec2:*Tags*", "ec2:Describe*",
          "ec2:*LaunchTemplate*", "ec2:RunInstances", "ec2:TerminateInstances",
          "ec2:*FlowLogs*", "ec2:*NetworkAcl*"
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoScalingAccess"
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup", "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups", "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:CreateLaunchConfiguration", "autoscaling:DeleteLaunchConfiguration",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_eks_ec2" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_eks_ec2.arn
}

# Policy 2: IAM permissions
resource "aws_iam_policy" "terraform_iam" {
  name = "${var.project_name}-gha-terraform-iam"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:ListRoles",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:ListRolePolicies", "iam:UpdateAssumeRolePolicy", "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-eks-node-group-*"
        ]
      },
      {
        Sid    = "IAMPolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:ListPolicies",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion", "iam:TagPolicy", "iam:UntagPolicy"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AmazonEKS_*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWS_Load_Balancer_Controller*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/EBS_CSI*"
        ]
      },
      {
        Sid    = "IAMInstanceProfile"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:ListInstanceProfiles", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile", "iam:ListInstanceProfilesForRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project_name}*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*-eks-node-group-*"
        ]
      },
      {
        Sid      = "IAMServiceLinkedRoles"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
          }
        }
      },
      {
        Sid      = "IAMGetServiceLinkedRoles"
        Effect   = "Allow"
        Action   = "iam:GetRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
      },
      {
        Sid      = "IAMOIDCProvider"
        Effect   = "Allow"
        Action   = ["iam:*OpenIDConnectProvider*"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_iam" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_iam.arn
}

# Policy 3: Storage and data services (S3, ECR, RDS)
resource "aws_iam_policy" "terraform_storage" {
  name = "${var.project_name}-gha-terraform-storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Enumerated instead of s3:* (Trivy AWS-0345): bucket lifecycle plus the
        # Get/Put/Delete configuration calls the AWS provider makes for
        # aws_s3_bucket_* resources, and object access for state and artifacts.
        # No s3:*, no PutBucketObjectLockConfiguration bypass, no replication.
        Sid    = "S3BucketManagement"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket", "s3:ListBucketVersions",
          "s3:GetBucket*", "s3:PutBucket*", "s3:DeleteBucketPolicy", "s3:DeleteBucketOwnershipControls",
          "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
          "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration",
          "s3:GetAccelerateConfiguration", "s3:GetReplicationConfiguration",
          "s3:GetIntelligentTieringConfiguration", "s3:GetAnalyticsConfiguration",
          "s3:GetInventoryConfiguration", "s3:GetMetricsConfiguration",
          "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject",
          "s3:DeleteObject", "s3:DeleteObjectVersion"
        ]
        Resource = ["arn:aws:s3:::${var.project_name}*", "arn:aws:s3:::${var.project_name}*/*"]
      },
      {
        Sid      = "S3ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
        Resource = "*"
      },
      {
        Sid      = "ECRManagement"
        Effect   = "Allow"
        Action   = ["ecr:*"]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}*"
      },
      {
        Sid      = "ECRGetToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "RDSManagement"
        Effect = "Allow"
        Action = ["rds:*"]
        Resource = [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:db:${var.project_name}*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subgrp:${var.project_name}*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:snapshot:${var.project_name}*"
        ]
      },
      {
        Sid      = "RDSDescribe"
        Effect   = "Allow"
        Action   = ["rds:Describe*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_storage" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_storage.arn
}

# Policy 4: Other services (KMS, CloudWatch, Backup, SSM)
# Secrets Manager: RDS manage_master_user_password creates/rotates a secret
# under the rds! prefix AS THE CALLER, and the platform layer manages its own
# secrets under the project prefix. Discovered on first real deploy - the
# scoped role's initial policy set predated RDS-managed master passwords.
resource "aws_iam_policy" "secretsmanager_rds_managed" {
  name = "${var.project_name}-gha-secretsmanager-rds-managed"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSManagedMasterSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:UpdateSecret",
          "secretsmanager:RotateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:rds!*"
      },
      {
        Sid    = "PlatformSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:UpdateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secretsmanager_rds_managed" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.secretsmanager_rds_managed.arn
}

resource "aws_iam_policy" "terraform_services" {
  name = "${var.project_name}-gha-terraform-services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # KMS: key-management actions only on keys tagged Project=<project>
      # (provider default_tags put that tag on every key the env roots
      # create). Previously PutKeyPolicy/ScheduleKeyDeletion applied to every
      # key in the account. The state-bucket key carries the same Project tag
      # (bootstrap default_tags), so it is protected by the explicit Deny below.
      {
        Sid    = "DenyStateKeyAdministration"
        Effect = "Deny"
        Action = [
          "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion", "kms:DisableKey",
          "kms:UntagResource", "kms:TagResource"
        ]
        Resource = aws_kms_key.terraform_state.arn
      },
      {
        Sid      = "KMSCreateProjectKeys"
        Effect   = "Allow"
        Action   = ["kms:CreateKey", "kms:TagResource"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestTag/Project" = var.project_name }
        }
      },
      {
        Sid    = "KMSManageProjectKeys"
        Effect = "Allow"
        Action = [
          "kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus",
          "kms:ListResourceTags", "kms:TagResource", "kms:UntagResource",
          "kms:EnableKeyRotation", "kms:CreateAlias", "kms:DeleteAlias",
          "kms:CreateGrant", "kms:ListGrants", "kms:RetireGrant",
          "kms:ScheduleKeyDeletion", "kms:PutKeyPolicy",
          # CreateBackupVault with a CMK needs these on the key (AWS Backup docs).
          "kms:Decrypt", "kms:GenerateDataKey"
        ]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = var.project_name }
        }
      },
      {
        Sid    = "KMSProjectAliases"
        Effect = "Allow"
        Action = ["kms:CreateAlias", "kms:DeleteAlias"]
        Resource = [
          "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/${var.project_name}*",
          "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/eks/${var.project_name}*"
        ]
      },
      {
        Sid      = "KMSList"
        Effect   = "Allow"
        Action   = ["kms:ListAliases", "kms:ListKeys"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsManagement"
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${var.project_name}*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-logs/${var.project_name}*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${var.project_name}*"
        ]
      },
      {
        Sid      = "CloudWatchLogsDescribe"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      # Backup: the actions Terraform needs for the vault, plan and selection
      # in modules/eks/backup.tf. No restore, recovery-point deletion or
      # vault-lock actions: teardown runs locally as an admin, never in CI.
      {
        Sid    = "BackupProjectVault"
        Effect = "Allow"
        Action = [
          "backup:CreateBackupVault", "backup:DeleteBackupVault", "backup:DescribeBackupVault",
          "backup:PutBackupVaultAccessPolicy", "backup:GetBackupVaultAccessPolicy",
          "backup:DeleteBackupVaultAccessPolicy", "backup:ListRecoveryPointsByBackupVault"
        ]
        Resource = "arn:aws:backup:${var.aws_region}:${data.aws_caller_identity.current.account_id}:backup-vault:${var.project_name}*"
      },
      {
        # Plan ARNs carry a generated id, not the name, so these stay on "*".
        Sid    = "BackupPlansAndSelections"
        Effect = "Allow"
        Action = [
          "backup:CreateBackupPlan", "backup:UpdateBackupPlan", "backup:DeleteBackupPlan",
          "backup:GetBackupPlan", "backup:ListBackupPlans", "backup:ListBackupPlanVersions",
          "backup:CreateBackupSelection", "backup:DeleteBackupSelection",
          "backup:GetBackupSelection", "backup:ListBackupSelections",
          "backup:ListBackupVaults", "backup:TagResource", "backup:UntagResource", "backup:ListTags"
        ]
        Resource = "*"
      },
      {
        # Required by CreateBackupVault.
        Sid      = "BackupStorageMount"
        Effect   = "Allow"
        Action   = "backup-storage:MountCapsule"
        Resource = "*"
      },
      {
        Sid      = "SSMParameterAccess"
        Effect   = "Allow"
        Action   = ["ssm:*Parameter*", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}*"
      },
      {
        Sid    = "SSMPublicParameterAccess"
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = [
          "arn:aws:ssm:${var.aws_region}::parameter/aws/service/eks/*",
          "arn:aws:ssm:${var.aws_region}::parameter/aws/service/bottlerocket/*"
        ]
      },
      {
        Sid      = "SSMDescribe"
        Effect   = "Allow"
        Action   = "ssm:DescribeParameters"
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = "secretsmanager:*"
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}*"
        ]
      },
      {
        Sid      = "STSAccess"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_services" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_services.arn
}

# Outputs

output "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_locks_table" {
  description = "DynamoDB table name for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "terraform_locks_table_arn" {
  description = "DynamoDB table ARN for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "IAM role name for GitHub Actions"
  value       = aws_iam_role.github_actions.name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Output the backend configuration for copy-paste
output "backend_config" {
  description = "Backend configuration to add to environments/aws/dev/providers.tf"
  value       = <<-EOT
    # Add this to your terraform block in environments/aws/dev/providers.tf:
    backend "s3" {
      bucket         = "${aws_s3_bucket.terraform_state.id}"
      key            = "mlops-platform/dev/terraform.tfstate"
      region         = "${var.aws_region}"
      encrypt        = true
      dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
    }
  EOT
}

# Output GitHub Actions workflow configuration
output "github_actions_config" {
  description = "Configuration for GitHub Actions workflow"
  value       = <<-EOT
    # Add these to your GitHub Actions workflow:

    permissions:
      id-token: write
      contents: read

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${aws_iam_role.github_actions.arn}
        aws-region: ${var.aws_region}
  EOT
}