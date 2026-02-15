"""Unit tests for Pandera data schema."""

import pandas as pd
import pandera
import pytest

from pipelines.training.src.schema import IrisSchema


class TestIrisSchema:
    """Tests for IrisSchema validation."""

    def test_valid_iris_data(self, iris_dataframe):
        """Test that standard iris data passes schema validation."""
        validated = IrisSchema.validate(iris_dataframe)
        assert len(validated) == len(iris_dataframe)

    def test_allows_nulls(self):
        """Test that nullable columns accept null values."""
        df = pd.DataFrame(
            {
                "sepal_length": [5.1, None],
                "sepal_width": [3.5, 3.0],
                "petal_length": [1.4, 1.4],
                "petal_width": [0.2, None],
                "species": ["setosa", "versicolor"],
            }
        )
        validated = IrisSchema.validate(df)
        assert len(validated) == 2

    def test_rejects_negative_values(self):
        """Test that negative measurements are rejected."""
        df = pd.DataFrame(
            {
                "sepal_length": [-1.0],
                "sepal_width": [3.5],
                "petal_length": [1.4],
                "petal_width": [0.2],
                "species": ["setosa"],
            }
        )
        with pytest.raises(pandera.errors.SchemaError):
            IrisSchema.validate(df)

    def test_rejects_invalid_species(self):
        """Test that unknown species are rejected."""
        df = pd.DataFrame(
            {
                "sepal_length": [5.1],
                "sepal_width": [3.5],
                "petal_length": [1.4],
                "petal_width": [0.2],
                "species": ["unknown_species"],
            }
        )
        with pytest.raises(pandera.errors.SchemaError):
            IrisSchema.validate(df)

    def test_allows_extra_columns(self):
        """Test that extra columns don't cause failures (strict=False)."""
        df = pd.DataFrame(
            {
                "sepal_length": [5.1],
                "sepal_width": [3.5],
                "petal_length": [1.4],
                "petal_width": [0.2],
                "species": ["setosa"],
                "extra_feature": [42.0],
            }
        )
        validated = IrisSchema.validate(df)
        assert "extra_feature" in validated.columns

    def test_rejects_unreasonably_large_values(self):
        """Test that extremely large measurements are rejected."""
        df = pd.DataFrame(
            {
                "sepal_length": [100.0],
                "sepal_width": [3.5],
                "petal_length": [1.4],
                "petal_width": [0.2],
                "species": ["setosa"],
            }
        )
        with pytest.raises(pandera.errors.SchemaError):
            IrisSchema.validate(df)

    def test_coerces_types(self):
        """Test that string numbers are coerced to float."""
        df = pd.DataFrame(
            {
                "sepal_length": [5],  # int, should coerce to float
                "sepal_width": [3],
                "petal_length": [1],
                "petal_width": [0],
                "species": ["setosa"],
            }
        )
        validated = IrisSchema.validate(df)
        assert validated["sepal_length"].dtype == float
