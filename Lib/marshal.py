"""Minimal marshal implementation for moonpython.

This is NOT a complete CPython marshal implementation (e.g. code objects are
unsupported). It is sufficient for basic stdlib usage and a subset of Lib/test.
"""

version = 4


def dump(value, file, version=version):
    data = dumps(value, version=version)
    file.write(data)


def dumps(value, version=version):
    if version not in (0, 4):
        raise ValueError("unsupported marshal version")

    if value is None:
        return b"N"
    if value is True:
        return b"T"
    if value is False:
        return b"F"

    if isinstance(value, int):
        if -(1 << 31) <= value < (1 << 31):
            return b"i" + int(value).to_bytes(4, "little", signed=True)
        raise ValueError("marshal int out of range")

    if isinstance(value, (bytes, bytearray, memoryview)):
        b = bytes(value)
        return b"s" + len(b).to_bytes(4, "little", signed=False) + b

    if isinstance(value, str):
        b = value.encode("utf-8")
        return b"u" + len(b).to_bytes(4, "little", signed=False) + b

    raise NotImplementedError(f"marshal.dumps unsupported type: {type(value).__name__}")


def load(file):
    data = file.read()
    return loads(data)


def loads(data):
    if not isinstance(data, (bytes, bytearray, memoryview)):
        raise TypeError("marshal.loads() argument must be a bytes-like object")

    buf = memoryview(data)
    pos = 0

    def read(n):
        nonlocal pos
        if pos + n > len(buf):
            raise EOFError("marshal.loads truncated data")
        out = buf[pos : pos + n]
        pos += n
        return out

    tag = int(read(1)[0])

    if tag == ord("N"):
        return None
    if tag == ord("T"):
        return True
    if tag == ord("F"):
        return False
    if tag == ord("i"):
        return int.from_bytes(read(4), "little", signed=True)
    if tag == ord("s"):
        n = int.from_bytes(read(4), "little", signed=False)
        return bytes(read(n))
    if tag == ord("u"):
        n = int.from_bytes(read(4), "little", signed=False)
        return bytes(read(n)).decode("utf-8")

    raise ValueError("bad marshal data (unknown type code)")
