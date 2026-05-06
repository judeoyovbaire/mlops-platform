FROM python:3.12-slim

LABEL maintainer="mlops-platform" \
      description="KServe transformer for preprocessing inference requests"

WORKDIR /app

RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

COPY transformer.py .

USER 1000

ENTRYPOINT ["python", "transformer.py"]
