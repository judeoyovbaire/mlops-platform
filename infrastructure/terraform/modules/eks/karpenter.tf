# Karpenter - GPU/Training Node Autoscaling
# IRSA, controller policy, node IAM role, instance profile, and EKS access entry

# Karpenter - IRSA
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.8.2"

  name = "${var.cluster_name}-karpenter"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }

  # Karpenter controller policy (replaces removed attach_karpenter_controller_policy in IAM v6)
  policies = {
    karpenter_controller = aws_iam_policy.karpenter_controller.arn
  }

  tags = var.tags
}

# Comprehensive Karpenter controller policy
# Replaces the built-in attach_karpenter_controller_policy (removed in IAM module v6)
# and the previous karpenter_instance_profile policy, consolidated into a single policy
resource "aws_iam_policy" "karpenter_controller" {
  name        = "${var.cluster_name}-karpenter-controller"
  description = "Policy for Karpenter controller to manage EC2 instances and instance profiles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KarpenterEC2ReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribePlacementGroups",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeSpotPriceHistory"
        ]
        Resource = "*"
      },
      {
        Sid    = "KarpenterEC2WriteActions"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:RunInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.region
          }
        }
      },
      {
        # Destructive actions only on resources Karpenter launched for this
        # cluster (Karpenter v1 tags them kubernetes.io/cluster/<name>=owned
        # and karpenter.sh/nodepool), per the upstream reference policy.
        # Previously TerminateInstances applied to every instance in the region.
        Sid    = "KarpenterScopedDeleteActions"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"                                       = data.aws_region.current.region
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "KarpenterInstanceProfileManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfiles",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Sid      = "KarpenterPassRoleToNodeRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Sid    = "KarpenterSSMReadActions"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"
      },
      {
        Sid    = "KarpenterPricingActions"
        Effect = "Allow"
        Action = [
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Sid    = "KarpenterEKSActions"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "arn:aws:eks:*:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      },
      {
        # Interruption handling (JDH-415): the controller drains the queue
        # EventBridge fills below. Same three actions as the v1.15 reference.
        Sid    = "KarpenterInterruptionQueueActions"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })

  tags = var.tags
}

# IAM Role for Karpenter nodes
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name

  tags = var.tags
}

# Allow Karpenter nodes to join the cluster
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# Spot interruption handling (JDH-415)
#
# Karpenter only registers its interruption controller when
# settings.interruptionQueue names an SQS queue (v1.15.1
# pkg/controllers/controllers.go). Without it a spot reclaim kills the pods
# on the node with no 2-minute warning, cordon or drain, and scheduled
# maintenance is ignored. With it, Karpenter cordons and drains on spot
# interruption warnings, scheduled-change health events, instance
# stopping/terminating and capacity-reservation interruptions; rebalance
# recommendations only become a node event (v1.15.1
# pkg/controllers/interruption/utils.go, actionForMessage). The GPU and
# training NodePools are spot-only, so this matters for every benchmark and
# for any autoscaling or availability number (JDH-400).
#
# Queue, queue policy and rules follow Karpenter's v1.15 getting-started
# CloudFormation (website/content/en/preview/getting-started/
# getting-started-with-karpenter/cloudformation.yaml at v1.15.1). Two
# deliberate differences: the queue name carries a suffix so it is not
# mistaken for the cluster itself, and SendMessage is limited to this
# account (aws:SourceAccount), which the reference leaves open.
resource "aws_sqs_queue" "karpenter_interruption" {
  name = "${var.cluster_name}-karpenter-interruption"
  # Interruption notices are useless after the 2-minute warning has passed.
  message_retention_seconds = 300
  # SSE-SQS as in the reference. A CMK would need a key policy for
  # events.amazonaws.com, for a queue that holds only instance IDs.
  sqs_managed_sse_enabled = true

  tags = var.tags
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    sid    = "EC2InterruptionPolicy"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "DenyHTTP"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

# One EventBridge rule per event class in the reference. The state-change
# rule fires for every instance in the region; Karpenter discards the ones
# that are not its nodes, and SQS requests at this volume are within the
# free tier.
locals {
  karpenter_interruption_events = {
    spot-interruption     = { source = "aws.ec2", detail_type = "EC2 Spot Instance Interruption Warning" }
    rebalance             = { source = "aws.ec2", detail_type = "EC2 Instance Rebalance Recommendation" }
    instance-state-change = { source = "aws.ec2", detail_type = "EC2 Instance State-change Notification" }
    capacity-reservation  = { source = "aws.ec2", detail_type = "EC2 Capacity Reservation Instance Interruption Warning" }
    scheduled-change      = { source = "aws.health", detail_type = "AWS Health Event" }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  name        = "${var.cluster_name}-karpenter-${each.key}"
  description = "Karpenter interruption handling: ${each.value.detail_type}"
  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = [each.value.detail_type]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_interruption" {
  for_each = local.karpenter_interruption_events

  rule      = aws_cloudwatch_event_rule.karpenter_interruption[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}
