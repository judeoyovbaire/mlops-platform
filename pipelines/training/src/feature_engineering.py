"""
Feature engineering for ML pipeline.

This module performs feature transformations including scaling
numeric features using StandardScaler and encoding categorical
features using one-hot encoding.
"""

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import joblib
import pandas as pd
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from pipelines.training.src.exceptions import (
    FeatureEngineeringError,
    MissingColumnError,
)
from pipelines.training.src.logging_utils import get_logger

logger = get_logger(__name__)


@dataclass
class FeatureEngineeringResult:
    """Result of feature engineering operation."""

    output_path: str
    scaler_path: str | None
    encoder_path: str | None
    input_shape: tuple[int, int]
    output_shape: tuple[int, int]
    scaled_columns: list[str] = field(default_factory=list)
    encoded_columns: list[str] = field(default_factory=list)
    success: bool = True
    error_message: str | None = None


def feature_engineering(
    input_path: str,
    output_path: str,
    target_column: str,
    encode_categorical: bool = True,
    max_categories: int = 10,
) -> FeatureEngineeringResult:
    """
    Perform feature engineering on input data.

    This function loads CSV data, separates features from target,
    scales numeric features using StandardScaler, encodes categorical
    features using one-hot encoding, and saves the result.

    Args:
        input_path: Path to the input CSV file.
        output_path: Path to save the processed CSV file.
        target_column: Name of the target column to preserve without scaling.
        encode_categorical: Whether to one-hot encode categorical columns (default: True).
        max_categories: Maximum unique values for a column to be encoded (default: 10).
            Columns with more categories are dropped to prevent explosion.

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

    output_file = Path(output_path)
    scaled_columns = []
    encoded_columns = []
    scaler_path = None
    encoder_path = None

    # Identify column types
    numeric_cols = X.select_dtypes(
        include=["float64", "int64", "float32", "int32"]
    ).columns.tolist()
    categorical_cols = X.select_dtypes(include=["object", "category"]).columns.tolist()

    # Scale numeric columns
    if numeric_cols:
        logger.info(f"Scaling numeric columns: {numeric_cols}")
        scaler = StandardScaler()
        X[numeric_cols] = scaler.fit_transform(X[numeric_cols])
        scaled_columns = numeric_cols

        # Save scaler for inference
        scaler_path = str(output_file.parent / f"{output_file.stem}_scaler.joblib")
        os.makedirs(os.path.dirname(scaler_path) or ".", exist_ok=True)
        joblib.dump(scaler, scaler_path)
        logger.info(f"Scaler saved to {scaler_path}")

    # Encode categorical columns
    if encode_categorical and categorical_cols:
        # Filter columns with too many categories
        cols_to_encode = []
        cols_to_drop = []
        for col in categorical_cols:
            n_unique = X[col].nunique()
            if n_unique <= max_categories:
                cols_to_encode.append(col)
            else:
                cols_to_drop.append(col)
                logger.warning(
                    f"Dropping column '{col}' with {n_unique} categories (max: {max_categories})"
                )

        if cols_to_drop:
            X = X.drop(columns=cols_to_drop)

        if cols_to_encode:
            logger.info(f"One-hot encoding categorical columns: {cols_to_encode}")
            encoder = OneHotEncoder(sparse_output=False, handle_unknown="ignore", drop="if_binary")
            encoded_data = encoder.fit_transform(X[cols_to_encode])
            encoded_feature_names = encoder.get_feature_names_out(cols_to_encode).tolist()

            # Create DataFrame with encoded columns
            encoded_df = pd.DataFrame(encoded_data, columns=encoded_feature_names, index=X.index)

            # Drop original categorical columns and add encoded ones
            X = X.drop(columns=cols_to_encode)
            X = pd.concat([X, encoded_df], axis=1)
            encoded_columns = cols_to_encode

            # Save encoder for inference
            encoder_path = str(output_file.parent / f"{output_file.stem}_encoder.joblib")
            joblib.dump(encoder, encoder_path)
            logger.info(f"Encoder saved to {encoder_path}")

    elif categorical_cols and not encode_categorical:
        logger.info(f"Skipping encoding for categorical columns: {categorical_cols}")

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
        encoder_path=encoder_path,
        input_shape=input_shape,
        output_shape=output_shape,
        scaled_columns=scaled_columns,
        encoded_columns=encoded_columns,
        success=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Feature engineering")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--output", required=True, help="Path to save processed CSV")
    parser.add_argument("--target", required=True, help="Target column name")
    parser.add_argument(
        "--no-encode-categorical",
        action="store_true",
        help="Skip one-hot encoding of categorical columns",
    )
    parser.add_argument(
        "--max-categories",
        type=int,
        default=10,
        help="Max unique values for encoding (columns with more are dropped)",
    )

    args = parser.parse_args()

    try:
        result = feature_engineering(
            args.input,
            args.output,
            args.target,
            encode_categorical=not args.no_encode_categorical,
            max_categories=args.max_categories,
        )
        print(f"Feature engineering complete. Output shape: {result.output_shape}")
        if result.scaled_columns:
            print(f"Scaled columns: {result.scaled_columns}")
        if result.encoded_columns:
            print(f"Encoded columns: {result.encoded_columns}")
    except (FeatureEngineeringError, MissingColumnError) as e:
        print(f"Feature engineering error: {e}", file=sys.stderr)
        sys.exit(1)
