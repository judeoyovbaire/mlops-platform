# MLOps Platform on Kubernetes

A production-ready MLOps platform for model training, versioning, and deployment on AWS EKS. Enables data science teams to go from experiment to production with self-service workflows.

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
│  │                         AWS EKS Cluster                              │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │    │
│  │  │ GPU     │  │ S3 +    │  │ ALB     │  │ Prom/   │  │ ArgoCD  │   │    │
│  │  │ Nodes   │  │ RDS     │  │ Ingress │  │ Grafana │  │ GitOps  │   │    │
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
- **AWS ALB Ingress**: External access via Application Load Balancer
- **GitHub Actions**: CI/CD pipeline with validation, linting, and security scanning
- **Observability**: Prometheus ServiceMonitors, alerting rules, and Grafana dashboards
- **Security**: NetworkPolicies for namespace isolation, IRSA for AWS authentication

## Tech Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Pipeline Orchestration | Kubeflow Pipelines | Latest | ML workflow automation |
| Experiment Tracking | MLflow | 3.6.0 | Model versioning & metrics |
| Model Serving | KServe | 0.14.1 | Production inference (CNCF) |
| GitOps | ArgoCD | 7.7.x | Declarative deployments |
| Ingress | AWS ALB Controller | 1.7.1 | External load balancing |
| TLS | cert-manager | 1.16.2 | Certificate management |
| Monitoring | Prometheus + Grafana | Latest | Observability |
| Infrastructure | Terraform | 1.6+ | IaC for AWS EKS |
| CI/CD | GitHub Actions | - | Automated testing |

## Project Structure

```
mlops-platform/
├── .github/
│   └── workflows/           # CI/CD pipelines
├── components/
│   └── kserve/              # KServe InferenceService examples
├── examples/
│   └── iris-classifier/     # Complete end-to-end example
│       ├── train.py         # Training script
│       ├── test_inference.py # Inference testing
│       └── kserve-deployment.yaml
├── infrastructure/
│   ├── kubernetes/          # Network policies, monitoring
│   │   ├── network-policies.yaml
│   │   └── monitoring.yaml  # ServiceMonitors & alerts
│   ├── terraform/           # AWS EKS infrastructure
│   │   ├── modules/eks/     # Reusable EKS module
│   │   └── environments/dev/ # Dev environment config
│   └── helm/aws/            # AWS-specific Helm values
│       ├── mlflow-values.yaml
│       └── argocd-values.yaml
├── pipelines/
│   └── training/            # Training pipeline definitions
├── scripts/
│   └── deploy-aws.sh        # AWS deployment script
├── docs/
│   └── architecture.md      # Architecture documentation
└── Makefile                 # Common operations
```

## Getting Started

### Prerequisites

- AWS account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform 1.6+
- kubectl
- Helm 3.x
- Python 3.10+

### Quick Start - AWS EKS Deployment

```bash
# 1. Clone the repository
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform

# 2. Deploy to AWS EKS (~15-20 minutes)
make deploy

# 3. Check deployment status
make status

# 4. Access the dashboards (after deployment)
make port-forward-mlflow   # MLflow at localhost:5000
make port-forward-argocd   # ArgoCD at localhost:8080

# 5. Destroy when done (to avoid costs)
make destroy
```

### Using the Makefile

```bash
make help                  # Show all available commands

# AWS Deployment
make deploy                # Deploy to AWS EKS
make status                # Check deployment status
make destroy               # Destroy AWS resources

# Terraform (Advanced)
make terraform-init        # Initialize Terraform
make terraform-plan        # Plan infrastructure changes
make terraform-apply       # Apply infrastructure changes

# Validation
make validate              # Validate Terraform and Python
make lint                  # Lint Python and Terraform code

# Development (after deployment)
make port-forward-mlflow   # Forward MLflow to localhost:5000
make port-forward-argocd   # Forward ArgoCD to localhost:8080
make deploy-example        # Deploy iris classifier example
```

### Deploy a Model with KServe

```bash
# Deploy an sklearn model
kubectl apply -f components/kserve/inferenceservice-examples.yaml

# Check status
kubectl get inferenceservice -n mlops

# Test inference (after port-forward or via ALB URL)
curl -X POST "http://localhost:8082/v1/models/sklearn-iris:predict" \
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

## AWS Resources Created

The Terraform deployment creates:

| Resource | Purpose |
|----------|---------|
| VPC | Networking with public/private subnets across 3 AZs |
| EKS Cluster | Managed Kubernetes control plane |
| Node Groups | General (t3.large), Training (c5.2xlarge SPOT), GPU (g4dn.xlarge SPOT) |
| S3 Bucket | MLflow artifact storage |
| RDS PostgreSQL | MLflow metadata backend |
| IAM Roles | IRSA for secure pod authentication |
| ALB | External access to services |

### Cost Optimization

- Single NAT gateway for dev environment
- SPOT instances for training and GPU nodes
- Scale-to-zero for training/GPU node groups
- Auto-generated terraform.tfvars with secure passwords

## Roadmap

### Phase 1: Foundation
- [x] AWS EKS cluster with GPU support (Terraform)
- [x] MLflow 3.x with RDS + S3 backend
- [x] KServe for model serving
- [x] ArgoCD 3.x for GitOps
- [x] AWS ALB Ingress Controller
- [x] CI/CD pipeline (GitHub Actions)

### Phase 2: Training Infrastructure
- [x] GPU node groups in Terraform
- [ ] Distributed training support
- [ ] Pipeline templates for common ML tasks
- [ ] Data versioning with DVC

### Phase 3: Model Serving
- [x] KServe deployment
- [x] Canary deployment examples
- [x] Working end-to-end example
- [ ] Model monitoring and drift detection

### Phase 4: Production Hardening
- [ ] Multi-tenancy support
- [ ] Cost optimization and FinOps
- [x] Security hardening (NetworkPolicies, IRSA)
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