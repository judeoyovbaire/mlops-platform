"""
Fetch and validate a pretrained model from HuggingFace Hub.

This module downloads a model and tokenizer from HuggingFace Hub,
runs a sanity inference to confirm the model works, and saves the
artifacts for downstream registration.
"""

import argparse
import json
import os
import sys
from dataclasses import asdict, dataclass

from huggingface_hub import model_info
from transformers import pipeline

try:
    from pipelines.shared.logging_utils import get_logger
except ImportError:
    from shared.logging_utils import get_logger  # type: ignore[no-redef]

logger = get_logger(__name__)

# Default test inputs per task type
DEFAULT_TEST_INPUTS: dict[str, str] = {
    "text-classification": "I absolutely love this product, it works great!",
    "sentiment-analysis": "I absolutely love this product, it works great!",
    "fill-mask": "The capital of France is [MASK].",
    "text-generation": "Once upon a time",
    "token-classification": "My name is Sarah and I live in London.",
    "question-answering": "What is the capital of France?",
    "summarization": "Machine learning is a branch of artificial intelligence.",
    "translation_en_to_fr": "Hello, how are you?",
}


@dataclass
class FetchResult:
    """Result of fetching a pretrained model."""

    model_id: str
    task: str
    model_dir: str
    num_parameters: int | None
    pipeline_tag: str | None
    test_input: str
    test_output: str
    success: bool
    # Supply chain: the ref the caller asked for and the commit SHA it
    # resolved to. Downstream steps and MLflow lineage use the SHA only.
    requested_revision: str | None = None
    resolved_revision: str | None = None
    error_message: str | None = None


def fetch_model(
    model_id: str,
    output_dir: str,
    task: str = "text-classification",
    revision: str | None = None,
    test_input: str | None = None,
) -> FetchResult:
    """Download a pretrained model from HuggingFace Hub and validate it.

    Downloads the model and tokenizer, runs a sanity inference to confirm
    the pipeline works, and writes metadata for downstream steps.

    Args:
        model_id: HuggingFace model identifier (e.g. "distilbert/distilbert-base-uncased-finetuned-sst-2-english").
        output_dir: Directory to save model artifacts and metadata.
        task: HuggingFace pipeline task (default: "text-classification").
        revision: Ref to fetch (branch, tag, or commit SHA). Whatever is
            given, it is RESOLVED to a commit SHA before download - HF model
            repos are mutable git refs, the model-artifact equivalent of a
            :main image tag. Default None resolves the repo's default branch.
        test_input: Custom test input string. If None, a default for the task is used.

    Returns:
        FetchResult with model metadata, the resolved revision SHA, and
        validation output.

    Raises:
        RuntimeError: If revision resolution, download, or inference fails.
    """
    logger.info(f"Fetching model '{model_id}' for task '{task}'")

    os.makedirs(output_dir, exist_ok=True)

    # Resolve the ref to a commit SHA - a HARD gate, not best-effort. All
    # downloads below pin to this SHA and it travels to MLflow as lineage.
    try:
        info = model_info(model_id, revision=revision)
    except Exception as e:
        raise RuntimeError(
            f"Could not resolve '{model_id}' (revision={revision!r}) on the "
            f"Hub: {e}. Fetch requires resolvable model metadata - the "
            f"resolved commit SHA is the model's supply-chain identity."
        ) from e
    resolved_revision = getattr(info, "sha", None)
    if not resolved_revision:
        raise RuntimeError(f"Hub returned no commit SHA for '{model_id}' (revision={revision!r})")
    logger.info(f"Resolved revision: {revision or '(default branch)'} -> {resolved_revision}")

    num_parameters = getattr(info, "safetensors", None)
    if num_parameters and hasattr(num_parameters, "total"):
        num_parameters = num_parameters.total
    else:
        num_parameters = None
    pipeline_tag = getattr(info, "pipeline_tag", None)
    logger.info(f"Model info: pipeline_tag={pipeline_tag}, parameters={num_parameters}")

    # Build the pipeline (downloads model + tokenizer), pinned to the SHA.
    # use_safetensors: refuse pickle-based .bin weights - loading them
    # executes arbitrary code. trust_remote_code=False is the library
    # default but the security posture here is explicit, not implied.
    logger.info(f"Downloading model and tokenizer for '{model_id}@{resolved_revision[:12]}'...")
    try:
        pipe = pipeline(  # type: ignore[call-overload]  # task is a runtime str, overloads expect Literal
            task=task,
            model=model_id,
            revision=resolved_revision,
            trust_remote_code=False,
            model_kwargs={
                "cache_dir": os.path.join(output_dir, "cache"),
                "use_safetensors": True,
            },
        )
    except Exception as e:
        raise RuntimeError(f"Failed to download model '{model_id}': {e}") from e

    logger.info("Model downloaded successfully")

    # Run sanity inference
    if test_input is None:
        test_input = DEFAULT_TEST_INPUTS.get(task, "Hello world")

    logger.info(f"Running sanity inference: '{test_input[:80]}...'")
    try:
        result = pipe(test_input)
        test_output = json.dumps(result, default=str)
        logger.info(f"Inference output: {test_output[:200]}")
    except Exception as e:
        raise RuntimeError(f"Sanity inference failed for model '{model_id}': {e}") from e

    # Save model and tokenizer locally
    model_save_dir = os.path.join(output_dir, "model")
    os.makedirs(model_save_dir, exist_ok=True)
    pipe.model.save_pretrained(model_save_dir, safe_serialization=True)
    pipe.tokenizer.save_pretrained(model_save_dir)
    logger.info(f"Model saved to {model_save_dir}")

    # Belt and braces: the artifact that ships downstream must contain no
    # pickle-based weights, whatever the library defaults do.
    pickle_weights = [f for f in os.listdir(model_save_dir) if f.endswith(".bin")]
    if pickle_weights:
        raise RuntimeError(
            f"Pickle-based weight files in saved artifact: {pickle_weights}. "
            f"Only safetensors weights may be registered."
        )

    fetch_result = FetchResult(
        model_id=model_id,
        task=task,
        model_dir=model_save_dir,
        num_parameters=num_parameters,
        pipeline_tag=pipeline_tag or task,
        test_input=test_input,
        test_output=test_output,
        success=True,
        requested_revision=revision,
        resolved_revision=resolved_revision,
    )

    # Write metadata file for downstream steps
    metadata_path = os.path.join(output_dir, "metadata.json")
    with open(metadata_path, "w") as f:
        json.dump(asdict(fetch_result), f, indent=2)
    logger.info(f"Metadata written to {metadata_path}")

    return fetch_result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fetch pretrained model from HuggingFace Hub")
    parser.add_argument(
        "--model-id",
        required=True,
        help="HuggingFace model ID (e.g. distilbert/distilbert-base-uncased-finetuned-sst-2-english)",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory to save model artifacts",
    )
    parser.add_argument(
        "--task",
        default="text-classification",
        help="HuggingFace pipeline task (default: text-classification)",
    )
    parser.add_argument(
        "--revision",
        default=None,
        help=(
            "Ref to fetch (branch/tag/SHA) - always resolved to a commit SHA "
            "before download (default: repo default branch, resolved)"
        ),
    )
    parser.add_argument(
        "--test-input",
        default=None,
        help="Custom test input for sanity inference",
    )

    args = parser.parse_args()

    try:
        result = fetch_model(
            model_id=args.model_id,
            output_dir=args.output_dir,
            task=args.task,
            revision=args.revision,
            test_input=args.test_input,
        )
        print(
            f"Successfully fetched '{result.model_id}' "
            f"(task={result.task}, params={result.num_parameters})"
        )
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
