"""Unit tests for validate_model module."""

import joblib
import pytest
from sklearn.ensemble import RandomForestClassifier

from pipelines.training.src.exceptions import ModelTrainingError
from pipelines.training.src.validate_model import ModelValidationResult, validate_model


@pytest.fixture
def trained_iris_model(temp_dir, iris_csv_path):
    """Train a real model and save it for validation tests."""
    import pandas as pd

    df = pd.read_csv(iris_csv_path)
    X = df.drop(columns=["species"])
    y = df["species"]

    model = RandomForestClassifier(n_estimators=10, max_depth=3, random_state=42)
    model.fit(X, y)

    model_path = str(temp_dir / "model.joblib")
    joblib.dump(model, model_path)
    return model_path


@pytest.fixture
def degenerate_model(temp_dir, iris_csv_path):
    """Train on single-class data so the model only ever predicts one class."""
    import pandas as pd

    df = pd.read_csv(iris_csv_path)
    # Keep only 'setosa' rows — model will only learn one class
    df_single = df[df["species"] == "setosa"]
    X = df_single.drop(columns=["species"])
    y = df_single["species"]

    model = RandomForestClassifier(n_estimators=5, random_state=42)
    model.fit(X, y)

    model_path = str(temp_dir / "degenerate_model.joblib")
    joblib.dump(model, model_path)
    return model_path


class TestValidateModel:
    """Tests for validate_model function."""

    def test_passing_validation(self, trained_iris_model, iris_csv_path):
        """Test model that meets all criteria passes."""
        result = validate_model(
            model_path=trained_iris_model,
            data_path=iris_csv_path,
            target="species",
            accuracy_threshold=0.5,
        )

        assert isinstance(result, ModelValidationResult)
        assert result.passed is True
        assert result.accuracy >= 0.5
        assert result.num_classes_predicted >= 2
        assert result.prediction_failures == 0
        assert all(result.checks.values())

    def test_fails_accuracy_threshold(self, trained_iris_model, iris_csv_path):
        """Test model below accuracy threshold fails."""
        result = validate_model(
            model_path=trained_iris_model,
            data_path=iris_csv_path,
            target="species",
            accuracy_threshold=1.0,  # impossibly high
        )

        assert result.passed is False
        assert result.checks["accuracy_threshold"] is False
        assert result.error_message is not None

    def test_fails_class_diversity(self, degenerate_model, iris_csv_path):
        """Test degenerate model fails class diversity check."""
        result = validate_model(
            model_path=degenerate_model,
            data_path=iris_csv_path,
            target="species",
            accuracy_threshold=0.0,
        )

        assert result.checks["class_diversity"] is False

    def test_model_not_found(self, iris_csv_path):
        """Test error when model file doesn't exist."""
        with pytest.raises(ModelTrainingError, match="not found"):
            validate_model(
                model_path="/nonexistent/model.joblib",
                data_path=iris_csv_path,
                target="species",
                accuracy_threshold=0.5,
            )

    def test_data_not_found(self, trained_iris_model):
        """Test error when data file doesn't exist."""
        with pytest.raises(ModelTrainingError, match="not found"):
            validate_model(
                model_path=trained_iris_model,
                data_path="/nonexistent/data.csv",
                target="species",
                accuracy_threshold=0.5,
            )

    def test_missing_target_column(self, trained_iris_model, iris_csv_path):
        """Test error when target column doesn't exist in data."""
        with pytest.raises(ModelTrainingError, match="not found"):
            validate_model(
                model_path=trained_iris_model,
                data_path=iris_csv_path,
                target="nonexistent",
                accuracy_threshold=0.5,
            )

    def test_invalid_threshold(self, trained_iris_model, iris_csv_path):
        """Test error for out-of-range threshold."""
        with pytest.raises(ModelTrainingError, match="between 0 and 1"):
            validate_model(
                model_path=trained_iris_model,
                data_path=iris_csv_path,
                target="species",
                accuracy_threshold=1.5,
            )

    def test_result_dataclass_fields(self, trained_iris_model, iris_csv_path):
        """Test that ModelValidationResult has expected fields."""
        result = validate_model(
            model_path=trained_iris_model,
            data_path=iris_csv_path,
            target="species",
            accuracy_threshold=0.5,
        )

        assert hasattr(result, "passed")
        assert hasattr(result, "accuracy")
        assert hasattr(result, "threshold")
        assert hasattr(result, "num_classes_predicted")
        assert hasattr(result, "prediction_failures")
        assert hasattr(result, "checks")
        assert hasattr(result, "error_message")
