"""Integration tests for ML pipeline flow.

These tests verify that pipeline components work together correctly.
"""

import os
from unittest.mock import MagicMock

import pytest

from pipelines.training.src.feature_engineering import feature_engineering
from pipelines.training.src.validate_data import validate_data


class TestPipelineFlow:
    """Integration tests for complete pipeline flow."""

    @pytest.mark.integration
    def test_validate_then_feature_engineering(self, iris_csv_path, temp_dir):
        """Test that validate_data output works with feature_engineering."""
        validated_path = str(temp_dir / "validated.csv")
        features_path = str(temp_dir / "features.csv")

        # Step 1: Validate data
        validation_result = validate_data(iris_csv_path, validated_path)
        assert validation_result.success is True
        assert os.path.exists(validated_path)

        # Step 2: Feature engineering on validated data
        fe_result = feature_engineering(validated_path, features_path, "species")
        assert fe_result.success is True
        assert fe_result.input_shape[0] == validation_result.clean_rows

    @pytest.mark.integration
    def test_full_pipeline_data_flow(self, iris_csv_path, temp_dir, mocker):
        """Test complete data pipeline from validation to training."""
        validated_path = str(temp_dir / "validated.csv")
        features_path = str(temp_dir / "features.csv")
        model_path = str(temp_dir / "model.joblib")
        run_id_path = str(temp_dir / "run_id.txt")
        accuracy_path = str(temp_dir / "accuracy.txt")

        # Mock MLflow for training
        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        mock_run = MagicMock()
        mock_run.info.run_id = "integration-test-run"
        mock_run.__enter__ = MagicMock(return_value=mock_run)
        mock_run.__exit__ = MagicMock(return_value=False)

        mocker.patch("mlflow.start_run", return_value=mock_run)
        mocker.patch("mlflow.log_params")
        mocker.patch("mlflow.log_metrics")
        mocker.patch("mlflow.sklearn.log_model")

        # Step 1: Validate data
        validation_result = validate_data(iris_csv_path, validated_path)
        assert validation_result.success is True

        # Step 2: Feature engineering
        fe_result = feature_engineering(validated_path, features_path, "species")
        assert fe_result.success is True

        # Step 3: Train model (import here to avoid circular imports)
        from pipelines.training.src.train_model import train_model

        train_result = train_model(
            input_path=features_path,
            model_output_path=model_path,
            target="species",
            model_name="integration-test",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=run_id_path,
            accuracy_output_path=accuracy_path,
        )

        assert train_result.success is True
        assert train_result.accuracy > 0.8  # Iris should have high accuracy
        assert os.path.exists(model_path)

    @pytest.mark.integration
    def test_pipeline_handles_data_with_nulls(self, csv_with_nulls_path, temp_dir):
        """Test that pipeline correctly handles and cleans data with nulls."""
        validated_path = str(temp_dir / "validated.csv")
        features_path = str(temp_dir / "features.csv")

        # Validate and clean data
        validation_result = validate_data(csv_with_nulls_path, validated_path, min_rows=5)
        assert validation_result.rows_removed > 0
        assert validation_result.clean_rows >= 5

        # Feature engineering should work on cleaned data
        fe_result = feature_engineering(validated_path, features_path, "species")
        assert fe_result.success is True
        assert fe_result.input_shape[0] == validation_result.clean_rows
