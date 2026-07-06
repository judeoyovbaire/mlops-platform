"""Unit tests for resolve_serving_uri (registry alias -> serving URI)."""

from unittest.mock import MagicMock

import pytest

from pipelines.shared.exceptions import ModelRegistrationError
from pipelines.training.src.resolve_serving_uri import (
    ResolvedServingModel,
    resolve_serving_uri,
)


@pytest.fixture
def mock_client(mocker):
    client = MagicMock()
    mocker.patch(
        "pipelines.training.src.resolve_serving_uri.MlflowClient",
        return_value=client,
    )
    mocker.patch("mlflow.set_tracking_uri")
    return client


def _model_version(
    version="3", run_id="run-abc", source="s3://mlflow-artifacts/1/run-abc/artifacts/serving_model"
):
    mv = MagicMock()
    mv.version = version
    mv.run_id = run_id
    mv.source = source
    return mv


def _run(experiment_id="1"):
    run = MagicMock()
    run.info.experiment_id = experiment_id
    return run


class TestResolveServingUri:
    def test_resolves_alias_to_s3_uri(self, mock_client):
        mock_client.get_model_version_by_alias.return_value = _model_version()
        mock_client.get_run.return_value = _run(experiment_id="7")

        result = resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")

        assert isinstance(result, ResolvedServingModel)
        assert result.version == 3
        assert result.run_id == "run-abc"
        assert result.experiment_id == "7"
        assert result.storage_uri.startswith("s3://")
        mock_client.get_model_version_by_alias.assert_called_once_with(
            "iris-classifier", "champion"
        )

    def test_experiment_lookup_failure_does_not_block_resolution(self, mock_client):
        """Lineage lookup is best-effort - a registry alias that resolves must
        still deploy even if the run record is unavailable."""
        from mlflow.exceptions import MlflowException

        mock_client.get_model_version_by_alias.return_value = _model_version()
        mock_client.get_run.side_effect = MlflowException("run not found")

        result = resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")
        assert result.experiment_id == ""

    def test_missing_alias_raises_actionable_error(self, mock_client):
        from mlflow.exceptions import MlflowException

        mock_client.get_model_version_by_alias.side_effect = MlflowException(
            "alias champion not found"
        )

        with pytest.raises(ModelRegistrationError, match="run the training pipeline"):
            resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")

    def test_unfetchable_scheme_raises(self, mock_client):
        """mlflow-artifacts:/ (proxied artifacts) cannot be fetched by the
        KServe storage-initializer - must fail with the config hint."""
        mock_client.get_model_version_by_alias.return_value = _model_version(
            source="mlflow-artifacts:/1/run-abc/artifacts/serving_model"
        )

        with pytest.raises(ModelRegistrationError, match="storage-initializer cannot fetch"):
            resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")

    def test_gs_uri_accepted(self, mock_client):
        mock_client.get_model_version_by_alias.return_value = _model_version(
            source="gs://bucket/path/serving_model"
        )

        result = resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")
        assert result.storage_uri.startswith("gs://")
