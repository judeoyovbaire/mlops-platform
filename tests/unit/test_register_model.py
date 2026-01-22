"""Unit tests for register_model module."""

import pytest

from pipelines.training.src.exceptions import (
    InvalidThresholdError,
)
from pipelines.training.src.register_model import (
    RegistrationResult,
    register_model,
    validate_threshold,
)


class TestValidateThreshold:
    """Tests for threshold validation."""

    def test_valid_threshold_zero(self):
        """Test that threshold of 0 is valid."""
        validate_threshold(0.0)  # Should not raise

    def test_valid_threshold_one(self):
        """Test that threshold of 1 is valid."""
        validate_threshold(1.0)  # Should not raise

    def test_valid_threshold_middle(self):
        """Test that threshold of 0.5 is valid."""
        validate_threshold(0.5)  # Should not raise

    def test_invalid_threshold_negative(self):
        """Test that negative threshold raises error."""
        with pytest.raises(InvalidThresholdError, match="between 0 and 1"):
            validate_threshold(-0.1)

    def test_invalid_threshold_above_one(self):
        """Test that threshold above 1 raises error."""
        with pytest.raises(InvalidThresholdError, match="between 0 and 1"):
            validate_threshold(1.5)


class TestRegisterModel:
    """Tests for register_model function."""

    def test_successful_registration(self, mock_mlflow_client):
        """Test successful model registration when accuracy meets threshold."""
        result = register_model(
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            threshold=0.9,
            alias="champion",
            run_id="test-run-123",
        )

        assert isinstance(result, RegistrationResult)
        assert result.success is True
        assert result.registered is True
        assert result.version == 1
        assert result.alias == "champion"
        assert result.accuracy == 0.95

    def test_not_registered_below_threshold(self, mock_mlflow_client_low_accuracy):
        """Test model not registered when accuracy below threshold."""
        result = register_model(
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            threshold=0.9,
            alias="champion",
            run_id="test-run-123",
        )

        assert result.success is True
        assert result.registered is False
        assert result.version is None
        assert result.accuracy == 0.5

    def test_invalid_threshold_rejected(self, mock_mlflow_client):
        """Test that invalid threshold raises error."""
        with pytest.raises(InvalidThresholdError):
            register_model(
                model_name="test-model",
                mlflow_uri="http://localhost:5000",
                threshold=1.5,
                alias="champion",
                run_id="test-run-123",
            )

    def test_result_dataclass_fields_registered(self, mock_mlflow_client):
        """Test that RegistrationResult contains expected fields when registered."""
        result = register_model(
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            threshold=0.8,
            alias="champion",
            run_id="test-run-123",
        )

        assert hasattr(result, "model_name")
        assert hasattr(result, "run_id")
        assert hasattr(result, "accuracy")
        assert hasattr(result, "threshold")
        assert hasattr(result, "registered")
        assert hasattr(result, "version")
        assert hasattr(result, "alias")
        assert hasattr(result, "success")
        assert hasattr(result, "error_message")

    def test_result_dataclass_fields_not_registered(self, mock_mlflow_client_low_accuracy):
        """Test that RegistrationResult has correct values when not registered."""
        result = register_model(
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            threshold=0.9,
            alias="champion",
            run_id="test-run-123",
        )

        assert result.model_name == "test-model"
        assert result.run_id == "test-run-123"
        assert result.threshold == 0.9
        assert result.registered is False
        assert result.version is None
        assert result.alias is None
