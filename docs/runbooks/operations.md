# Operations Runbook

Day-to-day operational procedures for the MLOps platform.

## Table of Contents

- [Daily Operations](#daily-operations)
- [Deployment Procedures](#deployment-procedures)
- [Scaling Operations](#scaling-operations)
- [Backup and Recovery](#backup-and-recovery)
- [Incident Response](#incident-response)

---

## Daily Operations

### Health Check

Run a quick health check of all platform components:

```bash
# Check all pods across namespaces
kubectl get pods -A | grep -v Running | grep -v Completed

# Check node status
kubectl get nodes

# Check pending PVCs
kubectl get pvc -A | grep -v Bound

# Check certificate expiration
kubectl get certificates -A
```

### Viewing Logs

```bash
# MLflow logs
kubectl logs -n mlflow -l app=mlflow --tail=100

# ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# KServe controller logs
kubectl logs -n kserve -l control-plane=kserve-controller-manager --tail=100

# Argo Workflows controller
kubectl logs -n argo -l app=workflow-controller --tail=100
```

### Monitoring Dashboards

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Port forward ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

---

## Deployment Procedures

### Deploy New Model Version

1. **Register model in MLflow**
   ```bash
   # From training job or notebook
   mlflow.sklearn.log_model(model, "model")
   mlflow.register_model(f"runs:/{run_id}/model", "my-model")
   ```

2. **Update InferenceService**
   ```yaml
   # Update storageUri to new model version
   kubectl patch inferenceservice my-model -n mlops --type=merge \
     -p '{"spec":{"predictor":{"model":{"storageUri":"s3://models/my-model/v2"}}}}'
   ```

3. **Monitor rollout**
   ```bash
   kubectl get inferenceservice my-model -n mlops -w
   kubectl get pods -n mlops -l serving.kserve.io/inferenceservice=my-model
   ```

### Canary Deployment

1. **Start canary (10% traffic)**
   ```bash
   kubectl patch inferenceservice my-model -n mlops --type=merge \
     -p '{"spec":{"predictor":{"canaryTrafficPercent":10}}}'
   ```

2. **Monitor metrics in Grafana**
   - Compare error rates between stable and canary
   - Check P95 latency

3. **Promote or rollback**
   ```bash
   # Promote (increase traffic)
   kubectl patch inferenceservice my-model -n mlops --type=merge \
     -p '{"spec":{"predictor":{"canaryTrafficPercent":50}}}'

   # Rollback (send all traffic to stable)
   kubectl patch inferenceservice my-model -n mlops --type=merge \
     -p '{"spec":{"predictor":{"canaryTrafficPercent":0}}}'
   ```

### Run Training Pipeline

```bash
# Submit workflow from template
argo submit -n argo --from workflowtemplate/ml-training-pipeline \
  -p dataset-url="https://example.com/data.csv" \
  -p model-name="my-model"

# Watch workflow progress
argo watch -n argo @latest

# View logs
argo logs -n argo @latest
```

---

## Scaling Operations

### Manual Scaling

```bash
# Scale inference service replicas
kubectl scale deployment my-model-predictor -n mlops --replicas=5

# Scale Argo workflow controller (if needed)
kubectl scale deployment argo-workflows-workflow-controller -n argo --replicas=2
```

### GPU Node Scaling

**AWS (Karpenter)**
```bash
# Karpenter scales automatically based on pending pods
# To force node provisioning, create a pod requesting GPU
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: mlops
spec:
  containers:
  - name: cuda
    image: nvidia/cuda:12.0-base
    resources:
      limits:
        nvidia.com/gpu: 1
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
EOF
```

**Azure (KEDA)**
```bash
# Check KEDA scaler status
kubectl get scaledobject -n mlops

# View KEDA metrics
kubectl logs -n keda -l app=keda-operator
```

### Cluster Autoscaler Status

```bash
# Check cluster autoscaler logs (AWS)
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler

# Check Karpenter provisioner status (AWS)
kubectl get nodepools
kubectl get nodeclaims
```

---

## Backup and Recovery

### MLflow Database Backup

**AWS (RDS)**
```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier mlops-platform-dev-mlflow \
  --db-snapshot-identifier mlops-mlflow-backup-$(date +%Y%m%d)

# List snapshots
aws rds describe-db-snapshots --db-instance-identifier mlops-platform-dev-mlflow
```

**Azure (PostgreSQL Flexible)**
```bash
# Backups are automatic, but you can create on-demand
az postgres flexible-server backup create \
  --resource-group rg-mlops-platform-dev \
  --name mlops-platform-dev-mlflow \
  --backup-name manual-backup-$(date +%Y%m%d)
```

**GCP (Cloud SQL)**
```bash
# Create backup
gcloud sql backups create \
  --instance=mlops-platform-dev-mlflow \
  --description="Manual backup $(date +%Y%m%d)"
```

### Artifact Storage Backup

**AWS (S3)**
```bash
# Enable versioning (should be on by default)
aws s3api put-bucket-versioning \
  --bucket mlops-platform-dev-mlflow-artifacts \
  --versioning-configuration Status=Enabled

# Cross-region replication for DR (optional)
# Configure via Terraform
```

### Kubernetes Resource Backup

```bash
# Export all custom resources
kubectl get inferenceservice -n mlops -o yaml > backup/inferenceservices.yaml
kubectl get workflowtemplates -n argo -o yaml > backup/workflowtemplates.yaml

# Use Velero for full cluster backup (if installed)
velero backup create mlops-backup --include-namespaces mlops,mlflow,argo
```

---

## Incident Response

### High Error Rate on Inference Service

1. **Identify affected service**
   ```bash
   kubectl get inferenceservice -n mlops
   kubectl get pods -n mlops -l serving.kserve.io/inferenceservice=<name>
   ```

2. **Check pod logs**
   ```bash
   kubectl logs -n mlops -l serving.kserve.io/inferenceservice=<name> --tail=200
   ```

3. **Check resource usage**
   ```bash
   kubectl top pods -n mlops
   ```

4. **Rollback if needed**
   ```bash
   # Rollback to previous revision
   kubectl rollout undo deployment/<name>-predictor -n mlops
   ```

### MLflow Unreachable

1. **Check MLflow pod status**
   ```bash
   kubectl get pods -n mlflow -l app=mlflow
   kubectl describe pod -n mlflow -l app=mlflow
   ```

2. **Check database connectivity**
   ```bash
   kubectl exec -n mlflow deploy/mlflow -- \
     python -c "import psycopg2; psycopg2.connect('$DATABASE_URL')"
   ```

3. **Check storage connectivity**
   ```bash
   # AWS
   kubectl exec -n mlflow deploy/mlflow -- aws s3 ls s3://mlops-bucket/

   # Azure
   kubectl exec -n mlflow deploy/mlflow -- az storage blob list --container-name mlflow
   ```

4. **Restart if needed**
   ```bash
   kubectl rollout restart deployment mlflow -n mlflow
   ```

### Node Not Ready

1. **Identify the node**
   ```bash
   kubectl get nodes
   kubectl describe node <node-name>
   ```

2. **Check node conditions**
   ```bash
   kubectl get node <node-name> -o jsonpath='{.status.conditions[*].type}'
   ```

3. **Drain and replace (if needed)**
   ```bash
   # Drain the node
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

   # For managed node groups, the cloud provider will replace it
   # For Karpenter nodes, delete the nodeclaim
   kubectl delete nodeclaim <nodeclaim-name>
   ```

### Certificate Expiring

1. **Check certificate status**
   ```bash
   kubectl get certificates -A
   kubectl describe certificate <name> -n <namespace>
   ```

2. **Force renewal**
   ```bash
   kubectl delete secret <certificate-secret-name> -n <namespace>
   # cert-manager will automatically recreate
   ```

3. **Check cert-manager logs**
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

---

## Maintenance Windows

### Cluster Upgrade Procedure

1. **Pre-upgrade checks**
   ```bash
   # Check current version
   kubectl version

   # Check PDB status
   kubectl get pdb -A

   # Ensure all deployments are healthy
   kubectl get deployments -A | grep -v "1/1\|2/2\|3/3"
   ```

2. **Update Terraform**
   ```hcl
   # Update kubernetes_version in variables.tf
   kubernetes_version = "1.32"
   ```

3. **Apply upgrade**
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

4. **Post-upgrade verification**
   ```bash
   kubectl get nodes
   kubectl get pods -A | grep -v Running
   ```

### Helm Chart Updates

```bash
# Check for updates
helm repo update

# List installed releases
helm list -A

# Upgrade specific release
helm upgrade argocd argo/argo-cd -n argocd \
  -f infrastructure/helm/aws/argocd-values.yaml \
  --version 7.10.0
```