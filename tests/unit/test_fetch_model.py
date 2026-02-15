"""Tests for the HuggingFace pretrained model fetch pipeline step."""

import json
import os
from unittest.mock import MagicMock, patch

import pytest

from pipelines.pretrained.src.fetch_model import (
    DEFAULT_TEST_INPUTS,
    fetch_model,
)


@pytest.fixture
def output_dir(tmp_path):
    """Create a temporary output directory."""
    return str(tmp_path / "hf-model")


class TestFetchModel:
    """Tests for the fetch_model function."""

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_success(self, mock_model_info, mock_pipeline, output_dir):
        """Test successful model fetch and validation."""
        # Mock model info
        mock_info = MagicMock()
        mock_info.pipeline_tag = "text-classification"
        mock_info.safetensors = MagicMock()
        mock_info.safetensors.total = 66_000_000
        mock_model_info.return_value = mock_info

        # Mock pipeline
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.9998}]
        mock_pipe.model = MagicMock()
        mock_pipe.tokenizer = MagicMock()
        mock_pipeline.return_value = mock_pipe

        result = fetch_model(
            model_id="distilbert/distilbert-base-uncased-finetuned-sst-2-english",
            output_dir=output_dir,
            task="text-classification",
        )

        assert result.success is True
        assert result.model_id == "distilbert/distilbert-base-uncased-finetuned-sst-2-english"
        assert result.task == "text-classification"
        assert result.num_parameters == 66_000_000
        assert result.pipeline_tag == "text-classification"
        assert "POSITIVE" in result.test_output

        # Verify metadata was written
        metadata_path = os.path.join(output_dir, "metadata.json")
        assert os.path.exists(metadata_path)
        with open(metadata_path) as f:
            metadata = json.load(f)
        assert metadata["model_id"] == result.model_id

        # Verify model was saved
        mock_pipe.model.save_pretrained.assert_called_once()
        mock_pipe.tokenizer.save_pretrained.assert_called_once()

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_custom_test_input(self, mock_model_info, mock_pipeline, output_dir):
        """Test with custom test input."""
        mock_model_info.return_value = MagicMock(pipeline_tag=None, safetensors=None)
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "NEGATIVE", "score": 0.95}]
        mock_pipe.model = MagicMock()
        mock_pipe.tokenizer = MagicMock()
        mock_pipeline.return_value = mock_pipe

        result = fetch_model(
            model_id="test-model",
            output_dir=output_dir,
            task="text-classification",
            test_input="This is terrible!",
        )

        assert result.success is True
        assert result.test_input == "This is terrible!"
        mock_pipe.assert_called_once_with("This is terrible!")

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_download_failure(self, mock_model_info, mock_pipeline, output_dir):
        """Test failure when model download fails."""
        mock_model_info.return_value = MagicMock(pipeline_tag=None, safetensors=None)
        mock_pipeline.side_effect = OSError("Connection failed")

        with pytest.raises(RuntimeError, match="Failed to download model"):
            fetch_model(model_id="bad/model", output_dir=output_dir)

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_inference_failure(self, mock_model_info, mock_pipeline, output_dir):
        """Test failure when sanity inference fails."""
        mock_model_info.return_value = MagicMock(pipeline_tag=None, safetensors=None)
        mock_pipe = MagicMock()
        mock_pipe.side_effect = RuntimeError("Inference error")
        mock_pipeline.return_value = mock_pipe

        with pytest.raises(RuntimeError, match="Sanity inference failed"):
            fetch_model(model_id="test/model", output_dir=output_dir)

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_info_failure_non_fatal(self, mock_model_info, mock_pipeline, output_dir):
        """Test that model_info failure is non-fatal (warning only)."""
        mock_model_info.side_effect = Exception("API rate limit")
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.9}]
        mock_pipe.model = MagicMock()
        mock_pipe.tokenizer = MagicMock()
        mock_pipeline.return_value = mock_pipe

        result = fetch_model(model_id="test/model", output_dir=output_dir)

        assert result.success is True
        assert result.num_parameters is None

    def test_default_test_inputs_has_text_classification(self):
        """Test that default inputs cover text-classification."""
        assert "text-classification" in DEFAULT_TEST_INPUTS
        assert "sentiment-analysis" in DEFAULT_TEST_INPUTS
        assert len(DEFAULT_TEST_INPUTS["text-classification"]) > 0

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_with_revision(self, mock_model_info, mock_pipeline, output_dir):
        """Test fetch with specific revision."""
        mock_model_info.return_value = MagicMock(pipeline_tag=None, safetensors=None)
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.9}]
        mock_pipe.model = MagicMock()
        mock_pipe.tokenizer = MagicMock()
        mock_pipeline.return_value = mock_pipe

        fetch_model(
            model_id="test/model",
            output_dir=output_dir,
            revision="v1.0",
        )

        mock_pipeline.assert_called_once_with(
            task="text-classification",
            model="test/model",
            revision="v1.0",
            model_kwargs={"cache_dir": os.path.join(output_dir, "cache")},
        )
        mock_model_info.assert_called_once_with("test/model", revision="v1.0")
