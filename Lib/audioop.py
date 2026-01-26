"""Shim for `audioop`.

CPython's `audioop` is a C extension. moonpython intentionally does not support
C extensions, and we currently do not provide a compatible pure-Python
implementation.
"""

raise ModuleNotFoundError("No module named 'audioop'", name="audioop")
