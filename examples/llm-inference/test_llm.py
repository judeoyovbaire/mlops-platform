#!/usr/bin/env python3
"""
Test script for LLM inference with vLLM on KServe.

Usage:
    # Using kubectl port-forward
    kubectl port-forward svc/llm-mistral-predictor -n mlops 8080:80 &
    python test_llm.py

    # Using service URL directly
    python test_llm.py --url http://llm-mistral.mlops.svc.cluster.local

Requirements:
    pip install openai requests
"""

import argparse
import json
import time
from typing import Optional

import requests

# Optional: Use OpenAI client for cleaner interface
try:
    from openai import OpenAI

    HAS_OPENAI = True
except ImportError:
    HAS_OPENAI = False


def test_completions(base_url: str, model: str = "mistral-7b") -> dict:
    """Test the /v1/completions endpoint."""
    url = f"{base_url}/v1/completions"

    payload = {
        "model": model,
        "prompt": "Explain Kubernetes in one sentence:",
        "max_tokens": 100,
        "temperature": 0.7,
    }

    print(f"\n{'='*60}")
    print("Testing /v1/completions endpoint")
    print(f"{'='*60}")
    print(f"Prompt: {payload['prompt']}")

    start = time.time()
    response = requests.post(url, json=payload, timeout=120)
    elapsed = time.time() - start

    if response.status_code == 200:
        result = response.json()
        text = result["choices"][0]["text"]
        tokens = result["usage"]["completion_tokens"]

        print(f"\nResponse: {text}")
        print(f"\nTokens generated: {tokens}")
        print(f"Time: {elapsed:.2f}s")
        print(f"Tokens/sec: {tokens/elapsed:.1f}")
        return result
    else:
        print(f"Error: {response.status_code}")
        print(response.text)
        return {}


def test_chat_completions(base_url: str, model: str = "mistral-7b") -> dict:
    """Test the /v1/chat/completions endpoint."""
    url = f"{base_url}/v1/chat/completions"

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a helpful DevOps assistant."},
            {"role": "user", "content": "What is MLOps and why is it important?"},
        ],
        "max_tokens": 200,
        "temperature": 0.7,
    }

    print(f"\n{'='*60}")
    print("Testing /v1/chat/completions endpoint")
    print(f"{'='*60}")
    print(f"User: {payload['messages'][1]['content']}")

    start = time.time()
    response = requests.post(url, json=payload, timeout=120)
    elapsed = time.time() - start

    if response.status_code == 200:
        result = response.json()
        text = result["choices"][0]["message"]["content"]
        tokens = result["usage"]["completion_tokens"]

        print(f"\nAssistant: {text}")
        print(f"\nTokens generated: {tokens}")
        print(f"Time: {elapsed:.2f}s")
        print(f"Tokens/sec: {tokens/elapsed:.1f}")
        return result
    else:
        print(f"Error: {response.status_code}")
        print(response.text)
        return {}


def test_with_openai_client(base_url: str, model: str = "mistral-7b"):
    """Test using the OpenAI Python client."""
    if not HAS_OPENAI:
        print("OpenAI client not installed. Run: pip install openai")
        return

    print(f"\n{'='*60}")
    print("Testing with OpenAI Python client")
    print(f"{'='*60}")

    client = OpenAI(
        base_url=f"{base_url}/v1",
        api_key="not-needed",  # vLLM doesn't require API key
    )

    # Chat completion
    start = time.time()
    response = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "user", "content": "Write a haiku about Kubernetes."},
        ],
        max_tokens=50,
        temperature=0.8,
    )
    elapsed = time.time() - start

    print(f"Prompt: Write a haiku about Kubernetes.")
    print(f"\nResponse: {response.choices[0].message.content}")
    print(f"\nTokens: {response.usage.completion_tokens}")
    print(f"Time: {elapsed:.2f}s")


def test_streaming(base_url: str, model: str = "mistral-7b"):
    """Test streaming responses."""
    url = f"{base_url}/v1/chat/completions"

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "Count from 1 to 5 slowly."}],
        "max_tokens": 50,
        "stream": True,
    }

    print(f"\n{'='*60}")
    print("Testing streaming response")
    print(f"{'='*60}")
    print(f"Prompt: {payload['messages'][0]['content']}")
    print("\nStreaming: ", end="", flush=True)

    start = time.time()
    with requests.post(url, json=payload, stream=True, timeout=120) as response:
        for line in response.iter_lines():
            if line:
                line = line.decode("utf-8")
                if line.startswith("data: ") and not line.endswith("[DONE]"):
                    try:
                        data = json.loads(line[6:])
                        content = data["choices"][0]["delta"].get("content", "")
                        print(content, end="", flush=True)
                    except json.JSONDecodeError:
                        pass

    elapsed = time.time() - start
    print(f"\n\nTime: {elapsed:.2f}s")


def check_health(base_url: str) -> bool:
    """Check if the model server is healthy."""
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        return response.status_code == 200
    except requests.exceptions.RequestException:
        return False


def main():
    parser = argparse.ArgumentParser(description="Test LLM inference endpoint")
    parser.add_argument(
        "--url",
        default="http://localhost:8080",
        help="Base URL of the inference service",
    )
    parser.add_argument(
        "--model",
        default="mistral-7b",
        help="Model name (as configured in vLLM --served-model-name)",
    )
    parser.add_argument(
        "--test",
        choices=["completions", "chat", "openai", "streaming", "all"],
        default="all",
        help="Which test to run",
    )
    args = parser.parse_args()

    print(f"Testing LLM at: {args.url}")
    print(f"Model: {args.model}")

    # Health check
    print("\nChecking health...", end=" ")
    if check_health(args.url):
        print("OK")
    else:
        print("FAILED - Is the service running?")
        print("Try: kubectl port-forward svc/llm-mistral-predictor -n mlops 8080:80")
        return

    # Run tests
    if args.test in ["completions", "all"]:
        test_completions(args.url, args.model)

    if args.test in ["chat", "all"]:
        test_chat_completions(args.url, args.model)

    if args.test in ["openai", "all"]:
        test_with_openai_client(args.url, args.model)

    if args.test in ["streaming", "all"]:
        test_streaming(args.url, args.model)

    print(f"\n{'='*60}")
    print("All tests completed!")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
