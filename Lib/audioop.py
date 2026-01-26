# Minimal pure-Python `audioop` shim for moonpython.
#
# CPython's `audioop` is a C extension. A few stdlib tests (e.g. `test_aifc`)
# import it and use `byteswap`. Provide that and placeholder stubs for common
# helpers.

from __future__ import annotations


class error(Exception):
    pass


def byteswap(fragment, width):
    if not isinstance(fragment, (bytes, bytearray, memoryview)):
        raise TypeError("fragment must be bytes-like")
    if not isinstance(width, int):
        raise TypeError("width must be int")
    if width <= 0:
        raise error("width must be > 0")
    b = bytes(fragment)
    if len(b) % width != 0:
        raise error("not a whole number of frames")
    out = bytearray()
    for i in range(0, len(b), width):
        out.extend(b[i : i + width][::-1])
    return bytes(out)


def _unimplemented(name):
    raise NotImplementedError(f"audioop.{name} is not implemented in moonpython")


def alaw2lin(*args, **kwargs):
    _unimplemented("alaw2lin")


def ulaw2lin(*args, **kwargs):
    _unimplemented("ulaw2lin")


def adpcm2lin(*args, **kwargs):
    _unimplemented("adpcm2lin")


def lin2alaw(*args, **kwargs):
    _unimplemented("lin2alaw")


def lin2ulaw(*args, **kwargs):
    _unimplemented("lin2ulaw")


def lin2adpcm(*args, **kwargs):
    _unimplemented("lin2adpcm")

