"""KServe Transformer that applies preprocessing before forwarding to the predictor.

Loads a joblib-serialized ColumnTransformer (from the feature-engineering step)
and transforms raw feature DataFrames before sending them to the model predictor.
"""

import argparse
import logging
import os

import joblib
import pandas as pd
from kserve import InferRequest, InferResponse, Model, ModelServer

logger = logging.getLogger(__name__)

PREPROCESSOR_PATH = os.environ.get("PREPROCESSOR_PATH", "/mnt/models/preprocessor.joblib")


class IrisTransformer(Model):
    """Transformer that applies feature preprocessing to inference requests."""

    def __init__(self, name: str, predictor_host: str):
        super().__init__(name)
        self.predictor_host = predictor_host
        self.preprocessor = None

    def load(self) -> bool:
        """Load the preprocessor artifact."""
        try:
            self.preprocessor = joblib.load(PREPROCESSOR_PATH)
            logger.info("Loaded preprocessor from %s", PREPROCESSOR_PATH)
            self.ready = True
        except FileNotFoundError:
            logger.warning(
                "Preprocessor not found at %s, passing through raw features", PREPROCESSOR_PATH
            )
            self.ready = True
        return self.ready

    def preprocess(self, payload: InferRequest, headers: dict) -> InferRequest:
        """Apply preprocessing to the input features."""
        instances = payload.inputs[0].data
        df = pd.DataFrame(instances)
        if self.preprocessor is not None:
            transformed = self.preprocessor.transform(df)
            if hasattr(transformed, "toarray"):
                transformed = transformed.toarray()
            payload.inputs[0].data = transformed.tolist()
        return payload

    def postprocess(self, response: InferResponse, headers: dict) -> InferResponse:
        """Pass through predictor response unchanged."""
        return response


if __name__ == "__main__":
    parser = argparse.ArgumentParser(parents=[ModelServer.parser()])
    parser.add_argument(
        "--predictor_host", required=True, help="Predictor hostname for forwarding requests"
    )
    args, _ = parser.parse_known_args()

    transformer = IrisTransformer(
        name=args.model_name,
        predictor_host=args.predictor_host,
    )
    transformer.load()
    ModelServer().start(models=[transformer])
