"""
Build a serving-ready model that bundles preprocessing with prediction.

The feature-engineering step produces a ColumnTransformer preprocessor artifact
that must be applied to raw inputs before the sklearn model can predict.  In the
current pipeline the preprocessor lives as a separate file, meaning the serving
layer would need to re-implement the same preprocessing logic.

This module solves the problem by wrapping the preprocessor and trained model
into a single MLflow ``pyfunc`` model.  The resulting artifact accepts *raw*
feature DataFrames and returns predictions, making KServe deployment
straightforward.
"""

import argparse
import os
import sys
from dataclasses import dataclass

import joblib
import mlflow
import mlflow.pyfunc
import numpy as np
import pandas as pd

try:
    from pipelines.shared.exceptions import ModelTrainingError
    from pipelines.shared.logging_utils import get_logger
except ImportError:
    from shared.exceptions import ModelTrainingError
    from shared.logging_utils import get_logger

logger = get_logger(__name__)


class PreprocessingModel(mlflow.pyfunc.PythonModel):
    """MLflow pyfunc model that applies preprocessing before prediction.

    Attributes:
        model: The trained sklearn classifier.
        preprocessor: Optional ColumnTransformer for feature preprocessing.
    """

    def __init__(self, model, preprocessor=None):
        self.model = model
        self.preprocessor = preprocessor

    def predict(self, context, model_input: pd.DataFrame, params=None) -> np.ndarray:
        """Apply preprocessing then predict.

        Args:
            context: MLflow context (unused).
            model_input: Raw feature DataFrame.
            params: Optional prediction parameters (unused).

        Returns:
            Numpy array of predictions.
        """
        df = model_input.copy()

        if self.preprocessor is not None:
            self.preprocessor.set_output(transform="pandas")
            df = self.preprocessor.transform(df)

        return self.model.predict(df)


@dataclass
class ServingModelResult:
    """Result of building the serving model."""

    artifact_path: str
    run_id: str
    has_preprocessor: bool
    success: bool = True
    error_message: str | None = None


def build_serving_model(
    model_path: str,
    preprocessor_path: str | None,
    run_id: str,
    mlflow_uri: str,
    sample_input_path: str | None = None,
) -> ServingModelResult:
    """Build and log an MLflow pyfunc serving model.

    Args:
        model_path: Path to the trained sklearn model (.joblib).
        preprocessor_path: Path to the fitted ColumnTransformer (.joblib), or None.
        run_id: MLflow run ID to log the pyfunc model to.
        mlflow_uri: MLflow tracking server URI.
        sample_input_path: Optional path to a CSV for input example.

    Returns:
        ServingModelResult with artifact metadata.

    Raises:
        ModelTrainingError: If any artifact cannot be loaded.
    """
    logger.info("Building serving model with bundled preprocessing")

    # Load artifacts
    try:
        model = joblib.load(model_path)
    except FileNotFoundError as e:
        raise ModelTrainingError(f"Model file not found: {model_path}") from e

    preprocessor = None
    if preprocessor_path and os.path.exists(preprocessor_path):
        preprocessor = joblib.load(preprocessor_path)
        logger.info(f"Loaded preprocessor from {preprocessor_path}")

    pyfunc_model = PreprocessingModel(
        model=model,
        preprocessor=preprocessor,
    )

    # Log to MLflow under the existing run
    mlflow.set_tracking_uri(mlflow_uri)

    input_example = None
    if sample_input_path and os.path.exists(sample_input_path):
        sample_df = pd.read_csv(sample_input_path)
        input_example = sample_df.head(1)

    artifact_path = "serving_model"
    with mlflow.start_run(run_id=run_id):
        mlflow.pyfunc.log_model(
            artifact_path=artifact_path,
            python_model=pyfunc_model,
            input_example=input_example,
        )
    logger.info(f"Logged serving model to run {run_id} at '{artifact_path}'")

    return ServingModelResult(
        artifact_path=artifact_path,
        run_id=run_id,
        has_preprocessor=preprocessor is not None,
        success=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build serving model with preprocessing")
    parser.add_argument("--model", required=True, help="Path to trained model (.joblib)")
    parser.add_argument("--preprocessor", default=None, help="Path to preprocessor (.joblib)")
    parser.add_argument("--run-id", required=True, help="MLflow run ID")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")
    parser.add_argument("--sample-input", default=None, help="Path to sample input CSV")

    args = parser.parse_args()

    try:
        result = build_serving_model(
            model_path=args.model,
            preprocessor_path=args.preprocessor,
            run_id=args.run_id,
            mlflow_uri=args.mlflow_uri,
            sample_input_path=args.sample_input,
        )
        print(f"Serving model logged to run {result.run_id} at '{result.artifact_path}'")
    except ModelTrainingError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
