# Drift Statistics Library

A statistical drift-detection library with property-based tests. **Platform
integration is intentionally descoped** — see
[ADR-013](../../docs/adr/013-descope-drift-triggered-retraining.md).

## What this is

`drift_detector.py` implements the statistical core for comparing a reference
distribution against production data:

- **Kolmogorov–Smirnov test** with `alpha=0.001` (chosen to limit false
  positives under multiple comparisons across features)
- **Population Stability Index (PSI)** with Laplace smoothing and guards
  against binning noise on small samples
- **Jensen–Shannon divergence** for numeric distributions
- **Chi-squared with Cramér's V** effect size for categorical features
  (effect size rather than `1 - p_value`, which conflates significance
  with magnitude)
- Degenerate-distribution and NaN guards throughout

## Tests

The library is covered by unit tests and property-based tests
(`tests/property/test_drift_detector.py`) that verify statistical invariants —
e.g. PSI approximate symmetry, no-drift on identical distributions, and
detection on shifted distributions with `n >= 300` samples.

```bash
uv sync --frozen --extra drift-detection
uv run pytest tests/unit/test_drift_detector.py tests/property/test_drift_detector.py
```

## Why there is no deployment here

An earlier iteration shipped this as an always-on monitoring service wired to
an automated retraining loop. The end-to-end loop was descoped (ADR-013): the
platform's verification focus is the deploy → canary → auto-rollback path, and
a drift loop without production inference-data capture is a no-op in practice.
The statistical core is kept because it is correct, tested, and reusable —
integration can be revisited when there is real production traffic to monitor.
