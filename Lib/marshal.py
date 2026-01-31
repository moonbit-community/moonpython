"""Minimal marshal implementation for moonpython.

This is NOT a complete CPython marshal implementation (e.g. code objects are
unsupported). It is sufficient for basic stdlib usage and a subset of Lib/test.
"""

try:
    import types as _types
except Exception:  # pragma: no cover
    _CODE_TYPE = ()
else:
    _CODE_TYPE = _types.CodeType

version = 4


def dump(value, file, version=version):
    data = dumps(value, version=version)
    file.write(data)


def dumps(value, version=version):
    if version not in (0, 4):
        raise ValueError("unsupported marshal version")

    # Minimal code object support.
    #
    # CPython's marshal format is complex; moonpython only needs a stable
    # round-trip for the CodeType placeholders produced by builtin compile(),
    # so importlib can read/write .pyc-like caches.
    if isinstance(value, _CODE_TYPE):
        mode = getattr(value, "__mpython_mode__", "exec")
        filename = getattr(value, "co_filename", "<code>")
        source = getattr(value, "__mpython_source__", "")
        if not isinstance(mode, str):
            mode = "exec"
        if not isinstance(filename, str):
            filename = "<code>"
        if not isinstance(source, str):
            source = ""
        b_mode = mode.encode("utf-8")
        b_fn = filename.encode("utf-8")
        b_src = source.encode("utf-8")
        return (
            b"c"
            + len(b_mode).to_bytes(4, "little", signed=False)
            + b_mode
            + len(b_fn).to_bytes(4, "little", signed=False)
            + b_fn
            + len(b_src).to_bytes(4, "little", signed=False)
            + b_src
        )

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
    if tag == ord("c"):
        n_mode = int.from_bytes(read(4), "little", signed=False)
        mode = bytes(read(n_mode)).decode("utf-8")
        n_fn = int.from_bytes(read(4), "little", signed=False)
        filename = bytes(read(n_fn)).decode("utf-8")
        n_src = int.from_bytes(read(4), "little", signed=False)
        source = bytes(read(n_src)).decode("utf-8")
        return compile(source, filename, mode)
    if tag == ord("i"):
        return int.from_bytes(read(4), "little", signed=True)
    if tag == ord("s"):
        n = int.from_bytes(read(4), "little", signed=False)
        return bytes(read(n))
    if tag == ord("u"):
        n = int.from_bytes(read(4), "little", signed=False)
        return bytes(read(n)).decode("utf-8")

    raise ValueError("bad marshal data (unknown type code)")
