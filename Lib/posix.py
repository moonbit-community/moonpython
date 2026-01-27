"""Minimal posix shim for moonpython (no real OS access)."""

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
    "F_OK",
    "R_OK",
    "W_OK",
    "X_OK",
    "error",
    "fsencode",
    "fsdecode",
    "fspath",
    "getcwd",
    "getpid",
    "cpu_count",
    "listdir",
    "stat",
    "stat_result",
    "lstat",
    "fstat",
    "open",
    "write",
    "close",
    "unlink",
    "remove",
    "mkdir",
    "rmdir",
    "terminal_size",
    "get_terminal_size",
    "urandom",
    "putenv",
    "unsetenv",
    "O_RDONLY",
    "O_WRONLY",
    "O_RDWR",
    "O_CREAT",
    "O_EXCL",
    "O_TRUNC",
    "O_APPEND",
    "read",
    "lseek",
    "fstat",
    "isatty",
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

def putenv(key, value):
    # Minimal compatibility shim.
    #
    # CPython's `os._Environ` calls `putenv()` and then updates the underlying
    # `posix.environ` mapping itself. In moonpython, that mapping is this
    # module-level `environ` dict, so mutating it here would result in double
    # updates and break deletions (see `os._Environ.__delitem__`).
    #
    # Keep this as a no-op: `os.environ[...] = ...` is the supported API.
    return None


def unsetenv(key):
    # See `putenv()` above: `os._Environ` mutates the underlying mapping.
    return None

F_OK = 0
X_OK = 1
W_OK = 2
R_OK = 4

O_RDONLY = 0
O_WRONLY = 1
O_RDWR = 2
O_CREAT = 0x40
O_EXCL = 0x80
O_TRUNC = 0x200
O_APPEND = 0x400

error = OSError
_have_functions = set()

class stat_result:
    _fields = (
        "st_mode",
        "st_ino",
        "st_dev",
        "st_nlink",
        "st_uid",
        "st_gid",
        "st_size",
        "st_atime",
        "st_mtime",
        "st_ctime",
    )
    n_sequence_fields = len(_fields)
    n_fields = len(_fields)
    n_unnamed_fields = 0
    __match_args__ = _fields

    def __init__(self, seq):
        self._seq = tuple(seq)

    def __iter__(self):
        return iter(self._seq)

    def __len__(self):
        return len(self._seq)

    def __getitem__(self, idx):
        return self._seq[idx]

    def __getattr__(self, name):
        if name in self._fields:
            return self[self._fields.index(name)]
        raise AttributeError(name)


class terminal_size:
    _fields = ("columns", "lines")
    n_sequence_fields = len(_fields)
    n_fields = len(_fields)
    n_unnamed_fields = 0
    __match_args__ = _fields

    def __init__(self, seq):
        self._seq = tuple(seq)

    def __iter__(self):
        return iter(self._seq)

    def __len__(self):
        return len(self._seq)

    def __getitem__(self, idx):
        return self._seq[idx]

    def __getattr__(self, name):
        if name in self._fields:
            return self[self._fields.index(name)]
        raise AttributeError(name)


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
    return __mpython_posix_getcwd()


def chdir(path):
    return __mpython_posix_chdir(path)


def getpid():
    return 1


def cpu_count():
    return 1


def get_terminal_size(fd=0):
    return (80, 24)


def listdir(path=curdir):
    return __mpython_posix_listdir(path)


def _raise_unavailable():
    raise FileNotFoundError("operation not supported")


def stat(path, *args, **kwargs):
    return stat_result(__mpython_posix_stat(path))


def lstat(path, *args, **kwargs):
    return stat(path, *args, **kwargs)


def fstat(fd, *args, **kwargs):
    return stat_result(__mpython_posix_fstat(fd))


def open(path, flags, mode=0o777, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_open(path, flags, mode)

def read(fd, n):
    return __mpython_posix_read(fd, n)

def lseek(fd, pos, how):
    return __mpython_posix_lseek(fd, pos, how)

def isatty(fd):
    return False

def write(fd, data):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_write(fd, data)


def close(fd):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_close(fd)


def unlink(path, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_unlink(path)


def remove(path, *args, **kwargs):
    return unlink(path, *args, **kwargs)

def mkdir(path, mode=0o777, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_mkdir(path, mode)


def rmdir(path, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_rmdir(path)


def urandom(n):
    if n < 0:
        raise ValueError("negative argument not allowed")
    return bytes([0]) * n
