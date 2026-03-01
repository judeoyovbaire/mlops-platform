"""
Validate a pretrained HuggingFace model before registration.

This module loads saved model artifacts, runs inference on multiple
test inputs, checks output schema and latency, and writes a validation
result for downstream consumption.  It sits between the fetch-model
and register-model steps in the Argo DAG.
"""

import argparse
import json
import os
import sys
import time
from dataclasses import asdict, dataclass

from transformers import pipeline as hf_pipeline

try:
    from pipelines.shared.logging_utils import get_logger
except ImportError:
    from shared.logging_utils import get_logger  # type: ignore[no-redef]

logger = get_logger(__name__)

# Default test inputs for text-classification models
DEFAULT_VALIDATION_INPUTS = [
    "I absolutely love this product, it works great!",
    "This is the worst experience I have ever had.",
    "The weather today is partly cloudy with a chance of rain.",
    "I'm not sure how I feel about this new update.",
    "Excellent quality and fast shipping, highly recommend!",
]

# Maximum acceptable p95 latency per inference call (seconds)
DEFAULT_LATENCY_THRESHOLD = 5.0


@dataclass
class PretrainedValidationResult:
    """Result of pretrained model validation."""

    passed: bool
    model_id: str
    task: str
    num_inputs_tested: int
    num_successful: int
    num_failed: int
    avg_latency_seconds: float
    p95_latency_seconds: float
    latency_threshold: float
    schema_valid: bool
    checks: dict[str, bool]
    error_message: str | None = None


def validate_pretrained_model(
    metadata_path: str,
    output_path: str,
    test_inputs: list[str] | None = None,
    latency_threshold: float = DEFAULT_LATENCY_THRESHOLD,
) -> PretrainedValidationResult:
    """Validate a pretrained model by running inference on multiple inputs.

    Checks performed:
    1. **Inference success** — the model must produce output for all test inputs.
    2. **Output schema** — each output must contain ``label`` and ``score`` keys.
    3. **Latency** — p95 inference latency must be below the threshold.

    Args:
        metadata_path: Path to metadata.json from fetch_model step.
        output_path: Path to write the validation result JSON.
        test_inputs: Custom test input strings. If None, defaults are used.
        latency_threshold: Maximum acceptable p95 latency in seconds.

    Returns:
        PretrainedValidationResult with per-check status.

    Raises:
        RuntimeError: If the model cannot be loaded.
    """
    logger.info("Starting pretrained model validation")

    # Load metadata
    try:
        with open(metadata_path) as f:
            metadata = json.load(f)
    except FileNotFoundError as e:
        raise RuntimeError(f"Metadata file not found: {metadata_path}") from e
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid metadata JSON: {e}") from e

    model_id = metadata["model_id"]
    task = metadata["task"]
    model_dir = metadata["model_dir"]

    logger.info(f"Validating model: {model_id} (task={task})")

    # Load model pipeline
    try:
        pipe = hf_pipeline(task=task, model=model_dir, tokenizer=model_dir)
        logger.info("Loaded transformers pipeline from saved artifacts")
    except Exception as e:
        raise RuntimeError(f"Failed to load model for validation: {e}") from e

    # Determine test inputs
    if test_inputs is None:
        if task != "text-classification":
            logger.warning(
                f"Using default text-classification inputs for task '{task}'. "
                "Provide task-specific --test-inputs for accurate validation."
            )
        test_inputs = DEFAULT_VALIDATION_INPUTS

    # Run inference on all test inputs
    latencies: list[float] = []
    num_successful = 0
    num_failed = 0
    schema_valid = True

    for i, text in enumerate(test_inputs):
        try:
            start = time.monotonic()
            result = pipe(text)
            elapsed = time.monotonic() - start
            latencies.append(elapsed)
            num_successful += 1

            # Check output schema
            if isinstance(result, list) and len(result) > 0:
                entry = result[0]
                if not isinstance(entry, dict):
                    logger.warning(f"Input {i}: output entry is not a dict: {type(entry)}")
                    schema_valid = False
                elif "label" not in entry or "score" not in entry:
                    logger.warning(f"Input {i}: missing 'label' or 'score' keys: {entry.keys()}")
                    schema_valid = False
                else:
                    # Validate score range
                    score = entry.get("score")
                    if isinstance(score, int | float):
                        if not (0.0 <= score <= 1.0) or (
                            isinstance(score, float) and (score != score)
                        ):  # NaN check
                            schema_valid = False
                            logger.warning(f"Input {i}: score {score} outside [0, 1] or NaN")
            else:
                logger.warning(f"Input {i}: unexpected output format: {type(result)}")
                schema_valid = False

            logger.info(f"Input {i}: latency={elapsed:.3f}s, output={str(result)[:100]}")

        except Exception as e:
            logger.error(f"Input {i}: inference failed: {e}")
            num_failed += 1

    # Compute latency metrics
    avg_latency = sum(latencies) / len(latencies) if latencies else 0.0
    sorted_latencies = sorted(latencies)
    p95_index = max(0, int(len(sorted_latencies) * 0.95) - 1)
    p95_latency = sorted_latencies[p95_index] if sorted_latencies else 0.0

    # Evaluate checks
    all_passed = num_failed == 0
    latency_ok = p95_latency <= latency_threshold
    checks = {
        "all_inferences_passed": all_passed,
        "output_schema_valid": schema_valid,
        "latency_within_threshold": latency_ok,
    }
    passed = all(checks.values())

    logger.info(
        f"Validation {'PASSED' if passed else 'FAILED'}: "
        f"success={num_successful}/{len(test_inputs)}, "
        f"avg_latency={avg_latency:.3f}s, p95_latency={p95_latency:.3f}s, "
        f"checks={checks}"
    )

    result = PretrainedValidationResult(
        passed=passed,
        model_id=model_id,
        task=task,
        num_inputs_tested=len(test_inputs),
        num_successful=num_successful,
        num_failed=num_failed,
        avg_latency_seconds=round(avg_latency, 4),
        p95_latency_seconds=round(p95_latency, 4),
        latency_threshold=latency_threshold,
        schema_valid=schema_valid,
        checks=checks,
        error_message=None if passed else "Model did not pass validation gate",
    )

    # Write result for downstream consumption
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(asdict(result), f, indent=2)
    logger.info(f"Validation result written to {output_path}")

    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate pretrained HF model")
    parser.add_argument(
        "--metadata",
        required=True,
        help="Path to metadata.json from fetch step",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to write validation result JSON",
    )
    parser.add_argument(
        "--latency-threshold",
        type=float,
        default=DEFAULT_LATENCY_THRESHOLD,
        help=f"Max p95 latency in seconds (default: {DEFAULT_LATENCY_THRESHOLD})",
    )

    args = parser.parse_args()

    try:
        validation_result = validate_pretrained_model(
            metadata_path=args.metadata,
            output_path=args.output,
            latency_threshold=args.latency_threshold,
        )
        if validation_result.passed:
            print(
                f"Validation PASSED: {validation_result.num_successful}/{validation_result.num_inputs_tested} "
                f"inferences OK (p95={validation_result.p95_latency_seconds:.3f}s)"
            )
        else:
            print(
                f"Validation FAILED: {validation_result.error_message}",
                file=sys.stderr,
            )
            sys.exit(1)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
