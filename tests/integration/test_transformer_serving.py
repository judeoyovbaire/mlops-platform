"""Integration tests for the serving path with a REAL fitted preprocessor.

Regression tests for the transformer column-name bug: `pd.DataFrame(instances)`
produces integer column names, while the ColumnTransformer from
feature_engineering is fitted on *named* columns. These tests deliberately use
no mocks at the preprocessor seam — the artifact is produced by the actual
feature_engineering pipeline code and loaded with joblib, exactly as in the
serving container.
"""

import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier

from pipelines.training.src.build_serving_model import PreprocessingModel
from pipelines.training.src.feature_engineering import feature_engineering

# The kserve package is not a test dependency; stub it like the unit tests do
# (the seam under test is the preprocessor, not kserve plumbing).
_kserve_mock = MagicMock()
_kserve_mock.Model = type("Model", (), {"__init__": lambda self, name: None})
sys.modules.setdefault("kserve", _kserve_mock)

_transformer_dir = str(Path(__file__).resolve().parents[2] / "components" / "kserve-transformer")
if _transformer_dir not in sys.path:
    sys.path.insert(0, _transformer_dir)

from transformer import IrisTransformer  # noqa: E402


@pytest.fixture(scope="module")
def fitted_artifacts(tmp_path_factory):
    """Produce a real preprocessor + model via the actual pipeline code."""
    tmp = tmp_path_factory.mktemp("serving")
    rng = np.random.default_rng(42)
    n = 60
    df = pd.DataFrame(
        {
            "sepal_length": rng.normal(5.8, 0.8, n),
            "sepal_width": rng.normal(3.0, 0.4, n),
            "petal_length": rng.normal(3.7, 1.7, n),
            "petal_width": rng.normal(1.2, 0.7, n),
            "species": rng.choice(["setosa", "versicolor", "virginica"], n),
        }
    )
    input_csv = tmp / "input.csv"
    output_csv = tmp / "features.csv"
    df.to_csv(input_csv, index=False)

    result = feature_engineering(
        input_path=str(input_csv),
        output_path=str(output_csv),
        target_column="species",
    )
    assert result.preprocessor_path is not None

    preprocessor = joblib.load(result.preprocessor_path)
    features = pd.read_csv(output_csv)
    X = features.drop(columns=["species"])
    y = features["species"]
    model = RandomForestClassifier(n_estimators=10, random_state=42).fit(X, y)

    raw_X = df.drop(columns=["species"])
    return SimpleNamespace(
        preprocessor=preprocessor,
        preprocessor_path=result.preprocessor_path,
        model=model,
        raw_X=raw_X,
    )


def _make_payload(data):
    """Minimal stand-in for a KServe InferRequest."""
    return SimpleNamespace(inputs=[SimpleNamespace(data=data)])


@pytest.fixture
def loaded_transformer(fitted_artifacts, monkeypatch):
    """IrisTransformer with the REAL preprocessor loaded from disk."""
    import transformer as transformer_module

    monkeypatch.setattr(
        transformer_module, "PREPROCESSOR_PATH", fitted_artifacts.preprocessor_path
    )
    t = IrisTransformer(name="iris", predictor_host="localhost:8080")
    t.preprocessor = joblib.load(fitted_artifacts.preprocessor_path)
    return t


@pytest.mark.integration
class TestTransformerWithRealPreprocessor:
    """The seam the MagicMock unit tests could not cover."""

    def test_positional_payload_transforms(self, loaded_transformer, fitted_artifacts):
        """List-of-lists payload (integer columns) must not 500 — the bug."""
        raw = fitted_artifacts.raw_X
        payload = _make_payload(raw.head(3).values.tolist())

        result = loaded_transformer.preprocess(payload, headers={})

        expected = fitted_artifacts.preprocessor.transform(raw.head(3))
        if hasattr(expected, "to_numpy"):
            expected = expected.to_numpy()
        np.testing.assert_allclose(result.inputs[0].data, expected, rtol=1e-9)

    def test_named_payload_out_of_order_columns(self, loaded_transformer, fitted_artifacts):
        """Dict payload with shuffled key order must align to training order."""
        raw = fitted_artifacts.raw_X
        records = raw.head(2)[list(reversed(raw.columns))].to_dict(orient="records")
        payload = _make_payload(records)

        result = loaded_transformer.preprocess(payload, headers={})

        expected = fitted_artifacts.preprocessor.transform(raw.head(2))
        if hasattr(expected, "to_numpy"):
            expected = expected.to_numpy()
        np.testing.assert_allclose(result.inputs[0].data, expected, rtol=1e-9)

    def test_wrong_width_raises_actionable_error(self, loaded_transformer):
        """Wrong feature count should fail with the expected schema, not a
        cryptic sklearn traceback."""
        payload = _make_payload([[5.1, 3.5]])
        with pytest.raises(ValueError, match="Expected 4 features"):
            loaded_transformer.preprocess(payload, headers={})

    def test_missing_named_feature_raises(self, loaded_transformer, fitted_artifacts):
        raw = fitted_artifacts.raw_X
        records = raw.head(1).drop(columns=["petal_width"]).to_dict(orient="records")
        payload = _make_payload(records)
        with pytest.raises(ValueError, match="Missing required features"):
            loaded_transformer.preprocess(payload, headers={})


@pytest.mark.integration
class TestServingPyfuncEndToEnd:
    """Raw input → PreprocessingModel (the registered serving artifact) → prediction."""

    def test_raw_input_to_prediction(self, fitted_artifacts):
        serving = PreprocessingModel(
            model=fitted_artifacts.model,
            preprocessor=fitted_artifacts.preprocessor,
        )
        raw = fitted_artifacts.raw_X.head(5)

        predictions = serving.predict(context=None, model_input=raw)

        assert len(predictions) == 5
        assert set(np.unique(predictions)).issubset({"setosa", "versicolor", "virginica"})

    def test_transformer_output_matches_pyfunc_pipeline(self, loaded_transformer, fitted_artifacts):
        """The two serving paths (transformer+predictor vs bundled pyfunc)
        must produce identical predictions for the same raw input."""
        raw = fitted_artifacts.raw_X.head(4)

        # Path 1: KServe transformer preprocess → model
        payload = _make_payload(raw.values.tolist())
        transformed = loaded_transformer.preprocess(payload, headers={}).inputs[0].data
        path1 = fitted_artifacts.model.predict(
            pd.DataFrame(transformed, columns=fitted_artifacts.model.feature_names_in_)
        )

        # Path 2: bundled serving pyfunc
        serving = PreprocessingModel(
            model=fitted_artifacts.model, preprocessor=fitted_artifacts.preprocessor
        )
        path2 = serving.predict(context=None, model_input=raw)

        np.testing.assert_array_equal(path1, path2)
