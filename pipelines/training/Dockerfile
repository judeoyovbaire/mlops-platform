# Pre-built image for ML training pipeline steps.
# Baking dependencies into the image avoids running `pip install` at the start
# of every Argo Workflow step, cutting ~30-60 s of cold-start per container.

FROM python:3.15-slim@sha256:8c13a3f37a6a5b71498228e902c4b9f51c1f7900d49fabf71f9a650c6120e0d0

LABEL maintainer="mlops-platform" \
      description="ML training pipeline runtime"

WORKDIR /app
ENV PYTHONPATH=/app

# Patch OS-level vulnerabilities
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency resolution
COPY --from=ghcr.io/astral-sh/uv:0.7.2@sha256:3b898ca84fbe7628c5adcd836c1de78a0f1ded68344d019af8478d4358417399 /uv /usr/local/bin/uv

# Install Python dependencies (layer cached across rebuilds)
COPY training/requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# Copy code in the repo's package layout - modules import
# pipelines.shared.* / pipelines.training.src.*, so the image must provide
# the same package structure (PYTHONPATH=/app makes /app the root).
COPY shared/ /app/pipelines/shared/

COPY training/src/ /app/pipelines/training/src/

# Non-root user for security
USER 1000

# Ephemeral pipeline container — no health endpoint to check
HEALTHCHECK NONE
