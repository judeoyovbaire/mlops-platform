"""
Register model to MLflow Model Registry.

This module registers trained models to MLflow if they meet
the specified accuracy threshold.
"""

import argparse
import logging
import sys
from dataclasses import dataclass

import mlflow
from mlflow.exceptions import MlflowException
from mlflow.tracking import MlflowClient

from pipelines.training.src.exceptions import InvalidThresholdError, ModelRegistrationError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@dataclass
class RegistrationResult:
    """Result of model registration operation."""

    model_name: str
    run_id: str
    accuracy: float
    threshold: float
    registered: bool
    version: int | None = None
    alias: str | None = None
    success: bool = True
    error_message: str | None = None


def validate_threshold(threshold: float) -> None:
    """
    Validate that the threshold is within valid range.

    Args:
        threshold: Accuracy threshold value.

    Raises:
        InvalidThresholdError: If threshold is not between 0 and 1.
    """
    if not 0.0 <= threshold <= 1.0:
        raise InvalidThresholdError(f"Threshold must be between 0 and 1, got: {threshold}")


def register_model(
    model_name: str,
    mlflow_uri: str,
    threshold: float,
    alias: str,
    run_id: str,
) -> RegistrationResult:
    """
    Register a model to MLflow Model Registry if it meets threshold.

    Args:
        model_name: Name for the registered model.
        mlflow_uri: MLflow tracking server URI.
        threshold: Minimum accuracy required for registration.
        alias: Alias to assign to the registered model version.
        run_id: MLflow run ID containing the model.

    Returns:
        RegistrationResult containing registration status and details.

    Raises:
        InvalidThresholdError: If threshold is not between 0 and 1.
        ModelRegistrationError: If registration fails.
    """
    logger.info(f"Starting model registration for run {run_id}")

    validate_threshold(threshold)

    try:
        mlflow.set_tracking_uri(mlflow_uri)
        client = MlflowClient()
        logger.info(f"Connected to MLflow at {mlflow_uri}")
    except MlflowException as e:
        raise ModelRegistrationError(f"Failed to connect to MLflow: {e}") from e

    try:
        # Get run metrics
        run = client.get_run(run_id)
        accuracy = run.data.metrics.get("accuracy", 0.0)
        logger.info(f"Model accuracy: {accuracy:.4f}, threshold: {threshold}")
    except MlflowException as e:
        raise ModelRegistrationError(f"Failed to get run {run_id}: {e}") from e

    if accuracy >= threshold:
        try:
            # Register model
            model_uri = f"runs:/{run_id}/model"
            mv = mlflow.register_model(model_uri, model_name)
            logger.info(f"Registered {model_name} version {mv.version}")

            # Set alias
            client.set_registered_model_alias(model_name, alias, mv.version)
            logger.info(f"Set alias '{alias}' -> version {mv.version}")

            return RegistrationResult(
                model_name=model_name,
                run_id=run_id,
                accuracy=accuracy,
                threshold=threshold,
                registered=True,
                version=int(mv.version),
                alias=alias,
                success=True,
            )

        except MlflowException as e:
            raise ModelRegistrationError(f"Failed to register model: {e}") from e
    else:
        logger.info(f"Accuracy {accuracy:.4f} below threshold {threshold}, not registering")
        return RegistrationResult(
            model_name=model_name,
            run_id=run_id,
            accuracy=accuracy,
            threshold=threshold,
            registered=False,
            success=True,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Register model")
    parser.add_argument("--model-name", required=True, help="Model name")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")
    parser.add_argument("--threshold", type=float, required=True, help="Accuracy threshold")
    parser.add_argument("--alias", required=True, help="Model alias (e.g., champion)")
    parser.add_argument("--run-id", required=True, help="MLflow Run ID")

    args = parser.parse_args()

    try:
        result = register_model(
            args.model_name, args.mlflow_uri, args.threshold, args.alias, args.run_id
        )
        if result.registered:
            print(f"Registered {result.model_name} v{result.version} with alias '{result.alias}'")
        else:
            print(f"Model not registered: accuracy {result.accuracy:.4f} < threshold {result.threshold}")
    except (InvalidThresholdError, ModelRegistrationError) as e:
        print(f"Registration error: {e}", file=sys.stderr)
        sys.exit(1)
