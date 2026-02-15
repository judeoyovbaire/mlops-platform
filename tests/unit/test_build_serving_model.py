"""Unit tests for build_serving_model module."""

import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler

from pipelines.training.src.build_serving_model import PreprocessingModel
from pipelines.training.src.exceptions import ModelTrainingError


@pytest.fixture
def iris_features(iris_dataframe):
    """Return feature-only iris DataFrame (no target)."""
    return iris_dataframe.drop(columns=["species"])


@pytest.fixture
def fitted_scaler(iris_features):
    """Fit a StandardScaler on iris numeric features."""
    scaler = StandardScaler()
    numeric_cols = iris_features.select_dtypes(include="number").columns.tolist()
    scaler.fit(iris_features[numeric_cols])
    return scaler, numeric_cols


@pytest.fixture
def trained_rf(iris_dataframe):
    """Train a RandomForest on *scaled* iris features."""
    X = iris_dataframe.drop(columns=["species"])
    y = iris_dataframe["species"]

    scaler = StandardScaler()
    numeric_cols = X.select_dtypes(include="number").columns.tolist()
    X[numeric_cols] = scaler.fit_transform(X[numeric_cols])

    model = RandomForestClassifier(n_estimators=10, max_depth=3, random_state=42)
    model.fit(X, y)
    return model, scaler, numeric_cols


class TestPreprocessingModel:
    """Tests for the PreprocessingModel pyfunc wrapper."""

    def test_predict_with_scaler(self, trained_rf, iris_features):
        """Test that the wrapper scales inputs and produces predictions."""
        model, scaler, numeric_cols = trained_rf

        wrapper = PreprocessingModel(
            model=model,
            scaler=scaler,
            numeric_cols=numeric_cols,
        )

        preds = wrapper.predict(context=None, model_input=iris_features)
        assert isinstance(preds, np.ndarray)
        assert len(preds) == len(iris_features)
        assert set(preds).issubset({"setosa", "versicolor", "virginica"})

    def test_predict_without_scaler(self, iris_dataframe):
        """Test prediction works when no scaler is provided."""
        X = iris_dataframe.drop(columns=["species"])
        y = iris_dataframe["species"]

        model = RandomForestClassifier(n_estimators=10, random_state=42)
        model.fit(X, y)

        wrapper = PreprocessingModel(model=model)
        preds = wrapper.predict(context=None, model_input=X)
        assert len(preds) == len(X)

    def test_predict_ignores_missing_columns(self, trained_rf):
        """Test that missing columns in input are gracefully skipped."""
        model, scaler, numeric_cols = trained_rf

        wrapper = PreprocessingModel(
            model=model,
            scaler=scaler,
            numeric_cols=numeric_cols + ["nonexistent_col"],
        )

        # Only pass real columns — the wrapper should skip the extra one
        df = pd.DataFrame(
            {
                "sepal_length": [5.1],
                "sepal_width": [3.5],
                "petal_length": [1.4],
                "petal_width": [0.2],
            }
        )
        preds = wrapper.predict(context=None, model_input=df)
        assert len(preds) == 1


class TestBuildServingModelErrors:
    """Tests for error handling in build_serving_model."""

    def test_model_not_found(self):
        """Test error when model file doesn't exist."""
        from pipelines.training.src.build_serving_model import build_serving_model

        with pytest.raises(ModelTrainingError, match="not found"):
            build_serving_model(
                model_path="/nonexistent/model.joblib",
                scaler_path=None,
                encoder_path=None,
                run_id="fake-run",
                mlflow_uri="http://localhost:5000",
            )
