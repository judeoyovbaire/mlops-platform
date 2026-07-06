# IRSA for Argo Workflow pods (ML pipelines)
#
# Training/serving pipeline steps log artifacts to MLflow, whose artifact
# store is S3. MLflow clients upload DIRECTLY to the bucket (the tracking
# server only hands out the s3:// URI), so the workflow pods themselves
# need S3 credentials - without this role they fail with
# "Unable to locate credentials" at model-logging time.
module "argo_workflow_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

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

# Scoped to the MLflow artifact bucket only. Delete is included because the
# MLflow client cleans up partial uploads and registry operations can
# overwrite artifact metadata files.
resource "aws_iam_policy" "argo_workflow_mlflow_s3" {
  name        = "${var.cluster_name}-argo-workflow-mlflow-s3"
  description = "Allow Argo workflow pods to read/write MLflow artifacts in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.eks.mlflow_s3_bucket}"
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
        Resource = "arn:aws:s3:::${var.eks.mlflow_s3_bucket}/*"
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
