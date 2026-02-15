"""
OpenTelemetry tracing utilities for ML pipeline steps.

Provides a thin wrapper around the OTel SDK so each pipeline step
gets a properly configured ``Tracer`` that exports spans to the
cluster's OTel Collector (``otel-collector.monitoring:4317``).

Usage in a pipeline step::

    from tracing import get_tracer

    tracer = get_tracer("train-model")

    with tracer.start_as_current_span("fit") as span:
        span.set_attribute("n_estimators", 100)
        model.fit(X, y)

If the ``opentelemetry`` packages are not installed (e.g. local dev without
the OTel SDK) the module falls back to a no-op tracer so callers never need
to guard imports.
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING, Any

try:
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    _OTEL_AVAILABLE = True
except ImportError:  # pragma: no cover
    _OTEL_AVAILABLE = False

if TYPE_CHECKING:
    from opentelemetry.trace import Tracer

# Default collector endpoint (in-cluster)
_DEFAULT_ENDPOINT = "otel-collector.monitoring:4317"


def get_tracer(service_name: str = "ml-pipeline") -> Tracer:
    """Return a configured OTel ``Tracer``.

    The exporter endpoint is resolved from the ``OTEL_EXPORTER_OTLP_ENDPOINT``
    environment variable, falling back to the in-cluster default
    ``otel-collector.monitoring:4317``.

    If the OTel SDK is not installed, a no-op tracer is returned so callers
    can use ``tracer.start_as_current_span(...)`` unconditionally.

    Args:
        service_name: Logical name attached to every span (default: ``ml-pipeline``).

    Returns:
        An OpenTelemetry ``Tracer`` instance.
    """
    if not _OTEL_AVAILABLE:
        # Return a no-op tracer when the SDK is missing
        return trace.get_tracer(service_name) if "trace" in dir() else _NoOpTracer()  # type: ignore[return-value]

    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", _DEFAULT_ENDPOINT)

    resource = Resource.create({"service.name": service_name})
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=endpoint, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    return trace.get_tracer(service_name)


# ------------------------------------------------------------------
# Fallback no-op tracer for environments without the OTel SDK
# ------------------------------------------------------------------


class _NoOpSpan:
    """Minimal span stand-in."""

    def set_attribute(self, key: str, value: Any) -> None:  # noqa: ARG002
        pass

    def set_status(self, *args: Any, **kwargs: Any) -> None:  # noqa: ARG002
        pass

    def record_exception(self, exception: BaseException) -> None:  # noqa: ARG002
        pass

    def __enter__(self) -> _NoOpSpan:
        return self

    def __exit__(self, *args: Any) -> None:
        pass


class _NoOpTracer:
    """Minimal tracer stand-in that yields :class:`_NoOpSpan`."""

    def start_as_current_span(self, name: str, **kwargs: Any) -> _NoOpSpan:  # noqa: ARG002
        return _NoOpSpan()
