"""Stand-in for the kserve package in tests that do not install it.

kserve is an image dependency (components/kserve-transformer/requirements.in),
not a dev dependency. These stubs mirror the parts of the SDK the transformer
touches, so the tests exercise the transformer's own logic and the real
InvalidInput -> 400 contract (a MagicMock cannot be raised).

tests/integration/test_transformer_v2_protocol.py runs the same code against
the real SDK when it is installed (see its docstring).
"""

import sys
import types
from unittest.mock import MagicMock


class InvalidInput(ValueError):
    """kserve.errors.InvalidInput: the server answers HTTP 400."""


class Model:
    def __init__(self, name: str):
        self.name = name
        self.ready = False


class InferInput:
    def __init__(self, name, shape, datatype, data=None, parameters=None):
        self.name = name
        self.shape = list(shape)
        self.datatype = datatype.upper()
        self.data = data
        self.parameters = parameters


class InferRequest:
    def __init__(self, model_name, infer_inputs, request_id=None, parameters=None):
        self.model_name = model_name
        self.inputs = infer_inputs
        self.id = request_id
        self.parameters = parameters


def install() -> types.ModuleType:
    """Register the stub kserve modules in sys.modules (idempotent).

    If the real kserve is already imported in this session (for example
    tests/integration/test_transformer_v2_protocol.py ran first in a venv
    that has it), it is left in place: the transformer tests then run
    against the real SDK, which they also support. Never replace a real
    module with a stub behind an importer's back.
    """
    if "kserve" in sys.modules:
        return sys.modules["kserve"]
    kserve = types.ModuleType("kserve")
    kserve.__stub__ = True
    kserve.Model = Model
    kserve.InferInput = InferInput
    kserve.InferRequest = InferRequest
    kserve.InferResponse = MagicMock
    kserve.ModelServer = MagicMock
    kserve.model_server = MagicMock()
    errors = types.ModuleType("kserve.errors")
    errors.InvalidInput = InvalidInput
    kserve.errors = errors
    sys.modules["kserve"] = kserve
    sys.modules["kserve.errors"] = errors
    return kserve
