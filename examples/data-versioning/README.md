# Data Versioning with DVC

This example demonstrates data versioning using [DVC](https://dvc.org/) integrated with the MLOps platform.

## Overview

DVC (Data Version Control) provides Git-like versioning for datasets and ML artifacts:
- **Version datasets** alongside code in Git
- **Track large files** without storing them in Git
- **Reproduce pipelines** with versioned data
- **Share data** across teams via S3 remote storage

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Git Repo      │     │   DVC Remote    │     │  Argo Workflow  │
│   (.dvc files)  │────▶│   (S3 bucket)   │◀────│  (dvc pull)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                               │
        │                                               │
        └───────────────────────────────────────────────┘
                    Version-controlled
                    data + code + models
```

## Quick Start

### Local Setup

```bash
# Initialize DVC in your project
dvc init

# Configure S3 remote (uses MLflow bucket)
dvc remote add -d s3remote s3://mlflow-artifacts-{account-id}/dvc
dvc remote modify s3remote region eu-west-1

# Track a dataset
dvc add data/training_data.csv

# Commit the .dvc file to Git
git add data/training_data.csv.dvc data/.gitignore
git commit -m "Add training dataset v1"

# Push data to S3
dvc push
```

### In Argo Workflows

```yaml
- name: fetch-versioned-data
  container:
    image: python:3.11-slim
    command: [sh, -c]
    args:
      - |
        pip install dvc[s3]
        dvc pull data/training_data.csv
        # Data is now available for training
```

## DVC Configuration

### .dvc/config

```ini
[core]
    remote = s3remote
    autostage = true

[remote "s3remote"]
    url = s3://mlflow-artifacts-{account-id}/dvc
    region = eu-west-1
```

### IRSA Integration

DVC uses the pod's service account for S3 access (no credentials needed):

```yaml
spec:
  serviceAccountName: mlflow  # Has S3 access via IRSA
  containers:
    - name: dvc
      command: [dvc, pull]
```

## Example: Versioned Training Pipeline

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: versioned-training
spec:
  entrypoint: train-with-versioned-data
  templates:
    - name: train-with-versioned-data
      dag:
        tasks:
          - name: pull-data
            template: dvc-pull
          - name: train
            template: train-model
            dependencies: [pull-data]
          - name: push-model
            template: dvc-push
            dependencies: [train]

    - name: dvc-pull
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install dvc[s3]
            git clone https://github.com/your-org/ml-project.git
            cd ml-project
            dvc pull data/

    - name: train-model
      container:
        image: python:3.11-slim
        command: [python, train.py]

    - name: dvc-push
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            dvc add models/trained_model.pkl
            dvc push
```

## Best Practices

1. **Version data with code**: Commit `.dvc` files alongside training code
2. **Use meaningful tags**: `git tag data-v1.0` for dataset releases
3. **Lock pipeline versions**: Use `dvc.lock` for reproducible runs
4. **Separate data/model remotes**: Keep training data separate from model artifacts

## Integration with MLflow

DVC handles data versioning, MLflow handles experiment tracking:

```python
import dvc.api
import mlflow

# Get versioned data path
data_url = dvc.api.get_url('data/training.csv', repo='.')

# Log data version in MLflow
with mlflow.start_run():
    mlflow.log_param("data_version", dvc.api.get_rev())
    mlflow.log_param("data_url", data_url)
    # ... training code
```

## Dependencies

Add to `pyproject.toml`:

```toml
dependencies = [
    "dvc[s3]>=3.0.0",
]
```