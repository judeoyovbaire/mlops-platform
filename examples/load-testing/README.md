# Load Testing Examples

This directory contains load testing examples for KServe inference endpoints using k6 and Locust.

## k6 Load Test

### Installation

```bash
# macOS
brew install k6

# Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Windows
choco install k6
```

### Running the Test

```bash
# Port-forward inference service
kubectl port-forward -n mlops svc/sklearn-iris-predictor-default 8080:80

# Run load test
k6 run k6-load-test.js

# With custom endpoint
INFERENCE_ENDPOINT=http://localhost:8080/v1/models/sklearn-iris:predict k6 run k6-load-test.js
```

### Test Scenarios

The k6 test includes:
- **Ramp-up**: Gradual increase from 0 to 100 users
- **Sustained load**: 5 minutes at 100 users
- **Ramp-down**: Gradual decrease to 0 users
- **Thresholds**: P95 < 500ms, P99 < 1s, error rate < 5%

### Results

Results are saved to `load-test-results.json` and displayed in the console.

## Locust Load Test

### Installation

```bash
pip install locust
```

### Running the Test

```bash
# Port-forward inference service
kubectl port-forward -n mlops svc/sklearn-iris-predictor-default 8080:80

# Start Locust web UI
locust -f locust-load-test.py --host=http://localhost:8080

# Access web UI at http://localhost:8089
# Configure: Number of users, spawn rate, host
# Start test from web UI
```

### Test Scenarios

The Locust test includes:
- **Single predictions**: 75% of requests
- **Batch predictions**: 25% of requests (2-5 items per batch)
- **Health checks**: Periodic health endpoint checks

### Web UI Features

- Real-time metrics dashboard
- Charts for RPS, response times, failure rates
- Download results as CSV
- Stop/restart tests dynamically

## Performance Targets

| Metric | Target | Critical Threshold |
|--------|--------|-------------------|
| P95 Latency | < 500ms | > 1s |
| P99 Latency | < 1s | > 2s |
| Error Rate | < 1% | > 5% |
| Throughput | > 100 req/s | < 50 req/s |

## Interpreting Results

### Good Performance
- P95 latency < 500ms
- Error rate < 1%
- Consistent throughput
- No memory leaks (stable memory usage)

### Performance Issues
- **High latency**: Check model complexity, resource limits, network
- **High error rate**: Check model inputs, resource constraints
- **Throughput degradation**: Check autoscaling, resource limits
- **Memory growth**: Check for memory leaks in model serving

## Integration with CI/CD

Add load testing to your CI/CD pipeline:

```yaml
# .github/workflows/load-test.yaml
- name: Run load test
  run: |
    kubectl port-forward -n mlops svc/sklearn-iris-predictor-default 8080:80 &
    sleep 5
    k6 run examples/load-testing/k6-load-test.js
```

## Troubleshooting

**Connection refused:**
- Verify port-forward is running
- Check service is accessible: `kubectl get svc -n mlops`

**High latency:**
- Check pod resources: `kubectl top pods -n mlops`
- Verify autoscaling: `kubectl get hpa -n mlops`
- Check node resources: `kubectl top nodes`

**Test fails:**
- Verify inference service is ready: `kubectl get inferenceservice -n mlops`
- Check pod logs: `kubectl logs -n mlops -l serving.kserve.io/inferenceservice=sklearn-iris`
