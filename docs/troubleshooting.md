# Troubleshooting Guide

This guide covers common issues and their resolutions for the MLOps Platform.

## Quick Diagnostics

### Cluster Health Check

```bash
# Overall cluster status
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -20

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

### Component Status

```bash
# All platform components
kubectl get pods -n mlops
kubectl get pods -n argo
kubectl get pods -n kserve
kubectl get pods -n karpenter

# InferenceServices
kubectl get inferenceservice -A
```

## Common Issues

### Pod Issues

#### Pod Stuck in Pending

**Symptoms:** Pod remains in `Pending` state.

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Common Causes:**

| Cause | Events Message | Resolution |
|-------|----------------|------------|
| Insufficient resources | `Insufficient cpu/memory` | Scale nodes or reduce requests |
| Node selector mismatch | `node(s) didn't match node selector` | Check nodeSelector/affinity |
| Taint not tolerated | `node(s) had taints` | Add tolerations or use different nodes |
| PVC not bound | `persistentvolumeclaim not found` | Check PVC and storage class |

**Resolution for Karpenter:**
```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Check NodePool status
kubectl get nodepools
kubectl describe nodepool default
```

#### Pod Stuck in CrashLoopBackOff

**Symptoms:** Pod repeatedly crashes and restarts.

**Diagnosis:**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl describe pod <pod-name> -n <namespace>
```

**Common Causes:**

| Cause | Resolution |
|-------|------------|
| Application error | Check application logs, fix code |
| Missing config/secrets | Verify ConfigMaps and Secrets exist |
| Health probe failing | Adjust probe timing or fix endpoint |
| OOMKilled | Increase memory limits |

#### Pod OOMKilled

**Symptoms:** Pod terminated with `OOMKilled` reason.

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Last State"
```

**Resolution:**
```yaml
# Increase memory limits
resources:
  limits:
    memory: "1Gi"  # Increase as needed
  requests:
    memory: "512Mi"
```

### InferenceService Issues

#### InferenceService Not Ready

**Symptoms:** InferenceService stuck in `Unknown` or `False` ready state.

**Diagnosis:**
```bash
kubectl describe inferenceservice <name> -n mlops
kubectl get pods -n mlops -l serving.kserve.io/inferenceservice=<name>
kubectl logs -n mlops -l serving.kserve.io/inferenceservice=<name>
```

**Common Causes:**

| Cause | Resolution |
|-------|------------|
| Model download failure | Check storageUri and credentials |
| Image pull failure | Verify image exists and credentials |
| Resource constraints | Check resource requests/limits |
| Probe timeout | Increase initialDelaySeconds |

#### Prediction Errors

**Symptoms:** 4xx or 5xx errors from prediction endpoint.

**Diagnosis:**
```bash
# Check model logs
kubectl logs -n mlops -l serving.kserve.io/inferenceservice=sklearn-iris

# Test locally
kubectl port-forward svc/sklearn-iris-predictor -n mlops 8080:80
curl http://localhost:8080/v1/models/sklearn-iris
```

**Common Causes:**

| Error | Cause | Resolution |
|-------|-------|------------|
| 400 Bad Request | Invalid input format | Check input schema |
| 404 Not Found | Wrong model name | Verify model name in URL |
| 500 Internal Error | Model error | Check model logs |
| 503 Service Unavailable | Model not ready | Wait or check pod status |

### MLflow Issues

#### Cannot Connect to MLflow

**Symptoms:** MLflow UI inaccessible or tracking fails.

**Diagnosis:**
```bash
# Check MLflow pod
kubectl get pods -n mlops -l app=mlflow
kubectl logs -n mlops -l app=mlflow

# Check database connection
kubectl exec -n mlops deploy/mlflow -- nc -zv <rds-endpoint> 5432
```

**Resolution:**
See [MLflow Connection Issues Runbook](runbooks/mlflow-connection-issues.md)

#### Experiment Tracking Failures

**Symptoms:** `mlflow.log_*` calls fail.

**Common Causes:**

| Error | Cause | Resolution |
|-------|-------|------------|
| Connection refused | MLflow not running | Start MLflow deployment |
| Database error | RDS issue | Check RDS status |
| S3 permission denied | IAM issue | Check service account IRSA |

### Argo Workflows Issues

#### Workflow Stuck in Pending

**Symptoms:** Workflow remains in `Pending` state.

**Diagnosis:**
```bash
kubectl describe workflow <name> -n argo
kubectl get pods -n argo -l workflows.argoproj.io/workflow=<name>
```

**Common Causes:**

| Cause | Resolution |
|-------|------------|
| No executor | Check workflow controller logs |
| Service account missing | Create required service account |
| PVC not available | Check storage provisioner |

#### Workflow Failed

**Symptoms:** Workflow in `Failed` state.

**Diagnosis:**
```bash
# Get failed steps
argo get <workflow-name> -n argo

# Check logs of failed step
argo logs <workflow-name> -n argo --follow
```

### Network Issues

#### Service Not Reachable

**Symptoms:** Cannot connect to service from within cluster.

**Diagnosis:**
```bash
# Check service exists
kubectl get svc -n <namespace>

# Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# Test from debug pod
kubectl run debug --rm -it --image=busybox -- wget -qO- http://<service>.<namespace>.svc.cluster.local
```

#### ALB Ingress Not Working

**Symptoms:** External traffic not reaching services.

**Diagnosis:**
```bash
# Check ingress status
kubectl describe ingress <name> -n <namespace>

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Common Causes:**

| Cause | Resolution |
|-------|------------|
| Missing subnets tags | Add `kubernetes.io/cluster/<name>` tag |
| Security group rules | Allow ingress on required ports |
| Target health check failing | Check healthcheck-path annotation |

### Terraform Issues

#### State Lock Error

**Symptoms:** `Error acquiring state lock`

**Resolution:**
```bash
# Check who holds the lock
aws dynamodb get-item \
  --table-name mlops-platform-tfstate-lock \
  --key '{"LockID": {"S": "mlops-platform-tfstate-<account>/mlops-platform/dev/terraform.tfstate"}}'

# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

#### Plan Shows Unexpected Changes

**Symptoms:** Terraform shows changes that weren't expected.

**Diagnosis:**
```bash
# Check for drift
terraform refresh
terraform plan

# Compare state with actual
terraform state show <resource>
```

## Log Collection

### Collect All Logs for Support

```bash
# Create support bundle
mkdir -p /tmp/mlops-support
kubectl logs -n mlops --all-containers --since=1h > /tmp/mlops-support/mlops.log
kubectl logs -n argo --all-containers --since=1h > /tmp/mlops-support/argo.log
kubectl logs -n kserve --all-containers --since=1h > /tmp/mlops-support/kserve.log
kubectl logs -n karpenter --all-containers --since=1h > /tmp/mlops-support/karpenter.log
kubectl get events -A --sort-by='.lastTimestamp' > /tmp/mlops-support/events.log
tar -czf mlops-support-$(date +%Y%m%d-%H%M%S).tar.gz /tmp/mlops-support/
```

### View Real-time Logs

```bash
# Follow logs for component
kubectl logs -f -n mlops -l app.kubernetes.io/part-of=mlops-platform

# All containers in pod
kubectl logs -f <pod-name> -n <namespace> --all-containers
```

## Performance Issues

### High Latency

**Diagnosis:**
```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n mlops

# Check for throttling
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Resources"
```

**Resolution:**
- Increase resource limits
- Add horizontal pod autoscaling
- Check network latency between components

### Memory Pressure

**Symptoms:** Nodes showing `MemoryPressure` condition.

**Diagnosis:**
```bash
kubectl describe node <node-name> | grep -A5 Conditions
```

**Resolution:**
- Evict non-critical pods
- Scale up cluster
- Reduce memory requests

## Useful Commands Reference

```bash
# Restart deployment
kubectl rollout restart deployment/<name> -n <namespace>

# Force delete stuck pod
kubectl delete pod <name> -n <namespace> --force --grace-period=0

# Debug networking
kubectl run debug --rm -it --image=nicolaka/netshoot -- bash

# Check IRSA configuration
kubectl describe sa <name> -n <namespace> | grep Annotations

# Decode secret
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d
```

## Related Documentation

- [Runbooks](runbooks/README.md)
- [Disaster Recovery](disaster-recovery.md)
- [Architecture](architecture.md)
