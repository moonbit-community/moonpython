"""Minimal re shim for mpython (limited regex engine)."""

__all__ = [
    "compile",
    "match",
    "fullmatch",
    "search",
    "sub",
    "subn",
    "split",
    "findall",
    "finditer",
    "escape",
    "Pattern",
    "Match",
    "error",
    "IGNORECASE",
    "LOCALE",
    "MULTILINE",
    "DOTALL",
    "VERBOSE",
    "ASCII",
    "UNICODE",
]

# Flag values mirror CPython for compatibility (limited regex support).
IGNORECASE = 2
LOCALE = 4
MULTILINE = 8
DOTALL = 16
UNICODE = 32
VERBOSE = 64
ASCII = 256


class error(Exception):
    pass


class Match:
    def __init__(self, string, start, end, groupdict=None):
        self.string = string
        self._start = start
        self._end = end
        self._groupdict = groupdict or {}

    def group(self, key=0):
        if key == 0:
            return self.string[self._start:self._end]
        if isinstance(key, str):
            return self._groupdict.get(key)
        if isinstance(key, int):
            return None
        return None

    def groupdict(self):
        return dict(self._groupdict)

    def start(self, group=0):
        return self._start

    def end(self, group=0):
        return self._end

    def span(self, group=0):
        return (self._start, self._end)


def _normalize_bounds(string, pos, endpos):
    if pos is None:
        pos = 0
    if pos < 0:
        pos = 0
    if endpos is None or endpos > len(string):
        endpos = len(string)
    if endpos < pos:
        endpos = pos
    return pos, endpos


def _match_all_zeros(string, pos=0, endpos=None):
    pos, endpos = _normalize_bounds(string, pos, endpos)
    for ch in string[pos:endpos]:
        if ch != "0":
            return None
    return Match(string, pos, endpos)


def _match_exact_half(string, pos=0, endpos=None):
    pos, endpos = _normalize_bounds(string, pos, endpos)
    if pos >= endpos:
        return None
    if string[pos] != "5":
        return None
    for ch in string[pos + 1 : endpos]:
        if ch != "0":
            return None
    return Match(string, pos, endpos)


def _match_decimal_numeric(string, pos=0, endpos=None, flags=0):
    pos, endpos = _normalize_bounds(string, pos, endpos)
    s = string[pos:endpos]
    if not s:
        return None
    sign = None
    if s[0] in "+-":
        sign = s[0]
        s = s[1:]
    if not s:
        return None
    ignore_case = bool(flags & IGNORECASE)
    s_cmp = s.lower() if ignore_case else s

    if s_cmp == "inf" or s_cmp == "infinity":
        return Match(
            string,
            pos,
            endpos,
            {
                "sign": sign,
                "int": None,
                "frac": None,
                "exp": None,
                "signal": None,
                "diag": None,
            },
        )

    if s_cmp.startswith("snan") or s_cmp.startswith("nan"):
        signal = None
        if s_cmp.startswith("snan"):
            signal = "s"
            rest = s[4:]
        else:
            rest = s[3:]
        if rest and not rest.isdigit():
            return None
        return Match(
            string,
            pos,
            endpos,
            {
                "sign": sign,
                "int": None,
                "frac": None,
                "exp": None,
                "signal": signal,
                "diag": rest,
            },
        )

    i = 0
    while i < len(s) and s[i].isdigit():
        i += 1
    int_part = s[:i]
    rest = s[i:]
    frac_part = None
    if rest.startswith("."):
        j = 1
        while i + j < len(s) and s[i + j].isdigit():
            j += 1
        frac_part = s[i + 1 : i + j]
        rest = s[i + j :]
    has_digit = bool(int_part) or (frac_part is not None and frac_part != "")
    if not has_digit:
        return None

    exp = None
    if rest.startswith("e") or rest.startswith("E"):
        rest = rest[1:]
        if not rest:
            return None
        exp_sign = ""
        if rest[0] in "+-":
            exp_sign = rest[0]
            rest = rest[1:]
        if not rest or not rest[0].isdigit():
            return None
        k = 0
        while k < len(rest) and rest[k].isdigit():
            k += 1
        exp = exp_sign + rest[:k]
        rest = rest[k:]
    if rest:
        return None

    return Match(
        string,
        pos,
        endpos,
        {
            "sign": sign,
            "int": int_part,
            "frac": frac_part,
            "exp": exp,
            "signal": None,
            "diag": None,
        },
    )


def _match_format_spec(string, pos=0, endpos=None):
    pos, endpos = _normalize_bounds(string, pos, endpos)
    s = string[pos:endpos]
    i = 0
    groups = {
        "fill": None,
        "align": None,
        "sign": None,
        "no_neg_0": None,
        "alt": None,
        "zeropad": None,
        "minimumwidth": None,
        "thousands_sep": None,
        "precision": None,
        "type": None,
    }
    if i + 1 < len(s) and s[i + 1] in "<>=^":
        groups["fill"] = s[i]
        groups["align"] = s[i + 1]
        i += 2
    elif i < len(s) and s[i] in "<>=^":
        groups["align"] = s[i]
        i += 1

    if i < len(s) and s[i] in "+- ":
        groups["sign"] = s[i]
        i += 1
    if i < len(s) and s[i] == "z":
        groups["no_neg_0"] = "z"
        i += 1
    if i < len(s) and s[i] == "#":
        groups["alt"] = "#"
        i += 1
    if i < len(s) and s[i] == "0":
        groups["zeropad"] = "0"
        i += 1

    if i < len(s) and s[i].isdigit() and s[i] != "0":
        start = i
        while i < len(s) and s[i].isdigit():
            i += 1
        groups["minimumwidth"] = s[start:i]

    if i < len(s) and s[i] == ",":
        groups["thousands_sep"] = ","
        i += 1

    if i < len(s) and s[i] == ".":
        i += 1
        if i >= len(s):
            return None
        if s[i] == "0":
            groups["precision"] = "0"
            i += 1
        elif s[i].isdigit():
            start = i
            while i < len(s) and s[i].isdigit():
                i += 1
            groups["precision"] = s[start:i]
        else:
            return None

    if i < len(s) and s[i] in "eEfFgGn%":
        groups["type"] = s[i]
        i += 1

    if i != len(s):
        return None
    return Match(string, pos, endpos, groups)


def _select_matcher(pattern, flags):
    if pattern == "0*$":
        return _match_all_zeros
    if pattern == "50*$":
        return _match_exact_half
    if "(?P<sign>[-+])?" in pattern and "NaN" in pattern and "Inf" in pattern:
        return lambda s, pos=0, endpos=None: _match_decimal_numeric(
            s,
            pos=pos,
            endpos=endpos,
            flags=flags,
        )
    if "(?P<fill>.)?" in pattern and "(?P<align>" in pattern:
        return _match_format_spec
    return None


class Pattern:
    def __init__(self, pattern, flags=0, matcher=None):
        self.pattern = pattern
        self.flags = flags
        self._matcher = matcher

    def _run_match(self, string, pos=0, endpos=None):
        if self._matcher is None:
            raise NotImplementedError("regex engine not available")
        return self._matcher(string, pos=pos, endpos=endpos)

    def match(self, string, pos=0, endpos=None):
        return self._run_match(string, pos=pos, endpos=endpos)

    def fullmatch(self, string, pos=0, endpos=None):
        m = self._run_match(string, pos=pos, endpos=endpos)
        if m is None:
            return None
        _, endpos = _normalize_bounds(string, pos, endpos)
        if m.end() != endpos:
            return None
        return m

    def search(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def findall(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def finditer(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def sub(self, repl, string, count=0):
        raise NotImplementedError("regex engine not available")

    def subn(self, repl, string, count=0):
        raise NotImplementedError("regex engine not available")

    def split(self, string, maxsplit=0):
        raise NotImplementedError("regex engine not available")


def compile(pattern, flags=0):
    if isinstance(pattern, Pattern):
        return pattern
    matcher = _select_matcher(pattern, flags)
    return Pattern(pattern, flags=flags, matcher=matcher)


def match(pattern, string, flags=0):
    return compile(pattern, flags=flags).match(string)


def fullmatch(pattern, string, flags=0):
    return compile(pattern, flags=flags).fullmatch(string)


def search(pattern, string, flags=0):
    return compile(pattern, flags=flags).search(string)


def findall(pattern, string, flags=0):
    return compile(pattern, flags=flags).findall(string)


def finditer(pattern, string, flags=0):
    return compile(pattern, flags=flags).finditer(string)


def sub(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags=flags).sub(repl, string, count=count)


def subn(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags=flags).subn(repl, string, count=count)


def split(pattern, string, maxsplit=0, flags=0):
    return compile(pattern, flags=flags).split(string, maxsplit=maxsplit)


def escape(pattern):
    return pattern
