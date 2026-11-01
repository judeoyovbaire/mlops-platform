# Shared Helm Chart Versions
# Single source of truth — symlinked into environments/aws/dev.
# AWS-specific versions (AWS LB Controller, Karpenter, Argo Rollouts/Events, OpenCost, DCGM)
# remain in their respective environment variables.tf files.

# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
helm_cert_manager_version = "v1.21.3"
# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
helm_argocd_version = "10.11.6"
# renovate: datasource=docker depName=ghcr.io/kserve/charts/kserve
helm_kserve_version = "v0.16.0"
# Snapshot the MLflow RDS instance before bumping this version: with
# backendStore.databaseMigration: true (mlflow-values.yaml) an init container
# runs Alembic against RDS on first start, and those migrations are irreversible.
# renovate: datasource=helm depName=mlflow registryUrl=https://community-charts.github.io/helm-charts
helm_mlflow_version = "1.11.7"
# renovate: datasource=helm depName=argo-workflows registryUrl=https://argoproj.github.io/argo-helm
helm_argo_workflows_version = "0.47.3"
# renovate: datasource=helm depName=minio registryUrl=https://charts.min.io/
helm_minio_version = "5.4.0"
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
helm_prometheus_stack_version = "81.6.9"
# Capped below chart 3.10 in renovate.json: Kyverno 1.20 rejects create/update
# of ClusterPolicy (removed in 1.21), so the cap stays until the policies move
# to CEL ValidatingPolicy.
# renovate: datasource=helm depName=kyverno registryUrl=https://kyverno.github.io/kyverno
helm_kyverno_version = "3.9.2"
# renovate: datasource=helm depName=external-secrets registryUrl=https://charts.external-secrets.io
helm_external_secrets_version = "2.14.0"
# renovate: datasource=helm depName=loki registryUrl=https://grafana.github.io/helm-charts
helm_loki_version = "6.24.0"
# renovate: datasource=helm depName=tempo registryUrl=https://grafana.github.io/helm-charts
helm_tempo_version = "1.15.0"
# renovate: datasource=helm depName=opentelemetry-collector registryUrl=https://open-telemetry.github.io/opentelemetry-helm-charts
helm_otel_collector_version = "0.108.0"
# renovate: datasource=helm depName=alloy registryUrl=https://grafana.github.io/helm-charts
helm_alloy_version = "0.12.0"
# renovate: datasource=helm depName=nvidia-device-plugin registryUrl=https://nvidia.github.io/k8s-device-plugin
helm_nvidia_device_plugin_version = "0.19.3"
