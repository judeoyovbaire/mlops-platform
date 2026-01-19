# Performance Tuning Guide

This guide provides recommendations for optimizing the performance of the MLOps Platform across inference, training, and infrastructure components.

## Table of Contents

- [Inference Performance](#inference-performance)
- [Training Performance](#training-performance)
- [Database Optimization](#database-optimization)
- [Storage Performance](#storage-performance)
- [Network Optimization](#network-optimization)
- [Kubernetes Tuning](#kubernetes-tuning)
- [Benchmarking](#benchmarking)

## Inference Performance

### KServe Inference Optimization

#### 1. Resource Allocation

```yaml
# Optimal resource configuration for inference pods
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: optimized-model
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
      # Enable GPU for compatible models
      # resources:
      #   limits:
      #     nvidia.com/gpu: "1"
```

#### 2. Autoscaling Configuration

```yaml
# HPA for inference services
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: inference-hpa
spec:
  scaleTargetRef:
    apiVersion: serving.kserve.io/v1beta1
    kind: InferenceService
    name: my-model
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    # Custom metrics for inference-specific scaling
    - type: Pods
      pods:
        metric:
          name: inference_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"
```

#### 3. Batching Configuration

Enable request batching for throughput-optimized workloads:

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  annotations:
    # Enable batching
    serving.kserve.io/batcher: "true"
    serving.kserve.io/batchSize: "32"
    serving.kserve.io/maxLatency: "100"  # ms
```

#### 4. Model Optimization Techniques

| Technique | Latency Reduction | Memory Reduction | Use Case |
|-----------|-------------------|------------------|----------|
| Quantization (INT8) | 2-4x | 4x | CPU inference |
| Pruning | 1.5-2x | 2-3x | Large models |
| Distillation | 2-5x | 5-10x | Knowledge transfer |
| ONNX Conversion | 1.2-2x | - | Cross-platform |
| TensorRT | 2-6x | 2x | NVIDIA GPUs |

### Latency Targets

| Model Type | P50 Target | P99 Target | Notes |
|------------|------------|------------|-------|
| Small (< 100MB) | < 50ms | < 100ms | CPU-optimized |
| Medium (100MB-1GB) | < 100ms | < 200ms | Consider GPU |
| Large (> 1GB) | < 200ms | < 500ms | GPU recommended |
| LLM/Transformers | < 500ms | < 2s | GPU required |

## Training Performance

### Argo Workflows Optimization

#### 1. Parallel Execution

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
spec:
  parallelism: 10  # Max parallel tasks
  templates:
    - name: train-model
      # Use node selectors for GPU nodes
      nodeSelector:
        node.kubernetes.io/instance-type: "p3.2xlarge"
      # Tolerate GPU node taints
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Exists"
          effect: "NoSchedule"
```

#### 2. Resource Requests for Training

```yaml
# Training pod resources
resources:
  requests:
    cpu: "4"
    memory: "16Gi"
    nvidia.com/gpu: "1"
  limits:
    cpu: "8"
    memory: "32Gi"
    nvidia.com/gpu: "1"
```

#### 3. Data Loading Optimization

- Use persistent volume caching for datasets
- Enable GCS/S3 FUSE for large datasets
- Implement data prefetching in training scripts

```python
# PyTorch DataLoader optimization
train_loader = DataLoader(
    dataset,
    batch_size=64,
    num_workers=4,          # Parallel data loading
    pin_memory=True,        # Faster GPU transfer
    prefetch_factor=2,      # Prefetch batches
    persistent_workers=True # Keep workers alive
)
```

### GPU Utilization

#### Monitor GPU Usage

```bash
# Check GPU utilization
kubectl exec -it <pod-name> -- nvidia-smi

# Expected metrics:
# - GPU Utilization: > 80%
# - Memory Utilization: 60-90%
# - Power Draw: Near TDP
```

#### GPU Memory Optimization

| Technique | Description |
|-----------|-------------|
| Mixed Precision (FP16) | 2x memory reduction, faster training |
| Gradient Checkpointing | Trade compute for memory |
| Gradient Accumulation | Larger effective batch size |
| Model Parallelism | Split model across GPUs |

## Database Optimization

### PostgreSQL (RDS/Cloud SQL) Tuning

#### Connection Pooling

```yaml
# MLflow Helm values for connection pooling
mlflow:
  backendStore:
    postgres:
      # Connection pool settings
      poolSize: 10
      maxOverflow: 20
      poolTimeout: 30
```

#### Key PostgreSQL Parameters

```sql
-- Recommended settings for MLOps workloads
-- Memory
shared_buffers = '4GB'           -- 25% of RAM
effective_cache_size = '12GB'    -- 75% of RAM
work_mem = '256MB'               -- For complex queries

-- Connections
max_connections = 200
idle_in_transaction_session_timeout = '10min'

-- Write Performance
wal_buffers = '64MB'
checkpoint_completion_target = 0.9
synchronous_commit = 'off'       -- For non-critical writes

-- Query Performance
random_page_cost = 1.1           -- SSD storage
effective_io_concurrency = 200   -- SSD storage
```

#### Query Optimization

```sql
-- Create indexes for common MLflow queries
CREATE INDEX idx_runs_experiment ON runs(experiment_id);
CREATE INDEX idx_metrics_run ON metrics(run_uuid);
CREATE INDEX idx_params_run ON params(run_uuid);
CREATE INDEX idx_tags_run ON tags(run_uuid);

-- Analyze tables regularly
ANALYZE runs;
ANALYZE metrics;
```

## Storage Performance

### Object Storage (S3/GCS/Blob)

#### Transfer Optimization

```python
# Multipart upload for large files
import boto3
from boto3.s3.transfer import TransferConfig

config = TransferConfig(
    multipart_threshold=8 * 1024 * 1024,  # 8MB
    max_concurrency=10,
    multipart_chunksize=8 * 1024 * 1024,
    use_threads=True
)

s3_client.upload_file(
    'large_model.tar.gz',
    'bucket',
    'key',
    Config=config
)
```

#### Storage Class Selection

| Workload | AWS | Azure | GCP |
|----------|-----|-------|-----|
| Hot data (models) | S3 Standard | Hot | Standard |
| Warm data (artifacts) | S3 IA | Cool | Nearline |
| Cold data (archives) | S3 Glacier | Archive | Coldline |

### Persistent Volume Performance

```yaml
# High-performance storage class for training
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com  # AWS example
parameters:
  type: gp3
  iops: "16000"
  throughput: "1000"
volumeBindingMode: WaitForFirstConsumer
```

## Network Optimization

### Service Mesh Tuning

```yaml
# Istio sidecar resource allocation
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  name: default
  namespace: mlops
spec:
  egress:
    - hosts:
        - "./*"
        - "istio-system/*"
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
```

### Network Policies

```yaml
# Allow inference traffic with minimal overhead
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-inference-traffic
  namespace: mlops
spec:
  podSelector:
    matchLabels:
      app: inference
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
```

## Kubernetes Tuning

### Node Configuration

```yaml
# Kubelet configuration for ML workloads
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
# CPU management
cpuManagerPolicy: static
cpuManagerReconcilePeriod: 10s
# Memory management
systemReserved:
  cpu: 500m
  memory: 1Gi
kubeReserved:
  cpu: 500m
  memory: 1Gi
# Eviction thresholds
evictionHard:
  memory.available: "500Mi"
  nodefs.available: "10%"
```

### Pod Priority Classes

```yaml
# High priority for inference workloads
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: inference-critical
value: 1000000
globalDefault: false
description: "Critical inference workloads"
---
# Lower priority for training (can be preempted)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: training-batch
value: 100000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Batch training workloads"
```

### Resource Quotas

```yaml
# Resource quota for ML namespaces
apiVersion: v1
kind: ResourceQuota
metadata:
  name: mlops-quota
  namespace: mlops
spec:
  hard:
    requests.cpu: "100"
    requests.memory: "200Gi"
    requests.nvidia.com/gpu: "8"
    limits.cpu: "200"
    limits.memory: "400Gi"
    limits.nvidia.com/gpu: "8"
    persistentvolumeclaims: "20"
```

## Benchmarking

### Inference Benchmarking

```bash
#!/bin/bash
# Benchmark inference endpoint

MODEL_URL="http://model-service.mlops.svc.cluster.local/v1/models/my-model:predict"
CONCURRENT_USERS=10
DURATION=60

# Using hey for HTTP benchmarking
hey -z ${DURATION}s -c ${CONCURRENT_USERS} \
    -m POST \
    -H "Content-Type: application/json" \
    -D request.json \
    ${MODEL_URL}

# Expected output metrics:
# - Requests/sec: > 100 (depends on model)
# - Latency (P99): < 500ms
# - Error rate: < 0.1%
```

### Training Benchmark

```python
# training_benchmark.py
import time
import torch
from torch.utils.data import DataLoader

def benchmark_training(model, dataloader, device, epochs=1):
    """Benchmark training throughput."""
    model = model.to(device)
    optimizer = torch.optim.Adam(model.parameters())
    criterion = torch.nn.CrossEntropyLoss()

    start_time = time.time()
    total_samples = 0

    for epoch in range(epochs):
        for batch_idx, (data, target) in enumerate(dataloader):
            data, target = data.to(device), target.to(device)

            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()

            total_samples += len(data)

    elapsed_time = time.time() - start_time
    throughput = total_samples / elapsed_time

    print(f"Training throughput: {throughput:.2f} samples/sec")
    print(f"Time per epoch: {elapsed_time/epochs:.2f} seconds")

    return throughput
```

### Performance Checklist

- [ ] Inference P99 latency < 500ms
- [ ] GPU utilization > 80% during training
- [ ] Database query time < 100ms
- [ ] Storage throughput matches workload needs
- [ ] No OOM errors in production
- [ ] Autoscaling responds within 30s
- [ ] Network latency between services < 10ms
- [ ] Memory usage stable (no leaks)

## Summary

| Component | Key Metric | Target | Action if Missed |
|-----------|------------|--------|------------------|
| Inference | P99 Latency | < 500ms | Scale up, optimize model |
| Training | GPU Util | > 80% | Increase batch size, check I/O |
| Database | Query Time | < 100ms | Add indexes, tune params |
| Storage | Throughput | > 100 MB/s | Upgrade storage class |
| Network | Latency | < 10ms | Check network policies |