# Iris Classifier Model Container
# Used for custom model serving with KServe

FROM python:3.10-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    scikit-learn==1.3.0 \
    pandas==2.0.0 \
    mlflow==3.0.0 \
    flask==3.0.0 \
    gunicorn==21.2.0

# Copy model serving code
COPY serve.py .

# Create non-root user for security
RUN useradd -m -u 1000 model && chown -R model:model /app
USER model

# Expose port for inference
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the model server
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "60", "serve:app"]