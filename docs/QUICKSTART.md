# Quick Start Guide

Get the MLOps platform running and deploy your first model in 5 minutes (after infrastructure is ready).

## Prerequisites

Ensure you have one of the cloud environments deployed:
- `make deploy-aws` - AWS EKS (~15-20 min)
- `make deploy-azure` - Azure AKS (~15-25 min)
- `make deploy-gcp` - GCP GKE (~15-25 min)

## 5-Minute Demo

### Step 1: Access the Dashboards (1 min)

Open three terminals and start the port forwards:

```bash
# Terminal 1: MLflow - Experiment Tracking
make port-forward-mlflow
# Open: http://localhost:5000

# Terminal 2: ArgoCD - GitOps Dashboard
make port-forward-argocd
# Open: https://localhost:8080
# Username: admin, Password shown in terminal output

# Terminal 3: Grafana - Monitoring
make port-forward-grafana
# Open: http://localhost:3000
# Username: admin, Password: use `make secrets-aws` (or azure/gcp)
```

### Step 2: Deploy an Inference Service (2 min)

Deploy a pre-trained scikit-learn model:

```bash
# Deploy the example inference service
make deploy-example

# Check deployment status
kubectl get inferenceservice -n mlops
```

Expected output:
```
NAME           URL                                       READY   AGE
sklearn-iris   http://sklearn-iris.mlops.example.com     True    2m
```

### Step 3: Test the Model (1 min)

Send a prediction request:

```bash
# Get the inference service URL (for local testing, use port-forward)
kubectl port-forward svc/sklearn-iris-predictor 8080:80 -n mlops &

# Test prediction
curl -X POST http://localhost:8080/v1/models/sklearn-iris:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2], [6.2, 2.9, 4.3, 1.3]]}'
```

Expected response:
```json
{"predictions": [0, 1]}
```

### Step 4: Run a Training Pipeline (1 min)

Submit a training workflow to Argo:

```bash
# Apply the workflow template
kubectl apply -f pipelines/training/ml-training-workflow.yaml -n argo

# Check workflow status
kubectl get workflows -n argo

# View in Argo UI
make port-forward-argo-wf
# Open: http://localhost:2746
```

### Step 5: Explore the Platform

| Dashboard | URL | What to See |
|-----------|-----|-------------|
| MLflow | http://localhost:5000 | Experiments, model registry, metrics |
| ArgoCD | https://localhost:8080 | GitOps applications, sync status |
| Grafana | http://localhost:3000 | Platform metrics, pod status |
| Argo Workflows | http://localhost:2746 | Pipeline runs, DAG visualization |

## What You Just Did

```
                              MLOps Platform Demo
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   1. DEPLOYED MODEL              2. TESTED INFERENCE                        │
│   ┌─────────────┐                ┌─────────────┐                            │
│   │ KServe      │                │   curl      │                            │
│   │ Inference   │◄───────────────│  POST /v1/  │                            │
│   │ Service     │────────────────│  predict    │                            │
│   └─────────────┘                └─────────────┘                            │
│         │                              │                                    │
│         ▼                              ▼                                    │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │                    Kubernetes Cluster                           │       │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐             │       │
│   │  │ GPU Pod │  │ MLflow  │  │ ArgoCD  │  │ Prom/   │             │       │
│   │  │ (auto-  │  │ Server  │  │ GitOps  │  │ Grafana │             │       │
│   │  │ scaled) │  │         │  │         │  │         │             │       │
│   │  └─────────┘  └─────────┘  └─────────┘  └─────────┘             │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│   3. SUBMITTED PIPELINE          4. VIEWED METRICS                          │
│   ┌─────────────┐                ┌─────────────┐                            │
│   │ Argo        │                │  Grafana    │                            │
│   │ Workflow    │────────────────│  Dashboard  │                            │
│   │ (training)  │                │             │                            │
│   └─────────────┘                └─────────────┘                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Next Steps

### Deploy a Custom Model

1. Build your model container:
```bash
# Example: PyTorch model
docker build -t your-registry/my-model:v1 .
docker push your-registry/my-model:v1
```

2. Create an InferenceService:
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: my-model
  namespace: mlops
spec:
  predictor:
    containers:
      - name: kserve-container
        image: your-registry/my-model:v1
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
```

3. Apply and test:
```bash
kubectl apply -f my-inferenceservice.yaml
kubectl get inferenceservice my-model -n mlops
```

### Deploy with GPU

See [LLM Inference Example](../examples/llm-inference/README.md) for GPU-based model serving with vLLM.

### Production Deployment

For production use:
1. Configure proper ingress domains in Terraform variables
2. Set up TLS certificates with cert-manager
3. Enable production-grade monitoring alerts
4. Review [secrets management](./secrets-management.md) for credential rotation

## Troubleshooting

### Pod not starting?
```bash
kubectl describe pod -l serving.kserve.io/inferenceservice=sklearn-iris -n mlops
kubectl logs -l serving.kserve.io/inferenceservice=sklearn-iris -n mlops
```

### InferenceService stuck in "Unknown"?
```bash
# Check KServe controller logs
kubectl logs -l control-plane=kserve-controller-manager -n kserve
```

### Workflow failed?
```bash
# Check Argo controller
kubectl logs -l app=workflow-controller -n argo
# Or use Argo CLI
argo logs -n argo @latest
```

## Clean Up

```bash
# Delete example inference service
kubectl delete inferenceservice sklearn-iris -n mlops

# Stop port forwards
pkill -f "port-forward"

# Destroy infrastructure (when done)
make destroy-aws    # or destroy-azure, destroy-gcp
```