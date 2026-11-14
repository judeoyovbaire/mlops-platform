"""The transformer against the REAL kserve SDK, v2 protocol objects included.

The other transformer tests stub kserve (an image dependency). This file runs
only where the image's requirements are installed, for example:

    uv venv /tmp/kserve-venv --python 3.12
    uv pip install --python /tmp/kserve-venv/bin/python \\
        -r components/kserve-transformer/requirements.txt pytest
    /tmp/kserve-venv/bin/python -m pytest tests/integration/test_transformer_v2_protocol.py

It checks what a stub cannot: that the InferRequest the transformer hands
back serialises to a spec-valid v2 REST body (to_rest), that InvalidInput is
kserve's own 400 error, and that the flat-data form round-trips through
InferInput.as_numpy.
"""

import importlib.metadata
import sys
from pathlib import Path

import numpy as np
import pytest

try:
    importlib.metadata.version("kserve")
except importlib.metadata.PackageNotFoundError:  # pragma: no cover - dev env
    pytest.skip("kserve is not installed (image dependency)", allow_module_level=True)

if getattr(sys.modules.get("kserve"), "__stub__", False):  # pragma: no cover
    pytest.skip(
        "kserve is stubbed in this session; run this file on its own", allow_module_level=True
    )

from kserve import InferInput, InferRequest  # noqa: E402
from kserve.errors import InvalidInput  # noqa: E402
from sklearn.compose import ColumnTransformer  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402

_transformer_dir = str(Path(__file__).resolve().parents[2] / "components" / "kserve-transformer")
if _transformer_dir not in sys.path:
    sys.path.insert(0, _transformer_dir)

from transformer import IrisTransformer  # noqa: E402

FEATURES = ["sepal_length", "sepal_width", "petal_length", "petal_width"]


@pytest.fixture(scope="module")
def transformer():
    import pandas as pd

    rng = np.random.default_rng(0)
    X = pd.DataFrame(rng.normal(size=(50, 4)), columns=FEATURES)
    t = IrisTransformer(name="iris")
    t.preprocessor = ColumnTransformer([("s", StandardScaler(), FEATURES)]).fit(X)
    t.ready = True
    return t


def _request(data, shape, datatype="FP32"):
    return InferRequest(
        model_name="iris",
        infer_inputs=[InferInput(name="input-0", shape=shape, datatype=datatype, data=data)],
        request_id="r1",
    )


@pytest.mark.integration
class TestRealKserveV2:
    def test_flat_spec_request_round_trips(self, transformer):
        req = _request([5.1, 3.5, 1.4, 0.2], shape=[1, 4])

        out = transformer.preprocess(req, headers={})

        inp = out.inputs[0]
        assert isinstance(inp, InferInput)
        assert inp.shape == [1, 4]
        assert inp.datatype == "FP32"
        arr = inp.as_numpy()  # the predictor-side decode
        assert arr.shape == (1, 4) and arr.dtype == np.float32
        body, json_length = out.to_rest()
        assert json_length is None  # plain JSON, no binary tail
        assert body["inputs"][0]["shape"] == [1, 4]
        assert len(body["inputs"][0]["data"]) == 4

    def test_nested_rows_leave_flat(self, transformer):
        req = _request([[5.1, 3.5, 1.4, 0.2], [4.9, 3.0, 1.4, 0.2]], shape=[2, 4], datatype="FP64")

        out = transformer.preprocess(req, headers={})

        inp = out.inputs[0]
        assert inp.shape == [2, 4]
        assert inp.as_numpy().shape == (2, 4)
        assert out.to_rest()[0]["inputs"][0]["datatype"] == "FP64"

    def test_grpc_style_raw_tensor_is_decoded(self, transformer):
        """gRPC raw_input_contents reach preprocess as _raw_data with empty
        data; as_numpy decodes them (data=None never happens on a server path)."""
        inp = InferInput(name="input-0", shape=[1, 4], datatype="FP32")
        inp.set_data_from_numpy(
            np.array([[5.1, 3.5, 1.4, 0.2]], dtype=np.float32), binary_data=True
        )
        assert inp.data is None and inp._raw_data is not None
        req = InferRequest(model_name="iris", infer_inputs=[inp], request_id="r2")

        out = transformer.preprocess(req, headers={})

        assert out.inputs[0].shape == [1, 4]
        assert out.inputs[0].as_numpy().shape == (1, 4)

    def test_fp16_binary_request_is_forwardable(self, transformer):
        inp = InferInput(name="input-0", shape=[1, 4], datatype="FP16")
        inp.set_data_from_numpy(
            np.array([[5.1, 3.5, 1.4, 0.2]], dtype=np.float16), binary_data=True
        )
        req = InferRequest(model_name="iris", infer_inputs=[inp], request_id="r3")

        out = transformer.preprocess(req, headers={})

        assert out.inputs[0].datatype == "FP32"
        body, _ = out.to_rest()  # would raise for FP16
        assert body["inputs"][0]["datatype"] == "FP32"

    def test_errors_are_kserve_invalid_input(self, transformer):
        with pytest.raises(InvalidInput):
            transformer.preprocess(_request([5.1, 3.5, 1.4], shape=[1, 4]), headers={})
        with pytest.raises(InvalidInput):
            transformer.preprocess(b"not json", headers={})
        with pytest.raises(InvalidInput):
            transformer.preprocess({"inputs": []}, headers={})
