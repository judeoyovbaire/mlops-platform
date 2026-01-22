"""
Train ML model for pipeline.

This module trains a RandomForest classifier, logs metrics and parameters
to MLflow, and saves the trained model.
"""

import argparse
import logging
import os
import sys
from dataclasses import dataclass

import joblib
import mlflow
import pandas as pd
from mlflow.exceptions import MlflowException
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import train_test_split

from pipelines.training.src.exceptions import ModelTrainingError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@dataclass
class TrainingConfig:
    """Configuration for model training."""

    n_estimators: int = 100
    max_depth: int = 10
    test_size: float = 0.2
    random_state: int = 42


@dataclass
class TrainingResult:
    """Result of model training operation."""

    model_path: str
    run_id: str
    accuracy: float
    f1: float
    success: bool = True
    error_message: str | None = None


def train_model(
    input_path: str,
    model_output_path: str,
    target: str,
    model_name: str,
    mlflow_uri: str,
    n_estimators: int,
    max_depth: int,
    test_size: float,
    run_id_output_path: str,
    accuracy_output_path: str,
    random_state: int = 42,
) -> TrainingResult:
    """
    Train a RandomForest classifier and log to MLflow.

    Args:
        input_path: Path to input CSV with features and target.
        model_output_path: Path to save trained model (.joblib).
        target: Name of target column.
        model_name: Name for MLflow experiment.
        mlflow_uri: MLflow tracking server URI.
        n_estimators: Number of trees in the forest.
        max_depth: Maximum depth of trees.
        test_size: Proportion of data for test set.
        run_id_output_path: Path to save MLflow run ID.
        accuracy_output_path: Path to save accuracy metric.
        random_state: Random seed for reproducibility (default: 42).

    Returns:
        TrainingResult containing model path, run ID, and metrics.

    Raises:
        ModelTrainingError: If training fails due to data or MLflow issues.
    """
    logger.info(f"Starting model training with data from {input_path}")

    try:
        # Setup MLflow
        mlflow.set_tracking_uri(mlflow_uri)
        mlflow.set_experiment(model_name)
        logger.info(f"MLflow tracking URI: {mlflow_uri}, Experiment: {model_name}")
    except MlflowException as e:
        raise ModelTrainingError(f"Failed to setup MLflow: {e}") from e

    try:
        # Load data
        df = pd.read_csv(input_path)
        logger.info(f"Loaded {len(df)} rows from {input_path}")
    except FileNotFoundError as e:
        raise ModelTrainingError(f"Input file not found: {input_path}") from e
    except pd.errors.EmptyDataError as e:
        raise ModelTrainingError(f"Input file is empty: {input_path}") from e

    if target not in df.columns:
        raise ModelTrainingError(
            f"Target column '{target}' not found. Available: {list(df.columns)}"
        )

    X = df.drop(columns=[target])
    y = df[target]

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state
    )
    logger.info(f"Train set: {len(X_train)}, Test set: {len(X_test)}")

    try:
        with mlflow.start_run() as run:
            run_id = run.info.run_id
            logger.info(f"Starting MLflow run: {run_id}")

            # Log parameters
            params = {
                "n_estimators": n_estimators,
                "max_depth": max_depth,
                "test_size": test_size,
                "random_state": random_state,
            }
            mlflow.log_params(params)
            logger.info(f"Training parameters: {params}")

            # Train model
            model = RandomForestClassifier(
                n_estimators=n_estimators,
                max_depth=max_depth,
                random_state=random_state,
                n_jobs=-1,
            )
            model.fit(X_train, y_train)
            logger.info("Model training completed")

            # Evaluate
            y_pred = model.predict(X_test)
            accuracy = accuracy_score(y_test, y_pred)
            f1 = f1_score(y_test, y_pred, average="weighted")

            logger.info(f"Metrics - Accuracy: {accuracy:.4f}, F1: {f1:.4f}")
            mlflow.log_metrics({"accuracy": accuracy, "f1_score": f1})

            # Log model to MLflow
            mlflow.sklearn.log_model(model, "model", input_example=X_train.head(1))

            # Save outputs locally
            os.makedirs(os.path.dirname(model_output_path), exist_ok=True)
            joblib.dump(model, model_output_path)
            logger.info(f"Model saved to {model_output_path}")

            # Save run ID and accuracy for next pipeline steps
            with open(run_id_output_path, "w") as f:
                f.write(run_id)
            with open(accuracy_output_path, "w") as f:
                f.write(str(accuracy))

            return TrainingResult(
                model_path=model_output_path,
                run_id=run_id,
                accuracy=accuracy,
                f1=f1,
                success=True,
            )

    except MlflowException as e:
        raise ModelTrainingError(f"MLflow error during training: {e}") from e
    except Exception as e:
        raise ModelTrainingError(f"Training failed: {e}") from e


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train model")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--model-output", required=True, help="Path to save model (.joblib)")
    parser.add_argument("--run-id-output", required=True, help="Path to save run ID")
    parser.add_argument("--accuracy-output", required=True, help="Path to save accuracy")

    parser.add_argument("--target", required=True, help="Target column")
    parser.add_argument("--model-name", required=True, help="Model name for MLflow")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")

    parser.add_argument("--n-estimators", type=int, default=100, help="Number of trees")
    parser.add_argument("--max-depth", type=int, default=10, help="Max depth of trees")
    parser.add_argument("--test-size", type=float, default=0.2, help="Test set size")
    parser.add_argument("--random-state", type=int, default=42, help="Random seed")

    args = parser.parse_args()

    try:
        result = train_model(
            args.input,
            args.model_output,
            args.target,
            args.model_name,
            args.mlflow_uri,
            args.n_estimators,
            args.max_depth,
            args.test_size,
            args.run_id_output,
            args.accuracy_output,
            args.random_state,
        )
        print(f"Training complete. Accuracy: {result.accuracy:.4f}, F1: {result.f1:.4f}")
    except ModelTrainingError as e:
        print(f"Training error: {e}", file=sys.stderr)
        sys.exit(1)
