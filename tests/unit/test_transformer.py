"""Unit tests for KServe IrisTransformer."""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest

from tests import kserve_stub

# Stub kserve (an image dependency, not a dev one) before importing the module.
kserve_stub.install()

_transformer_dir = str(Path(__file__).resolve().parents[2] / "components" / "kserve-transformer")
if _transformer_dir not in sys.path:
    sys.path.insert(0, _transformer_dir)

# InvalidInput from the transformer's own namespace: it is bound to whichever
# kserve (stub or real) the module imported, see kserve_stub.install().
from transformer import InvalidInput, IrisTransformer  # noqa: E402

FEATURES = ["sepal_length", "sepal_width", "petal_length", "petal_width"]


def _v2(data, shape=None, datatype="FP64", name="input-0"):
    """A v2 request with one input, as kserve hands it to preprocess."""
    if shape is None:
        shape = [len(data), len(data[0])] if data and isinstance(data[0], list) else [len(data)]
    return kserve_stub.InferRequest(
        "iris", [kserve_stub.InferInput(name, shape, datatype, data=data)], request_id="r1"
    )


def _fitted(feature_names=FEATURES, transformed=None):
    """A mock preprocessor fitted on feature_names returning `transformed`."""
    pre = MagicMock()
    pre.feature_names_in_ = np.array(feature_names)
    if transformed is None:
        transformed = np.array([[1.0, 2.0, 3.0, 4.0]])
    pre.transform.return_value = transformed
    return pre


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

        result = iris_transformer.preprocess(_v2([[5.1, 3.5, 1.4, 0.2]]), headers={})

        call_args = mock_preprocessor.transform.call_args
        sent_df = call_args[0][0]
        assert isinstance(sent_df, pd.DataFrame)
        assert list(sent_df.columns) == feature_names
        # v2 data goes on flat, described by shape (spec form).
        assert result.inputs[0].data == transformed_array.flatten().tolist()
        assert result.inputs[0].shape == [1, 4]

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

        result = iris_transformer.preprocess(_v2([[5.1, 3.5, 1.4]]), headers={})
        mock_sparse.toarray.assert_called_once()
        assert result.inputs[0].data == [1.0, 0.0, 1.0]
        assert result.inputs[0].shape == [1, 3]

    def test_preprocess_wrong_width_raises(self, iris_transformer):
        """Payload width mismatch must produce an actionable error."""
        mock_preprocessor = MagicMock()
        mock_preprocessor.feature_names_in_ = np.array(["a", "b", "c", "d"])
        iris_transformer.preprocessor = mock_preprocessor

        # InvalidInput is a ValueError the server maps to HTTP 400.
        with pytest.raises(InvalidInput, match="Expected 4 features"):
            iris_transformer.preprocess(_v2([[5.1, 3.5]]), headers={})

    def test_preprocess_without_preprocessor(self, iris_transformer):
        """When preprocessor is None, data should pass through unchanged."""
        iris_transformer.preprocessor = None

        original_data = [[5.1, 3.5, 1.4, 0.2]]
        payload = _v2(original_data)

        result = iris_transformer.preprocess(payload, headers={})
        assert result is payload
        assert result.inputs[0].data == original_data


class TestV2Protocol:
    """The v2 edge cases from JDH-425: flat spec-style data, shape and
    datatype after the transform, and non-JSON bodies."""

    def test_flat_data_is_reshaped_by_shape(self, iris_transformer):
        """Spec form: data [5.1, 3.5, 1.4, 0.2] with shape [1, 4] is one row.
        It used to fail with 'got 1 values per instance'."""
        pre = _fitted()
        iris_transformer.preprocessor = pre

        iris_transformer.preprocess(_v2([5.1, 3.5, 1.4, 0.2], shape=[1, 4]), headers={})

        sent_df = pre.transform.call_args[0][0]
        assert sent_df.shape == (1, 4)
        assert sent_df.iloc[0].tolist() == [5.1, 3.5, 1.4, 0.2]

    def test_flat_data_two_rows(self, iris_transformer):
        pre = _fitted(transformed=np.zeros((2, 4)))
        iris_transformer.preprocessor = pre

        result = iris_transformer.preprocess(_v2([1.0] * 8, shape=[2, 4]), headers={})

        assert pre.transform.call_args[0][0].shape == (2, 4)
        assert result.inputs[0].shape == [2, 4]
        assert len(result.inputs[0].data) == 8

    def test_rank1_shape_is_one_instance(self, iris_transformer):
        pre = _fitted()
        iris_transformer.preprocessor = pre

        iris_transformer.preprocess(_v2([5.1, 3.5, 1.4, 0.2], shape=[4]), headers={})

        assert pre.transform.call_args[0][0].shape == (1, 4)

    def test_flat_data_not_matching_shape_is_400(self, iris_transformer):
        iris_transformer.preprocessor = _fitted()
        with pytest.raises(InvalidInput, match="do not fit shape"):
            iris_transformer.preprocess(_v2([5.1, 3.5, 1.4], shape=[1, 4]), headers={})

    def test_shape_and_datatype_follow_the_transform(self, iris_transformer):
        """The predictor receives the transformed tensor, so the input's shape
        and datatype must describe it (they used to be left as sent)."""
        # 4 raw features in, 6 encoded columns out, as a one-hot encoder would do.
        pre = _fitted(transformed=np.arange(12, dtype=np.float64).reshape(2, 6))
        iris_transformer.preprocessor = pre

        result = iris_transformer.preprocess(
            _v2([[5.1, 3.5, 1.4, 0.2], [4.9, 3.0, 1.4, 0.2]], shape=[2, 4], datatype="FP32"),
            headers={},
        )

        out = result.inputs[0]
        assert out.name == "input-0"
        assert out.shape == [2, 6]
        assert out.datatype == "FP32"  # a floating request datatype is kept
        assert out.data == [float(v) for v in range(12)]

    def test_integer_request_datatype_widens_to_fp64(self, iris_transformer):
        iris_transformer.preprocessor = _fitted()

        result = iris_transformer.preprocess(_v2([[5, 3, 1, 0]], datatype="INT64"), headers={})

        assert result.inputs[0].datatype == "FP64"

    def test_fp16_request_is_forwarded_as_fp32(self, iris_transformer):
        """kserve cannot send FP16 over JSON or gRPC (to_rest/to_grpc raise), so
        a kept FP16 would turn a valid request into a 400 blaming the client."""
        iris_transformer.preprocessor = _fitted()

        result = iris_transformer.preprocess(
            _v2([5.1, 3.5, 1.4, 0.2], shape=[1, 4], datatype="FP16"), headers={}
        )

        assert result.inputs[0].datatype == "FP32"

    def test_preprocessor_value_error_is_400(self, iris_transformer):
        """Values the fitted transformer rejects (strings in a numeric column)
        are the client's data, not a server fault."""
        pre = _fitted()
        pre.transform.side_effect = ValueError("could not convert string to float: 'x'")
        iris_transformer.preprocessor = pre

        with pytest.raises(InvalidInput, match="preprocessor rejected the input"):
            iris_transformer.preprocess({"instances": [["x", 3.5, 1.4, 0.2]]}, headers={})

    def test_bytes_body_is_400_not_500(self, iris_transformer):
        """Without content-type: application/json KServe hands the raw body
        to preprocess; that is the client's error."""
        iris_transformer.preprocessor = _fitted()
        with pytest.raises(InvalidInput, match="content-type: application/json"):
            iris_transformer.preprocess(b'{"instances": [[5.1, 3.5, 1.4, 0.2]]}', headers={})

    def test_v1_without_instances_is_400(self, iris_transformer):
        iris_transformer.preprocessor = _fitted()
        with pytest.raises(InvalidInput, match="instances"):
            iris_transformer.preprocess({"inputs": []}, headers={})

    def test_two_v2_inputs_is_400(self, iris_transformer):
        iris_transformer.preprocessor = _fitted()
        payload = _v2([[5.1, 3.5, 1.4, 0.2]])
        payload.inputs.append(kserve_stub.InferInput("extra", [1], "FP64", data=[1.0]))
        with pytest.raises(InvalidInput, match="exactly one v2 input"):
            iris_transformer.preprocess(payload, headers={})

    def test_named_rows_in_v2_still_work(self, iris_transformer):
        """The repo's own (non-spec) list-of-dicts form keeps working."""
        pre = _fitted()
        iris_transformer.preprocessor = pre
        row = {"petal_width": 0.2, "sepal_length": 5.1, "petal_length": 1.4, "sepal_width": 3.5}

        iris_transformer.preprocess(_v2([row], shape=[1], datatype="BYTES"), headers={})

        sent_df = pre.transform.call_args[0][0]
        assert list(sent_df.columns) == FEATURES
        assert sent_df.iloc[0].tolist() == [5.1, 3.5, 1.4, 0.2]


class TestPostprocess:
    """Tests for the postprocess() method."""

    def test_postprocess_passthrough(self, iris_transformer):
        """Postprocess should return the response unchanged."""
        mock_response = MagicMock()
        result = iris_transformer.postprocess(mock_response, headers={})
        assert result is mock_response
