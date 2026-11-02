"""Unit tests for KServe IrisTransformer."""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest

# Mock kserve before importing the transformer module
_kserve_mock = MagicMock()
_kserve_mock.Model = type("Model", (), {"__init__": lambda self, name: None})
_kserve_mock.InferRequest = MagicMock
_kserve_mock.InferResponse = MagicMock
_kserve_mock.ModelServer = MagicMock

sys.modules["kserve"] = _kserve_mock

_transformer_dir = str(Path(__file__).resolve().parents[2] / "components" / "kserve-transformer")
if _transformer_dir not in sys.path:
    sys.path.insert(0, _transformer_dir)

from transformer import IrisTransformer  # noqa: E402


@pytest.fixture
def iris_transformer():
    """Create an IrisTransformer instance."""
    return IrisTransformer(name="iris")


class TestTransformerLoad:
    """Tests for the load() method."""

    def test_load_success(self, iris_transformer):
        """Loading a valid preprocessor should set ready=True."""
        mock_preprocessor = MagicMock()
        with patch("transformer.joblib.load", return_value=mock_preprocessor):
            result = iris_transformer.load()

        assert result is True
        assert iris_transformer.ready is True
        assert iris_transformer.preprocessor is mock_preprocessor

    def test_load_missing_no_passthrough(self, iris_transformer, monkeypatch):
        """Missing preprocessor without PASSTHROUGH_MODE should set ready=False."""
        monkeypatch.delenv("PASSTHROUGH_MODE", raising=False)
        with patch("transformer.joblib.load", side_effect=FileNotFoundError):
            result = iris_transformer.load()

        assert result is False
        assert iris_transformer.ready is False
        assert iris_transformer.preprocessor is None

    def test_load_missing_with_passthrough(self, iris_transformer, monkeypatch):
        """Missing preprocessor with PASSTHROUGH_MODE=true should set ready=True."""
        monkeypatch.setenv("PASSTHROUGH_MODE", "true")
        with patch("transformer.joblib.load", side_effect=FileNotFoundError):
            result = iris_transformer.load()

        assert result is True
        assert iris_transformer.ready is True
        assert iris_transformer.preprocessor is None


class TestPreprocess:
    """Tests for the preprocess() method."""

    def test_preprocess_with_preprocessor(self, iris_transformer):
        """When preprocessor is set, transform should be called on a DataFrame
        carrying the TRAINING column names (regression: positional payloads
        used to produce integer columns that a fitted transformer rejects)."""
        feature_names = ["sepal_length", "sepal_width", "petal_length", "petal_width"]
        mock_preprocessor = MagicMock()
        mock_preprocessor.feature_names_in_ = np.array(feature_names)
        transformed_array = np.array([[1.0, 2.0, 3.0, 4.0]])
        mock_preprocessor.transform.return_value = transformed_array
        iris_transformer.preprocessor = mock_preprocessor

        mock_input = MagicMock()
        mock_input.data = [[5.1, 3.5, 1.4, 0.2]]
        mock_payload = MagicMock()
        mock_payload.inputs = [mock_input]

        result = iris_transformer.preprocess(mock_payload, headers={})

        call_args = mock_preprocessor.transform.call_args
        sent_df = call_args[0][0]
        assert isinstance(sent_df, pd.DataFrame)
        assert list(sent_df.columns) == feature_names
        assert result.inputs[0].data == transformed_array.tolist()

    def test_preprocess_v1_dict_positional(self, iris_transformer):
        """A v1 request reaches preprocess as a dict: positional instances get
        the training column names and the transformed rows replace them."""
        feature_names = ["sepal_length", "sepal_width", "petal_length", "petal_width"]
        mock_preprocessor = MagicMock()
        mock_preprocessor.feature_names_in_ = np.array(feature_names)
        transformed_array = np.array([[1.0, 2.0, 3.0, 4.0]])
        mock_preprocessor.transform.return_value = transformed_array
        iris_transformer.preprocessor = mock_preprocessor

        payload = {"instances": [[5.1, 3.5, 1.4, 0.2]]}
        result = iris_transformer.preprocess(payload, headers={})

        sent_df = mock_preprocessor.transform.call_args[0][0]
        assert list(sent_df.columns) == feature_names
        assert result is payload
        assert result["instances"] == transformed_array.tolist()

    def test_preprocess_v1_dict_named_reordered(self, iris_transformer):
        """Named v1 instances are reordered to the training column order."""
        feature_names = ["sepal_length", "sepal_width", "petal_length", "petal_width"]
        mock_preprocessor = MagicMock()
        mock_preprocessor.feature_names_in_ = np.array(feature_names)
        mock_preprocessor.transform.return_value = np.array([[0.0, 0.0, 0.0, 0.0]])
        iris_transformer.preprocessor = mock_preprocessor

        row = {"petal_width": 0.2, "sepal_length": 5.1, "petal_length": 1.4, "sepal_width": 3.5}
        iris_transformer.preprocess({"instances": [row]}, headers={})

        sent_df = mock_preprocessor.transform.call_args[0][0]
        assert list(sent_df.columns) == feature_names
        assert sent_df.iloc[0].tolist() == [5.1, 3.5, 1.4, 0.2]

    def test_preprocess_v1_dict_without_preprocessor(self, iris_transformer):
        """Passthrough mode leaves a v1 payload untouched."""
        iris_transformer.preprocessor = None
        payload = {"instances": [[5.1, 3.5, 1.4, 0.2]]}
        assert iris_transformer.preprocess(payload, headers={}) == {
            "instances": [[5.1, 3.5, 1.4, 0.2]]
        }

    def test_preprocess_with_sparse_output(self, iris_transformer):
        """When preprocessor returns sparse matrix, it should be converted."""
        mock_preprocessor = MagicMock()
        mock_preprocessor.feature_names_in_ = np.array(["a", "b", "c"])
        mock_sparse = MagicMock()
        mock_sparse.toarray.return_value = np.array([[1.0, 0.0, 1.0]])
        mock_preprocessor.transform.return_value = mock_sparse
        iris_transformer.preprocessor = mock_preprocessor

        mock_input = MagicMock()
        mock_input.data = [[5.1, 3.5, 1.4]]
        mock_payload = MagicMock()
        mock_payload.inputs = [mock_input]

        result = iris_transformer.preprocess(mock_payload, headers={})
        mock_sparse.toarray.assert_called_once()
        assert result.inputs[0].data == [[1.0, 0.0, 1.0]]

    def test_preprocess_wrong_width_raises(self, iris_transformer):
        """Payload width mismatch must produce an actionable error."""
        mock_preprocessor = MagicMock()
        mock_preprocessor.feature_names_in_ = np.array(["a", "b", "c", "d"])
        iris_transformer.preprocessor = mock_preprocessor

        mock_input = MagicMock()
        mock_input.data = [[5.1, 3.5]]
        mock_payload = MagicMock()
        mock_payload.inputs = [mock_input]

        with pytest.raises(ValueError, match="Expected 4 features"):
            iris_transformer.preprocess(mock_payload, headers={})

    def test_preprocess_without_preprocessor(self, iris_transformer):
        """When preprocessor is None, data should pass through unchanged."""
        iris_transformer.preprocessor = None

        original_data = [[5.1, 3.5, 1.4, 0.2]]
        mock_input = MagicMock()
        mock_input.data = original_data
        mock_payload = MagicMock()
        mock_payload.inputs = [mock_input]

        result = iris_transformer.preprocess(mock_payload, headers={})
        assert result.inputs[0].data == original_data


class TestPostprocess:
    """Tests for the postprocess() method."""

    def test_postprocess_passthrough(self, iris_transformer):
        """Postprocess should return the response unchanged."""
        mock_response = MagicMock()
        result = iris_transformer.postprocess(mock_response, headers={})
        assert result is mock_response
