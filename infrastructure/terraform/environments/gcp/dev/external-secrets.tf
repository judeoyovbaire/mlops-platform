# =============================================================================
# External Secrets Operator Configuration
# =============================================================================
# Syncs secrets from GCP Secret Manager to Kubernetes

# External Secrets Operator Helm release
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.helm_external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = module.gke.external_secrets_service_account_email
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }

  depends_on = [module.gke]
}

# Wait for CRDs to be ready
resource "time_sleep" "wait_for_external_secrets_crds" {
  depends_on      = [helm_release.external_secrets]
  create_duration = "60s"
}

# =============================================================================
# ClusterSecretStore - GCP Secret Manager
# =============================================================================

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: gcp-secret-manager
    spec:
      provider:
        gcpsm:
          projectID: ${var.project_id}
          auth:
            workloadIdentity:
              clusterLocation: ${var.zones[0]}
              clusterName: ${var.cluster_name}
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [time_sleep.wait_for_external_secrets_crds]
}

# =============================================================================
# External Secrets - MLflow
# =============================================================================

resource "kubectl_manifest" "mlflow_db_credentials" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: mlflow-db-credentials
      namespace: mlflow
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: gcp-secret-manager
        kind: ClusterSecretStore
      target:
        name: mlflow-db-credentials
        creationPolicy: Owner
      data:
        - secretKey: username
          remoteRef:
            key: ${module.gke.mlflow_db_password_secret}
            property: username
            decodingStrategy: None
            conversionStrategy: Default
        - secretKey: password
          remoteRef:
            key: ${module.gke.mlflow_db_password_secret}
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.mlflow
  ]
}

# =============================================================================
# External Secrets - Grafana
# =============================================================================

resource "kubectl_manifest" "grafana_admin_credentials" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: grafana-admin-credentials
      namespace: monitoring
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: gcp-secret-manager
        kind: ClusterSecretStore
      target:
        name: grafana-admin-credentials
        creationPolicy: Owner
      data:
        - secretKey: username
          remoteRef:
            key: ${module.gke.grafana_admin_password_secret}
            property: username
            decodingStrategy: None
            conversionStrategy: Default
        - secretKey: password
          remoteRef:
            key: ${module.gke.grafana_admin_password_secret}
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.monitoring
  ]
}

# =============================================================================
# External Secrets - ArgoCD
# =============================================================================

resource "kubectl_manifest" "argocd_admin_credentials" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: argocd-admin-credentials
      namespace: argocd
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: gcp-secret-manager
        kind: ClusterSecretStore
      target:
        name: argocd-secret
        creationPolicy: Owner
        template:
          type: Opaque
          data:
            admin.password: "{{ .password | bcrypt }}"
            admin.passwordMtime: "{{ now | unixEpoch | toString }}"
      data:
        - secretKey: password
          remoteRef:
            key: ${module.gke.argocd_admin_password_secret}
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    helm_release.argocd
  ]
}

# =============================================================================
# External Secrets - MinIO
# =============================================================================

resource "kubectl_manifest" "minio_credentials" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: minio-credentials
      namespace: argo
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: gcp-secret-manager
        kind: ClusterSecretStore
      target:
        name: minio-credentials
        creationPolicy: Owner
      data:
        - secretKey: accesskey
          remoteRef:
            key: ${module.gke.minio_root_password_secret}
            property: accesskey
            decodingStrategy: None
            conversionStrategy: Default
        - secretKey: secretkey
          remoteRef:
            key: ${module.gke.minio_root_password_secret}
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.argo
  ]
}
