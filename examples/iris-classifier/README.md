# Iris Classifier Example

A complete end-to-end example demonstrating the MLOps platform capabilities:
- Model training with experiment tracking via Kubeflow Pipelines
- Model registration with MLflow
- Model serving with KServe
- Inference testing

## Prerequisites

- MLOps platform deployed (see main README)
- `kubectl` configured to access the cluster
- Python 3.10+

## Quick Start

### 1. Run as Kubeflow Pipeline

```bash
# Compile the pipeline
cd ../../pipelines/training
python example-pipeline.py

# Upload ml_training_pipeline.yaml to Kubeflow Pipelines UI
# Or submit via CLI:
kfp run submit -f ml_training_pipeline.yaml
```

### 2. Deploy Model with KServe

```bash
# Deploy using the example from components/
kubectl apply -f ../../components/kserve/inferenceservice-examples.yaml

# Or deploy specifically the MLflow model:
cat <<EOF | kubectl apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-classifier
  namespace: mlops
spec:
  predictor:
    model:
      modelFormat:
        name: mlflow
      protocolVersion: v2
      storageUri: s3://mlops-platform-mlflow-artifacts/models/iris-classifier/1
EOF

# Wait for the service to be ready
kubectl wait --for=condition=Ready inferenceservice/iris-classifier -n mlops --timeout=300s

# Get the service URL
kubectl get inferenceservice iris-classifier -n mlops
```

### 3. Test Inference

```bash
# Run inference test
python test_inference.py

# Or use curl directly
SERVICE_URL=$(kubectl get inferenceservice iris-classifier -n mlops -o jsonpath='{.status.url}')
curl -X POST "${SERVICE_URL}/v1/models/iris-classifier:predict" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
```

## Project Structure

```
iris-classifier/
├── README.md              # This file
└── test_inference.py      # Inference testing script

# Related files:
# ../../pipelines/training/example-pipeline.py  - Training pipeline
# ../../components/kserve/inferenceservice-examples.yaml - KServe examples
```

## Expected Output

### Training Output (from Kubeflow Pipeline)
```
Training complete. Run ID: abc123
Accuracy: 0.9667, F1: 0.9665
Model registered as 'iris-classifier' version 1
Alias 'champion' set for this version
```

### Inference Output
```json
{
  "predictions": ["setosa"],
  "probabilities": [[0.98, 0.01, 0.01]]
}
```

## Customization

### Different Dataset
Modify pipeline parameters when submitting:

```bash
kfp run submit -f ml_training_pipeline.yaml \
  --param dataset_url="https://your-data-source/data.csv" \
  --param target_column="your_target"
```

### Hyperparameter Tuning
Adjust hyperparameters via pipeline parameters:

```bash
kfp run submit -f ml_training_pipeline.yaml \
  --param n_estimators=200 \
  --param max_depth=15
```

### Model Serving Configuration
See `../../components/kserve/inferenceservice-examples.yaml` for various deployment patterns:
- Basic deployment
- Canary deployment (90/10 traffic split)
- Autoscaling with HPA
- GPU-enabled LLM serving