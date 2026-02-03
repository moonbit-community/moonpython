"""Minimal time shim for moonpython."""

__all__ = [
    "time",
    "ctime",
    "perf_counter",
    "monotonic",
    "sleep",
]


def time():
    return 0.0


def ctime(_seconds=None):
    # Minimal stub aligned with CPython's epoch representation.
    # time.ctime(0) -> "Thu Jan  1 00:00:00 1970"
    return "Thu Jan  1 00:00:00 1970"


def perf_counter():
    return 0.0


def monotonic():
    return 0.0


def sleep(_seconds):
    return None
