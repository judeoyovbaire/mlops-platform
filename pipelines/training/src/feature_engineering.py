import argparse
import os
import sys

import pandas as pd
from sklearn.preprocessing import StandardScaler


def feature_engineering(input_path, output_path, target_column):
    try:
        print(f"Loading data from {input_path}")
        df = pd.read_csv(input_path)

        if target_column not in df.columns:
            print(f"Error: Target column {target_column} not found", file=sys.stderr)
            print(f"Available columns: {list(df.columns)}", file=sys.stderr)
            sys.exit(1)

        X = df.drop(columns=[target_column])
        y = df[target_column]

        # Scale numeric columns
        numeric_cols = X.select_dtypes(include=["float64", "int64"]).columns
        if len(numeric_cols) > 0:
            print(f"Scaling numeric columns: {list(numeric_cols)}")
            scaler = StandardScaler()
            X[numeric_cols] = scaler.fit_transform(X[numeric_cols])

        df_out = X.copy()
        df_out[target_column] = y.values

        # Ensure directory exists
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        df_out.to_csv(output_path, index=False)
        print(f"Feature engineering complete. Output shape: {df_out.shape}")

    except Exception as e:
        print(f"Feature engineering error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Feature engineering")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--output", required=True, help="Path to save processed CSV")
    parser.add_argument("--target", required=True, help="Target column name")

    args = parser.parse_args()
    feature_engineering(args.input, args.output, args.target)
