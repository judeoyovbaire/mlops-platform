# S3 Storage for MLOps Platform
# Buckets for MLflow artifacts, Loki logs, Tempo traces and Argo Workflows artifacts

# S3 bucket for MLflow artifacts
resource "aws_s3_bucket" "mlflow_artifacts" {
  bucket = "${var.cluster_name}-mlflow-artifacts-${data.aws_caller_identity.current.account_id}"

  # Non-prod teardown empties versioned buckets automatically - the July
  # destroy stalled on BucketNotEmpty until object versions were purged by
  # hand (docs/retros/aws-deploy-retro-2026-07.md, finding group 7).
  force_destroy = var.environment != "prod"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "mlflow_artifacts" {
  bucket = aws_s3_bucket.mlflow_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for Loki logs storage
resource "aws_s3_bucket" "loki_logs" {
  bucket = "${var.cluster_name}-loki-logs-${data.aws_caller_identity.current.account_id}"

  # Non-prod teardown empties versioned buckets automatically - the July
  # destroy stalled on BucketNotEmpty until object versions were purged by
  # hand (docs/retros/aws-deploy-retro-2026-07.md, finding group 7).
  force_destroy = var.environment != "prod"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for Loki logs (retain for 30 days)
resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 bucket for Tempo traces storage
resource "aws_s3_bucket" "tempo_traces" {
  bucket = "${var.cluster_name}-tempo-traces-${data.aws_caller_identity.current.account_id}"

  # Non-prod teardown empties versioned buckets automatically - the July
  # destroy stalled on BucketNotEmpty until object versions were purged by
  # hand (docs/retros/aws-deploy-retro-2026-07.md, finding group 7).
  force_destroy = var.environment != "prod"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for Tempo traces (retain for 7 days)
resource "aws_s3_bucket_lifecycle_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    id     = "delete-old-traces"
    status = "Enabled"

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 3
    }
  }
}

# Argo Workflows artifacts (declared step outputs). Replaces the
# in-cluster MinIO, whose upstream images stopped being publicly pullable
# (2026-11-01 dry run: quay.io/minio/minio 401, Docker Hub minio/minio empty).
# Workflow pods reach it through IRSA (aws-platform/argo-workflow-irsa.tf).
resource "aws_s3_bucket" "argo_artifacts" {
  bucket = "${var.cluster_name}-argo-artifacts-${data.aws_caller_identity.current.account_id}"

  # Allow deletion with objects for dev environments
  force_destroy = var.environment != "prod"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "argo_artifacts" {
  bucket = aws_s3_bucket.argo_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "argo_artifacts" {
  bucket = aws_s3_bucket.argo_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "argo_artifacts" {
  bucket = aws_s3_bucket.argo_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Intermediate artifacts only: models are registered in MLflow (its own bucket).
resource "aws_s3_bucket_lifecycle_configuration" "argo_artifacts" {
  bucket = aws_s3_bucket.argo_artifacts.id

  rule {
    id     = "expire-pipeline-artifacts"
    status = "Enabled"

    filter {}

    expiration {
      days = 14
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
