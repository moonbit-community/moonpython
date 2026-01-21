"""Minimal re shim for mpython (no regex engine)."""

__all__ = [
    "compile",
    "match",
    "fullmatch",
    "search",
    "sub",
    "subn",
    "split",
    "findall",
    "finditer",
    "escape",
    "Pattern",
    "Match",
    "error",
    "IGNORECASE",
    "LOCALE",
    "MULTILINE",
    "DOTALL",
    "VERBOSE",
    "ASCII",
    "UNICODE",
]

# Flag values mirror CPython for compatibility (no regex engine yet).
IGNORECASE = 2
LOCALE = 4
MULTILINE = 8
DOTALL = 16
UNICODE = 32
VERBOSE = 64
ASCII = 256


class error(Exception):
    pass


class Pattern:
    def __init__(self, pattern, flags=0):
        self.pattern = pattern
        self.flags = flags

    def match(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def fullmatch(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def search(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def findall(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def finditer(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def sub(self, repl, string, count=0):
        raise NotImplementedError("regex engine not available")

    def subn(self, repl, string, count=0):
        raise NotImplementedError("regex engine not available")

    def split(self, string, maxsplit=0):
        raise NotImplementedError("regex engine not available")


class Match:
    pass


def compile(pattern, flags=0):
    return Pattern(pattern, flags=flags)


def match(pattern, string, flags=0):
    return compile(pattern, flags=flags).match(string)


def fullmatch(pattern, string, flags=0):
    return compile(pattern, flags=flags).fullmatch(string)


def search(pattern, string, flags=0):
    return compile(pattern, flags=flags).search(string)


def findall(pattern, string, flags=0):
    return compile(pattern, flags=flags).findall(string)


def finditer(pattern, string, flags=0):
    return compile(pattern, flags=flags).finditer(string)


def sub(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags=flags).sub(repl, string, count=count)


def subn(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags=flags).subn(repl, string, count=count)


def split(pattern, string, maxsplit=0, flags=0):
    return compile(pattern, flags=flags).split(string, maxsplit=maxsplit)


def escape(pattern):
    return pattern
