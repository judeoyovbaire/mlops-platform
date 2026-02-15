"""
HuggingFace Pretrained Model Pipeline Source Module.

Pipeline steps for fetching, validating, and registering
pretrained models from HuggingFace Hub.
"""

try:
    from pipelines.pretrained.src.fetch_model import fetch_model
    from pipelines.pretrained.src.register_model import register_pretrained_model
except ImportError:
    from fetch_model import fetch_model  # type: ignore[no-redef]
    from register_model import register_pretrained_model  # type: ignore[no-redef]

__all__ = [
    "fetch_model",
    "register_pretrained_model",
]
