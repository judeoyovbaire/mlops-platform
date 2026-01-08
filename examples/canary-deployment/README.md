# Canary Deployment Example

This example demonstrates progressive model rollout using KServe's built-in canary deployment capabilities.

## Overview

Canary deployments allow you to release a new model version to a small percentage of traffic, monitor its performance, and gradually increase traffic if metrics look good.

```
                     Traffic Flow
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   Client Request                                        │
│         │                                               │
│         ▼                                               │
│   ┌─────────────┐                                       │
│   │   Ingress   │                                       │
│   └──────┬──────┘                                       │
│          │                                              │
│          ▼                                              │
│   ┌──────────────────────────────────────────────┐      │
│   │        KServe InferenceService               │      │
│   │                                              │      │
│   │   ┌─────────────┐      ┌─────────────┐       │      │
│   │   │  Stable     │ 90%  │   Canary    │ 10%   │      │
│   │   │  (v1)       │◄────►│   (v2)      │       │      │
│   │   └─────────────┘      └─────────────┘       │      │
│   └──────────────────────────────────────────────┘      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Deployment Steps

### 1. Deploy the Canary InferenceService

```bash
kubectl apply -f canary-inferenceservice.yaml
```

### 2. Verify Deployment

```bash
kubectl get inferenceservice sklearn-iris-canary -n mlops
```

Expected output:
```
NAME                  URL                                          READY   DEFAULT   CANARY   AGE
sklearn-iris-canary   http://sklearn-iris-canary.mlops.svc.local   True    90        10       2m
```

### 3. Monitor Metrics

Open Grafana and monitor:
- Error rate comparison between stable and canary
- P95 latency comparison
- Request success rate

```bash
make port-forward-grafana
# Open http://localhost:3000
```

### 4. Progressive Rollout

Increase canary traffic gradually:

```bash
# 10% -> 25%
kubectl patch inferenceservice sklearn-iris-canary -n mlops \
  --type=merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent": 25}}}'

# Wait 5-10 minutes, monitor metrics

# 25% -> 50%
kubectl patch inferenceservice sklearn-iris-canary -n mlops \
  --type=merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent": 50}}}'

# Wait 5-10 minutes, monitor metrics

# 50% -> 100% (full promotion)
kubectl patch inferenceservice sklearn-iris-canary -n mlops \
  --type=merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent": 100}}}'
```

### 5. Rollback (if needed)

If canary shows issues, rollback immediately:

```bash
kubectl patch inferenceservice sklearn-iris-canary -n mlops \
  --type=merge \
  -p '{"spec":{"predictor":{"canaryTrafficPercent": 0}}}'
```

## Alerting

The example includes PrometheusRules that will alert when:

| Alert | Condition | Action |
|-------|-----------|--------|
| `CanaryHigherErrorRate` | Canary error rate 50% higher than stable | Consider rollback |
| `CanaryHigherLatency` | Canary P95 latency 30% higher than stable | Investigate cause |

## Best Practices

1. **Start Small**: Begin with 10% canary traffic
2. **Monitor Closely**: Watch metrics for at least 5-10 minutes between promotions
3. **Automate Rollback**: Set up alerts to trigger automatic rollback
4. **Test at Scale**: Ensure canary handles production-like load patterns
5. **Version Tracking**: Use annotations to track model versions

## Files

| File | Description |
|------|-------------|
| `canary-inferenceservice.yaml` | Main InferenceService with canary config |
| Includes: PrometheusRule | Canary-specific alerting rules |
| Includes: ConfigMap | Rollback and promote scripts |

## Related Documentation

- [KServe Canary Rollout](https://kserve.github.io/website/latest/modelserving/v1beta1/rollout/canary/)
- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/overview/)