"""Minimal stub of the CPython _io module for moonpython."""

DEFAULT_BUFFER_SIZE = 8192


class UnsupportedOperation(OSError):
    pass


class BlockingIOError(OSError):
    pass


class _IOBase:
    pass


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
    pass


class IncrementalNewlineDecoder:
    def __init__(self, *args, **kwargs):
        pass


def text_encoding(encoding, stacklevel=2):
    if encoding:
        return encoding
    return "utf-8"


def open(*args, **kwargs):
    raise UnsupportedOperation("open() not supported")


def open_code(*args, **kwargs):
    raise UnsupportedOperation("open_code() not supported")
