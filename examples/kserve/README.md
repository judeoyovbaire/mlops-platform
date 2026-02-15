# KServe Examples

Example KServe InferenceService configurations for model serving.

## Files

| File | Description |
|------|-------------|
| `inferenceservice-examples.yaml` | Complete example with sklearn model, ingress, and PDB |

## Quick Start

Deploy the sklearn-iris example:

```bash
kubectl apply -f inferenceservice-examples.yaml
```

Check the deployment status:

```bash
kubectl get inferenceservice -n mlops
```

## Included Resources

### InferenceService: sklearn-iris

A production-ready sklearn model deployment:
- Uses public sklearn iris model from GCS
- Configured with resource limits
- Pod anti-affinity for high availability
- Autoscaling from 1-3 replicas

### Ingress: sklearn-iris-ingress

AWS ALB ingress for external access:
- Internet-facing scheme
- Health check on model endpoint
- IP target type

### ServiceAccount: kserve-inference

Dedicated service account for inference workloads.

### PodDisruptionBudget: sklearn-iris-pdb

Ensures at least 1 replica during cluster maintenance.

## Testing the Model

After deployment, port-forward to test locally:

```bash
kubectl port-forward svc/sklearn-iris-predictor -n mlops 8080:80
```

Send a test prediction:

```bash
curl -X POST http://localhost:8080/v1/models/sklearn-iris:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
```

## Customization

To deploy your own model, modify the `storageUri`:

```yaml
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn  # or pytorch, tensorflow, etc.
      storageUri: gs://your-bucket/models/your-model
```

## HuggingFace Sentiment Analysis

Deploy a pretrained sentiment analysis model using KServe's native HuggingFace runtime:

```bash
kubectl apply -f huggingface-sentiment.yaml
```

Wait for readiness:

```bash
kubectl wait --for=condition=Ready inferenceservice/hf-sentiment -n mlops --timeout=600s
```

Test:

```bash
kubectl port-forward svc/hf-sentiment-predictor -n mlops 8080:80
curl -X POST http://localhost:8080/v1/models/sentiment:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": ["I love this product!"]}'
```

## Related Examples

- `examples/llm-inference/` - LLM serving with vLLM
- `examples/distributed-training/` - Multi-GPU training
