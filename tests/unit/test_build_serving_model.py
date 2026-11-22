"""Unit tests for build_serving_model module."""

import os

import numpy as np
import pandas as pd
import pytest
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler

from pipelines.shared.exceptions import ModelTrainingError
from pipelines.training.src.build_serving_model import PreprocessingModel


@pytest.fixture
def iris_features(iris_dataframe):
    """Return feature-only iris DataFrame (no target)."""
    return iris_dataframe.drop(columns=["species"])


@pytest.fixture
def fitted_preprocessor(iris_features):
    """Fit a ColumnTransformer on iris numeric features."""
    numeric_cols = iris_features.select_dtypes(include="number").columns.tolist()
    preprocessor = ColumnTransformer(
        transformers=[("scaler", StandardScaler(), numeric_cols)],
        remainder="drop",
    )
    preprocessor.set_output(transform="pandas")
    preprocessor.fit(iris_features)
    return preprocessor


@pytest.fixture
def trained_rf(iris_dataframe, fitted_preprocessor):
    """Train a RandomForest on preprocessed iris features."""
    X = iris_dataframe.drop(columns=["species"])
    y = iris_dataframe["species"]

    X_transformed = fitted_preprocessor.transform(X)

    model = RandomForestClassifier(n_estimators=10, max_depth=3, random_state=42)
    model.fit(X_transformed, y)
    return model


class TestPreprocessingModel:
    """Tests for the PreprocessingModel pyfunc wrapper."""

    def test_predict_with_preprocessor(self, trained_rf, fitted_preprocessor, iris_features):
        """Test that the wrapper preprocesses inputs and produces predictions."""
        wrapper = PreprocessingModel(
            model=trained_rf,
            preprocessor=fitted_preprocessor,
        )

        preds = wrapper.predict(context=None, model_input=iris_features)
        assert isinstance(preds, np.ndarray)
        assert len(preds) == len(iris_features)
        assert set(preds).issubset({"setosa", "versicolor", "virginica"})

    def test_predict_without_preprocessor(self, iris_dataframe):
        """Test prediction works when no preprocessor is provided."""
        X = iris_dataframe.drop(columns=["species"])
        y = iris_dataframe["species"]

        model = RandomForestClassifier(n_estimators=10, random_state=42)
        model.fit(X, y)

        wrapper = PreprocessingModel(model=model)
        preds = wrapper.predict(context=None, model_input=X)
        assert len(preds) == len(X)

    def test_predict_single_row(self, trained_rf, fitted_preprocessor):
        """Test prediction on a single input row."""
        wrapper = PreprocessingModel(
            model=trained_rf,
            preprocessor=fitted_preprocessor,
        )

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
                preprocessor_path=None,
                run_id="fake-run",
                mlflow_uri="http://localhost:5000",
            )


class TestLocalServingCopy:
    """The local pyfunc copy feeds the serving-load-test workflow gate."""

    def test_local_copy_is_loadable_pyfunc(
        self, tmp_path, trained_rf, fitted_preprocessor, iris_features, mocker
    ):
        """The saved copy must load via pyfunc and score the input example -
        the same operations the serving-load-test step runs in the MLServer
        image (there it additionally proves interpreter compatibility)."""
        import joblib
        import mlflow

        from pipelines.training.src.build_serving_model import build_serving_model

        model_file = tmp_path / "model.joblib"
        joblib.dump(trained_rf, model_file)
        preproc_file = tmp_path / "preprocessor.joblib"
        joblib.dump(fitted_preprocessor, preproc_file)
        sample_csv = tmp_path / "input.csv"
        sample = iris_features.head(3).copy()
        sample["species"] = "setosa"
        sample.to_csv(sample_csv, index=False)

        # Keep the test hermetic: no tracking server, only the local save.
        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.start_run")
        mocker.patch("mlflow.pyfunc.log_model")
        mocker.patch("mlflow.log_artifacts")
        mocker.patch("mlflow.log_artifact")

        local_copy = tmp_path / "serving_model"
        result = build_serving_model(
            model_path=str(model_file),
            preprocessor_path=str(preproc_file),
            run_id="fake-run",
            mlflow_uri="http://localhost:5000",
            sample_input_path=str(sample_csv),
            target_column="species",
            local_copy_path=str(local_copy),
        )

        assert result.success
        loaded = mlflow.pyfunc.load_model(str(local_copy))
        preds = loaded.predict(iris_features.head(2))
        assert len(preds) == 2

    def test_local_copy_carries_input_example(
        self, tmp_path, trained_rf, fitted_preprocessor, iris_features, mocker
    ):
        """load_serving_example in the gate step needs the example files."""
        import joblib

        from pipelines.training.src.build_serving_model import build_serving_model

        model_file = tmp_path / "model.joblib"
        joblib.dump(trained_rf, model_file)
        preproc_file = tmp_path / "preprocessor.joblib"
        joblib.dump(fitted_preprocessor, preproc_file)
        sample_csv = tmp_path / "input.csv"
        iris_features.head(3).to_csv(sample_csv, index=False)

        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.start_run")
        mocker.patch("mlflow.pyfunc.log_model")
        mocker.patch("mlflow.log_artifacts")
        mocker.patch("mlflow.log_artifact")

        local_copy = tmp_path / "serving_model"
        build_serving_model(
            model_path=str(model_file),
            preprocessor_path=str(preproc_file),
            run_id="fake-run",
            mlflow_uri="http://localhost:5000",
            sample_input_path=str(sample_csv),
            local_copy_path=str(local_copy),
        )

        assert (local_copy / "input_example.json").exists()
        assert (local_copy / "serving_input_example.json").exists()


class TestTransformerPatternArtifacts:
    """The run also carries the bare estimator and the preprocessor as plain
    artifacts, the two storageUris of the transformer example (JDH-425)."""

    def _build(
        self, tmp_path, trained_rf, fitted_preprocessor, iris_features, mocker, *, with_preprocessor
    ):
        import joblib

        from pipelines.training.src.build_serving_model import build_serving_model

        model_file = tmp_path / "model.joblib"
        joblib.dump(trained_rf, model_file)
        preproc_file = None
        if with_preprocessor:
            preproc_file = tmp_path / "preprocessor.joblib"
            joblib.dump(fitted_preprocessor, preproc_file)
        sample_csv = tmp_path / "input.csv"
        iris_features.head(3).to_csv(sample_csv, index=False)

        mocker.patch("mlflow.set_tracking_uri")
        mocker.patch("mlflow.start_run")
        mocker.patch("mlflow.pyfunc.log_model")
        log_artifacts = mocker.patch("mlflow.log_artifacts")
        log_artifact = mocker.patch("mlflow.log_artifact")

        result = build_serving_model(
            model_path=str(model_file),
            preprocessor_path=str(preproc_file) if preproc_file else None,
            run_id="fake-run",
            mlflow_uri="http://localhost:5000",
            sample_input_path=str(sample_csv),
        )
        return result, log_artifacts, log_artifact, preproc_file

    def test_bare_model_is_a_loadable_sklearn_flavour_without_signature(
        self, tmp_path, trained_rf, fitted_preprocessor, iris_features, mocker
    ):
        import mlflow

        result, log_artifacts, log_artifact, preproc_file = self._build(
            tmp_path, trained_rf, fitted_preprocessor, iris_features, mocker, with_preprocessor=True
        )

        assert result.bare_model_artifact_path == "bare_model"
        assert result.preprocessor_artifact_path == "preprocessor"
        log_artifacts.assert_called_once()
        saved_dir, kwargs = log_artifacts.call_args.args[0], log_artifacts.call_args.kwargs
        assert kwargs == {"artifact_path": "bare_model"}
        # The temporary directory is gone by now; the call must have pointed
        # at a directory named after the artifact path.
        assert os.path.basename(saved_dir) == "bare_model"
        log_artifact.assert_called_once_with(str(preproc_file), artifact_path="preprocessor")

        # Save the same way the code does and prove the flavour loads and
        # scores a positional (transformed) tensor, which is what the
        # transformer forwards: no signature, no column names required.
        bare_dir = tmp_path / "bare_model"
        mlflow.sklearn.save_model(trained_rf, str(bare_dir), serialization_format="cloudpickle")
        loaded = mlflow.pyfunc.load_model(str(bare_dir))
        assert loaded.metadata.signature is None
        # .to_numpy(): MLServer's np codec hands the model an ndarray, not the
        # pandas-output DataFrame the fixture's preprocessor returns.
        transformed = fitted_preprocessor.transform(iris_features.head(2)).to_numpy()
        assert len(loaded.predict(transformed)) == 2

    def test_no_preprocessor_logs_only_the_bare_model(
        self, tmp_path, trained_rf, fitted_preprocessor, iris_features, mocker
    ):
        result, log_artifacts, log_artifact, _ = self._build(
            tmp_path,
            trained_rf,
            fitted_preprocessor,
            iris_features,
            mocker,
            with_preprocessor=False,
        )

        assert result.has_preprocessor is False
        assert result.preprocessor_artifact_path is None
        log_artifacts.assert_called_once()
        log_artifact.assert_not_called()
