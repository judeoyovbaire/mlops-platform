"""Unit tests for feature_engineering module."""

import pandas as pd
import pytest

from pipelines.training.src.feature_engineering import (
    feature_engineering,
    FeatureEngineeringResult,
)
from pipelines.training.src.exceptions import (
    FeatureEngineeringError,
    MissingColumnError,
)


class TestFeatureEngineering:
    """Tests for feature_engineering function."""

    def test_successful_feature_engineering(self, iris_csv_path, temp_dir):
        """Test successful feature engineering on iris data."""
        output_path = str(temp_dir / "features.csv")

        result = feature_engineering(iris_csv_path, output_path, "species")

        assert isinstance(result, FeatureEngineeringResult)
        assert result.success is True
        assert result.input_shape == (150, 5)
        assert result.output_shape == (150, 5)
        assert len(result.scaled_columns) == 4  # 4 numeric columns

    def test_numeric_columns_scaled(self, iris_csv_path, temp_dir):
        """Test that numeric columns are scaled to zero mean."""
        output_path = str(temp_dir / "features.csv")

        feature_engineering(iris_csv_path, output_path, "species")

        # Read output and verify scaling
        df = pd.read_csv(output_path)
        numeric_cols = ["sepal_length", "sepal_width", "petal_length", "petal_width"]

        for col in numeric_cols:
            # After StandardScaler, mean should be approximately 0
            assert abs(df[col].mean()) < 1e-10

    def test_target_column_preserved(self, iris_csv_path, temp_dir):
        """Test that target column is not modified."""
        output_path = str(temp_dir / "features.csv")

        # Read original target values
        df_original = pd.read_csv(iris_csv_path)
        original_target = df_original["species"].tolist()

        feature_engineering(iris_csv_path, output_path, "species")

        # Verify target is unchanged
        df_output = pd.read_csv(output_path)
        assert df_output["species"].tolist() == original_target

    def test_missing_target_column(self, iris_csv_path, temp_dir):
        """Test error when target column doesn't exist."""
        output_path = str(temp_dir / "features.csv")

        with pytest.raises(MissingColumnError, match="not found"):
            feature_engineering(iris_csv_path, output_path, "nonexistent_column")

    def test_file_not_found(self, temp_dir):
        """Test handling of missing input file."""
        output_path = str(temp_dir / "features.csv")

        with pytest.raises(FeatureEngineeringError, match="not found"):
            feature_engineering("/nonexistent/file.csv", output_path, "target")

    def test_scaled_columns_tracked(self, numeric_only_csv_path, temp_dir):
        """Test that scaled columns are tracked in result."""
        output_path = str(temp_dir / "features.csv")

        result = feature_engineering(numeric_only_csv_path, output_path, "target")

        assert "a" in result.scaled_columns
        assert "b" in result.scaled_columns
        assert "c" in result.scaled_columns
        assert "target" not in result.scaled_columns

    def test_result_dataclass_fields(self, iris_csv_path, temp_dir):
        """Test that FeatureEngineeringResult contains expected fields."""
        output_path = str(temp_dir / "features.csv")

        result = feature_engineering(iris_csv_path, output_path, "species")

        assert hasattr(result, "output_path")
        assert hasattr(result, "input_shape")
        assert hasattr(result, "output_shape")
        assert hasattr(result, "scaled_columns")
        assert hasattr(result, "success")
        assert hasattr(result, "error_message")

    def test_output_file_created(self, iris_csv_path, temp_dir):
        """Test that output file is created after feature engineering."""
        output_path = temp_dir / "features.csv"

        result = feature_engineering(iris_csv_path, str(output_path), "species")

        assert output_path.exists()
        assert result.output_path == str(output_path)