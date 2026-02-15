"""
Shared MLflow utilities for pipeline components.

This module provides timeout handling for MLflow operations to prevent
indefinite hangs when the tracking server is unreachable.
"""

from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FuturesTimeoutError
from typing import TypeVar

try:
    from pipelines.training.src.exceptions import MLflowTimeoutError
except ImportError:
    from exceptions import MLflowTimeoutError

# Default timeout for MLflow connection (seconds)
MLFLOW_CONNECTION_TIMEOUT = 30

T = TypeVar("T")


def run_with_timeout(
    fn,
    *,
    seconds: int = MLFLOW_CONNECTION_TIMEOUT,
    error_message: str = "Operation timed out",
) -> T:
    """Execute *fn* in a thread and enforce a hard timeout.

    Unlike the previous ``mlflow_timeout`` context-manager (which only set a
    flag after the deadline but could not interrupt a blocking call), this
    function submits *fn* to a :class:`~concurrent.futures.ThreadPoolExecutor`
    and calls :meth:`Future.result` with *seconds* as the timeout.

    Args:
        fn: Zero-argument callable to execute.
        seconds: Maximum wall-clock seconds to wait (default: 30).
        error_message: Message for the :class:`MLflowTimeoutError` raised on timeout.

    Returns:
        The return value of *fn*.

    Raises:
        MLflowTimeoutError: If *fn* does not complete within *seconds*.
    """
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(fn)
        try:
            return future.result(timeout=seconds)
        except FuturesTimeoutError as exc:
            future.cancel()
            raise MLflowTimeoutError(error_message) from exc
