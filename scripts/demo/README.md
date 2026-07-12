# Rollback demo tooling (JDH-372, ADR-016)

The canary story in one directory. The mechanism under demonstration:

```
promote: canaryTrafficPercent=N on the InferenceService   (KServe shifts traffic)
analyze: AnalysisRun from ml-model-canary-analysis        (metrics judge the canary)
verdict: Failed -> canaryTrafficPercent=0 (rollback)      (automated, <2 min)
         Successful -> promote (canary becomes default)
```

## Files

- `run-canary-analysis.py` — instantiates the AnalysisTemplate as a
  standalone AnalysisRun (substituting args), waits for the verdict, and
  acts on it: rollback on failure, promote on success. `--no-act` for
  observe-only runs.
- `register-degraded-challenger.py` — registers a model version that loads
  healthily but fails every prediction. The demo's villain: it passes
  admission and readiness, then degrades under traffic. Never touches the
  champion alias.
- `traffic.sh` — steady inference traffic against the predictor (v2
  protocol, pandas codec), so the analysis gates have data.

## Demo script (cluster burst)

1. Baseline: champion serving, traffic flowing, success-rate ~100%.
2. `register-degraded-challenger.py` → challenger version in the registry.
3. Patch the InferenceService to the challenger spec with
   `canaryTrafficPercent: 30`.
4. `run-canary-analysis.py --service-name iris-classifier` — gates evaluate
   canary pods only.
5. Error-rate gate breaches (challenger 5xxs every request) → verdict
   Failed → **automated rollback to 0% canary**; stable traffic never
   degraded beyond the canary share.
6. Evidence: AnalysisRun measurements, the rollback patch timestamp,
   Prometheus queries showing canary error spike + recovery.
