"""Unit tests for train_model module."""

from unittest.mock import MagicMock

import pytest

from pipelines.training.src.exceptions import ModelTrainingError
from pipelines.training.src.train_model import TrainingConfig, TrainingResult, train_model


class TestTrainingConfig:
    """Tests for TrainingConfig dataclass."""

    def test_default_values(self):
        """Test default configuration values."""
        config = TrainingConfig()

        assert config.n_estimators == 100
        assert config.max_depth == 10
        assert config.test_size == 0.2
        assert config.random_state == 42
        assert config.cv_folds == 5
        assert config.use_cross_validation is True

    def test_custom_values(self):
        """Test custom configuration values."""
        config = TrainingConfig(n_estimators=50, max_depth=5, test_size=0.3)

        assert config.n_estimators == 50
        assert config.max_depth == 5
        assert config.test_size == 0.3


class TestTrainModel:
    """Tests for train_model function."""

    def test_successful_training(self, trained_model_artifacts, mocker):
        """Test successful model training with mocked MLflow."""
        artifacts = trained_model_artifacts

        # Mock MLflow
        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        mock_run = MagicMock()
        mock_run.info.run_id = "test-run-123"
        mock_run.__enter__ = MagicMock(return_value=mock_run)
        mock_run.__exit__ = MagicMock(return_value=False)

        mocker.patch("mlflow.start_run", return_value=mock_run)
        mocker.patch("mlflow.log_params")
        mocker.patch("mlflow.log_metrics")
        mocker.patch("mlflow.sklearn.log_model")

        result = train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
        )

        assert isinstance(result, TrainingResult)
        assert result.success is True
        assert result.run_id == "test-run-123"
        assert 0.0 <= result.accuracy <= 1.0
        assert 0.0 <= result.f1 <= 1.0

    def test_file_not_found(self, temp_dir, mocker):
        """Test handling of missing input file."""
        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        with pytest.raises(ModelTrainingError, match="not found"):
            train_model(
                input_path="/nonexistent/file.csv",
                model_output_path=str(temp_dir / "model.joblib"),
                target="species",
                model_name="test",
                mlflow_uri="http://localhost:5000",
                n_estimators=10,
                max_depth=3,
                test_size=0.2,
                run_id_output_path=str(temp_dir / "run_id.txt"),
                accuracy_output_path=str(temp_dir / "accuracy.txt"),
            )

    def test_missing_target_column(self, trained_model_artifacts, mocker):
        """Test error when target column doesn't exist."""
        artifacts = trained_model_artifacts

        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        with pytest.raises(ModelTrainingError, match="not found"):
            train_model(
                input_path=artifacts["data_path"],
                model_output_path=artifacts["model_path"],
                target="nonexistent_column",
                model_name="test",
                mlflow_uri="http://localhost:5000",
                n_estimators=10,
                max_depth=3,
                test_size=0.2,
                run_id_output_path=artifacts["run_id_path"],
                accuracy_output_path=artifacts["accuracy_path"],
            )

    def test_model_saved_to_disk(self, trained_model_artifacts, temp_dir, mocker):
        """Test that model is saved to specified path."""
        artifacts = trained_model_artifacts

        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        mock_run = MagicMock()
        mock_run.info.run_id = "test-run-123"
        mock_run.__enter__ = MagicMock(return_value=mock_run)
        mock_run.__exit__ = MagicMock(return_value=False)

        mocker.patch("mlflow.start_run", return_value=mock_run)
        mocker.patch("mlflow.log_params")
        mocker.patch("mlflow.log_metrics")
        mocker.patch("mlflow.sklearn.log_model")

        result = train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
        )

        import os

        assert os.path.exists(artifacts["model_path"])

    def test_run_id_saved(self, trained_model_artifacts, mocker):
        """Test that run ID is saved to file."""
        artifacts = trained_model_artifacts

        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        mock_run = MagicMock()
        mock_run.info.run_id = "test-run-456"
        mock_run.__enter__ = MagicMock(return_value=mock_run)
        mock_run.__exit__ = MagicMock(return_value=False)

        mocker.patch("mlflow.start_run", return_value=mock_run)
        mocker.patch("mlflow.log_params")
        mocker.patch("mlflow.log_metrics")
        mocker.patch("mlflow.sklearn.log_model")

        train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
        )

        with open(artifacts["run_id_path"]) as f:
            saved_run_id = f.read()
        assert saved_run_id == "test-run-456"

    def test_result_dataclass_fields(self, trained_model_artifacts, mocker):
        """Test that TrainingResult contains expected fields."""
        artifacts = trained_model_artifacts

        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        mock_run = MagicMock()
        mock_run.info.run_id = "test-run-789"
        mock_run.__enter__ = MagicMock(return_value=mock_run)
        mock_run.__exit__ = MagicMock(return_value=False)

        mocker.patch("mlflow.start_run", return_value=mock_run)
        mocker.patch("mlflow.log_params")
        mocker.patch("mlflow.log_metrics")
        mocker.patch("mlflow.sklearn.log_model")

        result = train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
        )

        assert hasattr(result, "model_path")
        assert hasattr(result, "run_id")
        assert hasattr(result, "accuracy")
        assert hasattr(result, "f1")
        assert hasattr(result, "cv_mean")
        assert hasattr(result, "cv_std")
        assert hasattr(result, "success")
        assert hasattr(result, "error_message")
