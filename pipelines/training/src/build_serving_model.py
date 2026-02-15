"""
Build a serving-ready model that bundles preprocessing with prediction.

The feature-engineering step produces scaler/encoder artifacts that must be
applied to raw inputs before the sklearn model can predict.  In the current
pipeline these artifacts live as separate files, meaning the serving layer
would need to re-implement the same preprocessing logic.

This module solves the problem by wrapping the scaler, encoder, and trained
model into a single MLflow ``pyfunc`` model.  The resulting artifact accepts
*raw* feature DataFrames and returns predictions, making KServe deployment
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
    from pipelines.training.src.exceptions import ModelTrainingError
    from pipelines.training.src.logging_utils import get_logger
except ImportError:
    from exceptions import ModelTrainingError
    from logging_utils import get_logger

logger = get_logger(__name__)


class PreprocessingModel(mlflow.pyfunc.PythonModel):
    """MLflow pyfunc model that applies preprocessing before prediction.

    Attributes:
        model: The trained sklearn classifier.
        scaler: Optional StandardScaler for numeric features.
        encoder: Optional OneHotEncoder for categorical features.
        numeric_cols: Column names that should be scaled.
        categorical_cols: Column names that should be encoded.
    """

    def __init__(
        self,
        model,
        scaler=None,
        encoder=None,
        numeric_cols: list[str] | None = None,
        categorical_cols: list[str] | None = None,
    ):
        self.model = model
        self.scaler = scaler
        self.encoder = encoder
        self.numeric_cols = numeric_cols or []
        self.categorical_cols = categorical_cols or []

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

        # Apply scaling to numeric columns
        if self.scaler is not None and self.numeric_cols:
            cols_present = [c for c in self.numeric_cols if c in df.columns]
            if cols_present:
                df[cols_present] = self.scaler.transform(df[cols_present])

        # Apply encoding to categorical columns
        if self.encoder is not None and self.categorical_cols:
            cols_present = [c for c in self.categorical_cols if c in df.columns]
            if cols_present:
                encoded = self.encoder.transform(df[cols_present])
                encoded_names = self.encoder.get_feature_names_out(cols_present).tolist()
                encoded_df = pd.DataFrame(encoded, columns=encoded_names, index=df.index)
                df = df.drop(columns=cols_present)
                df = pd.concat([df, encoded_df], axis=1)

        return self.model.predict(df)


@dataclass
class ServingModelResult:
    """Result of building the serving model."""

    artifact_path: str
    run_id: str
    has_scaler: bool
    has_encoder: bool
    success: bool = True
    error_message: str | None = None


def build_serving_model(
    model_path: str,
    scaler_path: str | None,
    encoder_path: str | None,
    run_id: str,
    mlflow_uri: str,
    numeric_cols: list[str] | None = None,
    categorical_cols: list[str] | None = None,
    sample_input_path: str | None = None,
) -> ServingModelResult:
    """Build and log an MLflow pyfunc serving model.

    Args:
        model_path: Path to the trained sklearn model (.joblib).
        scaler_path: Path to the fitted StandardScaler (.joblib), or None.
        encoder_path: Path to the fitted OneHotEncoder (.joblib), or None.
        run_id: MLflow run ID to log the pyfunc model to.
        mlflow_uri: MLflow tracking server URI.
        numeric_cols: Names of numeric columns the scaler was fitted on.
        categorical_cols: Names of categorical columns the encoder was fitted on.
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

    scaler = None
    if scaler_path and os.path.exists(scaler_path):
        scaler = joblib.load(scaler_path)
        logger.info(f"Loaded scaler from {scaler_path}")

    encoder = None
    if encoder_path and os.path.exists(encoder_path):
        encoder = joblib.load(encoder_path)
        logger.info(f"Loaded encoder from {encoder_path}")

    pyfunc_model = PreprocessingModel(
        model=model,
        scaler=scaler,
        encoder=encoder,
        numeric_cols=numeric_cols or [],
        categorical_cols=categorical_cols or [],
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
        has_scaler=scaler is not None,
        has_encoder=encoder is not None,
        success=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build serving model with preprocessing")
    parser.add_argument("--model", required=True, help="Path to trained model (.joblib)")
    parser.add_argument("--scaler", default=None, help="Path to scaler (.joblib)")
    parser.add_argument("--encoder", default=None, help="Path to encoder (.joblib)")
    parser.add_argument("--run-id", required=True, help="MLflow run ID")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")
    parser.add_argument("--numeric-cols", nargs="*", default=[], help="Numeric column names")
    parser.add_argument("--categorical-cols", nargs="*", default=[], help="Categorical column names")
    parser.add_argument("--sample-input", default=None, help="Path to sample input CSV")

    args = parser.parse_args()

    try:
        result = build_serving_model(
            model_path=args.model,
            scaler_path=args.scaler,
            encoder_path=args.encoder,
            run_id=args.run_id,
            mlflow_uri=args.mlflow_uri,
            numeric_cols=args.numeric_cols,
            categorical_cols=args.categorical_cols,
            sample_input_path=args.sample_input,
        )
        print(f"Serving model logged to run {result.run_id} at '{result.artifact_path}'")
    except ModelTrainingError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
