import argparse
import os
import sys

import pandas as pd


def validate_data(input_path, output_path):
    try:
        print(f"Loading data from {input_path}")
        df = pd.read_csv(input_path)
        print(f"Loaded {len(df)} rows, {len(df.columns)} columns")

        # Check for nulls
        null_count = df.isnull().sum().sum()
        print(f"Null values: {null_count}")

        # Remove nulls
        df_clean = df.dropna()
        rows_removed = len(df) - len(df_clean)
        print(f"Removed {rows_removed} rows with nulls")

        if len(df_clean) < 10:
            print("Error: Less than 10 rows after cleaning", file=sys.stderr)
            sys.exit(1)

        # Ensure directory exists
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        df_clean.to_csv(output_path, index=False)
        print(f"Validation complete: {len(df_clean)} clean rows saved to {output_path}")

    except Exception as e:
        print(f"Validation error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate data")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--output", required=True, help="Path to save validated CSV")

    args = parser.parse_args()
    validate_data(args.input, args.output)
