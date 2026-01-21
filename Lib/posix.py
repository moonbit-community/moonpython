"""Minimal posix shim for mpython (no real OS access)."""

__all__ = [
    "name",
    "sep",
    "pathsep",
    "defpath",
    "linesep",
    "curdir",
    "pardir",
    "extsep",
    "altsep",
    "devnull",
    "environ",
    "error",
    "fsencode",
    "fsdecode",
    "fspath",
    "getcwd",
    "listdir",
    "stat",
    "lstat",
    "fstat",
    "open",
    "close",
]

name = "posix"
sep = "/"
pathsep = ":"
defpath = "/bin:/usr/bin"
linesep = "\n"
curdir = "."
pardir = ".."
extsep = "."
altsep = None
devnull = "/dev/null"

environ = {}

error = OSError
_have_functions = set()


def fspath(path):
    if isinstance(path, (str, bytes)):
        return path
    if hasattr(path, "__fspath__"):
        return path.__fspath__()
    raise TypeError("expected str, bytes, or os.PathLike object")


def fsencode(filename):
    if isinstance(filename, bytes):
        return filename
    if isinstance(filename, str):
        return filename.encode()
    return fspath(filename).encode()


def fsdecode(filename):
    if isinstance(filename, str):
        return filename
    if isinstance(filename, bytes):
        return filename.decode()
    value = fspath(filename)
    if isinstance(value, bytes):
        return value.decode()
    return value


def getcwd():
    return curdir


def listdir(path=curdir):
    return []


def _raise_unavailable():
    raise FileNotFoundError("operation not supported")


def stat(path, *args, **kwargs):
    _raise_unavailable()


def lstat(path, *args, **kwargs):
    _raise_unavailable()


def fstat(fd, *args, **kwargs):
    _raise_unavailable()


def open(path, flags, mode=0o777, *args, **kwargs):
    _raise_unavailable()


def close(fd):
    _raise_unavailable()
