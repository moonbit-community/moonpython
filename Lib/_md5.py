"""Minimal _md5 shim for moonpython.

CPython exposes MD5 via the `_md5` C extension. moonpython doesn't support C
extensions, so we provide a tiny pure-Python substitute that is compatible
enough for stdlib imports.

This is NOT cryptographically secure and must not be used for security.
"""


def _mix_bytes(data):
    value = 0
    for b in data:
        value = (value * 1315423911 + b) % (1 << 64)
    return value


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
        data = self.digest()
        hex_chars = "0123456789abcdef"
        out = []
        for b in data:
            out.append(hex_chars[(b >> 4) & 0xF])
            out.append(hex_chars[b & 0xF])
        return "".join(out)

    def copy(self):
        return _FakeHash(self.name, self.digest_size, self.block_size, self._data)


def md5(data=b""):
    return _FakeHash("md5", 16, 64, data)

