# IRSA for Argo Workflow pods (ML pipelines)
#
# Two buckets:
# - MLflow artifacts: pipeline steps log models to MLflow, whose clients
#   upload DIRECTLY to S3 (the tracking server only hands out the s3:// URI).
# - Argo artifacts: the executor's init and wait containers download and
#   upload declared step artifacts with these credentials (useSDKCreds).
#   Logs are not archived (archiveLogs is off). The argo-server has no S3
#   role, so the UI cannot show artifact contents.
module "argo_workflow_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.8.2"

  name = "${var.cluster_name}-argo-workflow"

  oidc_providers = {
    main = {
      provider_arn               = var.eks.oidc_provider_arn
      namespace_service_accounts = ["argo:argo-workflow"]
    }
  }

  policies = {
    mlflow_artifacts = aws_iam_policy.argo_workflow_mlflow_s3.arn
  }
}

# Scoped to the two buckets. Delete is included because the MLflow client
# cleans up partial uploads and registry operations can overwrite artifact
# metadata files.
resource "aws_iam_policy" "argo_workflow_mlflow_s3" {
  name        = "${var.cluster_name}-argo-workflow-mlflow-s3"
  description = "Allow Argo workflow pods to read/write MLflow and Argo artifacts in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.eks.mlflow_s3_bucket}",
          "arn:aws:s3:::${var.eks.argo_artifacts_s3_bucket}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "arn:aws:s3:::${var.eks.mlflow_s3_bucket}/*",
          "arn:aws:s3:::${var.eks.argo_artifacts_s3_bucket}/*",
        ]
      },
      {
        # The artifact bucket is SSE-KMS encrypted and its key policy
        # delegates to IAM, so PutObject/GetObject also need the data-key
        # operations. ViaService keeps this usable only through S3.
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}
