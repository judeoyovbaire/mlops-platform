# AWS Backup for RDS and Other Resources

resource "aws_backup_vault" "mlops" {
  count = var.enable_aws_backup ? 1 : 0

  name        = "${var.cluster_name}-mlops-backup-vault"
  kms_key_arn = var.enable_kms_encryption ? aws_kms_key.mlops[0].arn : null

  tags = var.tags
}

resource "aws_backup_plan" "mlops" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${var.cluster_name}-mlops-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.mlops[0].name
    schedule          = "cron(0 5 ? * * *)" # Daily at 5 AM UTC

    lifecycle {
      delete_after = var.backup_retention_days
    }

    recovery_point_tags = var.tags
  }

  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.mlops[0].name
    schedule          = "cron(0 5 ? * SUN *)" # Weekly on Sunday at 5 AM UTC

    lifecycle {
      delete_after = var.backup_retention_days * 4 # Keep weekly backups 4x longer
    }

    recovery_point_tags = var.tags
  }

  tags = var.tags
}

resource "aws_backup_selection" "mlops_rds" {
  count = var.enable_aws_backup ? 1 : 0

  name         = "${var.cluster_name}-mlops-rds-backup"
  plan_id      = aws_backup_plan.mlops[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  resources = [
    aws_db_instance.mlflow.arn
  ]
}

resource "aws_iam_role" "backup" {
  count = var.enable_aws_backup ? 1 : 0

  name = "${var.cluster_name}-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  count = var.enable_aws_backup ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup[0].name
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  count = var.enable_aws_backup ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  role       = aws_iam_role.backup[0].name
}
