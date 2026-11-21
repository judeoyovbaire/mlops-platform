"""Unit tests for train_model module."""

from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier

from pipelines.shared.exceptions import ModelTrainingError
from pipelines.training.src.train_model import (
    TrainingResult,
    shap_feature_importance,
    train_model,
)


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
        mock_log_params = mocker.patch("mlflow.log_params")
        mock_log_metrics = mocker.patch("mlflow.log_metrics")
        mock_log_metric = mocker.patch("mlflow.log_metric")
        mock_log_model = mocker.patch("mlflow.sklearn.log_model")

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

        # Verify MLflow tracking calls
        mock_log_params.assert_called()
        mock_log_metrics.assert_called()
        mock_log_model.assert_called_once()

        # One shap_importance_<feature> metric per feature column. Before
        # JDH-427 this block raised on shap >= 0.45 (3-D multiclass array)
        # and was swallowed by the broad except, so nothing was logged.
        features = [c for c in pd.read_csv(artifacts["data_path"]).columns if c != "species"]
        shap_calls = {
            call.args[0]: call.args[1]
            for call in mock_log_metric.call_args_list
            if call.args[0].startswith("shap_importance_")
        }
        assert set(shap_calls) == {f"shap_importance_{f}" for f in features}
        assert all(isinstance(v, float) and v >= 0.0 for v in shap_calls.values())
        assert any(v > 0.0 for v in shap_calls.values())
        # skops (MLflow 3.17's default) rejects tree models; the format must
        # be explicit.
        assert mock_log_model.call_args.kwargs["serialization_format"] == "cloudpickle"

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
        mocker.patch("mlflow.log_metric")
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
        mocker.patch("mlflow.log_metric")
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
        mocker.patch("mlflow.log_metric")
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
        assert hasattr(result, "best_params")


class TestGridSearch:
    """Tests for GridSearchCV hyperparameter tuning."""

    def _mock_mlflow(self, mocker):
        """Helper to set up MLflow mocks."""
        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.set_experiment")

        mock_run = MagicMock()
        mock_run.info.run_id = "grid-search-run"
        mock_run.__enter__ = MagicMock(return_value=mock_run)
        mock_run.__exit__ = MagicMock(return_value=False)

        mocker.patch("mlflow.start_run", return_value=mock_run)
        mocker.patch("mlflow.log_params")
        mock_log_metrics = mocker.patch("mlflow.log_metrics")
        mocker.patch("mlflow.log_metric")
        mocker.patch("mlflow.sklearn.log_model")
        return mock_log_metrics

    def test_grid_search_enabled(self, trained_model_artifacts, mocker):
        """Test that GridSearchCV populates best_params when enabled."""
        artifacts = trained_model_artifacts
        self._mock_mlflow(mocker)

        result = train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-grid",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
            use_grid_search=True,
        )

        assert result.success is True
        assert result.best_params is not None
        assert "n_estimators" in result.best_params
        assert "max_depth" in result.best_params

    def test_grid_search_disabled_by_default(self, trained_model_artifacts, mocker):
        """Test that best_params is None when grid search is not used."""
        artifacts = trained_model_artifacts
        self._mock_mlflow(mocker)

        result = train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-no-grid",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
        )

        assert result.best_params is None

    def test_grid_search_logs_to_mlflow(self, trained_model_artifacts, mocker):
        """Test that GridSearchCV results are logged to MLflow."""
        artifacts = trained_model_artifacts
        self._mock_mlflow(mocker)
        mock_log_params = mocker.patch("mlflow.log_params")
        mock_log_metric = mocker.patch("mlflow.log_metric")

        train_model(
            input_path=artifacts["data_path"],
            model_output_path=artifacts["model_path"],
            target="species",
            model_name="test-grid-mlflow",
            mlflow_uri="http://localhost:5000",
            n_estimators=10,
            max_depth=3,
            test_size=0.2,
            run_id_output_path=artifacts["run_id_path"],
            accuracy_output_path=artifacts["accuracy_path"],
            use_grid_search=True,
        )

        # Check that best params were logged
        all_params = {}
        for call in mock_log_params.call_args_list:
            all_params.update(call[0][0])
        assert any(k.startswith("best_") for k in all_params)

        # Check that grid_search_best_score metric was logged
        metric_names = [call[0][0] for call in mock_log_metric.call_args_list]
        assert "grid_search_best_score" in metric_names


class TestShapFeatureImportance:
    """Tests for shap_feature_importance (JDH-427)."""

    @staticmethod
    def _fit(n_classes: int) -> tuple[RandomForestClassifier, pd.DataFrame]:
        rng = np.random.default_rng(0)
        X = pd.DataFrame(rng.normal(size=(120, 4)), columns=["a", "b", "c", "d"])
        # Only "a" and "b" carry signal; "c" and "d" are noise.
        y = (X["a"] + X["b"] > 0).astype(int)
        if n_classes == 3:
            y = y + (X["a"] > 1).astype(int)
        model = RandomForestClassifier(n_estimators=10, max_depth=3, random_state=0)
        model.fit(X, y)
        return model, X

    def test_multiclass_one_value_per_feature(self):
        """shap >= 0.45 returns (n, features, classes); the result still has one float per column."""
        model, X = self._fit(n_classes=3)
        result = shap_feature_importance(model, X)
        assert list(result) == ["a", "b", "c", "d"]
        assert all(isinstance(v, float) and v >= 0.0 for v in result.values())
        assert min(result["a"], result["b"]) > max(result["c"], result["d"])

    def test_binary(self):
        model, X = self._fit(n_classes=2)
        result = shap_feature_importance(model, X)
        assert list(result) == ["a", "b", "c", "d"]
        assert min(result["a"], result["b"]) > max(result["c"], result["d"])

    def test_old_shap_list_layout_matches_new_array_layout(self, mocker):
        """A list of per-class arrays (shap < 0.45) and one 3-D array (>= 0.45) give the same answer."""
        model, X = self._fit(n_classes=3)
        rng = np.random.default_rng(1)
        per_class = [rng.normal(size=(len(X), 4)) for _ in range(3)]
        expected = np.mean([np.abs(sv).mean(axis=0) for sv in per_class], axis=0)

        explainer = MagicMock()
        mocker.patch("shap.TreeExplainer", return_value=explainer)

        explainer.shap_values.return_value = per_class
        old = shap_feature_importance(model, X)
        explainer.shap_values.return_value = np.stack(per_class, axis=-1)
        new = shap_feature_importance(model, X)

        assert old == new
        assert np.allclose(list(new.values()), expected)

    def test_unexpected_shape_raises(self, mocker):
        model, X = self._fit(n_classes=2)
        explainer = MagicMock()
        explainer.shap_values.return_value = np.zeros((len(X),))
        mocker.patch("shap.TreeExplainer", return_value=explainer)
        with pytest.raises(ValueError, match="unexpected shap_values shape"):
            shap_feature_importance(model, X)

    def test_sample_is_capped(self, mocker):
        model, X = self._fit(n_classes=2)
        X = pd.concat([X] * 3, ignore_index=True)  # 360 rows
        explainer = MagicMock()
        explainer.shap_values.return_value = np.zeros((100, 4, 2))
        mocker.patch("shap.TreeExplainer", return_value=explainer)
        shap_feature_importance(model, X)
        assert len(explainer.shap_values.call_args.args[0]) == 100
