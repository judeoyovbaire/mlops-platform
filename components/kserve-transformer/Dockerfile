FROM python:3.12-slim@sha256:46cb7cc2877e60fbd5e21a9ae6115c30ace7a077b9f8772da879e4590c18c2e3

LABEL maintainer="mlops-platform" \
      description="KServe transformer for preprocessing inference requests"

WORKDIR /app

RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.7.2@sha256:89a052af62c612d0e05d2596f03edba77d7d904c4478b387a5dc6305821fe0a1 /uv /usr/local/bin/uv

COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

COPY transformer.py .

USER 1000

ENTRYPOINT ["python", "transformer.py"]
