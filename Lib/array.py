# Minimal pure-Python `array` shim for moonpython.
#
# CPython's `array` module is a C extension. moonpython doesn't support C
# extensions, but parts of the stdlib (e.g. multiprocessing) import `array`.
# This implementation aims to be "good enough" for stdlib imports and a small
# subset of behaviors, not full CPython compatibility.

from __future__ import annotations


def _itemsize(typecode: str) -> int:
    # Best-effort sizes for common codes used by stdlib.
    if typecode in ("b", "B"):
        return 1
    if typecode in ("h", "H"):
        return 2
    if typecode in ("i", "I", "l", "L"):
        return 4
    if typecode in ("q", "Q"):
        return 8
    if typecode in ("f",):
        return 4
    if typecode in ("d",):
        return 8
    # Unknown/unsupported: treat as bytes.
    return 1


class array:
    def __init__(self, typecode: str, initializer=None):
        if not isinstance(typecode, str) or len(typecode) == 0:
            raise TypeError("array() argument 1 must be a str")
        self.typecode = typecode
        self.itemsize = _itemsize(typecode)
        self._data = []
        if initializer is None:
            return
        if isinstance(initializer, array):
            self._data = list(initializer._data)
            return
        try:
            it = iter(initializer)
        except TypeError:
            raise TypeError("array() initializer must be iterable")
        for x in it:
            self.append(x)

    def __len__(self):
        return len(self._data)

    def __iter__(self):
        return iter(self._data)

    def __getitem__(self, idx):
        return self._data[idx]

    def __setitem__(self, idx, value):
        self._data[idx] = int(value)

    def append(self, value):
        self._data.append(int(value))

    def extend(self, iterable):
        for x in iterable:
            self.append(x)

    def tolist(self):
        return list(self._data)

    def __repr__(self):
        return "array(%r, %r)" % (self.typecode, self._data)


# CPython exposes this helper for pickling support (see pickle.py and tests).
# Our array is pure-Python, but providing the symbol avoids import failures.
def _array_reconstructor(arraytype, typecode, mformat_code, items):
    _ = mformat_code
    return arraytype(typecode, items)


ArrayType = array
