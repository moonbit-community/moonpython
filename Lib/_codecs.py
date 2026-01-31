# Minimal _codecs stub for moonpython.

_search_functions = []
_error_handlers = {}


def register(search_function):
    _search_functions.append(search_function)

def unregister(search_function):
    # Mirror CPython's registry behavior: remove the first matching entry.
    # This is enough for stdlib tests that register temporary codecs.
    try:
        _search_functions.remove(search_function)
    except ValueError:
        pass


def lookup(encoding):
    for func in _search_functions:
        result = func(encoding)
        if result is not None:
            return result
    raise LookupError("unknown encoding: " + str(encoding))


def encode(obj, encoding="utf-8", errors="strict"):
    if isinstance(obj, str):
        return bytes(obj, encoding, errors)
    return bytes(obj)


def decode(obj, encoding="utf-8", errors="strict"):
    if isinstance(obj, str):
        return obj
    encoding = str(encoding).lower().replace("_", "-")
    if encoding in ("latin-1", "latin1", "iso-8859-1", "iso8859-1"):
        # One byte -> one codepoint.
        out = ""
        for ch in obj:
            out = out + chr(ch if isinstance(ch, int) else ord(ch))
        return out
    if encoding not in ("utf-8", "utf8", "ascii"):
        raise LookupError("unknown encoding: " + str(encoding))
    if errors not in ("strict", "ignore", "replace"):
        raise LookupError("unknown error handler: " + str(errors))
    out = ""
    for ch in obj:
        if isinstance(ch, int):
            out = out + chr(ch)
        else:
            out = out + ch
    return out


def register_error(name, handler):
    _error_handlers[name] = handler


def lookup_error(name):
    if name in _error_handlers:
        return _error_handlers[name]
    raise LookupError("unknown error handler: " + str(name))


def strict_errors(exc):
    raise exc


def ignore_errors(exc):
    return ("", getattr(exc, "end", 0))


def replace_errors(exc):
    return ("?", getattr(exc, "end", 0))


def backslashreplace_errors(exc):
    return ("?", getattr(exc, "end", 0))


def xmlcharrefreplace_errors(exc):
    return ("?", getattr(exc, "end", 0))


def namereplace_errors(exc):
    return ("?", getattr(exc, "end", 0))


register_error("strict", strict_errors)
register_error("ignore", ignore_errors)
register_error("replace", replace_errors)
register_error("backslashreplace", backslashreplace_errors)
register_error("xmlcharrefreplace", xmlcharrefreplace_errors)
register_error("namereplace", namereplace_errors)
