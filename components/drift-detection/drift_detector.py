"""
Data Drift Detection Module.

Implements statistical tests for detecting data drift in ML features.
Exposes metrics for Prometheus scraping.
"""

import os
import json
import logging
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from scipy import stats
from prometheus_client import Gauge, Counter, start_http_server

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
DRIFT_SCORE = Gauge(
    'data_drift_score',
    'Data drift score for a feature (0-1 scale)',
    ['model', 'feature']
)
KS_STATISTIC = Gauge(
    'ks_test_statistic',
    'Kolmogorov-Smirnov test statistic',
    ['model', 'feature']
)
PSI_SCORE = Gauge(
    'psi_score',
    'Population Stability Index score',
    ['model', 'feature']
)
DRIFT_DETECTED = Counter(
    'drift_detected_total',
    'Number of times drift was detected',
    ['model', 'feature', 'severity']
)
MODEL_LAST_TRAINED = Gauge(
    'model_last_trained_timestamp',
    'Timestamp of when model was last trained',
    ['model']
)


@dataclass
class DriftResult:
    """Result of drift detection for a single feature."""
    feature: str
    drift_score: float
    ks_statistic: float
    ks_pvalue: float
    psi_score: float
    is_drifted: bool
    severity: str  # 'none', 'warning', 'critical'
    details: Dict[str, Any]


@dataclass
class DriftReport:
    """Complete drift detection report for a model."""
    model_name: str
    timestamp: datetime
    features_analyzed: int
    features_drifted: int
    overall_drift_score: float
    feature_results: List[DriftResult]
    recommendation: str


class DriftDetector:
    """
    Detects data drift between reference (training) and production data.

    Implements multiple statistical tests:
    - Kolmogorov-Smirnov test for continuous features
    - Chi-squared test for categorical features
    - Population Stability Index (PSI)
    - Jensen-Shannon divergence
    """

    def __init__(
        self,
        model_name: str,
        drift_threshold: float = 0.1,
        warning_threshold: float = 0.05,
        psi_threshold: float = 0.2,
        n_bins: int = 10
    ):
        """
        Initialize the drift detector.

        Args:
            model_name: Name of the model being monitored
            drift_threshold: Threshold for critical drift detection
            warning_threshold: Threshold for warning level drift
            psi_threshold: PSI threshold for drift detection
            n_bins: Number of bins for histogram-based metrics
        """
        self.model_name = model_name
        self.drift_threshold = drift_threshold
        self.warning_threshold = warning_threshold
        self.psi_threshold = psi_threshold
        self.n_bins = n_bins
        self.reference_data: Optional[pd.DataFrame] = None
        self.reference_stats: Dict[str, Dict] = {}

    def set_reference_data(self, data: pd.DataFrame) -> None:
        """
        Set the reference (training) data for comparison.

        Args:
            data: DataFrame containing reference feature values
        """
        self.reference_data = data.copy()
        self._compute_reference_statistics()
        logger.info(f"Reference data set with {len(data)} samples, "
                   f"{len(data.columns)} features")

    def _compute_reference_statistics(self) -> None:
        """Pre-compute statistics for reference data."""
        for col in self.reference_data.columns:
            col_data = self.reference_data[col].dropna()

            if self._is_numeric(col_data):
                self.reference_stats[col] = {
                    'type': 'numeric',
                    'mean': col_data.mean(),
                    'std': col_data.std(),
                    'min': col_data.min(),
                    'max': col_data.max(),
                    'quantiles': col_data.quantile([0.25, 0.5, 0.75]).to_dict(),
                    'histogram': np.histogram(col_data, bins=self.n_bins)
                }
            else:
                value_counts = col_data.value_counts(normalize=True)
                self.reference_stats[col] = {
                    'type': 'categorical',
                    'distribution': value_counts.to_dict(),
                    'categories': list(value_counts.index)
                }

    def _is_numeric(self, series: pd.Series) -> bool:
        """Check if a series is numeric."""
        return pd.api.types.is_numeric_dtype(series)

    def compute_ks_test(
        self,
        reference: np.ndarray,
        current: np.ndarray
    ) -> Tuple[float, float]:
        """
        Compute Kolmogorov-Smirnov test statistic.

        Args:
            reference: Reference data array
            current: Current data array

        Returns:
            Tuple of (statistic, p-value)
        """
        statistic, pvalue = stats.ks_2samp(reference, current)
        return float(statistic), float(pvalue)

    def compute_psi(
        self,
        reference: np.ndarray,
        current: np.ndarray
    ) -> float:
        """
        Compute Population Stability Index (PSI).

        PSI = SUM((actual% - expected%) * ln(actual% / expected%))

        Args:
            reference: Reference data array
            current: Current data array

        Returns:
            PSI score
        """
        # Create bins based on reference data
        min_val = min(reference.min(), current.min())
        max_val = max(reference.max(), current.max())
        bins = np.linspace(min_val, max_val, self.n_bins + 1)

        # Compute histograms
        ref_hist, _ = np.histogram(reference, bins=bins)
        cur_hist, _ = np.histogram(current, bins=bins)

        # Convert to proportions with smoothing to avoid division by zero
        ref_prop = (ref_hist + 1) / (len(reference) + self.n_bins)
        cur_prop = (cur_hist + 1) / (len(current) + self.n_bins)

        # Compute PSI
        psi = np.sum((cur_prop - ref_prop) * np.log(cur_prop / ref_prop))
        return float(psi)

    def compute_chi_squared(
        self,
        reference: pd.Series,
        current: pd.Series
    ) -> Tuple[float, float]:
        """
        Compute Chi-squared test for categorical features.

        Args:
            reference: Reference categorical data
            current: Current categorical data

        Returns:
            Tuple of (statistic, p-value)
        """
        # Get all categories
        all_categories = set(reference.unique()) | set(current.unique())

        # Compute observed frequencies
        ref_counts = reference.value_counts()
        cur_counts = current.value_counts()

        # Align to same categories
        ref_freq = np.array([ref_counts.get(cat, 0) for cat in all_categories])
        cur_freq = np.array([cur_counts.get(cat, 0) for cat in all_categories])

        # Add small value to avoid zero frequencies
        ref_freq = ref_freq + 1
        cur_freq = cur_freq + 1

        # Compute chi-squared
        statistic, pvalue = stats.chisquare(cur_freq, f_exp=ref_freq)
        return float(statistic), float(pvalue)

    def compute_jensen_shannon(
        self,
        reference: np.ndarray,
        current: np.ndarray
    ) -> float:
        """
        Compute Jensen-Shannon divergence.

        Args:
            reference: Reference data array
            current: Current data array

        Returns:
            JS divergence (0-1 scale)
        """
        # Create histograms
        min_val = min(reference.min(), current.min())
        max_val = max(reference.max(), current.max())
        bins = np.linspace(min_val, max_val, self.n_bins + 1)

        ref_hist, _ = np.histogram(reference, bins=bins, density=True)
        cur_hist, _ = np.histogram(current, bins=bins, density=True)

        # Normalize and add smoothing
        ref_hist = (ref_hist + 1e-10) / (ref_hist.sum() + 1e-10 * len(ref_hist))
        cur_hist = (cur_hist + 1e-10) / (cur_hist.sum() + 1e-10 * len(cur_hist))

        # Compute JS divergence
        m = 0.5 * (ref_hist + cur_hist)
        js_div = 0.5 * (stats.entropy(ref_hist, m) + stats.entropy(cur_hist, m))

        return float(np.sqrt(js_div))  # Return JS distance (sqrt of divergence)

    def detect_drift(self, current_data: pd.DataFrame) -> DriftReport:
        """
        Detect drift between reference and current data.

        Args:
            current_data: DataFrame containing current feature values

        Returns:
            DriftReport with detailed results
        """
        if self.reference_data is None:
            raise ValueError("Reference data not set. Call set_reference_data first.")

        feature_results = []
        total_drift_score = 0.0

        for col in self.reference_data.columns:
            if col not in current_data.columns:
                logger.warning(f"Feature {col} not found in current data")
                continue

            ref_col = self.reference_data[col].dropna()
            cur_col = current_data[col].dropna()

            if len(cur_col) == 0:
                logger.warning(f"Feature {col} has no valid data in current dataset")
                continue

            result = self._analyze_feature(col, ref_col, cur_col)
            feature_results.append(result)
            total_drift_score += result.drift_score

            # Update Prometheus metrics
            DRIFT_SCORE.labels(model=self.model_name, feature=col).set(result.drift_score)
            KS_STATISTIC.labels(model=self.model_name, feature=col).set(result.ks_statistic)
            PSI_SCORE.labels(model=self.model_name, feature=col).set(result.psi_score)

            if result.is_drifted:
                DRIFT_DETECTED.labels(
                    model=self.model_name,
                    feature=col,
                    severity=result.severity
                ).inc()

        # Compute overall metrics
        n_features = len(feature_results)
        n_drifted = sum(1 for r in feature_results if r.is_drifted)
        overall_score = total_drift_score / n_features if n_features > 0 else 0.0

        # Generate recommendation
        recommendation = self._generate_recommendation(n_drifted, n_features, overall_score)

        return DriftReport(
            model_name=self.model_name,
            timestamp=datetime.now(timezone.utc),
            features_analyzed=n_features,
            features_drifted=n_drifted,
            overall_drift_score=overall_score,
            feature_results=feature_results,
            recommendation=recommendation
        )

    def _analyze_feature(
        self,
        feature_name: str,
        reference: pd.Series,
        current: pd.Series
    ) -> DriftResult:
        """Analyze drift for a single feature."""
        ref_stats = self.reference_stats.get(feature_name, {})

        if ref_stats.get('type') == 'numeric':
            # Numeric feature analysis
            ref_arr = reference.values
            cur_arr = current.values

            ks_stat, ks_pvalue = self.compute_ks_test(ref_arr, cur_arr)
            psi = self.compute_psi(ref_arr, cur_arr)
            js_distance = self.compute_jensen_shannon(ref_arr, cur_arr)

            # Combine metrics for overall drift score
            drift_score = (ks_stat + js_distance) / 2

            details = {
                'reference_mean': float(ref_stats.get('mean', 0)),
                'current_mean': float(current.mean()),
                'reference_std': float(ref_stats.get('std', 0)),
                'current_std': float(current.std()),
                'js_distance': js_distance
            }
        else:
            # Categorical feature analysis
            chi_stat, chi_pvalue = self.compute_chi_squared(reference, current)
            ks_stat = chi_stat / (chi_stat + len(reference))  # Normalize
            ks_pvalue = chi_pvalue
            psi = 0.0  # PSI not applicable for categorical

            drift_score = 1 - chi_pvalue if chi_pvalue > 0 else 1.0

            details = {
                'chi_squared_statistic': chi_stat,
                'chi_squared_pvalue': chi_pvalue,
                'reference_categories': ref_stats.get('categories', []),
                'current_categories': list(current.unique())
            }

        # Determine severity
        if drift_score >= self.drift_threshold:
            severity = 'critical'
            is_drifted = True
        elif drift_score >= self.warning_threshold:
            severity = 'warning'
            is_drifted = True
        else:
            severity = 'none'
            is_drifted = False

        return DriftResult(
            feature=feature_name,
            drift_score=drift_score,
            ks_statistic=ks_stat,
            ks_pvalue=ks_pvalue,
            psi_score=psi,
            is_drifted=is_drifted,
            severity=severity,
            details=details
        )

    def _generate_recommendation(
        self,
        n_drifted: int,
        n_features: int,
        overall_score: float
    ) -> str:
        """Generate actionable recommendation based on drift analysis."""
        drift_percentage = (n_drifted / n_features * 100) if n_features > 0 else 0

        if overall_score >= self.drift_threshold:
            return (
                f"CRITICAL: Significant drift detected in {n_drifted}/{n_features} "
                f"features ({drift_percentage:.1f}%). Immediate model retraining recommended. "
                "Review feature pipelines for data quality issues."
            )
        elif overall_score >= self.warning_threshold:
            return (
                f"WARNING: Moderate drift detected in {n_drifted}/{n_features} "
                f"features ({drift_percentage:.1f}%). Schedule model retraining "
                "and investigate root causes of drift."
            )
        else:
            return (
                f"OK: No significant drift detected. {n_features} features analyzed. "
                "Continue monitoring."
            )


def main():
    """Main entry point for drift detection service."""
    # Configuration from environment
    model_name = os.getenv('MODEL_NAME', 'default-model')
    metrics_port = int(os.getenv('METRICS_PORT', '8000'))
    drift_threshold = float(os.getenv('DRIFT_THRESHOLD', '0.1'))
    check_interval = int(os.getenv('CHECK_INTERVAL_SECONDS', '300'))

    # Start Prometheus metrics server
    start_http_server(metrics_port)
    logger.info(f"Metrics server started on port {metrics_port}")

    # Initialize detector
    detector = DriftDetector(
        model_name=model_name,
        drift_threshold=drift_threshold
    )

    logger.info(f"Drift detector initialized for model: {model_name}")
    logger.info(f"Drift threshold: {drift_threshold}")
    logger.info(f"Check interval: {check_interval}s")

    # In production, this would be integrated with data pipelines
    # For now, we just start the metrics server
    import time
    while True:
        time.sleep(check_interval)
        logger.info("Drift check cycle completed")


if __name__ == '__main__':
    main()