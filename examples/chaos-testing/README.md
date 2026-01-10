# Chaos Testing for MLOps Platform

This directory contains Chaos Mesh experiments for testing the resilience of the MLOps platform.

## Prerequisites

1. Install Chaos Mesh (v2.8.1):
```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

kubectl create namespace chaos-testing

helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-testing \
  --version 2.8.1 \
  --values ../../infrastructure/helm/common/chaos-mesh-values.yaml
```

2. Verify installation:
```bash
kubectl get pods -n chaos-testing
```

## Available Experiments

| Experiment | Description | Target |
|------------|-------------|--------|
| `pod-failure.yaml` | Kill inference service pods | KServe pods |
| `network-delay.yaml` | Add network latency | MLflow → Database |
| `network-partition.yaml` | Simulate network partition | Argo → MLflow |
| `cpu-stress.yaml` | CPU pressure on training | Training namespace |
| `memory-stress.yaml` | Memory pressure | Inference pods |

## Running Experiments

### 1. Pod Failure Test
Tests KServe's ability to recover from pod failures:
```bash
kubectl apply -f pod-failure.yaml
```

### 2. Network Delay Test
Tests system behavior with degraded network:
```bash
kubectl apply -f network-delay.yaml
```

### 3. Network Partition Test
Tests isolation handling:
```bash
kubectl apply -f network-partition.yaml
```

### 4. CPU Stress Test
Tests autoscaling under CPU pressure:
```bash
kubectl apply -f cpu-stress.yaml
```

### 5. Memory Stress Test
Tests OOM handling:
```bash
kubectl apply -f memory-stress.yaml
```

## Cleanup

Delete all chaos experiments:
```bash
kubectl delete -f .
```

## Dashboard Access

Access the Chaos Mesh dashboard:
```bash
kubectl port-forward -n chaos-testing svc/chaos-dashboard 2333:2333
```

Then open http://localhost:2333

## Best Practices

1. **Start small**: Begin with short duration experiments
2. **Monitor**: Watch metrics during experiments
3. **Document**: Record observations and recovery times
4. **Gradual**: Increase blast radius progressively
5. **Steady state**: Define what "normal" looks like first

## Expected Outcomes

| Scenario | Expected Behavior |
|----------|-------------------|
| Pod killed | KServe reschedules within 30s |
| Network delay 100ms | Requests succeed, latency increased |
| Network partition | Circuit breaker triggers, fallback works |
| CPU stress | HPA scales up pods |
| Memory stress | OOM kills pod, restarts cleanly |
