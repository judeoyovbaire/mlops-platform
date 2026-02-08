# External Secrets Operator - Secrets Manager to K8s Secret Sync

# IRSA for External Secrets Operator
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  policies = {
    secrets_read = aws_iam_policy.external_secrets_sm.arn
  }
}

# IAM policy for External Secrets to read from Secrets Manager
resource "aws_iam_policy" "external_secrets_sm" {
  name        = "${var.cluster_name}-external-secrets-sm"
  description = "Allow External Secrets Operator to read from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# External Secrets Operator Helm release
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.helm_external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa.arn
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }

  depends_on = [time_sleep.alb_controller_ready]
}

# ClusterSecretStore for AWS Secrets Manager
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: aws-sm
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}

# External Secret for MLflow (syncs Secrets Manager to K8s Secret)
resource "kubectl_manifest" "mlflow_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: mlflow-db-credentials
      namespace: mlflow
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-sm
        kind: ClusterSecretStore
      target:
        name: mlflow-db-credentials
        creationPolicy: Owner
      data:
        - secretKey: password
          remoteRef:
            key: ${var.cluster_name}/mlflow/db-password
            property: password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.mlflow
  ]
}

# External Secret for MinIO (Argo Workflows artifact storage)
resource "kubectl_manifest" "argo_minio_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: minio-credentials
      namespace: argo
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-sm
        kind: ClusterSecretStore
      target:
        name: minio-credentials
        creationPolicy: Owner
      data:
        - secretKey: root-password
          remoteRef:
            key: ${var.cluster_name}/minio/root-password
            property: password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.argo
  ]
}
