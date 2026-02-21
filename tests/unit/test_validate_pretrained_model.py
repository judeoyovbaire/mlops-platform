"""Tests for the HuggingFace pretrained model validation step."""

import json
import os
from unittest.mock import MagicMock, patch

import pytest

from pipelines.pretrained.src.validate_model import (
    DEFAULT_VALIDATION_INPUTS,
    PretrainedValidationResult,
    validate_pretrained_model,
)


@pytest.fixture
def metadata_file(tmp_path):
    """Create a temporary metadata.json file."""
    model_dir = tmp_path / "model"
    model_dir.mkdir()
    metadata = {
        "model_id": "distilbert/distilbert-base-uncased-finetuned-sst-2-english",
        "task": "text-classification",
        "model_dir": str(model_dir),
        "num_parameters": 66_000_000,
        "pipeline_tag": "text-classification",
        "test_input": "I love this product!",
        "test_output": '[{"label": "POSITIVE", "score": 0.9998}]',
        "success": True,
    }
    path = tmp_path / "metadata.json"
    path.write_text(json.dumps(metadata))
    return str(path)


@pytest.fixture
def output_path(tmp_path):
    """Return a temporary output path for validation results."""
    return str(tmp_path / "validation_result.json")


class TestValidatePretrainedModel:
    """Tests for the validate_pretrained_model function."""

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_validation_passes(self, mock_hf_pipeline, metadata_file, output_path):
        """Test that validation passes when model produces valid output."""
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.9998}]
        mock_hf_pipeline.return_value = mock_pipe

        result = validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
        )

        assert isinstance(result, PretrainedValidationResult)
        assert result.passed is True
        assert result.num_inputs_tested == len(DEFAULT_VALIDATION_INPUTS)
        assert result.num_successful == len(DEFAULT_VALIDATION_INPUTS)
        assert result.num_failed == 0
        assert result.schema_valid is True
        assert all(result.checks.values())

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_validation_custom_inputs(self, mock_hf_pipeline, metadata_file, output_path):
        """Test with custom test inputs."""
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "NEGATIVE", "score": 0.95}]
        mock_hf_pipeline.return_value = mock_pipe

        custom_inputs = ["Test input 1", "Test input 2"]
        result = validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
            test_inputs=custom_inputs,
        )

        assert result.passed is True
        assert result.num_inputs_tested == 2
        assert result.num_successful == 2
        assert mock_pipe.call_count == 2

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_validation_fails_inference_error(self, mock_hf_pipeline, metadata_file, output_path):
        """Test that validation fails when inference raises an error."""
        mock_pipe = MagicMock()
        mock_pipe.side_effect = RuntimeError("Inference error")
        mock_hf_pipeline.return_value = mock_pipe

        result = validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
        )

        assert result.passed is False
        assert result.num_failed == len(DEFAULT_VALIDATION_INPUTS)
        assert result.num_successful == 0
        assert result.checks["all_inferences_passed"] is False

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_validation_fails_bad_schema(self, mock_hf_pipeline, metadata_file, output_path):
        """Test that validation fails when output has wrong schema."""
        mock_pipe = MagicMock()
        # Missing 'score' key
        mock_pipe.return_value = [{"label": "POSITIVE"}]
        mock_hf_pipeline.return_value = mock_pipe

        result = validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
        )

        assert result.passed is False
        assert result.schema_valid is False
        assert result.checks["output_schema_valid"] is False

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    @patch("pipelines.pretrained.src.validate_model.time")
    def test_validation_fails_latency(
        self, mock_time, mock_hf_pipeline, metadata_file, output_path
    ):
        """Test that validation fails when latency exceeds threshold."""
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.99}]
        mock_hf_pipeline.return_value = mock_pipe

        # Simulate 10-second latency per call
        call_count = 0

        def mock_monotonic():
            nonlocal call_count
            call_count += 1
            return call_count * 5.0  # Each pair of calls = 5s latency

        mock_time.monotonic = mock_monotonic

        result = validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
            latency_threshold=0.001,  # Extremely low threshold
        )

        assert result.passed is False
        assert result.checks["latency_within_threshold"] is False

    def test_metadata_not_found(self, tmp_path, output_path):
        """Test error when metadata file doesn't exist."""
        with pytest.raises(RuntimeError, match="Metadata file not found"):
            validate_pretrained_model(
                metadata_path=str(tmp_path / "nonexistent.json"),
                output_path=output_path,
            )

    def test_invalid_metadata_json(self, tmp_path, output_path):
        """Test error when metadata file is not valid JSON."""
        bad_file = tmp_path / "bad.json"
        bad_file.write_text("not valid json{{{")

        with pytest.raises(RuntimeError, match="Invalid metadata JSON"):
            validate_pretrained_model(
                metadata_path=str(bad_file),
                output_path=output_path,
            )

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_model_load_failure(self, mock_hf_pipeline, metadata_file, output_path):
        """Test error when model pipeline fails to load."""
        mock_hf_pipeline.side_effect = OSError("Model files corrupted")

        with pytest.raises(RuntimeError, match="Failed to load model"):
            validate_pretrained_model(
                metadata_path=metadata_file,
                output_path=output_path,
            )

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_result_written_to_file(self, mock_hf_pipeline, metadata_file, output_path):
        """Test that validation result is written to output file."""
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.99}]
        mock_hf_pipeline.return_value = mock_pipe

        validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
        )

        assert os.path.exists(output_path)
        with open(output_path) as f:
            data = json.load(f)
        assert data["passed"] is True
        assert data["model_id"] == "distilbert/distilbert-base-uncased-finetuned-sst-2-english"

    @patch("pipelines.pretrained.src.validate_model.hf_pipeline")
    def test_result_dataclass_fields(self, mock_hf_pipeline, metadata_file, output_path):
        """Test that PretrainedValidationResult has expected fields."""
        mock_pipe = MagicMock()
        mock_pipe.return_value = [{"label": "POSITIVE", "score": 0.99}]
        mock_hf_pipeline.return_value = mock_pipe

        result = validate_pretrained_model(
            metadata_path=metadata_file,
            output_path=output_path,
        )

        assert hasattr(result, "passed")
        assert hasattr(result, "model_id")
        assert hasattr(result, "task")
        assert hasattr(result, "num_inputs_tested")
        assert hasattr(result, "num_successful")
        assert hasattr(result, "num_failed")
        assert hasattr(result, "avg_latency_seconds")
        assert hasattr(result, "p95_latency_seconds")
        assert hasattr(result, "latency_threshold")
        assert hasattr(result, "schema_valid")
        assert hasattr(result, "checks")
        assert hasattr(result, "error_message")
