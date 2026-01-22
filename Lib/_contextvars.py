"""Minimal pure-Python fallback for _contextvars."""

_MISSING = object()


class Token:
    MISSING = object()
    __slots__ = ("_var", "_context", "_old_value", "_used")

    def __init__(self, var, context, old_value):
        self._var = var
        self._context = context
        self._old_value = old_value
        self._used = False

    @property
    def var(self):
        return self._var

    @property
    def old_value(self):
        if self._old_value is _MISSING:
            return Token.MISSING
        return self._old_value

    @property
    def used(self):
        return self._used


class ContextVar:
    __slots__ = ("_name", "_default", "_has_default")

    def __init__(self, name, *, default=_MISSING):
        if not isinstance(name, str):
            raise TypeError("ContextVar name must be a str")
        hash(name)
        self._name = name
        if default is _MISSING:
            self._default = None
            self._has_default = False
        else:
            self._default = default
            self._has_default = True

    @property
    def name(self):
        return self._name

    def get(self, default=_MISSING):
        ctx = _current_context
        if self in ctx._data:
            return ctx._data[self]
        if default is not _MISSING:
            return default
        if self._has_default:
            return self._default
        raise LookupError("ContextVar has no value")

    def set(self, value):
        ctx = _current_context
        old_value = ctx._data.get(self, _MISSING)
        ctx._data[self] = value
        return Token(self, ctx, old_value)

    def reset(self, token):
        if not isinstance(token, Token) or token.var is not self:
            raise ValueError("Token was created by a different ContextVar")
        if token._context is not _current_context:
            raise ValueError("Token was created in a different Context")
        if token._used:
            raise RuntimeError("Token has already been used")
        if token._old_value is _MISSING:
            if self in _current_context._data:
                del _current_context._data[self]
        else:
            _current_context._data[self] = token._old_value
        token._used = True


class Context:
    __slots__ = ("_data", "_entered")

    def __init__(self):
        self._data = {}
        self._entered = False

    def run(self, func, *args, **kwargs):
        if self._entered:
            raise RuntimeError("Context is already entered")
        global _current_context
        prev = _current_context
        _current_context = self
        self._entered = True
        try:
            return func(*args, **kwargs)
        finally:
            self._entered = False
            _current_context = prev

    def copy(self):
        new_ctx = Context()
        new_ctx._data = dict(self._data)
        return new_ctx

    def get(self, var, default=None):
        if not isinstance(var, ContextVar):
            raise TypeError("ContextVar key was expected")
        if var in self._data:
            return self._data[var]
        return default

    def __getitem__(self, var):
        if not isinstance(var, ContextVar):
            raise TypeError("ContextVar key was expected")
        if var in self._data:
            return self._data[var]
        raise KeyError(var)

    def __contains__(self, var):
        if not isinstance(var, ContextVar):
            raise TypeError("ContextVar key was expected")
        return var in self._data

    def __len__(self):
        return len(self._data)

    def __iter__(self):
        return iter(self._data)

    def items(self):
        return list(self._data.items())

    def keys(self):
        return list(self._data.keys())

    def values(self):
        return list(self._data.values())

    def __eq__(self, other):
        if not isinstance(other, Context):
            return False
        return self._data == other._data


_current_context = Context()


def copy_context():
    return _current_context.copy()


__all__ = ["Context", "ContextVar", "Token", "copy_context"]
