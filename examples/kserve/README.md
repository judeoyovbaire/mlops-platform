# KServe Examples

KServe InferenceService configurations for the classic serving loop. These leave with the classic loop when JDH-376 lands (ADR-017).

## Files

| File | Description |
|------|-------------|
| `champion-inferenceservice.template.yaml` | CI deploy target: the registry champion served by MLServer (KServe v2 protocol), rendered by `reusable-deploy-model.yaml` |
| `hf-inferenceservice.template.yaml` | Serving template for the HuggingFace pretrained pipeline; also exercised by `scripts/test-policies.sh` |
| `transformer-inferenceservice.yaml` | Transformer + predictor pattern (`components/kserve-transformer`) |
| `inferenceservice-examples.yaml` | Manual demo: sklearn model, service account and PDB |
| `huggingface-sentiment.yaml` | Manual demo: KServe HuggingFace runtime |

> **Kyverno rejects both manual demos as committed.** `require-model-lineage` (Enforce, InferenceServices in `mlops`) requires the annotations `mlops.io/mlflow-experiment-id` and `mlops.io/mlflow-run-id`, which neither demo carries. `huggingface-sentiment.yaml` also lacks the `mlops.io/model-*` labels required by `require-model-metadata`. Add them before applying, for example:
>
> ```yaml
> metadata:
>   annotations:
>     mlops.io/mlflow-experiment-id: "external-demo"
>     mlops.io/mlflow-run-id: "external-demo"
> ```

## Quick Start

Deploy the sklearn-iris example (after adding the lineage annotations above):

```bash
kubectl apply -f inferenceservice-examples.yaml
```

Check the deployment status:

```bash
kubectl get inferenceservice -n mlops
```

## Included Resources

### InferenceService: sklearn-iris

Manual demo deployment:
- Public GCS model `gs://kfserving-examples/models/sklearn/1.0/model`
- Configured with resource limits
- Pod anti-affinity for high availability
- Autoscaling from 1-3 replicas

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
      storageUri: s3://<mlflow-artifacts-bucket>/path/to/model
```

The `kserve-inference` service account (IRSA) has read access to the MLflow artifacts bucket.

## HuggingFace Sentiment Analysis

Deploy a pretrained sentiment analysis model using KServe's native HuggingFace runtime (after adding the labels and annotations above):

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
