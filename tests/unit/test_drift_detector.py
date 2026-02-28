"""Unit tests for drift_detector module."""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

# drift-detection is a standalone component, not an installed package
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "components" / "drift-detection"))
from drift_detector import DriftDetector, DriftResult, DriftReport  # noqa: E402


@pytest.fixture
def detector():
    """Create a DriftDetector with default thresholds."""
    return DriftDetector(model_name="test-model")


@pytest.fixture
def reference_df():
    """Create reference data (normal distribution)."""
    rng = np.random.default_rng(42)
    return pd.DataFrame({
        "feature_a": rng.normal(0, 1, 200),
        "feature_b": rng.normal(5, 2, 200),
    })


@pytest.fixture
def similar_df():
    """Current data drawn from same distribution as reference."""
    rng = np.random.default_rng(99)
    return pd.DataFrame({
        "feature_a": rng.normal(0, 1, 200),
        "feature_b": rng.normal(5, 2, 200),
    })


@pytest.fixture
def drifted_df():
    """Current data drawn from a shifted distribution."""
    rng = np.random.default_rng(99)
    return pd.DataFrame({
        "feature_a": rng.normal(3, 1, 200),   # mean shifted from 0 to 3
        "feature_b": rng.normal(10, 4, 200),   # mean shifted, std doubled
    })


class TestComputePSI:
    """Tests for PSI computation."""

    def test_psi_identical_data(self, detector):
        """PSI should be near zero for identical distributions."""
        data = np.random.default_rng(42).normal(0, 1, 500)
        psi = detector.compute_psi(data, data)
        assert psi == pytest.approx(0.0, abs=0.01)

    def test_psi_shifted_data(self, detector):
        """PSI should be positive for shifted distributions."""
        rng = np.random.default_rng(42)
        ref = rng.normal(0, 1, 500)
        cur = rng.normal(2, 1, 500)
        psi = detector.compute_psi(ref, cur)
        assert psi > 0.1

    def test_psi_empty_arrays(self, detector):
        """PSI should return 0.0 for empty arrays."""
        psi = detector.compute_psi(np.array([]), np.array([]))
        assert psi == 0.0


class TestComputeKSTest:
    """Tests for Kolmogorov-Smirnov test."""

    def test_ks_same_distribution(self, detector):
        """KS p-value should be high for same distribution."""
        rng = np.random.default_rng(42)
        ref = rng.normal(0, 1, 500)
        cur = rng.normal(0, 1, 500)
        stat, pvalue = detector.compute_ks_test(ref, cur)
        assert pvalue > 0.05

    def test_ks_different_distribution(self, detector):
        """KS p-value should be low for different distributions."""
        rng = np.random.default_rng(42)
        ref = rng.normal(0, 1, 500)
        cur = rng.normal(5, 1, 500)
        stat, pvalue = detector.compute_ks_test(ref, cur)
        assert pvalue < 0.05
        assert stat > 0.5


class TestComputeChiSquared:
    """Tests for chi-squared test on categorical features."""

    def test_chi_squared_same_distribution(self, detector):
        """Chi-squared p-value should be high for same distribution."""
        rng = np.random.default_rng(42)
        categories = ["a", "b", "c"]
        ref = pd.Series(rng.choice(categories, 500, p=[0.5, 0.3, 0.2]))
        cur = pd.Series(rng.choice(categories, 500, p=[0.5, 0.3, 0.2]))
        stat, pvalue = detector.compute_chi_squared(ref, cur)
        assert pvalue > 0.01

    def test_chi_squared_different_distribution(self, detector):
        """Chi-squared p-value should be low for very different distributions."""
        rng = np.random.default_rng(42)
        categories = ["a", "b", "c"]
        ref = pd.Series(rng.choice(categories, 500, p=[0.9, 0.05, 0.05]))
        cur = pd.Series(rng.choice(categories, 500, p=[0.05, 0.05, 0.9]))
        stat, pvalue = detector.compute_chi_squared(ref, cur)
        assert pvalue < 0.05


class TestDetectDrift:
    """Tests for the full drift detection pipeline."""

    def test_no_drift_similar_data(self, detector, reference_df, similar_df):
        """No drift should be detected for similar distributions."""
        detector.set_reference_data(reference_df)
        report = detector.detect_drift(similar_df)

        assert isinstance(report, DriftReport)
        assert report.features_analyzed == 2
        assert report.overall_drift_score < 0.1

    def test_drift_detected_shifted_data(self, detector, reference_df, drifted_df):
        """Drift should be detected for shifted distributions."""
        detector.set_reference_data(reference_df)
        report = detector.detect_drift(drifted_df)

        assert report.features_drifted > 0
        assert report.overall_drift_score > 0.05

    def test_reference_data_not_set(self, detector, similar_df):
        """Should raise ValueError if reference data not set."""
        with pytest.raises(ValueError, match="Reference data not set"):
            detector.detect_drift(similar_df)

    def test_missing_feature_in_current(self, detector, reference_df):
        """Should skip features not present in current data."""
        detector.set_reference_data(reference_df)
        partial_df = reference_df[["feature_a"]].copy()
        report = detector.detect_drift(partial_df)
        assert report.features_analyzed == 1

    def test_empty_current_column(self, detector, reference_df):
        """Should skip features with all-NaN current data."""
        detector.set_reference_data(reference_df)
        nan_df = reference_df.copy()
        nan_df["feature_a"] = np.nan
        report = detector.detect_drift(nan_df)
        assert report.features_analyzed == 1


class TestDriftThresholds:
    """Tests for drift threshold logic."""

    def test_critical_severity(self, detector, reference_df, drifted_df):
        """Critical severity for drift_score >= drift_threshold."""
        detector.set_reference_data(reference_df)
        report = detector.detect_drift(drifted_df)

        critical = [r for r in report.feature_results if r.severity == "critical"]
        assert len(critical) > 0

    def test_none_severity_no_drift(self, reference_df, similar_df):
        """No severity for similar distributions."""
        # Use a higher warning_threshold because 200-sample draws from the
        # same distribution naturally produce KS stats ~0.05-0.10.
        lenient = DriftDetector(model_name="test-model", warning_threshold=0.15)
        lenient.set_reference_data(reference_df)
        report = lenient.detect_drift(similar_df)

        none_results = [r for r in report.feature_results if r.severity == "none"]
        assert len(none_results) > 0
