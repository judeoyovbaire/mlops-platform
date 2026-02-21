# Pre-built image for HuggingFace pretrained model pipeline steps.
# Installs transformers, huggingface_hub, and MLflow so the Argo
# Workflow steps can fetch, validate, and register HF models.

FROM python:3.12-slim

LABEL maintainer="mlops-platform" \
      description="HuggingFace pretrained model pipeline runtime"

WORKDIR /app
ENV PYTHONPATH=/app

# Install Python dependencies first (layer cached across rebuilds)
COPY pretrained/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared utilities
COPY shared/ /app/shared/

# Copy pipeline source code
COPY pretrained/src/ /app/src/

# Non-root user for security
USER 1000
