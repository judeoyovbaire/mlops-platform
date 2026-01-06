# =============================================================================
# External Secrets Operator - Azure Key Vault Integration
# =============================================================================

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.helm_external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true

  # Workload Identity for External Secrets
  set {
    name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
    value = module.aks.external_secrets_identity_client_id
  }

  set {
    name  = "podLabels.azure\\.workload\\.identity/use"
    value = "true"
    type  = "string"
  }

  depends_on = [module.aks]
}

# =============================================================================
# ClusterSecretStore for Azure Key Vault
# =============================================================================

resource "kubectl_manifest" "cluster_secret_store_azure" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: azure-keyvault
    spec:
      provider:
        azurekv:
          authType: WorkloadIdentity
          vaultUrl: ${module.aks.key_vault_uri}
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}

# =============================================================================
# External Secrets
# =============================================================================

# MLflow Database Credentials
resource "kubectl_manifest" "mlflow_db_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: mlflow-db-credentials
      namespace: mlflow
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: azure-keyvault
        kind: ClusterSecretStore
      target:
        name: mlflow-db-credentials
        creationPolicy: Owner
      data:
        - secretKey: password
          remoteRef:
            key: mlflow-db-password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store_azure,
    kubernetes_namespace.mlflow
  ]
}

# Grafana Admin Password
resource "kubectl_manifest" "grafana_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: grafana-admin-credentials
      namespace: monitoring
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: azure-keyvault
        kind: ClusterSecretStore
      target:
        name: grafana-admin-credentials
        creationPolicy: Owner
      data:
        - secretKey: admin-password
          remoteRef:
            key: grafana-admin-password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store_azure,
    kubernetes_namespace.monitoring
  ]
}

# ArgoCD Admin Password
resource "kubectl_manifest" "argocd_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: argocd-admin-credentials
      namespace: argocd
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: azure-keyvault
        kind: ClusterSecretStore
      target:
        name: argocd-admin-credentials
        creationPolicy: Owner
      data:
        - secretKey: password
          remoteRef:
            key: argocd-admin-password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store_azure,
    helm_release.argocd
  ]
}