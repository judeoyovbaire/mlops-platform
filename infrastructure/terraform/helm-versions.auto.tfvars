# Shared Helm Chart Versions
# Single source of truth — symlinked into environments/aws/dev.
# AWS-specific versions (AWS LB Controller, Karpenter, Argo Rollouts/Events, OpenCost, DCGM)
# remain in their respective environment variables.tf files.

# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
helm_cert_manager_version = "v1.21.3"
# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
helm_argocd_version = "10.11.6"
# One version for the kserve-crd, kserve-resources and kserve-runtime-configs
# charts. It also sets the huggingfaceserver image in
# pipelines/serving-runtime-contract.yaml (test_serving_runtime_contract.py).
# renovate: datasource=docker depName=ghcr.io/kserve/charts/kserve-resources
helm_kserve_version = "v0.21.0"
# Snapshot the MLflow RDS instance before bumping this version: with
# backendStore.databaseMigration: true (mlflow-values.yaml) an init container
# runs Alembic against RDS on first start, and those migrations are irreversible.
# renovate: datasource=helm depName=mlflow registryUrl=https://community-charts.github.io/helm-charts
helm_mlflow_version = "1.11.7"
# renovate: datasource=helm depName=argo-workflows registryUrl=https://argoproj.github.io/argo-helm
helm_argo_workflows_version = "2.0.15"
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
helm_prometheus_stack_version = "92.17.0"
# Capped below chart 3.10 in renovate.json: Kyverno 1.20 rejects create/update
# of ClusterPolicy (removed in 1.21), so the cap stays until the policies move
# to CEL ValidatingPolicy.
# renovate: datasource=helm depName=kyverno registryUrl=https://kyverno.github.io/kyverno
helm_kyverno_version = "3.9.2"
# renovate: datasource=helm depName=external-secrets registryUrl=https://charts.external-secrets.io
helm_external_secrets_version = "2.14.0"
# 6.55.0 is the last open-source chart in grafana/helm-charts: 7.x there is
# Enterprise-only (capped in renovate.json). The OSS chart continues in
# grafana-community/helm-charts; moving there is a separate change.
# renovate: datasource=helm depName=loki registryUrl=https://grafana.github.io/helm-charts
helm_loki_version = "6.55.0"
# grafana/tempo is deprecated; the chart continues in grafana-community.
# Held on 2.x (Tempo 2.10) in renovate.json: Tempo 3 needs a config rewrite.
# renovate: datasource=helm depName=tempo registryUrl=https://grafana-community.github.io/helm-charts
helm_tempo_version = "2.4.0"
# renovate: datasource=helm depName=opentelemetry-collector registryUrl=https://open-telemetry.github.io/opentelemetry-helm-charts
helm_otel_collector_version = "0.178.1"
# renovate: datasource=helm depName=alloy registryUrl=https://grafana.github.io/helm-charts
helm_alloy_version = "1.15.0"
# renovate: datasource=helm depName=nvidia-device-plugin registryUrl=https://nvidia.github.io/k8s-device-plugin
helm_nvidia_device_plugin_version = "0.20.1"
