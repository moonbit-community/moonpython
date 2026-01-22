"""Minimal stub for _tokenize."""


class TokenizerIter:
    def __init__(self, *args, **kwargs):
        self._done = False

    def __iter__(self):
        return self

    def __next__(self):
        if self._done:
            raise StopIteration
        self._done = True
        raise StopIteration
