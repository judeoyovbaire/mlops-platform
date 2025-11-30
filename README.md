# MLOps Platform on Kubernetes

A production-ready MLOps platform for model training, versioning, and deployment on Kubernetes. Enables data science teams to go from experiment to production with self-service workflows.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MLOps Platform                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │   Kubeflow   │    │    MLflow    │    │ Seldon Core  │                   │
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
- **MLflow**: Experiment tracking, model registry, and artifact storage
- **Seldon Core**: Production model serving with A/B testing and canary deployments
- **ArgoCD**: GitOps-based deployment automation
- **GPU Support**: NVIDIA GPU scheduling and resource optimization
- **Observability**: Prometheus metrics and Grafana dashboards for ML workloads

## Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Pipeline Orchestration | Kubeflow Pipelines | ML workflow automation |
| Experiment Tracking | MLflow | Model versioning & metrics |
| Model Serving | Seldon Core | Production inference |
| GitOps | ArgoCD | Declarative deployments |
| Service Mesh | Istio | Traffic management |
| Monitoring | Prometheus + Grafana | Observability |
| Infrastructure | Terraform | IaC for cloud resources |

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
│   └── seldon/           # Seldon Core configs
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
kubectl port-forward svc/istio-ingressgateway 8080:80 -n istio-system
```

## Roadmap

### Phase 1: Foundation (Current)
- [ ] Set up Kubernetes cluster with GPU support
- [ ] Deploy MLflow for experiment tracking
- [ ] Basic Kubeflow Pipelines installation
- [ ] ArgoCD for GitOps

### Phase 2: Training Infrastructure
- [ ] GPU scheduling and resource quotas
- [ ] Distributed training support
- [ ] Pipeline templates for common ML tasks
- [ ] Data versioning with DVC

### Phase 3: Model Serving
- [ ] Seldon Core deployment
- [ ] A/B testing framework
- [ ] Canary deployment automation
- [ ] Model monitoring and drift detection

### Phase 4: Production Hardening
- [ ] Multi-tenancy support
- [ ] Cost optimization and FinOps
- [ ] Security hardening (RBAC, network policies)
- [ ] Comprehensive observability

## Documentation

- [Architecture Deep Dive](docs/architecture.md)
- [Installation Guide](docs/installation.md)
- [Training Pipeline Guide](docs/training-pipelines.md)
- [Model Serving Guide](docs/model-serving.md)

## Contributing

Contributions are welcome! Please read the [contributing guidelines](CONTRIBUTING.md) first.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

**Jude Oyovbaire** - Senior DevOps Engineer & Platform Architect

- Website: [judaire.io](https://judaire.io)
- LinkedIn: [linkedin.com/in/judeoyovbaire](https://linkedin.com/in/judeoyovbaire)
- GitHub: [github.com/judeoyovbaire](https://github.com/judeoyovbaire)