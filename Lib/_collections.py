"""Minimal _collections shim for moonpython (no C extensions)."""

from operator import itemgetter

__all__ = [
    "defaultdict",
    "deque",
    "_deque_iterator",
    "OrderedDict",
    "_tuplegetter",
    "_count_elements",
]


class defaultdict(dict):
    def __init__(self, default_factory=None, *args, **kwargs):
        if default_factory is not None and not callable(default_factory):
            raise TypeError("default_factory must be callable or None")
        self.default_factory = default_factory
        super().__init__(*args, **kwargs)

    def __missing__(self, key):
        if self.default_factory is None:
            raise KeyError(key)
        value = self.default_factory()
        self[key] = value
        return value

    def __repr__(self):
        factory = self.default_factory
        if factory is None:
            f_repr = "None"
        else:
            f_repr = repr(factory)
        return f"defaultdict({f_repr}, {dict.__repr__(self)})"


class deque:
    def __init__(self, iterable=(), maxlen=None):
        if maxlen is not None:
            maxlen = int(maxlen)
            if maxlen < 0:
                raise ValueError("maxlen must be non-negative")
        self.maxlen = maxlen
        self._items = list(iterable)
        if self.maxlen is not None and len(self._items) > self.maxlen:
            self._items = self._items[-self.maxlen :]

    def __len__(self):
        return len(self._items)

    def __iter__(self):
        return iter(self._items)

    def __repr__(self):
        if self.maxlen is None:
            return f"deque({self._items!r})"
        return f"deque({self._items!r}, maxlen={self.maxlen!r})"

    def __eq__(self, other):
        if type(other) is deque:
            return self._items == other._items
        return NotImplemented

    def append(self, value):
        self._items.append(value)
        if self.maxlen is not None and len(self._items) > self.maxlen:
            del self._items[0]

    def appendleft(self, value):
        self._items.insert(0, value)
        if self.maxlen is not None and len(self._items) > self.maxlen:
            self._items.pop()

    def pop(self):
        if not self._items:
            raise IndexError("pop from an empty deque")
        return self._items.pop()

    def popleft(self):
        if not self._items:
            raise IndexError("pop from an empty deque")
        return self._items.pop(0)

    def clear(self):
        self._items.clear()

    def extend(self, iterable):
        for item in iterable:
            self.append(item)

    def extendleft(self, iterable):
        for item in iterable:
            self.appendleft(item)

    def __getitem__(self, index):
        return self._items[index]


class _deque_iterator:
    pass


class OrderedDict(dict):
    def __repr__(self):
        if not self:
            return "OrderedDict()"
        return f"OrderedDict({list(self.items())!r})"

    def copy(self):
        # CPython's OrderedDict.copy() preserves the OrderedDict type.
        return type(self)(self)

    def __reversed__(self):
        return reversed(list(self.keys()))

    def move_to_end(self, key, last=True):
        if key not in self:
            raise KeyError(key)
        value = self[key]
        del self[key]
        if last:
            self[key] = value
        else:
            items = [(key, value)]
            items.extend(list(self.items()))
            self.clear()
            for item_key, item_value in items:
                self[item_key] = item_value

    def popitem(self, last=True):
        if not self:
            raise KeyError("dictionary is empty")
        items = list(self.items())
        if last:
            key, value = items[-1]
        else:
            key, value = items[0]
        del self[key]
        return key, value


def _tuplegetter(index, doc):
    return property(itemgetter(index), doc=doc)


def _count_elements(mapping, iterable):
    mapping_get = mapping.get
    for elem in iterable:
        mapping[elem] = mapping_get(elem, 0) + 1
