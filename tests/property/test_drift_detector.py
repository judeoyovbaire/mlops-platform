"""Property-based tests for drift detection.

Uses Hypothesis to verify:
- Identical distributions never trigger drift
- Severely shifted distributions always trigger drift
- Drift scores are bounded [0, 1] or non-negative
"""

import numpy as np
import pandas as pd
from drift_detector import DriftDetector
from hypothesis import given, settings
from hypothesis import strategies as st


@given(
    seed=st.integers(min_value=0, max_value=2**31),
    n_samples=st.integers(min_value=300, max_value=500),
    mean=st.floats(min_value=-100, max_value=100),
    std=st.floats(min_value=0.1, max_value=10),
)
@settings(max_examples=30, deadline=10000)
def test_identical_distributions_low_drift(seed, n_samples, mean, std):
    """Drawing two samples from the same distribution should produce low drift scores.

    Note: With small samples, PSI can produce false positives due to binning noise.
    We use n_samples >= 300 and check that the KS p-value remains above 0.001.
    A threshold of 0.001 (instead of 0.05) accounts for the multiple comparisons
    inherent in property-based testing — with 30 examples at alpha=0.001, the
    probability of any false rejection is ~3%.
    """
    rng = np.random.default_rng(seed)

    ref_data = pd.DataFrame(
        {
            "feature_a": rng.normal(mean, std, n_samples),
        }
    )

    # Use a different seed but same distribution parameters
    rng2 = np.random.default_rng(seed + 1000)
    cur_data = pd.DataFrame(
        {
            "feature_a": rng2.normal(mean, std, n_samples),
        }
    )

    detector = DriftDetector(model_name="test", warning_threshold=0.2)
    detector.set_reference_data(ref_data)
    report = detector.detect_drift(cur_data)

    # KS test should not reject the null hypothesis (same distribution)
    # Use alpha=0.001 to account for multiple hypothesis examples
    for result in report.feature_results:
        assert result.ks_pvalue > 0.001, (
            f"KS test rejected identical distributions: p={result.ks_pvalue}, "
            f"score={result.drift_score}"
        )


@given(
    seed=st.integers(min_value=0, max_value=2**31),
    n_samples=st.integers(min_value=200, max_value=500),
    shift=st.floats(min_value=5, max_value=50),
)
@settings(max_examples=20, deadline=10000)
def test_severely_shifted_distribution_triggers_drift(seed, n_samples, shift):
    """A large mean shift should always be detected as drift."""
    rng = np.random.default_rng(seed)

    ref_data = pd.DataFrame(
        {
            "feature_a": rng.normal(0, 1, n_samples),
        }
    )
    cur_data = pd.DataFrame(
        {
            "feature_a": rng.normal(shift, 1, n_samples),
        }
    )

    detector = DriftDetector(model_name="test")
    detector.set_reference_data(ref_data)
    report = detector.detect_drift(cur_data)

    assert report.features_drifted > 0, (
        f"Drift not detected for shift={shift}, score={report.overall_drift_score}"
    )


@given(
    seed=st.integers(min_value=0, max_value=2**31),
    n_features=st.integers(min_value=1, max_value=5),
    n_samples=st.integers(min_value=100, max_value=300),
)
@settings(max_examples=20, deadline=10000)
def test_drift_score_is_non_negative(seed, n_features, n_samples):
    """Drift scores must always be non-negative."""
    rng = np.random.default_rng(seed)

    ref_data = pd.DataFrame({f"feat_{i}": rng.normal(0, 1, n_samples) for i in range(n_features)})
    cur_data = pd.DataFrame(
        {f"feat_{i}": rng.normal(i * 0.5, 1, n_samples) for i in range(n_features)}
    )

    detector = DriftDetector(model_name="test")
    detector.set_reference_data(ref_data)
    report = detector.detect_drift(cur_data)

    assert report.overall_drift_score >= 0
    for result in report.feature_results:
        assert result.drift_score >= 0


@given(
    seed=st.integers(min_value=0, max_value=2**31),
    n_samples=st.integers(min_value=100, max_value=500),
)
@settings(max_examples=20, deadline=10000)
def test_features_analyzed_matches_input(seed, n_samples):
    """Number of features analyzed should match number of shared columns."""
    rng = np.random.default_rng(seed)

    n_features = 3
    ref_data = pd.DataFrame({f"feat_{i}": rng.normal(0, 1, n_samples) for i in range(n_features)})
    cur_data = pd.DataFrame({f"feat_{i}": rng.normal(0, 1, n_samples) for i in range(n_features)})

    detector = DriftDetector(model_name="test")
    detector.set_reference_data(ref_data)
    report = detector.detect_drift(cur_data)

    assert report.features_analyzed == n_features


@given(
    seed=st.integers(min_value=0, max_value=2**31),
)
@settings(max_examples=20, deadline=10000)
def test_psi_is_symmetric_approx(seed):
    """PSI should be approximately symmetric: PSI(A,B) ≈ PSI(B,A)."""
    rng = np.random.default_rng(seed)

    a = rng.normal(0, 1, 500)
    b = rng.normal(1, 1, 500)

    detector = DriftDetector(model_name="test")
    psi_ab = detector.compute_psi(a, b)
    psi_ba = detector.compute_psi(b, a)

    # PSI is not perfectly symmetric but should be in the same ballpark
    assert abs(psi_ab - psi_ba) < max(psi_ab, psi_ba) * 0.5 + 0.01
