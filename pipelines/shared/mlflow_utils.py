"""
Shared MLflow utilities for pipeline components.

This module provides timeout handling for MLflow operations to prevent
indefinite hangs when the tracking server is unreachable.
"""

from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FuturesTimeoutError
from typing import TypeVar

try:
    from pipelines.shared.exceptions import MLflowTimeoutError
except ImportError:
    from shared.exceptions import MLflowTimeoutError

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
    # Avoid the `with` context manager which calls shutdown(wait=True) on
    # exit — that blocks until the worker thread finishes, defeating the
    # timeout.  Instead, manage the executor lifecycle explicitly.
    executor = ThreadPoolExecutor(max_workers=1)
    try:
        future = executor.submit(fn)
        result = future.result(timeout=seconds)
    except FuturesTimeoutError as exc:
        future.cancel()
        raise MLflowTimeoutError(error_message) from exc
    finally:
        # shutdown(wait=False) allows the caller to proceed immediately.
        # The worker thread (if still blocked on I/O) is a daemon thread that
        # will be cleaned up when the process exits (Kubernetes pod termination).
        executor.shutdown(wait=False)
    return result
