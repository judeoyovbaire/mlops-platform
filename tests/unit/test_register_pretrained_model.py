"""Tests for the HuggingFace pretrained model registration step."""

import json
import sys
from unittest.mock import MagicMock, patch

import pytest

from pipelines.pretrained.src.register_model import (
    register_pretrained_model,
)
from pipelines.shared.exceptions import ModelRegistrationError


@pytest.fixture
def metadata_file(tmp_path):
    """Create a temporary metadata.json file."""
    metadata = {
        "model_id": "distilbert/distilbert-base-uncased-finetuned-sst-2-english",
        "task": "text-classification",
        "model_dir": str(tmp_path / "model"),
        "num_parameters": 66_000_000,
        "pipeline_tag": "text-classification",
        "test_input": "I love this product!",
        "test_output": '[{"label": "POSITIVE", "score": 0.9998}]',
        "success": True,
        "requested_revision": None,
        "resolved_revision": "714eb0fa89d2f80546fda750413ed43d93601a13",
    }
    path = tmp_path / "metadata.json"
    path.write_text(json.dumps(metadata))
    return str(path)


@pytest.fixture(autouse=True)
def fake_torch_stack(monkeypatch):
    """torch/transformers exist in the pipeline image, not the dev venv -
    register_model imports them at call time to pin pip requirements."""
    monkeypatch.setitem(sys.modules, "torch", MagicMock(__version__="2.6.0+cpu"))
    monkeypatch.setitem(sys.modules, "transformers", MagicMock(__version__="4.51.3"))


class TestRegisterPretrainedModel:
    """Tests for the register_pretrained_model function."""

    def test_register_requires_resolved_revision(self, tmp_path):
        """Artifacts without a pinned Hub commit SHA are not registrable -
        the supply chain must not be bypassable at the registration step."""
        metadata = {"model_id": "m", "task": "t", "model_dir": str(tmp_path)}
        path = tmp_path / "metadata.json"
        path.write_text(json.dumps(metadata))

        with pytest.raises(ModelRegistrationError, match="resolved_revision"):
            register_pretrained_model(
                metadata_path=str(path),
                model_name="sentiment-classifier",
                mlflow_uri="http://localhost:5000",
            )

    @patch("pipelines.pretrained.src.register_model.mlflow")
    @patch("pipelines.pretrained.src.register_model.hf_pipeline")
    @patch("pipelines.pretrained.src.register_model.run_with_timeout")
    def test_register_success(self, mock_timeout, mock_hf_pipeline, mock_mlflow, metadata_file):
        """Test successful model registration."""
        # Mock MLflow client
        mock_client = MagicMock()
        mock_timeout.return_value = mock_client

        # Mock transformers pipeline
        mock_pipe = MagicMock()
        mock_hf_pipeline.return_value = mock_pipe

        # Mock MLflow run
        mock_run = MagicMock()
        mock_run.info.run_id = "test-run-123"
        mock_mlflow.start_run.return_value.__enter__ = MagicMock(return_value=mock_run)
        mock_mlflow.start_run.return_value.__exit__ = MagicMock(return_value=False)

        # Mock model registration
        mock_mv = MagicMock()
        mock_mv.version = 1
        mock_mlflow.register_model.return_value = mock_mv

        result = register_pretrained_model(
            metadata_path=metadata_file,
            model_name="sentiment-classifier",
            mlflow_uri="http://localhost:5000",
            alias="champion",
        )

        assert result.registered is True
        assert result.model_name == "sentiment-classifier"
        assert result.model_id == "distilbert/distilbert-base-uncased-finetuned-sst-2-english"
        assert result.task == "text-classification"
        assert result.version == 1
        assert result.alias == "champion"
        assert result.success is True

        # Verify MLflow was called correctly
        mock_mlflow.log_params.assert_called_once()
        mock_mlflow.transformers.log_model.assert_called_once()
        mock_mlflow.register_model.assert_called_once_with(
            "runs:/test-run-123/model", "sentiment-classifier"
        )
        mock_client.set_registered_model_alias.assert_called_once_with(
            "sentiment-classifier", "champion", 1
        )

    def test_register_missing_metadata_file(self, tmp_path):
        """Test failure when metadata file doesn't exist."""
        with pytest.raises(ModelRegistrationError, match="Metadata file not found"):
            register_pretrained_model(
                metadata_path=str(tmp_path / "nonexistent.json"),
                model_name="test-model",
                mlflow_uri="http://localhost:5000",
            )

    def test_register_invalid_metadata_json(self, tmp_path):
        """Test failure when metadata file is not valid JSON."""
        bad_file = tmp_path / "bad.json"
        bad_file.write_text("not valid json{{{")

        with pytest.raises(ModelRegistrationError, match="Invalid metadata JSON"):
            register_pretrained_model(
                metadata_path=str(bad_file),
                model_name="test-model",
                mlflow_uri="http://localhost:5000",
            )

    @patch("pipelines.pretrained.src.register_model.run_with_timeout")
    def test_register_mlflow_timeout(self, mock_timeout, metadata_file):
        """Test failure when MLflow connection times out."""
        from pipelines.shared.exceptions import MLflowTimeoutError

        mock_timeout.side_effect = MLflowTimeoutError("Connection timed out")

        with pytest.raises(ModelRegistrationError, match="Connection timed out"):
            register_pretrained_model(
                metadata_path=metadata_file,
                model_name="test-model",
                mlflow_uri="http://localhost:5000",
            )

    @patch("pipelines.pretrained.src.register_model.mlflow")
    @patch("pipelines.pretrained.src.register_model.hf_pipeline")
    @patch("pipelines.pretrained.src.register_model.run_with_timeout")
    def test_register_pipeline_load_failure(
        self, mock_timeout, mock_hf_pipeline, mock_mlflow, metadata_file
    ):
        """Test failure when transformers pipeline can't load."""
        mock_timeout.return_value = MagicMock()
        mock_hf_pipeline.side_effect = OSError("Model files corrupted")

        with pytest.raises(ModelRegistrationError, match="Failed to load transformers pipeline"):
            register_pretrained_model(
                metadata_path=metadata_file,
                model_name="test-model",
                mlflow_uri="http://localhost:5000",
            )

    @patch("pipelines.pretrained.src.register_model.mlflow")
    @patch("pipelines.pretrained.src.register_model.hf_pipeline")
    @patch("pipelines.pretrained.src.register_model.run_with_timeout")
    def test_register_logs_params_with_num_parameters(
        self, mock_timeout, mock_hf_pipeline, mock_mlflow, metadata_file
    ):
        """Test that num_parameters is logged when present."""
        mock_timeout.return_value = MagicMock()
        mock_hf_pipeline.return_value = MagicMock()
        mock_run = MagicMock()
        mock_run.info.run_id = "run-456"
        mock_mlflow.start_run.return_value.__enter__ = MagicMock(return_value=mock_run)
        mock_mlflow.start_run.return_value.__exit__ = MagicMock(return_value=False)
        mock_mv = MagicMock()
        mock_mv.version = 2
        mock_mlflow.register_model.return_value = mock_mv

        register_pretrained_model(
            metadata_path=metadata_file,
            model_name="test-model",
            mlflow_uri="http://localhost:5000",
        )

        # Verify num_parameters was included in params
        logged_params = mock_mlflow.log_params.call_args[0][0]
        assert "num_parameters" in logged_params
        assert logged_params["num_parameters"] == "66000000"
