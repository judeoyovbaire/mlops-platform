# MLOps Platform on Kubernetes

A production-ready MLOps platform for model training, versioning, and deployment on Kubernetes. Enables data science teams to go from experiment to production with self-service workflows.

[![CI](https://github.com/judeoyovbaire/mlops-platform/actions/workflows/ci.yaml/badge.svg)](https://github.com/judeoyovbaire/mlops-platform/actions/workflows/ci.yaml)

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
- **Terraform**: Infrastructure as Code for AWS EKS with GPU node groups
- **GitHub Actions**: CI/CD pipeline with validation, linting, and security scanning
- **Observability**: Prometheus ServiceMonitors, alerting rules, and Grafana dashboards
- **Security**: NetworkPolicies for namespace isolation

## Tech Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Pipeline Orchestration | Kubeflow Pipelines | Latest | ML workflow automation |
| Experiment Tracking | MLflow | 3.6.0 | Model versioning & metrics |
| Model Serving | KServe | 0.15.0 | Production inference (CNCF) |
| GitOps | ArgoCD | 3.2.x | Declarative deployments |
| Service Mesh | Istio | Latest | Traffic management |
| Monitoring | Prometheus + Grafana | Latest | Observability |
| Infrastructure | Terraform | 1.6+ | IaC for AWS EKS |
| CI/CD | GitHub Actions | - | Automated testing |

## Project Structure

```
mlops-platform/
├── .github/
│   └── workflows/           # CI/CD pipelines (disabled by default)
├── components/
│   ├── kubeflow/            # Kubeflow setup
│   └── kserve/              # KServe InferenceService examples (Kustomize)
├── examples/
│   └── iris-classifier/     # Complete end-to-end example
│       ├── train.py         # Training script
│       ├── test_inference.py # Inference testing
│       └── kserve-deployment.yaml
├── infrastructure/
│   ├── kubernetes/          # Kustomize-managed manifests
│   │   ├── namespace.yaml
│   │   ├── network-policies.yaml
│   │   └── monitoring.yaml  # ServiceMonitors & alerts
│   ├── terraform/           # AWS EKS infrastructure
│   │   ├── modules/eks/     # Reusable EKS module
│   │   └── environments/dev/ # Dev environment config
│   └── helm/                # Helm values for third-party apps
│       ├── mlflow-values.yaml   # MLflow configuration
│       └── argocd-values.yaml   # ArgoCD configuration
├── pipelines/
│   ├── training/            # Training pipeline definitions
│   └── inference/           # Inference pipeline definitions
├── scripts/
│   └── install.sh           # Platform installation script
├── docs/
│   └── architecture.md      # Architecture documentation
└── Makefile                 # Common operations
```

### Helm vs Kustomize

| Tool | Used For | Location |
|------|----------|----------|
| **Helm** | Third-party apps (MLflow, ArgoCD) | `infrastructure/helm/` |
| **Kustomize** | Our manifests (namespaces, policies, KServe examples) | `infrastructure/kubernetes/` |

## Getting Started

### Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or local with kind/minikube)
- kubectl configured
- Helm 3.x
- Terraform 1.6+ (for cloud infrastructure)
- Python 3.10+

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform

# 2. Set up AWS EKS infrastructure (optional)
cd infrastructure/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
terraform init && terraform apply

# 3. Install platform components
./scripts/install.sh

# 4. Access the dashboards
make port-forward-mlflow   # MLflow at localhost:5000
make port-forward-argocd   # ArgoCD at localhost:8080
```

### Using the Makefile

```bash
make help                  # Show all available commands
make install               # Install platform components
make validate              # Validate all manifests
make lint                  # Lint Python and Terraform code
make status                # Check platform status
make deploy-example        # Deploy iris classifier example
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

### Run the Example End-to-End

```bash
cd examples/iris-classifier

# Train locally (optional)
pip install -r requirements.txt
python train.py --register

# Deploy to KServe
kubectl apply -f kserve-deployment.yaml

# Test inference
python test_inference.py
```

## Roadmap

### Phase 1: Foundation ✅
- [x] Kubernetes cluster with GPU support (Terraform EKS)
- [x] MLflow 3.x for experiment tracking
- [x] Kubeflow Pipelines installation
- [x] ArgoCD 3.x for GitOps
- [x] KServe for model serving
- [x] CI/CD pipeline (GitHub Actions)

### Phase 2: Training Infrastructure
- [x] GPU node groups in Terraform
- [ ] Distributed training support
- [ ] Pipeline templates for common ML tasks
- [ ] Data versioning with DVC

### Phase 3: Model Serving ✅
- [x] KServe deployment
- [x] Canary deployment examples
- [x] Working end-to-end example
- [ ] Model monitoring and drift detection

### Phase 4: Production Hardening
- [ ] Multi-tenancy support
- [ ] Cost optimization and FinOps
- [x] Security hardening (NetworkPolicies)
- [x] Observability (ServiceMonitors, alerts, dashboards)

## Documentation

- [Architecture Deep Dive](docs/architecture.md)
- [Example: Iris Classifier](examples/iris-classifier/README.md)

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