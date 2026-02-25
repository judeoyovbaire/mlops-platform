"""
Feature engineering for ML pipeline.

This module performs feature transformations using a sklearn ColumnTransformer
that bundles scaling of numeric features (StandardScaler) and encoding of
categorical features (OneHotEncoder) into a single preprocessor artifact.
"""

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler

try:
    from pipelines.shared.exceptions import (
        FeatureEngineeringError,
        MissingColumnError,
    )
    from pipelines.shared.logging_utils import get_logger
    from pipelines.training.src.tracing import get_tracer
except ImportError:
    from shared.exceptions import (
        FeatureEngineeringError,
        MissingColumnError,
    )
    from shared.logging_utils import get_logger
    from tracing import get_tracer

logger = get_logger(__name__)
tracer = get_tracer("feature-engineering")


@dataclass
class FeatureEngineeringResult:
    """Result of feature engineering operation."""

    output_path: str
    preprocessor_path: str | None
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
    builds a sklearn ColumnTransformer that scales numeric features
    and one-hot encodes categorical features, and saves the result.

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

    with tracer.start_as_current_span("feature_engineering") as span:
        span.set_attribute("input_path", input_path)

        try:
            df = pd.read_csv(input_path)
        except FileNotFoundError as e:
            raise FeatureEngineeringError(f"Input file not found: {input_path}") from e
        except pd.errors.EmptyDataError as e:
            raise FeatureEngineeringError(f"Input file is empty: {input_path}") from e
        except pd.errors.ParserError as e:
            raise FeatureEngineeringError(f"Failed to parse CSV: {e}") from e

        input_shape = df.shape
        span.set_attribute("input_shape", str(input_shape))
        logger.info(f"Loaded data with shape {input_shape}")

        if target_column not in df.columns:
            raise MissingColumnError(
                f"Target column '{target_column}' not found. Available columns: {list(df.columns)}"
            )

        # Separate features and target
        X = df.drop(columns=[target_column])
        y = df[target_column]

        output_file = Path(output_path)
        scaled_columns: list[str] = []
        encoded_columns: list[str] = []
        preprocessor_path: str | None = None

        # Identify column types
        numeric_cols = X.select_dtypes(
            include=["float64", "int64", "float32", "int32"]
        ).columns.tolist()
        categorical_cols = X.select_dtypes(include=["object", "category"]).columns.tolist()

        # Filter high-cardinality categorical columns before building transformer
        cols_to_encode: list[str] = []
        cols_to_drop: list[str] = []
        if encode_categorical and categorical_cols:
            for col in categorical_cols:
                n_unique = X[col].nunique()
                if n_unique <= max_categories:
                    cols_to_encode.append(col)
                else:
                    cols_to_drop.append(col)
                    logger.warning(
                        f"Dropping column '{col}' with {n_unique} categories "
                        f"(max: {max_categories})"
                    )

            if cols_to_drop:
                X = X.drop(columns=cols_to_drop)

        elif categorical_cols and not encode_categorical:
            logger.info(f"Skipping encoding for categorical columns: {categorical_cols}")

        # Build ColumnTransformer with identified transformers
        transformers = []
        if numeric_cols:
            transformers.append(("scaler", StandardScaler(), numeric_cols))
            scaled_columns = numeric_cols
            logger.info(f"Scaling numeric columns: {numeric_cols}")

        if cols_to_encode:
            transformers.append(
                (
                    "encoder",
                    OneHotEncoder(sparse_output=False, handle_unknown="ignore", drop="if_binary"),
                    cols_to_encode,
                )
            )
            encoded_columns = cols_to_encode
            logger.info(f"One-hot encoding categorical columns: {cols_to_encode}")

        if transformers:
            preprocessor = ColumnTransformer(transformers=transformers, remainder="drop")
            preprocessor.set_output(transform="pandas")
            X_transformed = preprocessor.fit_transform(X)

            # Save preprocessor for inference
            preprocessor_path = str(output_file.parent / f"{output_file.stem}_preprocessor.joblib")
            os.makedirs(os.path.dirname(preprocessor_path) or ".", exist_ok=True)
            joblib.dump(preprocessor, preprocessor_path)
            logger.info(f"Preprocessor saved to {preprocessor_path}")
        else:
            X_transformed = X

        # Combine features and target
        df_out = X_transformed.copy()
        df_out[target_column] = y.values

        output_shape = df_out.shape
        span.set_attribute("output_shape", str(output_shape))
        span.set_attribute("num_scaled_columns", len(scaled_columns))
        span.set_attribute("num_encoded_columns", len(encoded_columns))

        # Ensure output directory exists
        output_dir = os.path.dirname(output_path)
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)

        # Save processed data
        df_out.to_csv(output_path, index=False)
        logger.info(f"Feature engineering complete. Output shape: {output_shape}")

        return FeatureEngineeringResult(
            output_path=output_path,
            preprocessor_path=preprocessor_path,
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
