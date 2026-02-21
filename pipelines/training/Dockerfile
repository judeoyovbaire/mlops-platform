# Pre-built image for ML training pipeline steps.
# Baking dependencies into the image avoids running `pip install` at the start
# of every Argo Workflow step, cutting ~30-60 s of cold-start per container.

FROM python:3.12-slim

LABEL maintainer="mlops-platform" \
      description="ML training pipeline runtime"

WORKDIR /app
ENV PYTHONPATH=/app

# Install Python dependencies first (layer cached across rebuilds)
COPY training/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared utilities
COPY shared/ /app/shared/

# Copy pipeline source code
COPY training/src/ /app/src/

# Non-root user for security
USER 1000
