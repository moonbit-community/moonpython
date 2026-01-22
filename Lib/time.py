"""Minimal time shim for moonpython."""

__all__ = [
    "time",
    "perf_counter",
    "monotonic",
    "sleep",
]


def time():
    return 0.0


def perf_counter():
    return 0.0


def monotonic():
    return 0.0


def sleep(_seconds):
    return None
