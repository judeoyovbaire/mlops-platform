"""
Shared MLflow utilities for pipeline components.

This module provides timeout handling for MLflow operations to prevent
indefinite hangs when the tracking server is unreachable.
"""

import threading

try:
    from pipelines.training.src.exceptions import MLflowTimeoutError
except ImportError:
    from exceptions import MLflowTimeoutError

# Default timeout for MLflow connection (seconds)
MLFLOW_CONNECTION_TIMEOUT = 30


class mlflow_timeout:
    """Cross-platform context manager for timing out operations using threading."""

    def __init__(self, seconds: int, error_message: str = "Operation timed out"):
        self.seconds = seconds
        self.error_message = error_message
        self._timer: threading.Timer | None = None
        self._timed_out = False

    def _handle_timeout(self) -> None:
        self._timed_out = True

    def __enter__(self) -> "mlflow_timeout":
        self._timer = threading.Timer(self.seconds, self._handle_timeout)
        self._timer.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        if self._timer is not None:
            self._timer.cancel()
        if self._timed_out:
            raise MLflowTimeoutError(self.error_message)
