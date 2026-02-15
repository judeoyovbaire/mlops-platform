# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-cloud MLOps platform for model training, versioning, and deployment on AWS EKS, Azure AKS, or GCP GKE. Provides self-service ML infrastructure where data scientists can deploy models without DevOps tickets.

## Common Commands

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest tests/ -v --tb=short                    # All tests
pytest tests/test_pipeline_components.py -v   # Single test file
pytest tests/ -v -k "test_function_name"      # Single test by name
pytest tests/ -v --cov=pipelines              # With coverage

# Linting
ruff check pipelines/ examples/               # Check Python code
ruff format --check pipelines/ examples/      # Check formatting
terraform fmt -check -recursive infrastructure/terraform/  # Check Terraform

# Validate configuration
make validate                                 # All validations
python -c "import yaml; yaml.safe_load_all(open('pipelines/training/ml-training-workflow.yaml'))"  # Validate Argo workflow

# Local development (Kind cluster - no cloud credentials needed)
make deploy-local                             # Deploy to local Kind cluster
make status-local                             # Check local cluster status
make destroy-local                            # Destroy local Kind cluster

# Deploy to cloud (requires credentials)
make deploy-aws                               # Deploy to AWS EKS
make deploy-azure                             # Deploy to Azure AKS
make deploy-gcp                               # Deploy to GCP GKE

# Port forwarding (post-deployment)
make port-forward-mlflow                      # MLflow at localhost:5000
make port-forward-argocd                      # ArgoCD at localhost:8080
make port-forward-grafana                     # Grafana at localhost:3000
make port-forward-argo-wf                     # Argo Workflows at localhost:2746

# Destroy infrastructure
cd infrastructure/terraform/environments/aws/dev && terraform destroy
cd infrastructure/terraform/environments/azure/dev && terraform destroy
cd infrastructure/terraform/environments/gcp/dev && terraform destroy
```

## Infrastructure Teardown Notes

When destroying AWS infrastructure, be aware of these potential issues:

1. **Karpenter nodes**: The terraform configuration includes automatic cleanup of Karpenter-managed nodes before destruction. If this fails, manually delete NodePools first:
   ```bash
   kubectl delete nodepools --all
   kubectl delete ec2nodeclasses --all
   ```

2. **KServe InferenceServices**: If namespaces get stuck during deletion due to finalizers:
   ```bash
   kubectl patch inferenceservice <name> -n mlops --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
   ```

3. **State locks**: If terraform shows state lock errors, force unlock:
   ```bash
   terraform force-unlock -force <lock-id>
   ```

4. **ENI cleanup**: AWS may take 10-20 minutes to clean up ENIs after EC2 instances terminate. Subnets cannot be deleted until ENIs are released.

## Architecture

### Cloud Provider Modules

Each cloud has a dedicated Terraform module under `infrastructure/terraform/modules/`:
- **eks/**: AWS EKS with Karpenter for GPU autoscaling, IRSA for pod identity, ALB Ingress
- **aks/**: Azure AKS with KEDA for event-driven scaling, Workload Identity, Key Vault integration
- **gke/**: GCP GKE with Node Auto-provisioning, Workload Identity Federation, Secret Manager

All modules create: VPC/VNet, managed Kubernetes cluster, node pools (general/training/GPU), storage backend for MLflow, container registry, and secrets management.

### MLOps Stack (Deployed via Helm)

- **Argo Workflows** (`argo` namespace): ML pipeline orchestration
- **MLflow** (`mlflow` namespace): Experiment tracking and model registry
- **KServe** (`mlops` namespace): Model serving with RawDeployment mode (not Serverless - see ADR-003)
- **ArgoCD** (`argocd` namespace): GitOps deployments
- **Prometheus/Grafana** (`monitoring` namespace): Observability

### Training Pipeline

The ML pipeline is defined in `pipelines/training/ml-training-workflow.yaml` as an Argo WorkflowTemplate with 5 DAG steps:
1. `load-data` → 2. `validate-data` → 3. `feature-engineering` → 4. `train-model` → 5. `register-model`

Python scripts for each step are in `pipelines/training/src/` and mounted via ConfigMap.

### Helm Values Structure

Cloud-specific Helm values are in `infrastructure/helm/{aws,azure,gcp}/`. Common values shared across clouds are in `infrastructure/helm/common/`.

## Key Design Decisions

- **KServe over Seldon Core**: Seldon moved to BSL 1.1 (paid for commercial use). KServe is Apache 2.0, CNCF Incubating.
- **Karpenter over Cluster Autoscaler (AWS)**: Faster provisioning, better bin-packing, native spot support.
- **RawDeployment mode for KServe**: Simpler debugging, works without Istio/Knative, direct service mesh control.

See `docs/adr/` for full Architecture Decision Records.

## Testing

Tests are in `tests/` using pytest:

| File | Purpose |
|------|---------|
| `test_pipeline_components.py` | Unit tests for pipeline scripts in `pipelines/training/src/` |
| `test_terraform_modules.py` | Terraform configuration validation |
| `test_ci_integration.py` | CI workflow validation |
| `test_infrastructure.py` | Infrastructure module tests |
| `test_e2e_deployment.py` | End-to-end deployment tests |

Key fixtures in `conftest.py`:
- `iris_dataframe`: Iris dataset as DataFrame with species column
- `iris_csv_path`: Temp CSV file with iris data (for file-based tests)
- `sample_features`, `sample_batch_features`: NumPy arrays for prediction tests
- `mock_mlflow`, `mock_mlflow_client`: Mocked MLflow for unit tests
- `trained_model_artifacts`: Dict with paths for model training tests
- `csv_with_nulls_path`, `malformed_csv_path`: Edge case test data

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/ci-cd.yaml`) runs on every push/PR:
1. Lint Python (ruff) and Terraform (fmt)
2. Validate Terraform, Kubernetes manifests, and Helm values
3. Security scan (Trivy)
4. Run pytest with coverage
5. Terraform plan for all clouds (parallel)

Manual deployment triggers: Actions → CI/CD → Run workflow → Select cloud and action.