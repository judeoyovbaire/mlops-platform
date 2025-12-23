# =============================================================================
# External Secrets Operator - SSM to K8s Secret Sync
# =============================================================================

# IRSA for External Secrets Operator
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    ssm_read = aws_iam_policy.external_secrets_ssm.arn
  }
}

# IAM policy for External Secrets to read from SSM
resource "aws_iam_policy" "external_secrets_ssm" {
  name        = "${var.cluster_name}-external-secrets-ssm"
  description = "Allow External Secrets Operator to read from SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
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
  version          = "1.1.1" # Latest stable
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa.iam_role_arn
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }

  depends_on = [module.eks]
}

# ClusterSecretStore for AWS SSM Parameter Store
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: aws-ssm
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}

# External Secret for MLflow (syncs SSM to K8s Secret)
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
        name: aws-ssm
        kind: ClusterSecretStore
      target:
        name: mlflow-db-credentials
        creationPolicy: Owner
      data:
        - secretKey: password
          remoteRef:
            key: /${var.cluster_name}/mlflow/db-password
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
        name: aws-ssm
        kind: ClusterSecretStore
      target:
        name: minio-credentials
        creationPolicy: Owner
      data:
        - secretKey: root-password
          remoteRef:
            key: /${var.cluster_name}/minio/root-password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.argo
  ]
}
