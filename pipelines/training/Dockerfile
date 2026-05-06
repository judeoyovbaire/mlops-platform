# Pre-built image for ML training pipeline steps.
# Baking dependencies into the image avoids running `pip install` at the start
# of every Argo Workflow step, cutting ~30-60 s of cold-start per container.

FROM python:3.12-slim@sha256:46cb7cc2877e60fbd5e21a9ae6115c30ace7a077b9f8772da879e4590c18c2e3

LABEL maintainer="mlops-platform" \
      description="ML training pipeline runtime"

WORKDIR /app
ENV PYTHONPATH=/app

# Patch OS-level vulnerabilities
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency resolution
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install Python dependencies (layer cached across rebuilds)
COPY training/requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# Copy shared utilities
COPY shared/ /app/shared/

# Copy pipeline source code
COPY training/src/ /app/src/

# Non-root user for security
USER 1000

# Ephemeral pipeline container — no health endpoint to check
HEALTHCHECK NONE
