# Pre-built image for HuggingFace pretrained model pipeline steps.
# Installs transformers, huggingface_hub, and MLflow so the Argo
# Workflow steps can fetch, validate, and register HF models.

FROM python:3.12-slim@sha256:46cb7cc2877e60fbd5e21a9ae6115c30ace7a077b9f8772da879e4590c18c2e3

LABEL maintainer="mlops-platform" \
      description="HuggingFace pretrained model pipeline runtime"

WORKDIR /app
ENV PYTHONPATH=/app

# Patch OS-level vulnerabilities
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency resolution
COPY --from=ghcr.io/astral-sh/uv:0.7.2@sha256:89a052af62c612d0e05d2596f03edba77d7d904c4478b387a5dc6305821fe0a1 /uv /usr/local/bin/uv

# Install Python dependencies (layer cached across rebuilds)
COPY pretrained/requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# Copy shared utilities
COPY shared/ /app/shared/

# Copy pipeline source code
COPY pretrained/src/ /app/src/

# Non-root user for security
USER 1000

# Ephemeral pipeline container — no health endpoint to check
HEALTHCHECK NONE
