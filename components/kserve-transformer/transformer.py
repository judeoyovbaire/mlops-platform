"""KServe Transformer that applies preprocessing before forwarding to the predictor.

Loads a joblib-serialized ColumnTransformer (from the feature-engineering step)
and transforms raw feature DataFrames before sending them to the model predictor.
"""

import argparse
import logging
import os

import joblib
import numpy as np
import pandas as pd
from kserve import InferInput, InferRequest, InferResponse, Model, ModelServer, model_server
from kserve.errors import InvalidInput

logger = logging.getLogger(__name__)

PREPROCESSOR_PATH = os.environ.get("PREPROCESSOR_PATH", "/mnt/models/preprocessor.joblib")

# v2 datatypes the transformed (floating point) features can keep. FP16 is
# upcast to FP32: kserve cannot send FP16 as JSON (to_rest) or gRPC. Anything
# else (INT*, BOOL, BYTES) is widened to FP64, since scaling yields floats.
_FLOAT_DATATYPES = {"FP32": np.float32, "FP64": np.float64}


def _forward_datatype(datatype: str) -> str:
    if datatype == "FP16":
        return "FP32"
    return datatype if datatype in _FLOAT_DATATYPES else "FP64"


def _rows_from_v2_input(infer_input: InferInput) -> list:
    """Return the instances of a v2 input as a list of rows.

    The repo's own clients send nested rows (list of lists, or list of dicts
    for named features) and the spec's flat ``data`` with a ``shape``
    (``[5.1, 3.5, 1.4, 0.2]`` with shape ``[1, 4]``). Both are accepted; the
    flat form is reshaped by ``shape``. kserve decodes REST binary tensors into
    ``data`` before preprocess; gRPC ``raw_input_contents`` arrive as raw bytes
    and are decoded here with ``as_numpy``.
    """
    name = infer_input.name
    data = infer_input.data
    if not data and getattr(infer_input, "_raw_data", None) is not None:
        arr = infer_input.as_numpy()
        if arr.ndim == 1:
            return [arr.tolist()]
        if arr.ndim == 2:
            return arr.tolist()
        raise InvalidInput(f"input '{name}': tensor of rank {arr.ndim}, expected 2")
    if data is None:
        raise InvalidInput(f"input '{name}' carries no 'data'")
    data = list(data)
    if data and isinstance(data[0], (list, dict)):
        return data
    shape = list(infer_input.shape or [])
    if len(shape) <= 1:
        # A single instance: shape [N] (or none) with N values.
        return [data]
    if len(shape) != 2:
        raise InvalidInput(f"input '{name}': shape {shape} has rank {len(shape)}, expected 2")
    try:
        return np.asarray(data).reshape(shape).tolist()
    except ValueError as e:
        raise InvalidInput(f"input '{name}': {len(data)} values do not fit shape {shape}") from e


class IrisTransformer(Model):
    """Transformer that applies feature preprocessing to inference requests."""

    def __init__(self, name: str):
        # The predictor host is not held here: ModelServer builds a
        # PredictorConfig from --predictor_host/--predictor_protocol and the
        # base class reads it from the kserve context when forwarding
        # (kserve >= 0.15). KServe injects --model_name, --predictor_host,
        # --http_port and --workers, but NOT the protocol, which defaults to
        # v1: in front of a v2 predictor (MLServer), set
        # args: ["--predictor_protocol=v2"] on the transformer container.
        super().__init__(name)
        self.preprocessor = None

    def load(self) -> bool:
        """Load the preprocessor artifact.

        If PASSTHROUGH_MODE is set, missing preprocessor is acceptable.
        Otherwise, a missing preprocessor prevents the transformer from serving.
        """
        passthrough = os.environ.get("PASSTHROUGH_MODE", "false").lower() == "true"
        try:
            self.preprocessor = joblib.load(PREPROCESSOR_PATH)
            logger.info("Loaded preprocessor from %s", PREPROCESSOR_PATH)
            self.ready = True
        except FileNotFoundError:
            if passthrough:
                logger.warning(
                    "Preprocessor not found at %s, running in passthrough mode", PREPROCESSOR_PATH
                )
                self.ready = True
            else:
                logger.error(
                    "Preprocessor not found at %s. Set PASSTHROUGH_MODE=true to skip.",
                    PREPROCESSOR_PATH,
                )
                self.ready = False
        return self.ready

    def _align(self, instances: list) -> pd.DataFrame:
        """Build the DataFrame the fitted ColumnTransformer expects.

        It was trained on *named* columns: positional rows (list of lists) get
        the training column names; named rows (list of dicts) are reordered to
        the training column order. Schema errors are InvalidInput (HTTP 400).
        """
        df = pd.DataFrame(instances)
        expected = getattr(self.preprocessor, "feature_names_in_", None)
        if expected is None:
            return df
        expected = list(expected)
        if df.columns.inferred_type == "integer":
            if df.shape[1] != len(expected):
                raise InvalidInput(
                    f"Expected {len(expected)} features {expected}, "
                    f"got {df.shape[1]} values per instance"
                )
            df.columns = expected
        else:
            missing = [c for c in expected if c not in df.columns]
            if missing:
                raise InvalidInput(
                    f"Missing required features: {missing}. Expected features: {expected}"
                )
            df = df[expected]
        return df

    def preprocess(
        self, payload: InferRequest | dict, headers: dict | None = None
    ) -> InferRequest | dict:
        """Apply preprocessing to the input features.

        KServe hands a v1 request ({"instances": [...]}) to preprocess as a
        dict and a v2 request as an InferRequest; both are handled, and the
        payload goes on to the predictor in the protocol it arrived in. The
        transformer's --predictor_protocol must match the predictor's.

        A body KServe could not decode (no JSON content-type) arrives as
        bytes; that is a client error, so it is rejected with InvalidInput
        (HTTP 400) rather than failing deeper with a 500.
        """
        if isinstance(payload, dict):
            if "instances" not in payload:
                raise InvalidInput("v1 request must carry 'instances'")
            instances = payload["instances"]
            infer_input = None
        elif hasattr(payload, "inputs"):
            inputs = list(payload.inputs or [])
            if len(inputs) != 1:
                raise InvalidInput(
                    f"expected exactly one v2 input (the feature tensor), got {len(inputs)}"
                )
            infer_input = inputs[0]
            instances = _rows_from_v2_input(infer_input)
        else:
            raise InvalidInput(
                f"unsupported request body ({type(payload).__name__}); "
                "send JSON with content-type: application/json"
            )

        if self.preprocessor is None:
            return payload

        try:
            transformed = self.preprocessor.transform(self._align(instances))
        except ValueError as e:
            # Values the fitted transformer cannot handle (strings in a numeric
            # column, NaN for a scaler): the client's data, so 400 not 500.
            raise InvalidInput(f"preprocessor rejected the input: {e}") from e
        if hasattr(transformed, "toarray"):
            transformed = transformed.toarray()
        elif hasattr(transformed, "to_numpy"):
            transformed = transformed.to_numpy()
        transformed = np.asarray(transformed)

        if infer_input is None:
            payload["instances"] = transformed.tolist()
            return payload

        # v2: the predictor sees the transformed tensor, so shape and datatype
        # must describe it. Keep a floating request datatype, widen the rest.
        datatype = _forward_datatype(infer_input.datatype)
        out = transformed.astype(_FLOAT_DATATYPES[datatype])
        payload.inputs[0] = InferInput(
            name=infer_input.name,
            shape=list(out.shape),
            datatype=datatype,
            data=out.flatten().tolist(),
            parameters=infer_input.parameters,
        )
        return payload

    def postprocess(
        self, response: InferResponse | dict, headers: dict | None = None
    ) -> InferResponse | dict:
        """Pass through predictor response unchanged."""
        return response


if __name__ == "__main__":
    # kserve's own parser defines --model_name and the --predictor_* flags
    # (ModelServer.parser() was removed after 0.14).
    parser = argparse.ArgumentParser(parents=[model_server.parser])
    args, _ = parser.parse_known_args()
    if not args.predictor_host:
        parser.error("--predictor_host is required (KServe injects it into the transformer)")

    transformer = IrisTransformer(name=args.model_name)
    transformer.load()
    ModelServer().start(models=[transformer])
