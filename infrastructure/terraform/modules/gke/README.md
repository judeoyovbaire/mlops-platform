# GKE Module

Provisions a GCP GKE cluster with VPC, system/training/GPU node pools, Node Auto-Provisioning (NAP), GCS buckets for artifacts, Cloud SQL PostgreSQL for MLflow metadata, Artifact Registry, Secret Manager secrets, Workload Identity Federation service accounts, and VPC Flow Logs.

## Usage

```hcl
module "gke" {
  source = "../../modules/gke"

  project_id         = "my-gcp-project"
  cluster_name       = "mlops-platform-dev"
  environment        = "dev"
  region             = "europe-west4"
  kubernetes_version = "1.32"

  master_authorized_networks = [
    {
      cidr_block   = "10.0.0.0/8"
      display_name = "Internal networks"
    }
  ]

  labels = {
    project     = "mlops-platform"
    environment = "dev"
    managed_by  = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_id | GCP project ID | `string` | n/a | yes |
| cluster_name | Name of the GKE cluster | `string` | `"mlops-platform-dev"` | no |
| region | GCP region for the cluster | `string` | `"europe-west4"` | no |
| zones | GCP zones for node pools | `list(string)` | `["europe-west4-a"]` | no |
| kubernetes_version | Kubernetes version for the cluster | `string` | `"1.32"` | no |
| release_channel | GKE release channel (STABLE, REGULAR, RAPID) | `string` | `"STABLE"` | no |
| labels | Labels to apply to all resources | `map(string)` | `{ project = "mlops-platform", environment = "dev", managed_by = "terraform" }` | no |
| vpc_cidr | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| subnet_cidr | CIDR block for the GKE subnet | `string` | `"10.0.0.0/20"` | no |
| pods_cidr | Secondary CIDR block for pods | `string` | `"10.16.0.0/14"` | no |
| services_cidr | Secondary CIDR block for services | `string` | `"10.20.0.0/20"` | no |
| master_cidr | CIDR block for the GKE master (private cluster) | `string` | `"172.16.0.0/28"` | no |
| enable_private_nodes | Enable private nodes (no public IPs) | `bool` | `true` | no |
| enable_private_endpoint | Enable private endpoint (master not accessible from internet) | `bool` | `true` | no |
| environment | Deployment environment | `string` | `"dev"` | no |
| master_authorized_networks | List of CIDR blocks authorized to access the master | `list(object({ cidr_block = string, display_name = string }))` | n/a | yes |
| system_machine_type | Machine type for system node pool | `string` | `"e2-standard-4"` | no |
| system_min_count | Minimum number of system nodes | `number` | `2` | no |
| system_max_count | Maximum number of system nodes | `number` | `5` | no |
| system_disk_size_gb | Disk size for system nodes (GB) | `number` | `100` | no |
| training_machine_type | Machine type for training node pool | `string` | `"c2-standard-8"` | no |
| training_min_count | Minimum number of training nodes | `number` | `0` | no |
| training_max_count | Maximum number of training nodes | `number` | `10` | no |
| training_disk_size_gb | Disk size for training nodes (GB) | `number` | `100` | no |
| training_use_spot | Use Spot VMs for training nodes | `bool` | `true` | no |
| gpu_machine_type | Machine type for GPU node pool | `string` | `"n1-standard-8"` | no |
| gpu_accelerator_type | GPU accelerator type | `string` | `"nvidia-tesla-t4"` | no |
| gpu_accelerator_count | Number of GPUs per node | `number` | `1` | no |
| gpu_min_count | Minimum number of GPU nodes | `number` | `0` | no |
| gpu_max_count | Maximum number of GPU nodes | `number` | `4` | no |
| gpu_disk_size_gb | Disk size for GPU nodes (GB) | `number` | `200` | no |
| gpu_use_spot | Use Spot VMs for GPU nodes | `bool` | `true` | no |
| enable_node_autoprovisioning | Enable cluster autoscaler node auto-provisioning | `bool` | `true` | no |
| nap_min_cpu | Minimum CPU cores for NAP | `number` | `4` | no |
| nap_max_cpu | Maximum CPU cores for NAP | `number` | `100` | no |
| nap_min_memory_gb | Minimum memory (GB) for NAP | `number` | `16` | no |
| nap_max_memory_gb | Maximum memory (GB) for NAP | `number` | `400` | no |
| nap_max_gpus | Maximum number of GPUs for NAP | `number` | `8` | no |
| cloudsql_tier | Cloud SQL machine tier | `string` | `"db-f1-micro"` | no |
| cloudsql_disk_size | Cloud SQL disk size (GB) | `number` | `20` | no |
| cloudsql_backup_enabled | Enable automated backups for Cloud SQL | `bool` | `true` | no |
| cloudsql_high_availability | Enable high availability for Cloud SQL | `bool` | `false` | no |
| cloudsql_database_version | PostgreSQL version for Cloud SQL | `string` | `"POSTGRES_17"` | no |
| artifact_registry_format | Artifact Registry format (DOCKER, MAVEN, NPM, etc.) | `string` | `"DOCKER"` | no |
| artifact_registry_immutable_tags | Enable immutable tags for Artifact Registry | `bool` | `false` | no |
| enable_vpc_flow_logs | Enable VPC Flow Logs for network troubleshooting | `bool` | `true` | no |
| flow_logs_aggregation_interval | Aggregation interval for VPC Flow Logs | `string` | `"INTERVAL_5_SEC"` | no |
| flow_logs_sampling_rate | Sampling rate for VPC Flow Logs (0.0 to 1.0) | `number` | `0.5` | no |
| slack_notifications_enabled | Enable Slack notifications for AlertManager | `bool` | `false` | no |
| slack_webhook_url | Slack webhook URL for AlertManager notifications | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_name | GKE cluster name |
| cluster_endpoint | GKE cluster endpoint |
| cluster_ca_certificate | GKE cluster CA certificate (base64 encoded) |
| cluster_location | GKE cluster location |
| cluster_master_version | GKE cluster master version |
| workload_identity_pool | Workload Identity pool for the cluster |
| vpc_id | VPC network ID |
| vpc_name | VPC network name |
| subnet_id | GKE subnet ID |
| subnet_name | GKE subnet name |
| mlflow_artifacts_bucket | GCS bucket name for MLflow artifacts |
| mlflow_artifacts_bucket_url | GCS bucket URL for MLflow artifacts |
| loki_gcs_bucket | GCS bucket name for Loki logs |
| tempo_gcs_bucket | GCS bucket name for Tempo traces |
| cloudsql_instance_name | Cloud SQL instance name |
| cloudsql_connection_name | Cloud SQL connection name for Cloud SQL Proxy |
| cloudsql_private_ip | Cloud SQL private IP address |
| cloudsql_database_name | Cloud SQL database name |
| cloudsql_user | Cloud SQL username |
| artifact_registry_repository | Artifact Registry repository name |
| artifact_registry_url | Artifact Registry repository URL |
| mlflow_db_password_secret | Secret Manager secret ID for MLflow DB password |
| minio_root_password_secret | Secret Manager secret ID for MinIO root password |
| argocd_admin_password_secret | Secret Manager secret ID for ArgoCD admin password |
| grafana_admin_password_secret | Secret Manager secret ID for Grafana admin password |
| slack_webhook_url_secret | Secret Manager secret ID for Slack webhook URL |
| mlflow_service_account_email | MLflow service account email |
| external_secrets_service_account_email | External Secrets service account email |
| argo_workflows_service_account_email | Argo Workflows service account email |
| argocd_service_account_email | ArgoCD service account email |
| kserve_service_account_email | KServe service account email |
| prometheus_service_account_email | Prometheus service account email |
| loki_service_account_email | Loki service account email |
| tempo_service_account_email | Tempo service account email |
| node_pool_service_account_email | Node pool service account email |
| project_id | GCP project ID |
| project_number | GCP project number |
| region | GCP region |
| kubectl_config_command | Command to configure kubectl |
| access_info | Access information for deployed services |
