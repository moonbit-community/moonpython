"""Minimal pure-Python fallback for CPython's _typing C extension."""

def _idfunc(x):
    return x


class _BaseTypeVar:
    def __init__(
        self,
        name,
        *constraints,
        bound=None,
        covariant=False,
        contravariant=False,
        infer_variance=False,
    ):
        self.__name__ = name
        self.__constraints__ = constraints
        self.__bound__ = bound
        self.__covariant__ = covariant
        self.__contravariant__ = contravariant
        self.__infer_variance__ = infer_variance
        self.__module__ = "typing"

    def __repr__(self):
        return self.__name__

    def __hash__(self):
        return id(self)

    def __eq__(self, other):
        return self is other

    def __or__(self, other):
        import typing
        return typing._make_union(self, other)

    def __ror__(self, other):
        import typing
        return typing._make_union(other, self)


class TypeVar(_BaseTypeVar):
    pass


class ParamSpec(_BaseTypeVar):
    def __init__(self, name, **kwargs):
        super().__init__(name, **kwargs)
        self.args = ParamSpecArgs(self)
        self.kwargs = ParamSpecKwargs(self)


class TypeVarTuple(_BaseTypeVar):
    pass


class ParamSpecArgs:
    def __init__(self, origin):
        self.__origin__ = origin

    def __repr__(self):
        return f"{self.__origin__.__name__}.args"


class ParamSpecKwargs:
    def __init__(self, origin):
        self.__origin__ = origin

    def __repr__(self):
        return f"{self.__origin__.__name__}.kwargs"


class TypeAliasType:
    def __init__(self, name, value, *, type_params=()):
        self.__name__ = name
        self.__value__ = value
        self.__type_params__ = type_params
        self.__module__ = "typing"

    def __repr__(self):
        return self.__name__


class Generic:
    def __class_getitem__(cls, params):
        import typing
        return typing._GenericAlias(cls, params)
