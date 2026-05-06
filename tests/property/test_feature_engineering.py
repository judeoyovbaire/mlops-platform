"""Property-based tests for feature engineering module.

Uses Hypothesis to verify invariants that must hold for any valid input:
- Row count is preserved after feature engineering
- NaN values are handled without crashing
- Output schema matches expected structure
"""

import tempfile
from pathlib import Path

import pandas as pd
from hypothesis import given, settings
from hypothesis import strategies as st
from hypothesis.extra.pandas import column, data_frames

from pipelines.training.src.feature_engineering import (
    FeatureEngineeringResult,
    feature_engineering,
)

# Strategy: generate DataFrames with numeric columns and a target column
numeric_dfs = data_frames(
    columns=[
        column(
            "feat_a",
            dtype=float,
            elements=st.floats(
                min_value=-1e6, max_value=1e6, allow_nan=False, allow_infinity=False
            ),
        ),
        column(
            "feat_b",
            dtype=float,
            elements=st.floats(
                min_value=-1e6, max_value=1e6, allow_nan=False, allow_infinity=False
            ),
        ),
        column(
            "feat_c",
            dtype=float,
            elements=st.floats(
                min_value=-1e6, max_value=1e6, allow_nan=False, allow_infinity=False
            ),
        ),
        column("target", dtype=int, elements=st.integers(min_value=0, max_value=2)),
    ],
    index=st.just(pd.RangeIndex(10)),
)


@given(df=numeric_dfs)
@settings(max_examples=30, deadline=10000)
def test_row_count_preserved(df):
    """Feature engineering must never change the number of rows."""
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = str(Path(tmpdir) / "input.csv")
        output_path = str(Path(tmpdir) / "output.csv")

        df.to_csv(input_path, index=False)

        result = feature_engineering(input_path, output_path, "target")

        assert result.output_shape[0] == len(df)
        assert result.input_shape[0] == len(df)


@given(df=numeric_dfs)
@settings(max_examples=30, deadline=10000)
def test_target_column_unchanged(df):
    """Target column values must not be modified by feature engineering."""
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = str(Path(tmpdir) / "input.csv")
        output_path = str(Path(tmpdir) / "output.csv")

        df.to_csv(input_path, index=False)
        original_target = df["target"].tolist()

        feature_engineering(input_path, output_path, "target")

        df_out = pd.read_csv(output_path)
        assert df_out["target"].tolist() == original_target


@given(df=numeric_dfs)
@settings(max_examples=30, deadline=10000)
def test_result_is_successful(df):
    """Feature engineering must return success for valid numeric input."""
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = str(Path(tmpdir) / "input.csv")
        output_path = str(Path(tmpdir) / "output.csv")

        df.to_csv(input_path, index=False)

        result = feature_engineering(input_path, output_path, "target")

        assert isinstance(result, FeatureEngineeringResult)
        assert result.success is True
        assert result.error_message is None


@given(df=numeric_dfs)
@settings(max_examples=30, deadline=10000)
def test_output_file_is_valid_csv(df):
    """Output must be a readable CSV with the correct number of rows."""
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = str(Path(tmpdir) / "input.csv")
        output_path = str(Path(tmpdir) / "output.csv")

        df.to_csv(input_path, index=False)
        feature_engineering(input_path, output_path, "target")

        df_out = pd.read_csv(output_path)
        assert len(df_out) == len(df)
        assert "target" in df_out.columns


# Strategy: generate DataFrames with NaN values in some cells
numeric_dfs_with_nans = data_frames(
    columns=[
        column(
            "feat_a",
            dtype=float,
            elements=st.floats(min_value=-1e6, max_value=1e6, allow_infinity=False),
        ),
        column(
            "feat_b",
            dtype=float,
            elements=st.floats(min_value=-1e6, max_value=1e6, allow_infinity=False),
        ),
        column("target", dtype=int, elements=st.integers(min_value=0, max_value=1)),
    ],
    index=st.just(pd.RangeIndex(10)),
)


@given(df=numeric_dfs_with_nans)
@settings(max_examples=20, deadline=10000)
def test_nan_handling_no_crash(df):
    """Feature engineering must not crash on DataFrames containing NaN values."""
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = str(Path(tmpdir) / "input.csv")
        output_path = str(Path(tmpdir) / "output.csv")

        df.to_csv(input_path, index=False)

        # Should not raise an exception
        result = feature_engineering(input_path, output_path, "target")
        assert result.success is True


@given(df=numeric_dfs)
@settings(max_examples=20, deadline=10000)
def test_scaled_columns_have_zero_mean(df):
    """After StandardScaler, numeric columns should have approximately zero mean."""
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = str(Path(tmpdir) / "input.csv")
        output_path = str(Path(tmpdir) / "output.csv")

        df.to_csv(input_path, index=False)
        result = feature_engineering(input_path, output_path, "target")

        if result.scaled_columns:
            df_out = pd.read_csv(output_path)
            scaler_cols = [c for c in df_out.columns if c.startswith("scaler__")]
            for col in scaler_cols:
                col_mean = df_out[col].dropna().mean()
                assert abs(col_mean) < 1e-6, f"Column {col} has non-zero mean: {col_mean}"
