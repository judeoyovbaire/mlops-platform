# IRSA for KServe InferenceService pods
#
# The champion InferenceService (examples/kserve) runs its predictor under
# the kserve-inference SA. The KServe storage-initializer pulls the model
# artifacts straight from the MLflow S3 bucket, so this SA needs read
# access - the GKE side wires the equivalent through Workload Identity
# (modules/gke/workload-identity.tf).
module "kserve_inference_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-kserve-inference"

  oidc_providers = {
    main = {
      provider_arn               = var.eks.oidc_provider_arn
      namespace_service_accounts = ["mlops:kserve-inference"]
    }
  }

  policies = {
    mlflow_artifacts_read = aws_iam_policy.kserve_inference_mlflow_s3_read.arn
  }
}

# Read-only: serving pods only ever download model artifacts.
resource "aws_iam_policy" "kserve_inference_mlflow_s3_read" {
  name        = "${var.cluster_name}-kserve-inference-mlflow-s3-read"
  description = "Allow KServe inference pods to read MLflow model artifacts from S3"

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
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.eks.mlflow_s3_bucket}/*"
      },
      {
        # Objects are SSE-KMS encrypted; reads need the decrypt half only.
        Effect = "Allow"
        Action = [
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

resource "kubernetes_service_account" "kserve_inference" {
  metadata {
    name      = "kserve-inference"
    namespace = kubernetes_namespace.mlops.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.kserve_inference_irsa.arn
    }
    labels = {
      "app.kubernetes.io/name"    = "kserve-inference"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }
}
