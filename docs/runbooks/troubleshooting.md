# Troubleshooting Guide

Common issues and their solutions for the MLOps platform.

## Table of Contents

- [Deployment Issues](#deployment-issues)
- [Inference Service Issues](#inference-service-issues)
- [MLflow Issues](#mlflow-issues)
- [Argo Workflows Issues](#argo-workflows-issues)
- [Networking Issues](#networking-issues)
- [Security Issues](#security-issues)
- [Resource Issues](#resource-issues)

---

## Deployment Issues

### Terraform Apply Fails

**Symptom**: `terraform apply` fails with provider errors

**Diagnosis**:
```bash
# Check provider versions
terraform providers

# Verify credentials
aws sts get-caller-identity  # AWS
az account show              # Azure
gcloud auth list             # GCP
```

**Solutions**:

1. **Lock file mismatch**
   ```bash
   rm .terraform.lock.hcl
   terraform init -upgrade
   ```

2. **State lock stuck**
   ```bash
   # AWS
   aws dynamodb delete-item \
     --table-name terraform-locks \
     --key '{"LockID":{"S":"<lock-id>"}}'

   # Or force unlock
   terraform force-unlock <lock-id>
   ```

3. **Resource already exists**
   ```bash
   # Import existing resource
   terraform import <resource_address> <resource_id>
   ```

### Helm Release Fails

**Symptom**: Helm release stuck in `pending-install` or `failed`

**Diagnosis**:
```bash
helm list -A
helm history <release-name> -n <namespace>
```

**Solutions**:

1. **Delete failed release**
   ```bash
   helm uninstall <release-name> -n <namespace>
   # Then re-apply via Terraform
   ```

2. **CRDs not installed**
   ```bash
   # Install CRDs first
   kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.16.0/kserve-crd.yaml
   ```

3. **Webhook timeout**
   ```bash
   # Delete blocking webhooks temporarily
   kubectl delete validatingwebhookconfiguration <webhook-name>
   ```

---

## Inference Service Issues

### InferenceService Stuck in "Unknown"

**Symptom**: InferenceService shows `READY: Unknown`

**Diagnosis**:
```bash
kubectl get inferenceservice <name> -n mlops -o yaml
kubectl describe inferenceservice <name> -n mlops
kubectl get pods -n mlops -l serving.kserve.io/inferenceservice=<name>
```

**Solutions**:

1. **Check KServe controller**
   ```bash
   kubectl logs -n kserve -l control-plane=kserve-controller-manager --tail=100
   ```

2. **Storage access issue**
   ```bash
   # Verify service account has storage access
   kubectl get sa -n mlops -o yaml

   # Test S3 access (AWS)
   kubectl run test-s3 --rm -it --image=amazon/aws-cli \
     --overrides='{"spec":{"serviceAccountName":"kserve-inference"}}' \
     -- s3 ls s3://your-bucket/
   ```

3. **Image pull error**
   ```bash
   kubectl describe pod -n mlops -l serving.kserve.io/inferenceservice=<name>
   # Check Events section for ImagePullBackOff
   ```

### Model Loading Fails

**Symptom**: Pod starts but model fails to load

**Diagnosis**:
```bash
kubectl logs -n mlops <pod-name> -c kserve-container
```

**Solutions**:

1. **Wrong model format**
   ```yaml
   # Ensure modelFormat matches the model
   spec:
     predictor:
       model:
         modelFormat:
           name: sklearn  # or pytorch, tensorflow, etc.
   ```

2. **Insufficient memory**
   ```yaml
   spec:
     predictor:
       model:
         resources:
           limits:
             memory: 4Gi  # Increase as needed
   ```

3. **Model path incorrect**
   ```bash
   # Verify model exists at storageUri
   aws s3 ls s3://bucket/path/to/model/
   ```

### High Latency

**Symptom**: P95 latency exceeds SLA

**Diagnosis**:
```bash
# Check Prometheus metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Query: histogram_quantile(0.95, rate(revision_request_latencies_bucket[5m]))
```

**Solutions**:

1. **Scale up replicas**
   ```bash
   kubectl patch inferenceservice <name> -n mlops --type=merge \
     -p '{"spec":{"predictor":{"minReplicas":3}}}'
   ```

2. **Increase resources**
   ```yaml
   resources:
     requests:
       cpu: "2"
       memory: 4Gi
   ```

3. **Enable GPU** (for large models)
   ```yaml
   resources:
     limits:
       nvidia.com/gpu: 1
   tolerations:
     - key: nvidia.com/gpu
       operator: Exists
   ```

---

## MLflow Issues

### MLflow UI Not Accessible

**Symptom**: Cannot connect to MLflow tracking server

**Diagnosis**:
```bash
kubectl get pods -n mlflow
kubectl get svc -n mlflow
kubectl logs -n mlflow -l app=mlflow
```

**Solutions**:

1. **Pod not running**
   ```bash
   kubectl describe pod -n mlflow -l app=mlflow
   # Check Events for errors
   kubectl rollout restart deployment mlflow -n mlflow
   ```

2. **Service misconfigured**
   ```bash
   kubectl get endpoints mlflow -n mlflow
   # Should show pod IPs
   ```

3. **Network policy blocking**
   ```bash
   kubectl get networkpolicy -n mlflow
   # Ensure ingress is allowed
   ```

### Experiment Logging Fails

**Symptom**: `mlflow.log_*` calls fail from training jobs

**Diagnosis**:
```python
import mlflow
mlflow.set_tracking_uri("http://mlflow.mlflow.svc.cluster.local:5000")
# Try simple operation
mlflow.set_experiment("test")
```

**Solutions**:

1. **DNS resolution**
   ```bash
   # From training pod
   nslookup mlflow.mlflow.svc.cluster.local
   ```

2. **Network policy**
   ```bash
   # Ensure argo namespace can reach mlflow
   kubectl get networkpolicy allow-mlflow-from-mlops -n mlflow -o yaml
   ```

3. **Database connection**
   ```bash
   kubectl logs -n mlflow -l app=mlflow | grep -i "database\|postgres"
   ```

### Artifact Storage Fails

**Symptom**: Cannot upload/download artifacts

**Diagnosis**:
```bash
kubectl logs -n mlflow -l app=mlflow | grep -i "s3\|blob\|storage"
```

**Solutions**:

1. **IRSA/Workload Identity not configured**
   ```bash
   # Check service account annotation
   kubectl get sa mlflow -n mlflow -o yaml | grep -A5 annotations
   ```

2. **Bucket permissions**
   ```bash
   # AWS - check IAM role
   aws iam get-role-policy --role-name mlflow-irsa-role --policy-name mlflow-s3-access
   ```

3. **Wrong bucket name**
   ```bash
   kubectl get configmap mlflow-config -n mlflow -o yaml
   ```

---

## Argo Workflows Issues

### Workflow Stuck in Pending

**Symptom**: Workflow shows `Pending` status

**Diagnosis**:
```bash
argo get -n argo <workflow-name>
kubectl describe workflow <workflow-name> -n argo
```

**Solutions**:

1. **No executor service account**
   ```bash
   kubectl get sa argo-workflows-server -n argo
   # Create if missing
   ```

2. **Resource quota exceeded**
   ```bash
   kubectl describe resourcequota -n argo
   ```

3. **Node selector no matching nodes**
   ```bash
   kubectl get nodes --show-labels | grep <required-label>
   ```

### Artifact Passing Fails

**Symptom**: Steps cannot access artifacts from previous steps

**Diagnosis**:
```bash
argo logs -n argo <workflow-name>
# Check artifact repository config
kubectl get configmap artifact-repositories -n argo -o yaml
```

**Solutions**:

1. **Artifact repository not configured**
   ```yaml
   # Ensure ConfigMap exists
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: artifact-repositories
     namespace: argo
   data:
     default-artifact-repository: |
       s3:
         bucket: mlops-artifacts
         endpoint: s3.amazonaws.com
   ```

2. **Service account lacks storage access**
   ```bash
   kubectl get sa argo-workflows-server -n argo -o yaml
   ```

---

## Networking Issues

### Ingress Not Working

**Symptom**: External URL returns 404 or connection refused

**Diagnosis**:
```bash
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>

# AWS - check ALB
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerName,State.Code]'

# Azure - check nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

**Solutions**:

1. **Target group unhealthy (AWS)**
   ```bash
   # Check health check path
   kubectl get ingress <name> -n <namespace> -o yaml | grep healthcheck
   ```

2. **Certificate not ready**
   ```bash
   kubectl get certificates -A
   kubectl describe certificate <name> -n <namespace>
   ```

3. **Ingress class mismatch**
   ```yaml
   # Ensure correct ingress class
   spec:
     ingressClassName: alb  # or nginx
   ```

### Pods Cannot Reach External Services

**Symptom**: Pods timeout when calling external APIs

**Diagnosis**:
```bash
kubectl run test-net --rm -it --image=busybox -- wget -O- https://google.com
```

**Solutions**:

1. **Network policy blocking egress**
   ```bash
   kubectl get networkpolicy -n <namespace>
   # Check egress rules
   ```

2. **NAT Gateway issue (AWS)**
   ```bash
   # Check NAT gateway in VPC console
   aws ec2 describe-nat-gateways
   ```

3. **DNS not working**
   ```bash
   kubectl run test-dns --rm -it --image=busybox -- nslookup google.com
   ```

---

## Security Issues

### Pod Rejected by PSA

**Symptom**: Pod fails to create with security context error

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for: "violates PodSecurity"
```

**Solutions**:

1. **Add required security context**
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 1000
     seccompProfile:
       type: RuntimeDefault
   containers:
     - securityContext:
         allowPrivilegeEscalation: false
         capabilities:
           drop: ["ALL"]
   ```

2. **Change namespace PSA level** (if appropriate)
   ```bash
   kubectl label namespace <ns> pod-security.kubernetes.io/enforce=baseline --overwrite
   ```

### Kyverno Policy Blocking Resources

**Symptom**: Resources rejected by Kyverno admission webhook

**Diagnosis**:
```bash
kubectl get policyreport -A
kubectl describe clusterpolicy <policy-name>
```

**Solutions**:

1. **Check policy details**
   ```bash
   kubectl get clusterpolicy <name> -o yaml
   ```

2. **Create policy exception**
   ```yaml
   apiVersion: kyverno.io/v2alpha1
   kind: PolicyException
   metadata:
     name: allow-specific-resource
   spec:
     exceptions:
     - policyName: require-resource-limits
       ruleNames:
       - require-limits
     match:
       any:
       - resources:
           kinds:
           - Pod
           namespaces:
           - special-namespace
   ```

---

## Resource Issues

### Pods OOMKilled

**Symptom**: Pod restarts with `OOMKilled` reason

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Last State"
kubectl top pods -n <namespace>
```

**Solutions**:

1. **Increase memory limit**
   ```yaml
   resources:
     limits:
       memory: 4Gi  # Increase
   ```

2. **Check for memory leaks**
   ```bash
   # Monitor memory over time
   kubectl top pod <pod-name> -n <namespace> --containers
   ```

### GPU Not Available

**Symptom**: GPU pods stuck in Pending

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n <namespace>
# Look for: "Insufficient nvidia.com/gpu"

kubectl get nodes -l nvidia.com/gpu=true
```

**Solutions**:

1. **No GPU nodes**
   ```bash
   # AWS Karpenter - check nodepools
   kubectl get nodepools
   kubectl describe nodepool gpu-workloads
   ```

2. **GPU driver not installed**
   ```bash
   # Check nvidia device plugin
   kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
   ```

3. **Missing tolerations**
   ```yaml
   tolerations:
     - key: nvidia.com/gpu
       operator: Exists
       effect: NoSchedule
   ```

### Disk Pressure

**Symptom**: Node shows DiskPressure condition

**Diagnosis**:
```bash
kubectl describe node <node-name> | grep -A10 Conditions
```

**Solutions**:

1. **Clean up unused images**
   ```bash
   # Done automatically by kubelet, but can force
   kubectl get pods -A -o wide | grep <node-name>
   # Identify unused images
   ```

2. **Increase node disk size** (via Terraform)
   ```hcl
   disk_size = 100  # Increase from default
   ```

3. **Clean up completed pods**
   ```bash
   kubectl delete pods --field-selector=status.phase==Succeeded -A
   kubectl delete pods --field-selector=status.phase==Failed -A
   ```
