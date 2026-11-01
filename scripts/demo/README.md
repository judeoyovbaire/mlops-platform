# Rollback demo tooling (JDH-372, ADR-016)

Post-deploy verification with automated rollback, in one directory. There is no traffic splitting: KServe RawDeployment ignores `canaryTrafficPercent`, so a challenger update is a full in-place rollout. The mechanism under demonstration:

```
deploy:  patch storageUri to the challenger              (full in-place rollout)
analyze: AnalysisRun from ml-model-canary-analysis       (metrics judge it under traffic)
verdict: Failed -> patch storageUri back (--rollback-uri), exit 1
         Successful -> keep the challenger, exit 0
```

## Files

- `run-canary-analysis.py`: instantiates the AnalysisTemplate as a
  standalone AnalysisRun (substituting args), waits for the verdict, and
  acts on it: on any non-Successful verdict it patches `storageUri` back to
  `--rollback-uri`. `--no-act` for observe-only runs.
- `register-degraded-challenger.py`: registers a model version that loads
  healthily but fails every prediction. The demo's villain: it passes
  admission and readiness, then degrades under traffic. Never touches the
  champion alias.

The analysis gates need live traffic during the window; drive steady
inference requests against the predictor (v2 protocol) with any load
generator. No traffic script is committed.

## Demo script (cluster burst)

1. Baseline: champion serving, traffic flowing, success-rate ~100%.
2. `register-degraded-challenger.py` → challenger version in the registry.
3. Patch the InferenceService `storageUri` to the challenger.
4. `run-canary-analysis.py --service-name iris-classifier --rollback-uri s3://.../serving_model`
   (the champion's artifact URI). The gates judge all current predictor pods.
5. Error-rate gate breaches (challenger 5xxs every request) → verdict
   Failed → **automated rollback to the champion** within ~80 s of the first
   measurement. During the window 100% of traffic hit the challenger.
6. Evidence: [AnalysisRun](../../docs/evidence/rollback-demo-analysisrun.yaml)
   and [error-rate timeline](../../docs/evidence/rollback-demo-error-rate-timeline.json).
