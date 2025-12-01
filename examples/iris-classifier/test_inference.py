#!/usr/bin/env python3
"""
Iris Classifier Inference Test Script

Tests the deployed KServe InferenceService with sample data.

Usage:
    python test_inference.py [--service-url URL]
"""

import argparse
import json
import subprocess
import sys

import requests


# Sample test data (Iris features: sepal_length, sepal_width, petal_length, petal_width)
TEST_SAMPLES = [
    {"features": [5.1, 3.5, 1.4, 0.2], "expected": "setosa"},
    {"features": [7.0, 3.2, 4.7, 1.4], "expected": "versicolor"},
    {"features": [6.3, 3.3, 6.0, 2.5], "expected": "virginica"},
]

SPECIES_MAP = {0: "setosa", 1: "versicolor", 2: "virginica"}


def get_service_url() -> str:
    """Get the KServe service URL from kubectl."""
    try:
        result = subprocess.run(
            [
                "kubectl", "get", "inferenceservice", "iris-classifier",
                "-n", "mlops",
                "-o", "jsonpath={.status.url}"
            ],
            capture_output=True,
            text=True,
            check=True
        )
        url = result.stdout.strip()
        if not url:
            raise ValueError("Service URL is empty. Is the InferenceService deployed?")
        return url
    except subprocess.CalledProcessError as e:
        print(f"Error getting service URL: {e}")
        print("Make sure the InferenceService is deployed:")
        print("  kubectl apply -f kserve-deployment.yaml")
        sys.exit(1)


def test_inference(service_url: str, features: list) -> dict:
    """Send inference request to the service."""
    url = f"{service_url}/v1/models/iris-classifier:predict"

    payload = {
        "instances": [features]
    }

    headers = {
        "Content-Type": "application/json"
    }

    response = requests.post(url, json=payload, headers=headers, timeout=30)
    response.raise_for_status()

    return response.json()


def run_tests(service_url: str) -> bool:
    """Run all test cases."""
    print(f"Testing service at: {service_url}")
    print("=" * 60)

    all_passed = True

    for i, sample in enumerate(TEST_SAMPLES, 1):
        features = sample["features"]
        expected = sample["expected"]

        print(f"\nTest {i}: Features = {features}")
        print(f"Expected: {expected}")

        try:
            result = test_inference(service_url, features)

            # Parse prediction
            predictions = result.get("predictions", [])
            if predictions:
                # Handle both numeric and string predictions
                pred = predictions[0]
                if isinstance(pred, int):
                    predicted = SPECIES_MAP.get(pred, str(pred))
                else:
                    predicted = str(pred)

                print(f"Predicted: {predicted}")

                if predicted.lower() == expected.lower():
                    print("✓ PASSED")
                else:
                    print("✗ FAILED")
                    all_passed = False
            else:
                print(f"Unexpected response format: {result}")
                all_passed = False

        except requests.exceptions.RequestException as e:
            print(f"✗ ERROR: {e}")
            all_passed = False

    print("\n" + "=" * 60)
    if all_passed:
        print("All tests PASSED!")
    else:
        print("Some tests FAILED!")

    return all_passed


def main():
    parser = argparse.ArgumentParser(description="Test Iris Classifier Inference")
    parser.add_argument(
        "--service-url",
        help="KServe service URL (auto-detected if not provided)"
    )
    parser.add_argument(
        "--local",
        action="store_true",
        help="Test against local MLflow model server"
    )
    args = parser.parse_args()

    if args.local:
        service_url = "http://localhost:5001"
        print("Testing against local MLflow model server...")
    elif args.service_url:
        service_url = args.service_url
    else:
        print("Auto-detecting KServe service URL...")
        service_url = get_service_url()

    success = run_tests(service_url)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()