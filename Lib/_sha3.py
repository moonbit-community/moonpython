"""Minimal _sha3 shim for moonpython.

CPython exposes SHA-3 and SHAKE via the `_sha3` C extension. moonpython doesn't
support C extensions, so we provide a tiny pure-Python substitute that is
compatible enough for stdlib imports.

This is NOT cryptographically secure and must not be used for security.
"""


def _mix_bytes(data):
    value = 0
    for b in data:
        value = (value * 1315423911 + b) % (1 << 64)
    return value


def _hexlify(data: bytes) -> str:
    hex_chars = "0123456789abcdef"
    out = []
    for b in data:
        out.append(hex_chars[(b >> 4) & 0xF])
        out.append(hex_chars[b & 0xF])
    return "".join(out)


class _FakeHash:
    def __init__(self, name: str, digest_size: int, block_size: int, data=b""):
        self.name = name
        self.digest_size = digest_size
        self.block_size = block_size
        self._data = b""
        if data:
            self.update(data)

    def update(self, data):
        self._data += bytes(data)

    def digest(self):
        value = _mix_bytes(self._data)
        out = []
        for i in range(self.digest_size):
            value = (value * 6364136223846793005 + 1442695040888963407 + i) % (1 << 64)
            out.append(value & 0xFF)
        return bytes(out)

    def hexdigest(self):
        return _hexlify(self.digest())

    def copy(self):
        return _FakeHash(self.name, self.digest_size, self.block_size, self._data)


class _FakeShake:
    def __init__(self, name: str, block_size: int, data=b""):
        self.name = name
        self.digest_size = 0
        self.block_size = block_size
        self._data = b""
        if data:
            self.update(data)

    def update(self, data):
        self._data += bytes(data)

    def digest(self, length):
        length = int(length)
        if length < 0:
            raise ValueError("length must be non-negative")
        value = _mix_bytes(self._data)
        out = []
        for i in range(length):
            value = (value * 6364136223846793005 + 1442695040888963407 + i) % (1 << 64)
            out.append(value & 0xFF)
        return bytes(out)

    def hexdigest(self, length):
        return _hexlify(self.digest(length))

    def copy(self):
        return _FakeShake(self.name, self.block_size, self._data)


def sha3_224(data=b""):
    return _FakeHash("sha3_224", 28, 144, data)


def sha3_256(data=b""):
    return _FakeHash("sha3_256", 32, 136, data)


def sha3_384(data=b""):
    return _FakeHash("sha3_384", 48, 104, data)


def sha3_512(data=b""):
    return _FakeHash("sha3_512", 64, 72, data)


def shake_128(data=b""):
    return _FakeShake("shake_128", 168, data)


def shake_256(data=b""):
    return _FakeShake("shake_256", 136, data)

