# Secret Generation via AWS Secrets Manager. The random_password values below
# are also stored in Terraform state.
#
# The MLflow database password is not here: RDS manages it
# (manage_master_user_password, modules/eks/database.tf). The ArgoCD login is
# the chart's argocd-initial-admin-secret. See docs/secrets-management.md.

# Grafana admin password: generated once, stored in SSM
# (modules/aws-platform/monitoring.tf) and in Terraform state.
resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

# Slack Webhook URL for AlertManager notifications
resource "aws_secretsmanager_secret" "slack_webhook_url" {
  count = var.slack_notifications_enabled ? 1 : 0

  name        = "${var.cluster_name}/alertmanager/slack-webhook-url"
  description = "Slack webhook URL for AlertManager notifications"
  kms_key_id  = var.kms_key_arn
  # Dev secrets guard infrastructure that terraform destroy removes with
  # them - skip the 30-day recovery window that left soft-deleted entries
  # behind after the July teardown.
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "slack_webhook_url" {
  count = var.slack_notifications_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.slack_webhook_url[0].id
  secret_string = var.slack_webhook_url

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Non-secret configuration in SSM for easy access

resource "aws_ssm_parameter" "cluster_endpoint" {
  name        = "/${var.cluster_name}/cluster/endpoint"
  description = "EKS cluster endpoint"
  type        = "String"
  value       = module.eks.cluster_endpoint

  tags = var.tags
}

resource "aws_ssm_parameter" "cluster_name_param" {
  name        = "/${var.cluster_name}/cluster/name"
  description = "EKS cluster name"
  type        = "String"
  value       = module.eks.cluster_name

  tags = var.tags
}

# Outputs - reference ARNs, not values (to avoid state exposure)
