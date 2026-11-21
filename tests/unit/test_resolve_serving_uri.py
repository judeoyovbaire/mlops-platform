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

    def test_models_uri_resolved_through_download_uri(self, mock_client):
        """MLflow 3 sets mv.source to the logged-model URI (models:/m-<id>);
        the serving URI is the version's download URI."""
        mock_client.get_model_version_by_alias.return_value = _model_version(
            version="1", source="models:/m-d4109ca6e57240fb84f552af7220d495"
        )
        mock_client.get_model_version_download_uri.return_value = (
            "s3://mlflow-artifacts/1/models/m-d4109ca6e57240fb84f552af7220d495/artifacts"
        )
        mock_client.get_run.return_value = _run()

        result = resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")

        assert result.storage_uri == (
            "s3://mlflow-artifacts/1/models/m-d4109ca6e57240fb84f552af7220d495/artifacts"
        )
        mock_client.get_model_version_download_uri.assert_called_once_with("iris-classifier", "1")

    def test_models_uri_without_download_uri_raises(self, mock_client):
        """If the download URI cannot be fetched, the models:/ source is still
        unfetchable and the error must say so."""
        from mlflow.exceptions import MlflowException

        mock_client.get_model_version_by_alias.return_value = _model_version(
            source="models:/m-d4109ca6e57240fb84f552af7220d495"
        )
        mock_client.get_model_version_download_uri.side_effect = MlflowException("boom")

        with pytest.raises(ModelRegistrationError) as exc_info:
            resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")
        message = str(exc_info.value)
        assert "models:/m-d4109ca6e57240fb84f552af7220d495" in message
        assert "storage-initializer cannot fetch" in message
        assert "get-download-uri" in message

    def test_models_uri_with_unfetchable_download_uri_raises(self, mock_client):
        """A download URI that is itself proxied (mlflow-artifacts:/) still
        fails, with the proxied-artifacts hint."""
        mock_client.get_model_version_by_alias.return_value = _model_version(
            source="models:/m-d4109ca6e57240fb84f552af7220d495"
        )
        mock_client.get_model_version_download_uri.return_value = (
            "mlflow-artifacts:/1/models/m-d4109ca6e57240fb84f552af7220d495/artifacts"
        )

        with pytest.raises(ModelRegistrationError, match="proxied artifacts"):
            resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")

    def test_gs_uri_accepted(self, mock_client):
        mock_client.get_model_version_by_alias.return_value = _model_version(
            source="gs://bucket/path/serving_model"
        )

        result = resolve_serving_uri("iris-classifier", "champion", "http://mlflow:5000")
        assert result.storage_uri.startswith("gs://")
