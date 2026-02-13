"""
Validate and clean data for ML pipeline.

This module performs data validation including null checking,
data cleaning, and ensuring minimum data requirements.
"""

import argparse
import os
import sys
from dataclasses import dataclass

import pandas as pd

try:
    from pipelines.training.src.exceptions import (
        DataValidationError,
        EmptyDataError,
        InsufficientDataError,
    )
    from pipelines.training.src.logging_utils import get_logger
except ImportError:
    from exceptions import (
        DataValidationError,
        EmptyDataError,
        InsufficientDataError,
    )
    from logging_utils import get_logger

logger = get_logger(__name__)

MIN_ROWS_DEFAULT = 10
# Default threshold: drop column if more than 50% of values are null
NULL_THRESHOLD_DEFAULT = 0.5


@dataclass
class ValidationResult:
    """Result of data validation operation."""

    output_path: str
    original_rows: int
    clean_rows: int
    null_count: int
    rows_removed: int
    columns_dropped: list[str]
    imputed_columns: list[str]
    success: bool
    error_message: str | None = None


def validate_data(
    input_path: str,
    output_path: str,
    min_rows: int = MIN_ROWS_DEFAULT,
    null_threshold: float = NULL_THRESHOLD_DEFAULT,
    drop_all_null_rows: bool = False,
) -> ValidationResult:
    """
    Validate and clean data from input CSV file.

    This function loads CSV data, handles null values intelligently using
    column-specific thresholds, and ensures the remaining data meets minimum
    row requirements.

    Null handling strategy:
    1. Drop columns where null percentage exceeds null_threshold
    2. For remaining columns with nulls:
       - Numeric columns: impute with median
       - Categorical columns: impute with mode
    3. Optionally drop rows that still have nulls (if drop_all_null_rows=True)

    Args:
        input_path: Path to the input CSV file.
        output_path: Path to save the validated/cleaned CSV file.
        min_rows: Minimum number of rows required after cleaning.
        null_threshold: Maximum null percentage per column (0.0-1.0).
            Columns exceeding this are dropped. Default: 0.5 (50%).
        drop_all_null_rows: If True, drop rows with any remaining nulls
            after imputation. Default: False.

    Returns:
        ValidationResult containing validation statistics and status.

    Raises:
        DataValidationError: If the input file cannot be read or parsed.
        EmptyDataError: If the input data is empty.
        InsufficientDataError: If cleaned data has fewer rows than min_rows.
    """
    logger.info(f"Starting validation of {input_path}")

    # Input validation
    if not 0.0 <= null_threshold <= 1.0:
        raise DataValidationError(
            f"null_threshold must be between 0.0 and 1.0, got: {null_threshold}"
        )
    if min_rows < 1:
        raise DataValidationError(f"min_rows must be >= 1, got: {min_rows}")

    try:
        df = pd.read_csv(input_path)
    except FileNotFoundError as e:
        raise DataValidationError(f"Input file not found: {input_path}") from e
    except pd.errors.EmptyDataError as e:
        raise EmptyDataError(f"Input file is empty: {input_path}") from e
    except pd.errors.ParserError as e:
        raise DataValidationError(f"Failed to parse CSV: {e}") from e

    original_rows = len(df)
    num_columns = len(df.columns)
    logger.info(f"Loaded {original_rows} rows, {num_columns} columns")

    if original_rows == 0:
        raise EmptyDataError("Input data contains no rows")

    # Check for nulls
    null_count = int(df.isnull().sum().sum())
    logger.info(f"Total null values found: {null_count}")

    # Calculate null percentage per column
    null_percentages = df.isnull().sum() / len(df)
    columns_to_drop = null_percentages[null_percentages > null_threshold].index.tolist()

    if columns_to_drop:
        logger.info(
            f"Dropping {len(columns_to_drop)} columns with >{null_threshold * 100:.0f}% nulls: "
            f"{columns_to_drop}"
        )
        df = df.drop(columns=columns_to_drop)

    # Impute remaining nulls column by column
    imputed_columns = []
    for col in df.columns:
        if df[col].isnull().any():
            null_pct = df[col].isnull().sum() / len(df) * 100
            if pd.api.types.is_numeric_dtype(df[col]):
                # Numeric: impute with median
                median_val = df[col].median()
                df[col] = df[col].fillna(median_val)
                logger.info(f"Imputed {col} ({null_pct:.1f}% nulls) with median: {median_val}")
                imputed_columns.append(col)
            else:
                # Categorical: impute with mode
                mode_val = df[col].mode()
                if len(mode_val) > 0:
                    df[col] = df[col].fillna(mode_val.iloc[0])
                    logger.info(
                        f"Imputed {col} ({null_pct:.1f}% nulls) with mode: {mode_val.iloc[0]}"
                    )
                    imputed_columns.append(col)

    # Optionally drop any remaining rows with nulls
    rows_removed = 0
    if drop_all_null_rows and df.isnull().any().any():
        rows_before = len(df)
        df = df.dropna()
        rows_removed = rows_before - len(df)
        logger.info(f"Dropped {rows_removed} rows with remaining null values")

    clean_rows = len(df)
    if clean_rows < min_rows:
        raise InsufficientDataError(
            f"Only {clean_rows} rows after cleaning, minimum required: {min_rows}"
        )

    # Ensure output directory exists
    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    # Save cleaned data
    df.to_csv(output_path, index=False)
    logger.info(f"Validation complete: {clean_rows} clean rows saved to {output_path}")

    return ValidationResult(
        output_path=output_path,
        original_rows=original_rows,
        clean_rows=clean_rows,
        null_count=null_count,
        rows_removed=rows_removed,
        columns_dropped=columns_to_drop,
        imputed_columns=imputed_columns,
        success=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate data")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--output", required=True, help="Path to save validated CSV")
    parser.add_argument(
        "--min-rows",
        type=int,
        default=MIN_ROWS_DEFAULT,
        help=f"Minimum rows required after cleaning (default: {MIN_ROWS_DEFAULT})",
    )
    parser.add_argument(
        "--null-threshold",
        type=float,
        default=NULL_THRESHOLD_DEFAULT,
        help=f"Max null percentage per column before dropping (default: {NULL_THRESHOLD_DEFAULT})",
    )
    parser.add_argument(
        "--drop-null-rows",
        action="store_true",
        help="Drop rows with any remaining nulls after imputation",
    )

    args = parser.parse_args()

    try:
        result = validate_data(
            args.input,
            args.output,
            args.min_rows,
            args.null_threshold,
            args.drop_null_rows,
        )
        print(f"Validation complete: {result.clean_rows} clean rows saved to {result.output_path}")
        if result.columns_dropped:
            print(f"Columns dropped: {result.columns_dropped}")
        if result.imputed_columns:
            print(f"Columns imputed: {result.imputed_columns}")
    except (DataValidationError, EmptyDataError, InsufficientDataError) as e:
        print(f"Validation error: {e}", file=sys.stderr)
        sys.exit(1)
