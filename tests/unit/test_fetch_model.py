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


RESOLVED_SHA = "714eb0fa89d2f80546fda750413ed43d93601a13"


def _hub_info(pipeline_tag=None, safetensors=None, sha=RESOLVED_SHA):
    info = MagicMock()
    info.pipeline_tag = pipeline_tag
    info.safetensors = safetensors
    info.sha = sha
    return info


class TestFetchModel:
    """Tests for the fetch_model function."""

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_success(self, mock_model_info, mock_pipeline, output_dir):
        """Test successful model fetch and validation."""
        # Mock model info
        safetensors = MagicMock()
        safetensors.total = 66_000_000
        mock_model_info.return_value = _hub_info(
            pipeline_tag="text-classification", safetensors=safetensors
        )

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
        # Supply-chain lineage travels in the metadata
        assert metadata["resolved_revision"] == RESOLVED_SHA
        assert result.resolved_revision == RESOLVED_SHA

        # Verify model was saved
        mock_pipe.model.save_pretrained.assert_called_once()
        mock_pipe.tokenizer.save_pretrained.assert_called_once()

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_custom_test_input(self, mock_model_info, mock_pipeline, output_dir):
        """Test with custom test input."""
        mock_model_info.return_value = _hub_info()
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
        mock_model_info.return_value = _hub_info()
        mock_pipeline.side_effect = OSError("Connection failed")

        with pytest.raises(RuntimeError, match="Failed to download model"):
            fetch_model(model_id="bad/model", output_dir=output_dir)

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_inference_failure(self, mock_model_info, mock_pipeline, output_dir):
        """Test failure when sanity inference fails."""
        mock_model_info.return_value = _hub_info()
        mock_pipe = MagicMock()
        mock_pipe.side_effect = RuntimeError("Inference error")
        mock_pipeline.return_value = mock_pipe

        with pytest.raises(RuntimeError, match="Sanity inference failed"):
            fetch_model(model_id="test/model", output_dir=output_dir)

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_unresolvable_revision_is_fatal(
        self, mock_model_info, mock_pipeline, output_dir
    ):
        """Revision resolution is a hard supply-chain gate, not best-effort:
        without a resolved commit SHA the model has no provenance identity."""
        mock_model_info.side_effect = Exception("API rate limit")

        with pytest.raises(RuntimeError, match="Could not resolve"):
            fetch_model(model_id="test/model", output_dir=output_dir)
        mock_pipeline.assert_not_called()

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_missing_sha_is_fatal(self, mock_model_info, mock_pipeline, output_dir):
        """Hub metadata without a commit SHA must also fail."""
        mock_model_info.return_value = _hub_info(sha=None)

        with pytest.raises(RuntimeError, match="no commit SHA"):
            fetch_model(model_id="test/model", output_dir=output_dir)
        mock_pipeline.assert_not_called()

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_rejects_pickle_weights(self, mock_model_info, mock_pipeline, output_dir):
        """A .bin weight file in the saved artifact must fail the fetch -
        pickle-based weights execute arbitrary code on load."""
        mock_model_info.return_value = _hub_info()
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.9}]

        def _save_with_pickle(path, **kwargs):
            with open(os.path.join(path, "pytorch_model.bin"), "wb") as f:
                f.write(b"pickle")

        mock_pipe.model.save_pretrained.side_effect = _save_with_pickle
        mock_pipe.tokenizer = MagicMock()
        mock_pipeline.return_value = mock_pipe

        with pytest.raises(RuntimeError, match="Pickle-based weight files"):
            fetch_model(model_id="test/model", output_dir=output_dir)

    def test_default_test_inputs_has_text_classification(self):
        """Test that default inputs cover text-classification."""
        assert "text-classification" in DEFAULT_TEST_INPUTS
        assert "sentiment-analysis" in DEFAULT_TEST_INPUTS
        assert len(DEFAULT_TEST_INPUTS["text-classification"]) > 0

    @patch("pipelines.pretrained.src.fetch_model.pipeline")
    @patch("pipelines.pretrained.src.fetch_model.model_info")
    def test_fetch_model_with_revision(self, mock_model_info, mock_pipeline, output_dir):
        """Test fetch with specific revision."""
        mock_model_info.return_value = _hub_info()
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.9}]
        mock_pipe.model = MagicMock()
        mock_pipe.tokenizer = MagicMock()
        mock_pipeline.return_value = mock_pipe

        result = fetch_model(
            model_id="test/model",
            output_dir=output_dir,
            revision="v1.0",
        )

        # The download pins to the RESOLVED SHA, never the mutable ref
        mock_pipeline.assert_called_once_with(
            task="text-classification",
            model="test/model",
            revision=RESOLVED_SHA,
            trust_remote_code=False,
            model_kwargs={
                "cache_dir": os.path.join(output_dir, "cache"),
                "use_safetensors": True,
            },
        )
        mock_model_info.assert_called_once_with("test/model", revision="v1.0")
        assert result.requested_revision == "v1.0"
        assert result.resolved_revision == RESOLVED_SHA
