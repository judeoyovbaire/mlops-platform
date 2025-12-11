"""
Iris Classifier Model Server
Flask-based inference server compatible with KServe v2 protocol
"""

import os
import json
import logging
from flask import Flask, request, jsonify
import numpy as np
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global model instance
model = None
class_names = ["setosa", "versicolor", "virginica"]


def load_model():
    """Train and load the iris classifier model."""
    global model
    logger.info("Loading iris dataset and training model...")

    # Load data
    iris = load_iris()
    X, y = iris.data, iris.target

    # Train model
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)

    # Log accuracy
    accuracy = model.score(X_test, y_test)
    logger.info(f"Model trained with accuracy: {accuracy:.4f}")

    return model


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "healthy"})


@app.route("/v1/models/iris-classifier", methods=["GET"])
def model_metadata():
    """Return model metadata (KServe v1 protocol)."""
    return jsonify({
        "name": "iris-classifier",
        "versions": ["v1"],
        "platform": "sklearn",
        "inputs": [
            {
                "name": "input",
                "datatype": "FP32",
                "shape": [-1, 4]
            }
        ],
        "outputs": [
            {
                "name": "output",
                "datatype": "INT64",
                "shape": [-1]
            }
        ]
    })


@app.route("/v1/models/iris-classifier:predict", methods=["POST"])
def predict_v1():
    """KServe v1 inference protocol."""
    try:
        data = request.get_json()
        instances = data.get("instances", [])

        if not instances:
            return jsonify({"error": "No instances provided"}), 400

        # Convert to numpy array
        X = np.array(instances)

        # Make predictions
        predictions = model.predict(X).tolist()
        probabilities = model.predict_proba(X).tolist()

        return jsonify({
            "predictions": predictions,
            "probabilities": probabilities,
            "class_names": [class_names[p] for p in predictions]
        })

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/v2/models/iris-classifier/infer", methods=["POST"])
def predict_v2():
    """KServe v2 inference protocol (Open Inference Protocol)."""
    try:
        data = request.get_json()
        inputs = data.get("inputs", [])

        if not inputs:
            return jsonify({"error": "No inputs provided"}), 400

        # Extract data from v2 format
        input_data = inputs[0].get("data", [])
        shape = inputs[0].get("shape", [])

        # Reshape if needed
        X = np.array(input_data)
        if len(shape) == 2:
            X = X.reshape(shape)

        # Make predictions
        predictions = model.predict(X)
        probabilities = model.predict_proba(X)

        return jsonify({
            "model_name": "iris-classifier",
            "model_version": "v1",
            "outputs": [
                {
                    "name": "predictions",
                    "datatype": "INT64",
                    "shape": list(predictions.shape),
                    "data": predictions.tolist()
                },
                {
                    "name": "probabilities",
                    "datatype": "FP32",
                    "shape": list(probabilities.shape),
                    "data": probabilities.tolist()
                }
            ]
        })

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/", methods=["GET"])
def root():
    """Root endpoint with API information."""
    return jsonify({
        "name": "iris-classifier",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "metadata": "/v1/models/iris-classifier",
            "predict_v1": "/v1/models/iris-classifier:predict",
            "predict_v2": "/v2/models/iris-classifier/infer"
        }
    })


# Initialize model on startup
with app.app_context():
    load_model()

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
