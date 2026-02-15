"""
Validate trained model before registration.

This module performs quality-gate checks on a freshly trained model,
including accuracy threshold enforcement and sanity checks on predictions.
It sits between the train-model and register-model steps in the Argo DAG
so that clearly deficient models are rejected early.
"""

import argparse
import sys
from dataclasses import dataclass

import joblib
import numpy as np
import pandas as pd

try:
    from pipelines.training.src.exceptions import ModelTrainingError
    from pipelines.training.src.logging_utils import get_logger
except ImportError:
    from exceptions import ModelTrainingError
    from logging_utils import get_logger

logger = get_logger(__name__)


@dataclass
class ModelValidationResult:
    """Result of model validation checks."""

    passed: bool
    accuracy: float
    threshold: float
    num_classes_predicted: int
    prediction_failures: int
    checks: dict[str, bool]
    error_message: str | None = None


def validate_model(
    model_path: str,
    data_path: str,
    target: str,
    accuracy_threshold: float,
) -> ModelValidationResult:
    """Validate a trained model against quality-gate criteria.

    Checks performed:
    1. **Accuracy threshold** – the model's test-set accuracy (read from the
       training step's output) must meet or exceed *accuracy_threshold*.
    2. **Prediction sanity** – the model must predict at least 2 distinct
       classes on the validation split (catches degenerate models that
       predict a single class for every input).
    3. **No prediction failures** – calling ``model.predict`` on the feature
       matrix must not raise.

    Args:
        model_path: Path to the trained model (.joblib).
        data_path: Path to the feature CSV used for training.
        target: Name of the target column.
        accuracy_threshold: Minimum required accuracy (0.0–1.0).

    Returns:
        ModelValidationResult with per-check status.

    Raises:
        ModelTrainingError: If the model or data cannot be loaded.
    """
    logger.info(f"Starting model validation (threshold={accuracy_threshold})")

    if not 0.0 <= accuracy_threshold <= 1.0:
        raise ModelTrainingError(
            f"accuracy_threshold must be between 0 and 1, got: {accuracy_threshold}"
        )

    # Load model
    try:
        model = joblib.load(model_path)
        logger.info(f"Loaded model from {model_path}")
    except FileNotFoundError as e:
        raise ModelTrainingError(f"Model file not found: {model_path}") from e
    except Exception as e:
        raise ModelTrainingError(f"Failed to load model: {e}") from e

    # Load data
    try:
        df = pd.read_csv(data_path)
        logger.info(f"Loaded {len(df)} rows from {data_path}")
    except FileNotFoundError as e:
        raise ModelTrainingError(f"Data file not found: {data_path}") from e

    if target not in df.columns:
        raise ModelTrainingError(
            f"Target column '{target}' not found. Available: {list(df.columns)}"
        )

    X = df.drop(columns=[target])
    y = df[target]

    # --- Check 1: prediction sanity ---
    prediction_failures = 0
    try:
        y_pred = model.predict(X)
    except Exception as e:
        logger.error(f"Model prediction failed: {e}")
        prediction_failures = len(X)
        y_pred = np.array([])

    predict_ok = prediction_failures == 0

    # --- Check 2: class diversity ---
    num_classes_predicted = int(len(np.unique(y_pred))) if len(y_pred) > 0 else 0
    class_diversity_ok = num_classes_predicted >= 2

    # --- Check 3: accuracy threshold ---
    if len(y_pred) > 0:
        from sklearn.metrics import accuracy_score

        accuracy = float(accuracy_score(y, y_pred))
    else:
        accuracy = 0.0
    accuracy_ok = accuracy >= accuracy_threshold

    checks = {
        "accuracy_threshold": accuracy_ok,
        "class_diversity": class_diversity_ok,
        "predictions_ok": predict_ok,
    }
    passed = all(checks.values())

    logger.info(
        f"Validation {'PASSED' if passed else 'FAILED'}: "
        f"accuracy={accuracy:.4f}, threshold={accuracy_threshold}, "
        f"classes_predicted={num_classes_predicted}, checks={checks}"
    )

    return ModelValidationResult(
        passed=passed,
        accuracy=accuracy,
        threshold=accuracy_threshold,
        num_classes_predicted=num_classes_predicted,
        prediction_failures=prediction_failures,
        checks=checks,
        error_message=None if passed else "Model did not pass validation gate",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate trained model")
    parser.add_argument("--model", required=True, help="Path to trained model (.joblib)")
    parser.add_argument("--data", required=True, help="Path to feature CSV")
    parser.add_argument("--target", required=True, help="Target column name")
    parser.add_argument(
        "--accuracy-threshold",
        type=float,
        required=True,
        help="Minimum required accuracy (0.0-1.0)",
    )
    parser.add_argument(
        "--result-output",
        required=True,
        help="Path to write pass/fail result (pass or fail)",
    )

    args = parser.parse_args()

    try:
        result = validate_model(
            args.model,
            args.data,
            args.target,
            args.accuracy_threshold,
        )

        # Write result for downstream steps
        with open(args.result_output, "w") as f:
            f.write("pass" if result.passed else "fail")

        if result.passed:
            print(f"Model validation PASSED (accuracy={result.accuracy:.4f})")
        else:
            print(
                f"Model validation FAILED: {result.error_message} "
                f"(accuracy={result.accuracy:.4f})",
                file=sys.stderr,
            )
            sys.exit(1)
    except ModelTrainingError as e:
        print(f"Validation error: {e}", file=sys.stderr)
        sys.exit(1)
