"""Minimal _random shim for mpython (LCG-based)."""

_MODULUS = 2 ** 64
_MULTIPLIER = 6364136223846793005
_INCREMENT = 1


def _coerce_seed(value):
    if value is None:
        return 0
    if isinstance(value, (int, bool)):
        return int(value)
    if isinstance(value, (bytes, bytearray)):
        return int.from_bytes(value, "big", signed=False)
    if isinstance(value, str):
        return int.from_bytes(value.encode(), "utf-8", signed=False)
    return int(value)


class Random:
    def __init__(self, seed=None):
        self._state = 0
        self.seed(seed)

    def seed(self, a=None):
        self._state = _coerce_seed(a) % _MODULUS

    def getstate(self):
        return self._state

    def setstate(self, state):
        self._state = int(state) % _MODULUS

    def random(self):
        self._state = (_MULTIPLIER * self._state + _INCREMENT) % _MODULUS
        return self._state / _MODULUS

    def getrandbits(self, k):
        if k <= 0:
            return 0
        value = 0
        bits = 0
        while bits < k:
            self._state = (_MULTIPLIER * self._state + _INCREMENT) % _MODULUS
            value = (value << 64) | self._state
            bits += 64
        return value >> (bits - k)
