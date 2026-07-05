# Shared AWS platform layer (Karpenter, core Helm releases, security policies,
# monitoring, namespaces, storage, multi-tenancy). Environment differences are
# explicit module inputs - see modules/aws-platform/variables.tf.
module "platform" {
  source = "../../../modules/aws-platform"

  environment  = "dev"
  eks          = module.eks
  cluster_name = var.cluster_name
  aws_region   = var.aws_region
  tags         = var.tags

  grafana_admin_password = random_password.grafana_admin.result

  acm_certificate_arn         = var.acm_certificate_arn
  kserve_ingress_domain       = var.kserve_ingress_domain
  slack_notifications_enabled = var.slack_notifications_enabled
  slack_channel               = var.slack_channel

  # dev: standalone MinIO, small footprint (module defaults)

  helm_alloy_version             = var.helm_alloy_version
  helm_argo_events_version       = var.helm_argo_events_version
  helm_argo_rollouts_version     = var.helm_argo_rollouts_version
  helm_argo_workflows_version    = var.helm_argo_workflows_version
  helm_argocd_version            = var.helm_argocd_version
  helm_aws_lb_controller_version = var.helm_aws_lb_controller_version
  helm_cert_manager_version      = var.helm_cert_manager_version
  helm_dcgm_exporter_version     = var.helm_dcgm_exporter_version
  helm_external_secrets_version  = var.helm_external_secrets_version
  helm_karpenter_version         = var.helm_karpenter_version
  helm_kserve_version            = var.helm_kserve_version
  helm_kyverno_version           = var.helm_kyverno_version
  helm_loki_version              = var.helm_loki_version
  helm_minio_version             = var.helm_minio_version
  helm_mlflow_version            = var.helm_mlflow_version
  helm_opencost_version          = var.helm_opencost_version
  helm_otel_collector_version    = var.helm_otel_collector_version
  helm_prometheus_stack_version  = var.helm_prometheus_stack_version
  helm_tempo_version             = var.helm_tempo_version
  helm_tetragon_version          = var.helm_tetragon_version
}
