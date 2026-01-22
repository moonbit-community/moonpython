"""Minimal _sha2 shim for mpython."""


def _mix_bytes(data):
    value = 0
    for b in data:
        value = (value * 1315423911 + b) % (1 << 64)
    return value


class _FakeHash:
    def __init__(self, data=b""):
        self._data = b""
        if data:
            self.update(data)

    def update(self, data):
        self._data += bytes(data)

    def digest(self):
        value = _mix_bytes(self._data)
        out = bytearray(64)
        for i in range(64):
            value = (value * 6364136223846793005 + 1442695040888963407 + i) % (1 << 64)
            out[i] = value & 0xFF
        return bytes(out)

    def hexdigest(self):
        return self.digest().hex()

    def copy(self):
        return _FakeHash(self._data)


def sha512(data=b""):
    return _FakeHash(data)
