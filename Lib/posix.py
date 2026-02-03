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
    "chdir",
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
    "rename",
    "replace",
    "mkdir",
    "rmdir",
    "utime",
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
        if name in ("st_atime_ns", "st_mtime_ns", "st_ctime_ns"):
            base = name[:-3]
            sec = self[self._fields.index(base)]
            return int(sec) * 1_000_000_000
        raise AttributeError(name)

    def __repr__(self):
        return f"posix.stat_result({self._seq!r})"

    def __eq__(self, other):
        if isinstance(other, stat_result):
            return self._seq == other._seq
        if isinstance(other, tuple):
            return self._seq == other
        return NotImplemented


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


def _checked_path(path):
    # CPython raises ValueError for embedded NUL characters. Some higher-level
    # APIs (e.g. pathlib.Path.exists()) rely on this to return False rather
    # than silently truncating the path.
    p = fspath(path)
    if isinstance(p, str):
        if "\x00" in p:
            raise ValueError("embedded null character")
    elif isinstance(p, (bytes, bytearray)):
        if b"\x00" in bytes(p):
            raise ValueError("embedded null character")
    return p


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
    return __mpython_posix_listdir(_checked_path(path))


def _raise_unavailable():
    raise FileNotFoundError("operation not supported")


def stat(path, *args, **kwargs):
    p = _checked_path(path)
    seq = list(__mpython_posix_stat(p))
    # On many platforms, /dev/null is a character device. Moonpython's runtime
    # stat backend may report it as a regular file; adjust so pathlib tests can
    # detect it as a char device.
    if isinstance(p, str) and p == devnull and seq:
        # S_IFCHR (0o020000) + preserve permission bits.
        seq[0] = (seq[0] & 0o7777) | 0o020000
    return stat_result(seq)


def lstat(path, *args, **kwargs):
    return stat(path, *args, **kwargs)


def fstat(fd, *args, **kwargs):
    return stat_result(__mpython_posix_fstat(fd))


def open(path, flags, mode=0o777, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_open(_checked_path(path), flags, mode)

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
    return __mpython_posix_unlink(_checked_path(path))


def remove(path, *args, **kwargs):
    return unlink(path, *args, **kwargs)

def rename(src, dst, *args, **kwargs):
    # Minimal shim: emulate rename() without host support for atomic renames.
    #
    # Supports both files and directories (sufficient for pathlib/glob tests).
    import builtins as _builtins
    import stat as _stat

    src = fspath(src)
    dst = fspath(dst)

    def _join(a, b):
        if not a:
            return b
        if a.endswith("/"):
            return a + b
        return a + "/" + b

    def _move_dir(src_dir, dst_dir):
        mkdir(dst_dir)
        for name in listdir(src_dir):
            s = _join(src_dir, name)
            d = _join(dst_dir, name)
            if _stat.S_ISDIR(stat(s).st_mode):
                _move_dir(s, d)
            else:
                with _builtins.open(s, "rb") as f:
                    data = f.read()
                with _builtins.open(d, "wb") as f:
                    f.write(data)
                unlink(s)
        rmdir(src_dir)

    mode = stat(src).st_mode
    if _stat.S_ISDIR(mode):
        _move_dir(src, dst)
        return None

    with _builtins.open(src, "rb") as f:
        data = f.read()
    try:
        unlink(dst)
    except FileNotFoundError:
        pass
    with _builtins.open(dst, "wb") as f:
        f.write(data)
    unlink(src)


def replace(src, dst, *args, **kwargs):
    return rename(src, dst, *args, **kwargs)

def mkdir(path, mode=0o777, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_mkdir(_checked_path(path), mode)


def rmdir(path, *args, **kwargs):
    # Backed by host filesystem helpers in the interpreter runtime.
    return __mpython_posix_rmdir(_checked_path(path))


def utime(path, times=None, *, ns=None, dir_fd=None, follow_symlinks=True):
    # Minimal shim for pathlib/shutil. Advanced options are not supported yet.
    if dir_fd is not None:
        raise NotImplementedError("os.utime(dir_fd=...) is not supported")
    if not follow_symlinks:
        raise NotImplementedError("os.utime(follow_symlinks=False) is not supported")
    if times is not None and ns is not None:
        raise ValueError("utime: you may specify either 'times' or 'ns', not both")

    atime = None
    mtime = None
    if ns is not None:
        atime_ns, mtime_ns = ns
        # Keep a coarse seconds resolution for now (sufficient for Lib/test).
        atime = None if atime_ns is None else int(atime_ns) // 1_000_000_000
        mtime = None if mtime_ns is None else int(mtime_ns) // 1_000_000_000
    elif times is not None:
        atime, mtime = times

    return __mpython_posix_utime(path, atime, mtime)


def urandom(n):
    if n < 0:
        raise ValueError("negative argument not allowed")
    return bytes([0]) * n
