# Quick Start Guide

Deploy the MLOps platform and serve your first model in 5 minutes (after infrastructure is ready).

## Prerequisites

- One of the cloud environments deployed (see [Getting Started](README.md#getting-started)):
  - `make deploy-aws` — AWS EKS (~15-20 min)
  - `make deploy-azure` — Azure AKS (~15-25 min)
  - `make deploy-gcp` — GCP GKE (~15-25 min)
- `kubectl` configured for your cluster (deploy scripts do this automatically)

## Step 1: Access the Dashboards

Open separate terminals for each port-forward:

```bash
make port-forward-mlflow    # http://localhost:5000  — Experiment Tracking
make port-forward-argocd    # https://localhost:8080 — GitOps (admin / see terminal output)
make port-forward-grafana   # http://localhost:3000  — Monitoring (admin / make secrets-<cloud>)
```

## Step 2: Deploy an Inference Service

```bash
make deploy-example
kubectl get inferenceservice -n mlops
```

Expected output:
```
NAME           URL                                       READY   AGE
sklearn-iris   http://sklearn-iris.mlops.example.com     True    2m
```

## Step 3: Test the Model

```bash
# Port-forward the inference service (uses 8081 to avoid ArgoCD conflict)
kubectl port-forward svc/sklearn-iris-predictor 8081:80 -n mlops &

curl -X POST http://localhost:8081/v1/models/sklearn-iris:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2], [6.2, 2.9, 4.3, 1.3]]}'
```

Expected response:
```json
{"predictions": [0, 1]}
```

## Step 4: Run a Training Pipeline

```bash
# Register the workflow template
kubectl apply -f pipelines/training/ml-training-workflow.yaml

# Submit a pipeline run (requires Argo CLI: brew install argo)
argo submit --from workflowtemplate/ml-training-pipeline -n argo

# Watch progress
argo watch -n argo @latest

# Or view in the Argo UI
make port-forward-argo-wf   # http://localhost:2746
```

## Step 5: Explore

| Dashboard | URL | What to See |
|-----------|-----|-------------|
| MLflow | http://localhost:5000 | Experiments, model registry, metrics |
| ArgoCD | https://localhost:8080 | GitOps applications, sync status |
| Grafana | http://localhost:3000 | Platform metrics, pod health, cost dashboard |
| Argo Workflows | http://localhost:2746 | Pipeline runs, DAG visualization |

## Next Steps

- **Custom model** — build a container, create an `InferenceService`, and `kubectl apply`. See [examples/kserve/](examples/kserve/) for templates.
- **GPU serving** — deploy Mistral-7B with vLLM. See [examples/llm-inference/](examples/llm-inference/README.md).
- **Canary rollouts** — progressive traffic splitting. See [examples/canary-deployment/](examples/canary-deployment/).
- **Production hardening** — configure ingress domains, TLS via cert-manager, and [secrets rotation](docs/secrets-management.md).

## Troubleshooting

```bash
# InferenceService not ready?
kubectl describe inferenceservice sklearn-iris -n mlops
kubectl logs -l serving.kserve.io/inferenceservice=sklearn-iris -n mlops

# KServe controller issues?
kubectl logs -l control-plane=kserve-controller-manager -n kserve

# Workflow failed?
argo logs -n argo @latest
```

## Clean Up

```bash
kubectl delete inferenceservice sklearn-iris -n mlops
pkill -f "port-forward"
make destroy-aws    # or destroy-azure, destroy-gcp
```
