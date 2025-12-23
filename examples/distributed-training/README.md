# Distributed Training with Kubeflow Training Operator

This example demonstrates how to add distributed model training using [Kubeflow Training Operator](https://www.kubeflow.org/docs/components/training/).

> **Note:** The Training Operator is not deployed by default. This example serves as documentation for adding distributed training capabilities when needed.

## Overview

The Training Operator enables distributed training jobs on Kubernetes for:
- **PyTorch** - DistributedDataParallel (DDP)
- **TensorFlow** - MultiWorkerMirroredStrategy
- **MPI** - Horovod, DeepSpeed
- **XGBoost** - Distributed XGBoost

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   PyTorchJob CRD                        │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Master    │  │  Worker 0   │  │  Worker 1   │     │
│  │  (rank 0)   │  │  (rank 1)   │  │  (rank 2)   │     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │
│         │                │                │             │
│         └────────────────┼────────────────┘             │
│                          │                              │
│                   ┌──────▼──────┐                       │
│                   │   NCCL/Gloo │                       │
│                   │  (all-reduce)│                       │
│                   └─────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

## Deploying the Training Operator

```bash
# Add via Helm
helm repo add kubeflow https://kubeflow.github.io/training-operator
helm install training-operator kubeflow/training-operator \
  --namespace mlops \
  --version 1.8.1

# Then submit a PyTorch distributed training job
kubectl apply -f pytorch-distributed-job.yaml

# Monitor the job
kubectl get pytorchjobs -n mlops
kubectl logs -f pytorchjob/pytorch-mnist-master-0 -n mlops
```

## Examples

### PyTorch DDP Training

```yaml
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: pytorch-mnist
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      template:
        spec:
          containers:
            - name: pytorch
              image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
              resources:
                limits:
                  nvidia.com/gpu: 1
    Worker:
      replicas: 2
      template:
        spec:
          containers:
            - name: pytorch
              image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
              resources:
                limits:
                  nvidia.com/gpu: 1
```

### CPU-Only Training (for testing)

See `pytorch-distributed-job.yaml` for a CPU-based example that works without GPUs.

## Integration with MLflow

The training script logs metrics to MLflow:

```python
import mlflow

mlflow.set_tracking_uri("http://mlflow.mlflow:5000")
mlflow.set_experiment("distributed-training")

with mlflow.start_run():
    mlflow.log_param("world_size", world_size)
    mlflow.log_param("backend", "gloo")
    # Training loop...
    mlflow.log_metric("loss", loss)
```

## Karpenter Integration

Training jobs automatically provision nodes via Karpenter:

- **GPU jobs**: Provisions g4dn/g5 instances from `gpu-workloads` NodePool
- **CPU jobs**: Provisions c5/m5 instances from `training-workloads` NodePool

Nodes scale to zero when training completes.

## Resource Limits

Configure appropriate resources based on your model:

| Model Size | Workers | GPU per Worker | Instance Type |
|------------|---------|----------------|---------------|
| Small (<1B) | 2-4 | 1 x T4 | g4dn.xlarge |
| Medium (1-7B) | 4-8 | 1 x A10G | g5.xlarge |
| Large (7-70B) | 8+ | 8 x A100 | p4d.24xlarge |
