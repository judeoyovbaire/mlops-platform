"""KServe Transformer that applies preprocessing before forwarding to the predictor.

Loads a joblib-serialized ColumnTransformer (from the feature-engineering step)
and transforms raw feature DataFrames before sending them to the model predictor.
"""

import argparse
import logging
import os

import joblib
import pandas as pd
from kserve import InferRequest, InferResponse, Model, ModelServer, model_server

logger = logging.getLogger(__name__)

PREPROCESSOR_PATH = os.environ.get("PREPROCESSOR_PATH", "/mnt/models/preprocessor.joblib")


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

    def preprocess(
        self, payload: InferRequest | dict, headers: dict | None = None
    ) -> InferRequest | dict:
        """Apply preprocessing to the input features.

        The fitted ColumnTransformer was trained on *named* columns, so raw
        payloads must be aligned to the training schema before transform:
        positional rows (list-of-lists) get the training column names applied;
        named rows (list-of-dicts) are reordered to the training column order.

        KServe hands a v1 request ({"instances": [...]}) to preprocess as a
        dict and a v2 request as an InferRequest; both are handled, and the
        payload goes on to the predictor in the protocol it arrived in. The
        transformer's --predictor_protocol must match the predictor's.
        """
        if isinstance(payload, dict):
            instances = payload["instances"]
        else:
            instances = payload.inputs[0].data
        df = pd.DataFrame(instances)
        if self.preprocessor is not None:
            expected = getattr(self.preprocessor, "feature_names_in_", None)
            if expected is not None:
                expected = list(expected)
                if df.columns.inferred_type == "integer":
                    # Positional payload: apply training column names.
                    if df.shape[1] != len(expected):
                        raise ValueError(
                            f"Expected {len(expected)} features {expected}, "
                            f"got {df.shape[1]} values per instance"
                        )
                    df.columns = expected
                else:
                    # Named payload: validate and align column order.
                    missing = [c for c in expected if c not in df.columns]
                    if missing:
                        raise ValueError(
                            f"Missing required features: {missing}. Expected features: {expected}"
                        )
                    df = df[expected]
            transformed = self.preprocessor.transform(df)
            if hasattr(transformed, "toarray"):
                transformed = transformed.toarray()
            elif hasattr(transformed, "to_numpy"):
                transformed = transformed.to_numpy()
            if isinstance(payload, dict):
                payload["instances"] = transformed.tolist()
            else:
                payload.inputs[0].data = transformed.tolist()
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
