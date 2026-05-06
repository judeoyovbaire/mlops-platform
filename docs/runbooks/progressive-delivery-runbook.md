# Progressive Delivery Runbook

## Overview

This runbook covers operational procedures for Argo Rollouts progressive delivery of ML model deployments.

## Architecture

```text
New Model Version → Argo Rollout (canary) → AnalysisTemplate (Prometheus queries)
                                           ├── Success Rate >= 95%
                                           ├── P95 Latency <= 500ms
                                           └── Error Rate < 5%
                                           → Auto-promote or Auto-rollback
```

## Common Operations

### Check Rollout Status

```bash
# List all rollouts
kubectl argo rollouts list rollouts -n mlops

# Get detailed status
kubectl argo rollouts get rollout ml-model-rollout -n mlops

# Watch rollout progress in real-time
kubectl argo rollouts get rollout ml-model-rollout -n mlops --watch
```

### Manual Promotion

If a rollout is paused and you want to promote manually:

```bash
kubectl argo rollouts promote ml-model-rollout -n mlops
```

### Manual Rollback

To immediately abort a canary and roll back:

```bash
kubectl argo rollouts abort ml-model-rollout -n mlops
```

To undo to a specific revision:

```bash
kubectl argo rollouts undo ml-model-rollout -n mlops --to-revision=2
```

### Check AnalysisRun Results

```bash
# List analysis runs
kubectl get analysisrun -n mlops

# Get detailed results
kubectl describe analysisrun <name> -n mlops
```

## Troubleshooting

### Rollout Stuck in "Paused" State

**Symptoms:** Rollout shows "Paused" but no analysis is running.

**Resolution:**

1. Check if the AnalysisTemplate exists:

   ```bash
   kubectl get analysistemplate ml-model-canary-analysis -n mlops
   ```

2. Check Prometheus connectivity:

   ```bash
   kubectl exec -n mlops deploy/argo-rollouts -- \
     wget -qO- http://prometheus-kube-prometheus-prometheus.monitoring:9090/api/v1/status/config
   ```

3. Manually promote if analysis is not needed:

   ```bash
   kubectl argo rollouts promote ml-model-rollout -n mlops
   ```

### AnalysisRun Failing

**Symptoms:** AnalysisRun shows "Failed" status, rollout aborted.

**Resolution:**

1. Check which metric failed:

   ```bash
   kubectl get analysisrun -n mlops -o yaml | grep -A 5 "phase: Failed"
   ```

2. Verify Prometheus queries return data:

   ```bash
   # Port-forward to Prometheus
   kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

   # Test the success-rate query in Prometheus UI at localhost:9090
   ```

3. If metrics are missing (new deployment with no traffic), consider using `--initial-delay` or adjusting `failureLimit`.

### Canary Receiving No Traffic

**Symptoms:** Canary pods running but no metrics in Prometheus.

**Resolution:**

1. Verify the canary Service selector matches canary pods:

   ```bash
   kubectl get svc ml-model-canary -n mlops -o yaml
   kubectl get pods -n mlops -l app=ml-model --show-labels
   ```

2. Check if NGINX ingress is routing traffic to the canary Service.

3. Generate test traffic:

   ```bash
   kubectl run test-client --rm -it --image=busybox -n mlops -- \
     wget -qO- http://ml-model-canary:8080/health
   ```

## Dashboard

Access the Argo Rollouts dashboard:

```bash
make port-forward-argo-rollouts
# Open http://localhost:3100
```

The Grafana Progressive Delivery dashboard shows:

- Rollout phase and canary traffic weight
- Success rate and P95 latency by revision
- AnalysisRun results over time

## Metrics Reference

| Metric | Source | Threshold |
|--------|--------|-----------|
| Success Rate | `revision_request_count{response_code="200"}` | >= 95% |
| P95 Latency | `revision_request_latencies_bucket` | <= 500ms |
| Error Rate | `revision_request_count{response_code!="200"}` | < 5% |
