# API Reference

This document describes the inference API endpoints exposed by models deployed on the MLOps Platform.

## KServe V1 Protocol

All models deployed via KServe support the V1 inference protocol.

### Base URL

```
https://<service-name>.<namespace>.svc.cluster.local
```

For external access via ALB Ingress:
```
https://<ingress-endpoint>/
```

## Endpoints

### Health Check

**GET** `/v1/models/<model-name>`

Returns model readiness status.

**Response:**
```json
{
  "name": "sklearn-iris",
  "ready": true
}
```

**Status Codes:**
| Code | Description |
|------|-------------|
| 200 | Model is ready |
| 503 | Model is not ready |

### Predict

**POST** `/v1/models/<model-name>:predict`

Run inference on the model.

**Request Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "instances": [
    [5.1, 3.5, 1.4, 0.2],
    [6.2, 2.9, 4.3, 1.3]
  ]
}
```

**Response:**
```json
{
  "predictions": [0, 1]
}
```

**Status Codes:**
| Code | Description |
|------|-------------|
| 200 | Successful prediction |
| 400 | Invalid request format |
| 500 | Model inference error |

### Explain (if supported)

**POST** `/v1/models/<model-name>:explain`

Get model explanations for predictions.

**Request Body:**
```json
{
  "instances": [
    [5.1, 3.5, 1.4, 0.2]
  ]
}
```

**Response:**
```json
{
  "explanations": {
    "feature_importance": [0.35, 0.25, 0.30, 0.10]
  }
}
```

## Model-Specific Examples

### sklearn-iris

Iris flower classification model.

**Features:**
| Index | Name | Description | Range |
|-------|------|-------------|-------|
| 0 | sepal_length | Sepal length in cm | 4.3 - 7.9 |
| 1 | sepal_width | Sepal width in cm | 2.0 - 4.4 |
| 2 | petal_length | Petal length in cm | 1.0 - 6.9 |
| 3 | petal_width | Petal width in cm | 0.1 - 2.5 |

**Classes:**
| Value | Label |
|-------|-------|
| 0 | setosa |
| 1 | versicolor |
| 2 | virginica |

**Example Request:**
```bash
curl -X POST "http://<endpoint>/v1/models/sklearn-iris:predict" \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [
      [5.1, 3.5, 1.4, 0.2],
      [6.2, 2.9, 4.3, 1.3],
      [7.2, 3.0, 5.8, 1.6]
    ]
  }'
```

**Example Response:**
```json
{
  "predictions": [0, 1, 2]
}
```

## Error Responses

All error responses follow this format:

```json
{
  "error": "Error message description"
}
```

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| `Model not found` | Model name incorrect or not deployed | Verify model name and deployment status |
| `Invalid input shape` | Input dimensions don't match model expectations | Check feature count matches model |
| `Model not ready` | Model still loading | Wait for model to become ready |

## Rate Limiting

When using ALB Ingress, consider implementing rate limiting:

```yaml
# Annotations for ALB rate limiting
alb.ingress.kubernetes.io/actions.rate-limit: |
  {"type":"fixed-response","fixedResponseConfig":{"statusCode":"429","contentType":"application/json","messageBody":"{\"error\":\"Rate limit exceeded\"}"}}
```

## Authentication

For production deployments, enable authentication via:

1. **API Keys** - Header-based authentication
2. **OAuth2/OIDC** - Token-based authentication via Istio/Envoy
3. **mTLS** - Certificate-based authentication

Example with API key:
```bash
curl -X POST "http://<endpoint>/v1/models/sklearn-iris:predict" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: <your-api-key>" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
```

## Monitoring

### Metrics Endpoint

**GET** `/metrics`

Returns Prometheus metrics for the inference service.

Key metrics:
| Metric | Description |
|--------|-------------|
| `request_count` | Total number of requests |
| `request_latency_seconds` | Request latency histogram |
| `request_success_rate` | Successful request rate |

## SDK Examples

### Python

```python
import requests

def predict(endpoint: str, model_name: str, instances: list) -> dict:
    url = f"{endpoint}/v1/models/{model_name}:predict"
    response = requests.post(url, json={"instances": instances})
    response.raise_for_status()
    return response.json()

# Usage
result = predict(
    endpoint="http://sklearn-iris.mlops.svc.cluster.local",
    model_name="sklearn-iris",
    instances=[[5.1, 3.5, 1.4, 0.2]]
)
print(result["predictions"])  # [0]
```

### JavaScript

```javascript
async function predict(endpoint, modelName, instances) {
  const response = await fetch(`${endpoint}/v1/models/${modelName}:predict`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ instances })
  });
  return response.json();
}

// Usage
const result = await predict(
  'http://sklearn-iris.mlops.svc.cluster.local',
  'sklearn-iris',
  [[5.1, 3.5, 1.4, 0.2]]
);
console.log(result.predictions); // [0]
```

## Related Documentation

- [Architecture](architecture.md)
- [Disaster Recovery](disaster-recovery.md)
- [Runbooks](runbooks/README.md)
