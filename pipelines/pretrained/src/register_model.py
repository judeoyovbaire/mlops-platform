"""
Register a pretrained HuggingFace model in MLflow Model Registry.

This module loads the model metadata produced by fetch_model, creates an
MLflow experiment, logs parameters and the model artifact using
``mlflow.transformers.log_model()``, and assigns a registry alias.
"""

import argparse
import json
import sys
from dataclasses import dataclass

import mlflow
import mlflow.transformers
from mlflow.exceptions import MlflowException
from mlflow.tracking import MlflowClient
from transformers import pipeline as hf_pipeline

try:
    from pipelines.training.src.exceptions import (
        MLflowTimeoutError,
        ModelRegistrationError,
    )
    from pipelines.training.src.logging_utils import get_logger
    from pipelines.training.src.mlflow_utils import MLFLOW_CONNECTION_TIMEOUT, run_with_timeout
except ImportError:
    from exceptions import MLflowTimeoutError, ModelRegistrationError  # type: ignore[no-redef]
    from logging_utils import get_logger  # type: ignore[no-redef]
    from mlflow_utils import MLFLOW_CONNECTION_TIMEOUT, run_with_timeout  # type: ignore[no-redef]

logger = get_logger(__name__)


@dataclass
class PretrainedRegistrationResult:
    """Result of registering a pretrained model."""

    model_name: str
    model_id: str
    task: str
    run_id: str
    version: int | None
    alias: str | None
    registered: bool
    success: bool = True
    error_message: str | None = None


def register_pretrained_model(
    metadata_path: str,
    model_name: str,
    mlflow_uri: str,
    alias: str = "champion",
    mlflow_timeout_seconds: int = MLFLOW_CONNECTION_TIMEOUT,
) -> PretrainedRegistrationResult:
    """Register a pretrained HuggingFace model in MLflow.

    Reads metadata from the fetch step, loads the transformers pipeline,
    logs it to MLflow using ``mlflow.transformers.log_model()``, and
    registers it in the model registry with the specified alias.

    Args:
        metadata_path: Path to metadata.json from fetch_model step.
        model_name: Name for the registered model in MLflow.
        mlflow_uri: MLflow tracking server URI.
        alias: Alias to assign (default: "champion").
        mlflow_timeout_seconds: Timeout for MLflow connection (default: 30).

    Returns:
        PretrainedRegistrationResult with registration details.

    Raises:
        ModelRegistrationError: If registration fails.
    """
    logger.info(f"Starting pretrained model registration: {model_name}")

    # Load metadata from fetch step
    try:
        with open(metadata_path) as f:
            metadata = json.load(f)
    except FileNotFoundError as e:
        raise ModelRegistrationError(f"Metadata file not found: {metadata_path}") from e
    except json.JSONDecodeError as e:
        raise ModelRegistrationError(f"Invalid metadata JSON: {e}") from e

    model_id = metadata["model_id"]
    task = metadata["task"]
    model_dir = metadata["model_dir"]

    logger.info(f"Model: {model_id}, task: {task}, dir: {model_dir}")

    # Connect to MLflow
    try:
        logger.info(f"Connecting to MLflow at {mlflow_uri}")

        def _setup_mlflow() -> MlflowClient:
            mlflow.set_tracking_uri(mlflow_uri)
            mlflow.set_experiment(f"pretrained-{model_name}")
            return MlflowClient()

        client = run_with_timeout(
            _setup_mlflow,
            seconds=mlflow_timeout_seconds,
            error_message=f"MLflow connection timed out after {mlflow_timeout_seconds}s",
        )
        logger.info(f"Connected to MLflow at {mlflow_uri}")
    except MLflowTimeoutError as e:
        raise ModelRegistrationError(str(e)) from e
    except MlflowException as e:
        raise ModelRegistrationError(f"Failed to connect to MLflow: {e}") from e

    # Load the transformers pipeline from saved artifacts
    try:
        pipe = hf_pipeline(task=task, model=model_dir, tokenizer=model_dir)
        logger.info("Loaded transformers pipeline from saved artifacts")
    except Exception as e:
        raise ModelRegistrationError(f"Failed to load transformers pipeline: {e}") from e

    try:
        with mlflow.start_run() as run:
            run_id = run.info.run_id
            logger.info(f"MLflow run: {run_id}")

            # Log model metadata as params
            params = {
                "model_id": model_id,
                "task": task,
                "source": "huggingface_hub",
                "pipeline_tag": metadata.get("pipeline_tag", task),
            }
            if metadata.get("num_parameters"):
                params["num_parameters"] = str(metadata["num_parameters"])
            mlflow.log_params(params)

            # Log test prediction as artifact
            test_data = {
                "input": metadata.get("test_input", ""),
                "output": metadata.get("test_output", ""),
            }
            mlflow.log_dict(test_data, "test_prediction.json")

            # Log the transformers pipeline to MLflow
            logger.info("Logging transformers model to MLflow...")
            mlflow.transformers.log_model(
                transformers_model=pipe,
                artifact_path="model",
                task=task,
            )
            logger.info("Model logged to MLflow")

    except MlflowException as e:
        raise ModelRegistrationError(f"MLflow logging failed: {e}") from e

    # Register in model registry
    try:
        model_uri = f"runs:/{run_id}/model"
        mv = mlflow.register_model(model_uri, model_name)
        logger.info(f"Registered {model_name} version {mv.version}")

        client.set_registered_model_alias(model_name, alias, mv.version)
        logger.info(f"Set alias '{alias}' -> version {mv.version}")

        return PretrainedRegistrationResult(
            model_name=model_name,
            model_id=model_id,
            task=task,
            run_id=run_id,
            version=int(mv.version),
            alias=alias,
            registered=True,
            success=True,
        )
    except MlflowException as e:
        raise ModelRegistrationError(f"Failed to register model: {e}") from e


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Register pretrained HF model in MLflow")
    parser.add_argument(
        "--metadata",
        required=True,
        help="Path to metadata.json from fetch step",
    )
    parser.add_argument("--model-name", required=True, help="Model name for MLflow registry")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")
    parser.add_argument("--alias", default="champion", help="Model alias (default: champion)")
    parser.add_argument(
        "--mlflow-timeout",
        type=int,
        default=MLFLOW_CONNECTION_TIMEOUT,
        help="MLflow connection timeout in seconds",
    )

    args = parser.parse_args()

    try:
        result = register_pretrained_model(
            metadata_path=args.metadata,
            model_name=args.model_name,
            mlflow_uri=args.mlflow_uri,
            alias=args.alias,
            mlflow_timeout_seconds=args.mlflow_timeout,
        )
        print(
            f"Registered '{result.model_name}' v{result.version} "
            f"(alias='{result.alias}', source={result.model_id})"
        )
    except ModelRegistrationError as e:
        print(f"Registration error: {e}", file=sys.stderr)
        sys.exit(1)
