"""Unit tests for validate_data module."""

import pytest

from pipelines.training.src.validate_data import validate_data, ValidationResult
from pipelines.training.src.exceptions import (
    DataValidationError,
    EmptyDataError,
    InsufficientDataError,
)


class TestValidateData:
    """Tests for validate_data function."""

    def test_successful_validation(self, iris_csv_path, temp_dir):
        """Test successful validation of clean data."""
        output_path = str(temp_dir / "validated.csv")

        result = validate_data(iris_csv_path, output_path)

        assert isinstance(result, ValidationResult)
        assert result.success is True
        assert result.original_rows == 150
        assert result.clean_rows == 150
        assert result.null_count == 0
        assert result.rows_removed == 0

    def test_validation_with_nulls(self, csv_with_nulls_path, temp_dir):
        """Test validation removes rows with null values."""
        output_path = str(temp_dir / "validated.csv")

        result = validate_data(csv_with_nulls_path, output_path, min_rows=5)

        assert result.success is True
        assert result.original_rows == 15
        assert result.clean_rows == 11  # 4 rows have nulls
        assert result.rows_removed == 4
        assert result.null_count > 0

    def test_file_not_found(self, temp_dir):
        """Test handling of missing input file."""
        output_path = str(temp_dir / "validated.csv")

        with pytest.raises(DataValidationError, match="not found"):
            validate_data("/nonexistent/file.csv", output_path)

    def test_empty_file(self, empty_csv_path, temp_dir):
        """Test handling of empty CSV file (headers only)."""
        output_path = str(temp_dir / "validated.csv")

        with pytest.raises(EmptyDataError, match="no rows"):
            validate_data(empty_csv_path, output_path)

    def test_insufficient_data_after_cleaning(self, all_null_csv_path, temp_dir):
        """Test error when cleaned data has insufficient rows."""
        output_path = str(temp_dir / "validated.csv")

        with pytest.raises(InsufficientDataError, match="minimum required"):
            validate_data(all_null_csv_path, output_path, min_rows=10)

    def test_custom_min_rows(self, csv_with_nulls_path, temp_dir):
        """Test validation with custom minimum rows threshold."""
        output_path = str(temp_dir / "validated.csv")

        # Should succeed with low threshold
        result = validate_data(csv_with_nulls_path, output_path, min_rows=5)
        assert result.success is True

        # Should fail with high threshold
        with pytest.raises(InsufficientDataError):
            validate_data(csv_with_nulls_path, output_path, min_rows=50)

    def test_result_dataclass_fields(self, iris_csv_path, temp_dir):
        """Test that ValidationResult contains expected fields."""
        output_path = str(temp_dir / "validated.csv")

        result = validate_data(iris_csv_path, output_path)

        assert hasattr(result, "output_path")
        assert hasattr(result, "original_rows")
        assert hasattr(result, "clean_rows")
        assert hasattr(result, "null_count")
        assert hasattr(result, "rows_removed")
        assert hasattr(result, "success")
        assert hasattr(result, "error_message")

    def test_output_file_created(self, iris_csv_path, temp_dir):
        """Test that output file is created after validation."""
        output_path = temp_dir / "validated.csv"

        result = validate_data(iris_csv_path, str(output_path))

        assert output_path.exists()
        assert result.output_path == str(output_path)