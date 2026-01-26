"""Minimal stub of the CPython _io module for moonpython."""

DEFAULT_BUFFER_SIZE = 8192


class UnsupportedOperation(OSError):
    pass


class BlockingIOError(OSError):
    pass


class _IOBase:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True

    def flush(self):
        return None

    # Minimal context manager support used by linecache/tokenize.
    def __enter__(self):
        return self

    def __exit__(self, *args):
        try:
            close = getattr(self, "close")
        except Exception:
            return None
        try:
            close()
        except Exception:
            pass
        return None


class _RawIOBase(_IOBase):
    pass


class _BufferedIOBase(_IOBase):
    pass


class _TextIOBase(_IOBase):
    pass


class FileIO(_RawIOBase):
    pass


class BytesIO(_BufferedIOBase):
    def __init__(self, initial_bytes=None):
        super().__init__()
        if initial_bytes is None:
            self._buffer = b""
        else:
            self._buffer = bytes(initial_bytes)
        self._pos = 0

    def getvalue(self):
        if self.closed:
            raise ValueError("getvalue on closed file")
        return self._buffer

    def getbuffer(self):
        if self.closed:
            raise ValueError("getbuffer on closed file")
        return memoryview(self._buffer)

    def read(self, size=-1):
        if self.closed:
            raise ValueError("read from closed file")
        if size is None:
            size = -1
        else:
            try:
                size_index = size.__index__
            except AttributeError:
                raise TypeError(f"{size!r} is not an integer")
            else:
                size = size_index()
        if size < 0:
            size = len(self._buffer) - self._pos
        if self._pos >= len(self._buffer):
            return b""
        end = min(len(self._buffer), self._pos + size)
        data = self._buffer[self._pos : end]
        self._pos = end
        return data

    def readline(self, size=-1):
        if self.closed:
            raise ValueError("read from closed file")
        if size is None:
            size = -1
        else:
            try:
                size_index = size.__index__
            except AttributeError:
                raise TypeError(f"{size!r} is not an integer")
            else:
                size = size_index()
        if self._pos >= len(self._buffer):
            return b""
        limit = len(self._buffer) if size < 0 else min(len(self._buffer), self._pos + size)
        end = limit
        for i in range(self._pos, limit):
            if self._buffer[i] == 10:  # '\n'
                end = i + 1
                break
        data = self._buffer[self._pos : end]
        self._pos = end
        return data

    def readlines(self, hint=-1):
        lines = []
        total = 0
        while True:
            line = self.readline()
            if line == b"":
                break
            lines.append(line)
            total += len(line)
            if hint >= 0 and total >= hint:
                break
        return lines

    def write(self, b):
        if self.closed:
            raise ValueError("write to closed file")
        data = bytes(b)
        pos = self._pos
        if pos > len(self._buffer):
            self._buffer = self._buffer + (b"\x00" * (pos - len(self._buffer)))
        self._buffer = self._buffer[:pos] + data + self._buffer[pos + len(data) :]
        self._pos = pos + len(data)
        return len(data)

    def seek(self, offset, whence=0):
        if self.closed:
            raise ValueError("seek on closed file")
        try:
            offset_index = offset.__index__
        except AttributeError:
            raise TypeError(f"{offset!r} is not an integer")
        else:
            offset = offset_index()
        if whence == 0:
            newpos = offset
        elif whence == 1:
            newpos = self._pos + offset
        elif whence == 2:
            newpos = len(self._buffer) + offset
        else:
            raise ValueError("invalid whence")
        if newpos < 0:
            raise ValueError("negative seek position")
        self._pos = newpos
        return self._pos

    def tell(self):
        return self._pos

    def truncate(self, size=None):
        if self.closed:
            raise ValueError("truncate on closed file")
        if size is None:
            size = self._pos
        else:
            try:
                size_index = size.__index__
            except AttributeError:
                raise TypeError(f"{size!r} is not an integer")
            else:
                size = size_index()
        if size < 0:
            raise ValueError("negative size value")
        if size < len(self._buffer):
            self._buffer = self._buffer[:size]
        elif size > len(self._buffer):
            self._buffer = self._buffer + (b"\x00" * (size - len(self._buffer)))
        if self._pos > size:
            self._pos = size
        return size

    def readable(self):
        return True

    def writable(self):
        return True

    def seekable(self):
        return True

    def __iter__(self):
        return self

    def __next__(self):
        line = self.readline()
        if line == b"":
            raise StopIteration
        return line


class StringIO(_TextIOBase):
    def __init__(self, initial_value=""):
        super().__init__()
        self._buffer = []
        if initial_value:
            self._buffer.append(str(initial_value))

    def write(self, s):
        text = str(s)
        self._buffer.append(text)
        return len(text)

    def getvalue(self):
        return "".join(self._buffer)

    def flush(self):
        return None


class BufferedReader(_BufferedIOBase):
    pass


class BufferedWriter(_BufferedIOBase):
    pass


class BufferedRWPair(_BufferedIOBase):
    pass


class BufferedRandom(_BufferedIOBase):
    pass


class TextIOWrapper(_TextIOBase):
    def __init__(
        self,
        buffer,
        encoding=None,
        errors=None,
        newline=None,
        line_buffering=False,
        write_through=False,
    ):
        super().__init__()
        self.buffer = buffer
        self.encoding = text_encoding(encoding)
        self.errors = errors or "strict"
        self.newline = newline
        self.line_buffering = line_buffering
        self.write_through = write_through

    def close(self):
        if hasattr(self.buffer, "close"):
            try:
                self.buffer.close()
            except Exception:
                pass
        super().close()
        return None

    def read(self, size=-1):
        data = self.buffer.read(size)
        if isinstance(data, bytes):
            return data.decode(self.encoding, self.errors)
        return str(data)

    def readline(self, size=-1):
        data = self.buffer.readline(size)
        if isinstance(data, bytes):
            return data.decode(self.encoding, self.errors)
        return str(data)

    def readlines(self):
        lines = []
        for line in self:
            lines.append(line)
        return lines

    def __iter__(self):
        return self

    def __next__(self):
        line = self.readline()
        if line == "":
            raise StopIteration
        return line


class IncrementalNewlineDecoder:
    def __init__(self, *args, **kwargs):
        pass


def text_encoding(encoding, stacklevel=2):
    if encoding:
        return encoding
    return "utf-8"


def open(*args, **kwargs):
    import builtins
    return builtins.open(*args, **kwargs)


def open_code(*args, **kwargs):
    raise UnsupportedOperation("open_code() not supported")
