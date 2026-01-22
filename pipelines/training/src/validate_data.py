"""
Validate and clean data for ML pipeline.

This module performs data validation including null checking,
data cleaning, and ensuring minimum data requirements.
"""

import argparse
import logging
import os
import sys
from dataclasses import dataclass

import pandas as pd

from pipelines.training.src.exceptions import (
    DataValidationError,
    EmptyDataError,
    InsufficientDataError,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

MIN_ROWS_DEFAULT = 10


@dataclass
class ValidationResult:
    """Result of data validation operation."""

    output_path: str
    original_rows: int
    clean_rows: int
    null_count: int
    rows_removed: int
    success: bool
    error_message: str | None = None


def validate_data(
    input_path: str,
    output_path: str,
    min_rows: int = MIN_ROWS_DEFAULT,
) -> ValidationResult:
    """
    Validate and clean data from input CSV file.

    This function loads CSV data, checks for null values, removes rows with nulls,
    and ensures the remaining data meets minimum row requirements.

    Args:
        input_path: Path to the input CSV file.
        output_path: Path to save the validated/cleaned CSV file.
        min_rows: Minimum number of rows required after cleaning.

    Returns:
        ValidationResult containing validation statistics and status.

    Raises:
        DataValidationError: If the input file cannot be read or parsed.
        EmptyDataError: If the input data is empty.
        InsufficientDataError: If cleaned data has fewer rows than min_rows.
    """
    logger.info(f"Starting validation of {input_path}")

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
    logger.info(f"Null values found: {null_count}")

    # Remove nulls
    df_clean = df.dropna()
    rows_removed = original_rows - len(df_clean)
    logger.info(f"Removed {rows_removed} rows with null values")

    clean_rows = len(df_clean)
    if clean_rows < min_rows:
        raise InsufficientDataError(
            f"Only {clean_rows} rows after cleaning, minimum required: {min_rows}"
        )

    # Ensure output directory exists
    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    # Save cleaned data
    df_clean.to_csv(output_path, index=False)
    logger.info(f"Validation complete: {clean_rows} clean rows saved to {output_path}")

    return ValidationResult(
        output_path=output_path,
        original_rows=original_rows,
        clean_rows=clean_rows,
        null_count=null_count,
        rows_removed=rows_removed,
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

    args = parser.parse_args()

    try:
        result = validate_data(args.input, args.output, args.min_rows)
        print(f"Validation complete: {result.clean_rows} clean rows saved to {result.output_path}")
    except (DataValidationError, EmptyDataError, InsufficientDataError) as e:
        print(f"Validation error: {e}", file=sys.stderr)
        sys.exit(1)
