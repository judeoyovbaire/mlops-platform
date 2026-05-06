FROM python:3.12-slim@sha256:46cb7cc2877e60fbd5e21a9ae6115c30ace7a077b9f8772da879e4590c18c2e3

WORKDIR /app

# Patch OS-level vulnerabilities
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast, hash-verified dependency resolution
COPY --from=ghcr.io/astral-sh/uv:0.7.2@sha256:3b898ca84fbe7628c5adcd836c1de78a0f1ded68344d019af8478d4358417399 /uv /usr/local/bin/uv

# Install dependencies
COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# Copy application
COPY drift_detector.py .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose metrics port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/metrics')" || exit 1

CMD ["python", "drift_detector.py"]