# MLOps Platform Demo Script

This script guides you through a 5-minute demo of the MLOps platform, showcasing multi-cloud deployment, model training, serving, and monitoring.

## Prerequisites

- AWS/Azure/GCP account with credentials configured
- kubectl, helm, terraform installed
- Terminal with kubectl access to deployed cluster

## Demo Flow (5 minutes)

### 1. Introduction (30 seconds)

**Script:**
"Welcome to the MLOps Platform demo. This is a production-ready, multi-cloud MLOps platform that enables data scientists to deploy models without DevOps tickets. We'll deploy to AWS EKS, train a model, serve it with KServe, and monitor it in real-time."

**Show:**
- README.md with architecture diagram
- Multi-cloud support (AWS/Azure/GCP)

### 2. Infrastructure Overview (1 minute)

**Script:**
"Let's check our deployed infrastructure. We have an EKS cluster with Karpenter for GPU autoscaling, MLflow for experiment tracking, KServe for model serving, and Prometheus/Grafana for observability."

**Commands:**
```bash
# Show cluster nodes
kubectl get nodes

# Show namespaces
kubectl get namespaces

# Show MLflow deployment
kubectl get pods -n mlflow

# Show KServe deployments
kubectl get inferenceservice -n mlops
```

**Show:**
- Grafana dashboard (port-forward)
- MLflow UI (port-forward)

### 3. Model Training Pipeline (1.5 minutes)

**Script:**
"Now let's trigger a training pipeline. This Argo Workflow will load data, validate it, engineer features, train a model, and register it with MLflow."

**Commands:**
```bash
# Submit training workflow
argo submit --watch pipelines/training/ml-training-workflow.yaml \
  -p dataset-url="https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv" \
  -p model-name="iris-classifier" \
  -p accuracy-threshold="0.9"

# Watch workflow progress
argo watch ml-training-xxxxx

# Check MLflow for registered model
# (Open MLflow UI and show experiment)
```

**Show:**
- Argo Workflows UI showing pipeline steps
- MLflow UI showing experiment metrics
- Model version in MLflow registry

### 4. Model Serving (1 minute)

**Script:**
"Now let's deploy the trained model to KServe for production inference. KServe automatically handles autoscaling, canary deployments, and A/B testing."

**Commands:**
```bash
# Deploy inference service
kubectl apply -f examples/kserve/inferenceservice-examples.yaml

# Wait for deployment
kubectl wait --for=condition=Ready inferenceservice/sklearn-iris -n mlops --timeout=300s

# Get inference endpoint
kubectl get inferenceservice sklearn-iris -n mlops

# Test inference
curl -X POST http://sklearn-iris.mlops.svc.cluster.local/v1/models/sklearn-iris:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
```

**Show:**
- KServe inference service status
- Successful prediction response
- Autoscaling metrics in Grafana

### 5. Monitoring & Observability (1 minute)

**Script:**
"Finally, let's check our monitoring stack. We have Prometheus for metrics, Grafana for dashboards, Loki for logs, and Tempo for distributed tracing."

**Commands:**
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Check alerts
kubectl get prometheusrules -n monitoring
```

**Show:**
- Grafana dashboard with inference metrics
- Prometheus alerts
- Model performance graphs
- Cost dashboards

### 6. Multi-Cloud Capability (30 seconds)

**Script:**
"One of the key features is multi-cloud support. The same platform works identically on AWS EKS, Azure AKS, or GCP GKE. Let me show you the Terraform modules."

**Show:**
- `infrastructure/terraform/modules/eks/`
- `infrastructure/terraform/modules/aks/`
- `infrastructure/terraform/modules/gke/`

**Highlight:**
- Same Helm charts work across clouds
- Cloud-native implementations (Karpenter vs KEDA vs NAP)
- Unified CI/CD pipeline

## Key Talking Points

1. **Self-Service**: Data scientists deploy models without DevOps tickets
2. **Multi-Cloud**: Same capabilities on AWS, Azure, or GCP
3. **Production-Ready**: Security, observability, and reliability built-in
4. **Cost-Optimized**: GPU autoscaling, spot instances, scale-to-zero
5. **Open Source**: All components are CNCF/OSS projects

## Demo Checklist

- [ ] Cluster deployed and accessible
- [ ] MLflow UI accessible (port-forward)
- [ ] Grafana dashboard accessible (port-forward)
- [ ] Training pipeline ready to submit
- [ ] Example inference service manifest ready
- [ ] Test data prepared
- [ ] Monitoring dashboards configured

## Troubleshooting

**If workflow fails:**
- Check MLflow connectivity: `kubectl logs -n mlflow deployment/mlflow`
- Verify data URL is accessible
- Check Argo Workflows logs: `argo logs <workflow-name>`

**If inference service doesn't start:**
- Check KServe controller: `kubectl logs -n kserve-system deployment/kserve-controller-manager`
- Verify model is registered in MLflow
- Check pod events: `kubectl describe pod -n mlops`

**If metrics don't appear:**
- Verify Prometheus is scraping: `kubectl get servicemonitor -n monitoring`
- Check Prometheus targets: http://localhost:9090/targets
- Verify ServiceMonitor labels match

## Recording Tips

1. Use screen recording software (OBS, QuickTime, etc.)
2. Record at 1080p minimum
3. Use a clear, readable font in terminal
4. Add captions for key points
5. Keep it under 5 minutes
6. Show both terminal and browser windows
7. Highlight key metrics and dashboards

## Post-Production

- Add intro/outro music
- Add title card with project name
- Add captions for accessibility
- Upload to YouTube/Vimeo
- Embed in README.md
