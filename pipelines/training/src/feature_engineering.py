"""
Feature engineering for ML pipeline.

This module performs feature transformations including scaling
numeric features using StandardScaler.
"""

import argparse
import logging
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import joblib
import pandas as pd
from sklearn.preprocessing import StandardScaler

from pipelines.training.src.exceptions import (
    FeatureEngineeringError,
    MissingColumnError,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@dataclass
class FeatureEngineeringResult:
    """Result of feature engineering operation."""

    output_path: str
    scaler_path: str | None
    input_shape: tuple[int, int]
    output_shape: tuple[int, int]
    scaled_columns: list[str] = field(default_factory=list)
    success: bool = True
    error_message: str | None = None


def feature_engineering(
    input_path: str,
    output_path: str,
    target_column: str,
) -> FeatureEngineeringResult:
    """
    Perform feature engineering on input data.

    This function loads CSV data, separates features from target,
    scales numeric features using StandardScaler, and saves the result.

    Args:
        input_path: Path to the input CSV file.
        output_path: Path to save the processed CSV file.
        target_column: Name of the target column to preserve without scaling.

    Returns:
        FeatureEngineeringResult containing processing statistics and status.

    Raises:
        FeatureEngineeringError: If the input file cannot be read.
        MissingColumnError: If the target column is not in the data.
    """
    logger.info(f"Starting feature engineering on {input_path}")

    try:
        df = pd.read_csv(input_path)
    except FileNotFoundError as e:
        raise FeatureEngineeringError(f"Input file not found: {input_path}") from e
    except pd.errors.EmptyDataError as e:
        raise FeatureEngineeringError(f"Input file is empty: {input_path}") from e
    except pd.errors.ParserError as e:
        raise FeatureEngineeringError(f"Failed to parse CSV: {e}") from e

    input_shape = df.shape
    logger.info(f"Loaded data with shape {input_shape}")

    if target_column not in df.columns:
        raise MissingColumnError(
            f"Target column '{target_column}' not found. Available columns: {list(df.columns)}"
        )

    # Separate features and target
    X = df.drop(columns=[target_column])
    y = df[target_column]

    # Scale numeric columns
    numeric_cols = X.select_dtypes(include=["float64", "int64"]).columns.tolist()
    scaled_columns = []
    scaler_path = None

    if numeric_cols:
        logger.info(f"Scaling numeric columns: {numeric_cols}")
        scaler = StandardScaler()
        X[numeric_cols] = scaler.fit_transform(X[numeric_cols])
        scaled_columns = numeric_cols

        # Save scaler for inference using pathlib for robust path construction
        output_file = Path(output_path)
        scaler_path = str(output_file.parent / f"{output_file.stem}_scaler.joblib")
        os.makedirs(os.path.dirname(scaler_path) or ".", exist_ok=True)
        joblib.dump(scaler, scaler_path)
        logger.info(f"Scaler saved to {scaler_path}")

    # Combine features and target
    df_out = X.copy()
    df_out[target_column] = y.values

    output_shape = df_out.shape

    # Ensure output directory exists
    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    # Save processed data
    df_out.to_csv(output_path, index=False)
    logger.info(f"Feature engineering complete. Output shape: {output_shape}")

    return FeatureEngineeringResult(
        output_path=output_path,
        scaler_path=scaler_path,
        input_shape=input_shape,
        output_shape=output_shape,
        scaled_columns=scaled_columns,
        success=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Feature engineering")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--output", required=True, help="Path to save processed CSV")
    parser.add_argument("--target", required=True, help="Target column name")

    args = parser.parse_args()

    try:
        result = feature_engineering(args.input, args.output, args.target)
        print(f"Feature engineering complete. Output shape: {result.output_shape}")
    except (FeatureEngineeringError, MissingColumnError) as e:
        print(f"Feature engineering error: {e}", file=sys.stderr)
        sys.exit(1)
