# Pre-built image for HuggingFace pretrained model pipeline steps.
# Installs transformers, huggingface_hub, and MLflow so the Argo
# Workflow steps can fetch, validate, and register HF models.

FROM python:3.11.14-slim

LABEL maintainer="mlops-platform" \
      description="HuggingFace pretrained model pipeline runtime"

WORKDIR /app

# Install Python dependencies first (layer cached across rebuilds)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared utilities from training pipeline
COPY ../training/src/logging_utils.py /app/shared/logging_utils.py
COPY ../training/src/exceptions.py /app/shared/exceptions.py
COPY ../training/src/mlflow_utils.py /app/shared/mlflow_utils.py

# Copy pipeline source code
COPY src/ /app/src/

# Non-root user for security
USER 1000
