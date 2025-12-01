# MLOps Platform on Kubernetes

A production-ready MLOps platform for model training, versioning, and deployment on Kubernetes. Enables data science teams to go from experiment to production with self-service workflows.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MLOps Platform                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │   Kubeflow   │    │   MLflow 3   │    │   KServe     │                   │
│  │  Pipelines   │───▶│  Tracking &  │───▶│   Model      │                   │
│  │              │    │  Registry    │    │   Serving    │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│         │                   │                   │                            │
│         ▼                   ▼                   ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      Kubernetes (EKS/GKE/AKS)                        │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │    │
│  │  │ GPU     │  │ Storage │  │ Istio   │  │ Prom/   │  │ ArgoCD  │   │    │
│  │  │ Nodes   │  │ (S3/GCS)│  │ Mesh    │  │ Grafana │  │ GitOps  │   │    │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Features

- **Kubeflow Pipelines**: Orchestrate ML workflows with reproducible pipelines
- **MLflow 3.x**: Experiment tracking, model registry with aliases, and GenAI support
- **KServe**: Production model serving with canary deployments and autoscaling (CNCF Incubating)
- **ArgoCD 3.x**: GitOps-based deployment automation
- **GPU Support**: NVIDIA GPU scheduling and resource optimization
- **Observability**: Prometheus metrics and Grafana dashboards for ML workloads

## Tech Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Pipeline Orchestration | Kubeflow Pipelines | Latest | ML workflow automation |
| Experiment Tracking | MLflow | 3.6.0 | Model versioning & metrics |
| Model Serving | KServe | 0.15.0 | Production inference (CNCF) |
| GitOps | ArgoCD | 3.2.x | Declarative deployments |
| Service Mesh | Istio | Latest | Traffic management |
| Monitoring | Prometheus + Grafana | Latest | Observability |
| Infrastructure | Terraform | Latest | IaC for cloud resources |

## Project Structure

```
mlops-platform/
├── infrastructure/
│   ├── kubernetes/       # K8s manifests and Kustomize
│   ├── terraform/        # Cloud infrastructure (EKS/GKE)
│   └── helm/             # Helm chart values
├── pipelines/
│   ├── training/         # Training pipeline definitions
│   └── inference/        # Inference pipeline definitions
├── components/
│   ├── mlflow/           # MLflow configuration
│   ├── kubeflow/         # Kubeflow setup
│   └── kserve/           # KServe InferenceService configs
├── scripts/              # Utility scripts
├── docs/                 # Documentation
└── examples/             # Example ML projects
```

## Getting Started

### Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or local with kind/minikube)
- kubectl configured
- Helm 3.x
- Terraform (for cloud infrastructure)

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform

# 2. Set up infrastructure (optional - for cloud deployment)
cd infrastructure/terraform
terraform init && terraform apply

# 3. Install platform components
./scripts/install.sh

# 4. Access the dashboards
kubectl port-forward svc/mlflow 5000:5000 -n mlflow
kubectl port-forward svc/argocd-server 8080:443 -n argocd
```

### Deploy a Model with KServe

```bash
# Deploy an sklearn model
kubectl apply -f components/kserve/inferenceservice-examples.yaml

# Check status
kubectl get inferenceservice -n mlops

# Test inference
SERVICE_URL=$(kubectl get inferenceservice sklearn-iris -n mlops -o jsonpath='{.status.url}')
curl -X POST "$SERVICE_URL/v1/models/sklearn-iris:predict" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
```

### Run a Training Pipeline

```python
# Compile the pipeline
cd pipelines/training
python example-pipeline.py

# Upload to Kubeflow Pipelines UI or run via SDK
```

## Roadmap

### Phase 1: Foundation (Current)
- [x] Set up Kubernetes cluster with GPU support
- [x] Deploy MLflow 3.x for experiment tracking
- [x] Basic Kubeflow Pipelines installation
- [x] ArgoCD 3.x for GitOps
- [x] KServe for model serving

### Phase 2: Training Infrastructure
- [ ] GPU scheduling and resource quotas
- [ ] Distributed training support
- [ ] Pipeline templates for common ML tasks
- [ ] Data versioning with DVC

### Phase 3: Model Serving
- [x] KServe deployment
- [x] Canary deployment examples
- [ ] A/B testing framework
- [ ] Model monitoring and drift detection

### Phase 4: Production Hardening
- [ ] Multi-tenancy support
- [ ] Cost optimization and FinOps
- [ ] Security hardening (RBAC, network policies)
- [ ] Comprehensive observability

## Documentation

- [Architecture Deep Dive](docs/architecture.md)

## Why These Tools?

### MLflow 3.x over alternatives
- Open source, framework-agnostic
- Native GenAI/LLM support (prompt versioning, agent tracing)
- Model aliases replace deprecated staging workflow
- Largest community adoption

### KServe over Seldon Core
- **Licensing**: Seldon Core moved to BSL 1.1 (paid for commercial use as of Jan 2024)
- KServe is fully open source (Apache 2.0), CNCF Incubating project
- Better PyTorch support out-of-the-box
- Serverless inference with scale-to-zero
- Native Kubeflow integration

### ArgoCD for GitOps
- CNCF graduated project
- Declarative, version-controlled deployments
- Strong Kubernetes native support
- Active community and enterprise adoption

## Contributing

Contributions are welcome! Please read the contributing guidelines first.

## License

MIT License - see LICENSE for details.

## Author

**Jude Oyovbaire** - Senior DevOps Engineer & Platform Architect

- Website: [judaire.io](https://judaire.io)
- LinkedIn: [linkedin.com/in/judeoyovbaire](https://linkedin.com/in/judeoyovbaire)
- GitHub: [github.com/judeoyovbaire](https://github.com/judeoyovbaire)