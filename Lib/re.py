"""Minimal re shim for moonpython (limited regex engine)."""

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
    "purge",
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
    def __init__(self, string, start, end, groupdict=None, groups=None):
        self.string = string
        self._start = start
        self._end = end
        self._groupdict = groupdict or {}
        self._groups = tuple(groups or ())

    def group(self, key=0):
        if key == 0:
            return self.string[self._start:self._end]
        if isinstance(key, str):
            return self._groupdict.get(key)
        if isinstance(key, int):
            idx = key - 1
            if 0 <= idx < len(self._groups):
                return self._groups[idx]
            return None
        return None

    def groups(self, default=None):
        if default is None:
            return self._groups
        out = []
        for item in self._groups:
            if item is None:
                out.append(default)
            else:
                out.append(item)
        return tuple(out)

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
    def __init__(self, pattern, flags=0, matcher=None, compiled=None):
        self.pattern = pattern
        self.flags = flags
        self._matcher = matcher
        self._compiled = compiled

    def _run_match(self, string, pos=0, endpos=None):
        if self._compiled is not None:
            pos, endpos = _normalize_bounds(string, pos, endpos)
            m = _simple_regex_match(self._compiled, string, pos, endpos)
            return m
        if self._matcher is None:
            pos, endpos = _normalize_bounds(string, pos, endpos)
            if string.startswith(self.pattern, pos) and pos + len(self.pattern) <= endpos:
                return Match(string, pos, pos + len(self.pattern))
            return None
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
        pos, endpos = _normalize_bounds(string, pos, endpos)
        if self._compiled is not None:
            i = pos
            while i <= endpos:
                m = _simple_regex_match(self._compiled, string, i, endpos)
                if m is not None:
                    return m
                i += 1
            return None
        if self._matcher is not None:
            raise NotImplementedError("regex engine not available")
        idx = string.find(self.pattern, pos, endpos)
        if idx == -1:
            return None
        return Match(string, idx, idx + len(self.pattern))

    def findall(self, string, pos=0, endpos=None):
        # argparse help formatter uses this exact regexp to split usage.
        if self.pattern == (
            r"\(.*?\)+(?=\s|$)|"
            r"\[.*?\]+(?=\s|$)|"
            r"\S+"
        ):
            _, endpos = _normalize_bounds(string, pos, endpos)
            return string[pos:endpos].split()
        raise NotImplementedError("regex engine not available")

    def finditer(self, string, pos=0, endpos=None):
        raise NotImplementedError("regex engine not available")

    def sub(self, repl, string, count=0):
        # A few stdlib modules (argparse, gettext) only rely on a tiny subset.
        if self.pattern == r"\s+":
            return _sub_whitespace(repl, string, count=count)
        if self.pattern == r"\n\n\n+":
            return _sub_long_breaks(repl, string, count=count)
        if self.pattern == r"([\[(]) " and repl == r"\1":
            return _sub_trim_after_open_bracket(string, count=count)
        if self.pattern == r" ([\])])" and repl == r"\1":
            return _sub_trim_before_close_bracket(string, count=count)
        if self.pattern == r"[\[(] *[\])]" and repl == r"":
            return _sub_remove_empty_bracket_pairs(string, count=count)
        raise NotImplementedError("regex engine not available")

    def subn(self, repl, string, count=0):
        if self.pattern == r"\s+":
            return _subn_whitespace(repl, string, count=count)
        if self.pattern == r"\n\n\n+":
            return _subn_long_breaks(repl, string, count=count)
        if self.pattern == r"([\[(]) " and repl == r"\1":
            return _subn_trim_after_open_bracket(string, count=count)
        if self.pattern == r" ([\])])" and repl == r"\1":
            return _subn_trim_before_close_bracket(string, count=count)
        if self.pattern == r"[\[(] *[\])]" and repl == r"":
            return _subn_remove_empty_bracket_pairs(string, count=count)
        raise NotImplementedError("regex engine not available")

    def split(self, string, maxsplit=0):
        if self._compiled is None:
            raise NotImplementedError("regex engine not available")
        parts = []
        endpos = len(string)
        last = 0
        i = 0
        n = 0
        while i <= endpos and (maxsplit == 0 or n < maxsplit):
            m = _simple_regex_match(self._compiled, string, i, endpos)
            if m is None:
                i += 1
                continue
            start, end = m.start(), m.end()
            parts.append(string[last:start])
            for g in m.groups():
                parts.append(g)
            last = end
            i = end if end > start else start + 1
            n += 1
        parts.append(string[last:endpos])
        return parts


def compile(pattern, flags=0):
    if isinstance(pattern, Pattern):
        return pattern
    matcher = _select_matcher(pattern, flags)
    compiled = None
    if matcher is None:
        compiled = _try_compile_simple_regex(pattern)
    return Pattern(pattern, flags=flags, matcher=matcher, compiled=compiled)


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


def purge():
    # CPython clears the regex caches; this shim does not cache.
    return None


# ----------------------------
# Tiny "simple regex" engine
# ----------------------------

def _try_compile_simple_regex(pattern):
    # Only enable for the restricted syntax used by argparse nargs patterns.
    try:
        return _simple_regex_parse(pattern)
    except Exception:
        return None


def _simple_regex_parse(pattern):
    i = 0
    groups = []

    WORD_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    DIGIT_CHARS = set("0123456789")
    SPACE_CHARS = set(" \t\r\n\v\f")

    def parse_seq(stop=None):
        nonlocal i
        nodes = []
        while i < len(pattern) and (stop is None or pattern[i] != stop):
            c = pattern[i]
            if c == "^" and not nodes:
                i += 1
                node = ("anchor_start",)
                nodes.append(node)
                continue
            if c == "(":
                # capturing group or non-capturing group
                if pattern.startswith("(?:", i):
                    i += 3
                    inner = parse_seq(stop=")")
                    if i >= len(pattern) or pattern[i] != ")":
                        raise error("unbalanced group")
                    i += 1
                    node = ("group_nc", inner)
                else:
                    i += 1
                    inner = parse_seq(stop=")")
                    if i >= len(pattern) or pattern[i] != ")":
                        raise error("unbalanced group")
                    i += 1
                    gid = len(groups)
                    groups.append(gid)
                    node = ("group", gid, inner)
                node = parse_quant(node)
                nodes.append(node)
                continue
            if c == "[":
                i += 1
                negated = False
                if i < len(pattern) and pattern[i] == "^":
                    negated = True
                    i += 1
                chars = set()
                while i < len(pattern) and pattern[i] != "]":
                    ch = pattern[i]
                    if ch == "\\" and i + 1 < len(pattern):
                        i += 1
                        esc = pattern[i]
                        if esc == "w":
                            chars |= WORD_CHARS
                        elif esc == "d":
                            chars |= DIGIT_CHARS
                        elif esc == "s":
                            chars |= SPACE_CHARS
                        else:
                            chars.add(esc)
                        i += 1
                        continue
                    if i + 2 < len(pattern) and pattern[i + 1] == "-" and pattern[i + 2] != "]":
                        lo = ord(pattern[i])
                        hi = ord(pattern[i + 2])
                        if lo <= hi:
                            for code in range(lo, hi + 1):
                                chars.add(chr(code))
                        i += 3
                        continue
                    chars.add(ch)
                    i += 1
                if i >= len(pattern) or pattern[i] != "]":
                    raise error("unbalanced char class")
                i += 1
                node = ("class_neg", chars) if negated else ("class", chars)
                node = parse_quant(node)
                nodes.append(node)
                continue
            if c in ")?":
                break
            if c == "\\":
                i += 1
                if i >= len(pattern):
                    raise error("dangling escape")
                esc = pattern[i]
                i += 1
                if esc == "w":
                    node = ("class", WORD_CHARS)
                elif esc == "d":
                    node = ("class", DIGIT_CHARS)
                elif esc == "s":
                    node = ("class", SPACE_CHARS)
                elif esc == "A":
                    node = ("anchor_start",)
                elif esc == "Z":
                    node = ("anchor_end",)
                else:
                    node = ("lit", esc)
                node = parse_quant(node)
                nodes.append(node)
                continue
            # literal or dot
            i += 1
            node = ("dot",) if c == "." else ("lit", c)
            node = parse_quant(node)
            nodes.append(node)
        return nodes

    def parse_quant(node):
        nonlocal i
        if i >= len(pattern):
            return node
        c = pattern[i]
        if c == "?":
            i += 1
            return ("repeat", 0, 1, node)
        if c == "*":
            i += 1
            return ("repeat", 0, None, node)
        if c == "+":
            i += 1
            return ("repeat", 1, None, node)
        if c == "{":
            j = pattern.find("}", i)
            if j == -1:
                raise error("unbalanced quantifier")
            n_text = pattern[i + 1 : j]
            if not n_text.isdigit():
                raise error("unsupported quantifier")
            n = int(n_text)
            i = j + 1
            return ("repeat", n, n, node)
        return node

    ast = parse_seq()
    if i != len(pattern):
        raise error("unsupported regex")
    return (ast, len(groups))


def _simple_regex_match(compiled, string, pos, endpos):
    ast, group_count = compiled

    def match_nodes(nodes, si, captures):
        if not nodes:
            return si, captures
        node = nodes[0]
        rest = nodes[1:]
        kind = node[0]
        if kind == "anchor_start":
            if si == 0:
                return match_nodes(rest, si, captures)
            return None
        if kind == "anchor_end":
            if si == endpos:
                return match_nodes(rest, si, captures)
            return None
        if kind == "lit":
            if si < endpos and string[si] == node[1]:
                return match_nodes(rest, si + 1, captures)
            return None
        if kind == "dot":
            if si < endpos:
                return match_nodes(rest, si + 1, captures)
            return None
        if kind == "class":
            if si < endpos and string[si] in node[1]:
                return match_nodes(rest, si + 1, captures)
            return None
        if kind == "class_neg":
            if si < endpos and string[si] not in node[1]:
                return match_nodes(rest, si + 1, captures)
            return None
        if kind == "group_nc":
            inner = node[1]
            res = match_nodes(inner, si, captures)
            if res is None:
                return None
            si2, caps2 = res
            return match_nodes(rest, si2, caps2)
        if kind == "group":
            gid, inner = node[1], node[2]
            res = match_nodes(inner, si, captures)
            if res is None:
                return None
            si2, caps2 = res
            caps3 = list(caps2)
            caps3[gid] = string[si:si2]
            return match_nodes(rest, si2, tuple(caps3))
        if kind == "repeat":
            min_n, max_n, inner = node[1], node[2], node[3]
            # Try greedy, backtrack to satisfy the rest.
            matches = []
            si_cur = si
            caps_cur = captures
            n = 0
            while max_n is None or n < max_n:
                res = match_nodes([inner], si_cur, caps_cur)
                if res is None:
                    break
                si_next, caps_next = res
                if si_next == si_cur:
                    break
                matches.append((si_next, caps_next))
                si_cur, caps_cur = si_next, caps_next
                n += 1
            # include the "no more repeats" state as well
            for take in range(len(matches), -1, -1):
                if take < min_n:
                    continue
                if take == 0:
                    res = match_nodes(rest, si, captures)
                else:
                    res = match_nodes(rest, matches[take - 1][0], matches[take - 1][1])
                if res is not None:
                    return res
            return None
        return None

    res = match_nodes(ast, pos, tuple([None] * group_count))
    if res is None:
        return None
    end, caps = res
    return Match(string, pos, end, groups=caps)


def _sub_whitespace(repl, string, count=0):
    out, _ = _subn_whitespace(repl, string, count=count)
    return out


def _subn_whitespace(repl, string, count=0):
    if repl not in (" ", "") and not isinstance(repl, str):
        raise NotImplementedError("regex engine not available")
    out = []
    i = 0
    n = 0
    while i < len(string):
        if string[i] in " \t\r\n\v\f":
            j = i + 1
            while j < len(string) and string[j] in " \t\r\n\v\f":
                j += 1
            if count == 0 or n < count:
                out.append(repl)
                n += 1
            else:
                out.append(string[i:j])
            i = j
        else:
            out.append(string[i])
            i += 1
    return "".join(out), n


def _sub_long_breaks(repl, string, count=0):
    out, _ = _subn_long_breaks(repl, string, count=count)
    return out


def _subn_long_breaks(repl, string, count=0):
    out = []
    i = 0
    n = 0
    while i < len(string):
        if string.startswith("\n\n\n", i):
            j = i + 3
            while j < len(string) and string[j] == "\n":
                j += 1
            if count == 0 or n < count:
                out.append(repl)
                n += 1
            else:
                out.append(string[i:j])
            i = j
        else:
            out.append(string[i])
            i += 1
    return "".join(out), n


def _sub_trim_after_open_bracket(string, count=0):
    out, _ = _subn_trim_after_open_bracket(string, count=count)
    return out


def _subn_trim_after_open_bracket(string, count=0):
    out = []
    n = 0
    i = 0
    while i < len(string):
        c = string[i]
        if (c == "[" or c == "(") and i + 1 < len(string) and string[i + 1] == " " and (count == 0 or n < count):
            out.append(c)
            n += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out), n


def _sub_trim_before_close_bracket(string, count=0):
    out, _ = _subn_trim_before_close_bracket(string, count=count)
    return out


def _subn_trim_before_close_bracket(string, count=0):
    out = []
    n = 0
    i = 0
    while i < len(string):
        if string[i] == " " and i + 1 < len(string) and (string[i + 1] == "]" or string[i + 1] == ")") and (count == 0 or n < count):
            out.append(string[i + 1])
            n += 1
            i += 2
            continue
        out.append(string[i])
        i += 1
    return "".join(out), n


def _sub_remove_empty_bracket_pairs(string, count=0):
    out, _ = _subn_remove_empty_bracket_pairs(string, count=count)
    return out


def _subn_remove_empty_bracket_pairs(string, count=0):
    out = []
    n = 0
    i = 0
    while i < len(string):
        if (string[i] == "[" or string[i] == "("):
            j = i + 1
            while j < len(string) and string[j] == " ":
                j += 1
            if j < len(string) and ((string[i] == "[" and string[j] == "]") or (string[i] == "(" and string[j] == ")")) and (count == 0 or n < count):
                n += 1
                i = j + 1
                continue
        out.append(string[i])
        i += 1
    return "".join(out), n
