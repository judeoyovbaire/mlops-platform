# Pre-built image for HuggingFace pretrained model pipeline steps.
# Installs transformers, huggingface_hub, and MLflow so the Argo
# Workflow steps can fetch, validate, and register HF models.

FROM python:3.15-slim@sha256:65a65fc7b30b06cb6df4930fd4650697cb23f4c2698ab81fc87e4b031bc36928

LABEL maintainer="mlops-platform" \
      description="HuggingFace pretrained model pipeline runtime"

WORKDIR /app
ENV PYTHONPATH=/app
# Writable matplotlib cache for the non-root user (silences startup warning)
ENV MPLCONFIGDIR=/tmp/matplotlib

# Patch OS-level vulnerabilities
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency resolution
COPY --from=ghcr.io/astral-sh/uv:0.7.2@sha256:3b898ca84fbe7628c5adcd836c1de78a0f1ded68344d019af8478d4358417399 /uv /usr/local/bin/uv

# Install Python dependencies (layer cached across rebuilds)
# The lockfile names two indexes (PyPI and the PyTorch CPU wheels) and was
# compiled with best-match (pyproject.toml [tool.uv.pip]), which the build
# context does not include. Without the same strategy uv takes certifi, idna,
# requests, urllib3 and setuptools from the PyTorch index and fails on the
# pinned versions. Every requirement is hashed, so the strategy only decides
# where each pinned file is fetched from.
COPY pretrained/requirements.txt .
RUN UV_INDEX_STRATEGY=unsafe-best-match uv pip install --system --no-cache -r requirements.txt

# Copy code in the repo's package layout - modules import
# pipelines.shared.* / pipelines.pretrained.src.*, so the image must provide
# the same package structure (PYTHONPATH=/app makes /app the root).
COPY shared/ /app/pipelines/shared/

COPY pretrained/src/ /app/pipelines/pretrained/src/

# Non-root user for security
USER 1000

# Ephemeral pipeline container — no health endpoint to check
HEALTHCHECK NONE
