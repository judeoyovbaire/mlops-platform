# Iris Classifier Example

A complete end-to-end example demonstrating the MLOps platform capabilities:
- Model training with experiment tracking
- Model registration with MLflow
- Model serving with KServe
- Inference testing

## Prerequisites

- MLOps platform deployed (see main README)
- `kubectl` configured to access the cluster
- Python 3.10+

## Quick Start

### 1. Train the Model Locally (Optional)

```bash
# Install dependencies
pip install -r requirements.txt

# Train and register model
python train.py
```

### 2. Run as Kubeflow Pipeline

```bash
# Compile the pipeline
cd ../../pipelines/training
python example-pipeline.py

# Upload ml_training_pipeline.yaml to Kubeflow Pipelines UI
```

### 3. Deploy Model with KServe

```bash
# Deploy the trained model
kubectl apply -f kserve-deployment.yaml

# Wait for the service to be ready
kubectl wait --for=condition=Ready inferenceservice/iris-classifier -n mlops --timeout=300s

# Get the service URL
kubectl get inferenceservice iris-classifier -n mlops
```

### 4. Test Inference

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
├── requirements.txt       # Python dependencies
├── train.py              # Local training script
├── test_inference.py     # Inference testing script
└── kserve-deployment.yaml # KServe InferenceService manifest
```

## Expected Output

### Training Output
```
Training Iris Classifier...
Accuracy: 0.9667
F1 Score: 0.9665
Model registered with alias 'champion'
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
Modify `train.py` to use a different dataset:

```python
dataset_url = "https://your-data-source/data.csv"
target_column = "your_target"
```

### Hyperparameter Tuning
Adjust hyperparameters in `train.py`:

```python
params = {
    "n_estimators": 200,
    "max_depth": 15,
    "min_samples_split": 5
}
```

### Model Serving Configuration
Update `kserve-deployment.yaml` for production:

```yaml
spec:
  predictor:
    minReplicas: 2
    maxReplicas: 10
```