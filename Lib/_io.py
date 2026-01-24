"""Minimal stub of the CPython _io module for moonpython."""

DEFAULT_BUFFER_SIZE = 8192


class UnsupportedOperation(OSError):
    pass


class BlockingIOError(OSError):
    pass


class _IOBase:
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
    pass


class StringIO(_TextIOBase):
    def __init__(self, initial_value=""):
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
        self.buffer = buffer
        self.encoding = text_encoding(encoding)
        self.errors = errors or "strict"
        self.newline = newline
        self.line_buffering = line_buffering
        self.write_through = write_through

    def close(self):
        if hasattr(self.buffer, "close"):
            return self.buffer.close()
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
