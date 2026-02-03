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
    "Scanner",
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
    "A",
    "I",
    "L",
    "M",
    "S",
    "U",
    "X",
    "NOFLAG",
]

# Flag values mirror CPython for compatibility (limited regex support).
IGNORECASE = 2
LOCALE = 4
MULTILINE = 8
DOTALL = 16
UNICODE = 32
VERBOSE = 64
ASCII = 256
NOFLAG = 0

# Common flag aliases (CPython-compatible).
A = ASCII
I = IGNORECASE
L = LOCALE
M = MULTILINE
S = DOTALL
U = UNICODE
X = VERBOSE


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

def _match_pkgutil_resolve_name(string, pos=0, endpos=None):
    # Support pkgutil.resolve_name() validation regex (Lib/pkgutil.py).
    # Expected formats:
    #   W(.W)*
    #   W(.W)*:(W(.W)*)?
    pos, endpos = _normalize_bounds(string, pos, endpos)
    s = string[pos:endpos]
    if not s:
        return None
    if s.count(":") > 1:
        return None
    if ":" in s:
        pkg, obj = s.split(":", 1)
        cln = ":" + obj if obj else ":"
        obj_val = obj if obj else None
    else:
        pkg = s
        cln = None
        obj_val = None

    def valid_dotted_words(text):
        if not text:
            return False
        parts = text.split(".")
        for part in parts:
            if not part:
                return False
            if part[0].isdigit():
                return False
            for ch in part:
                # \w with UNICODE in CPython includes many codepoints; for now we
                # accept ASCII word characters which is sufficient for stdlib.
                if not (ch.isalnum() or ch == "_"):
                    return False
        return True

    if not valid_dotted_words(pkg):
        return None
    if obj_val is not None and not valid_dotted_words(obj_val):
        return None

    return Match(string, pos, endpos, {"pkg": pkg, "cln": cln, "obj": obj_val})

def _match_tokenize_blank_re(string, pos=0, endpos=None):
    # Match bytes regexp used by Lib/tokenize.py:
    #   br'^[ \\t\\f]*(?:[#\\r\\n]|$)'
    pos, endpos = _normalize_bounds(string, pos, endpos)
    s = string[pos:endpos]
    if not isinstance(s, (bytes, bytearray)):
        return None
    i = 0
    while i < len(s) and s[i] in (9, 12, 32):  # \t, \f, space
        i += 1
    if i >= len(s):
        return Match(string, pos, endpos)
    if s[i] in (35, 10, 13):  # '#', '\n', '\r'
        return Match(string, pos, pos + i + 1)
    return None


def _match_json_hexdigits(string, pos=0, endpos=None):
    # Match: r'[0-9A-Fa-f]{4}'
    pos, endpos = _normalize_bounds(string, pos, endpos)
    if pos + 4 > endpos:
        return None
    for ch in string[pos : pos + 4]:
        if not ("0" <= ch <= "9" or "A" <= ch <= "F" or "a" <= ch <= "f"):
            return None
    return Match(string, pos, pos + 4)


def _match_json_whitespace(string, pos=0, endpos=None):
    # Match: r'[ \t\n\r]*'
    pos, endpos = _normalize_bounds(string, pos, endpos)
    i = pos
    while i < endpos and string[i] in " \t\n\r":
        i += 1
    return Match(string, pos, i)


def _match_json_stringchunk(string, pos=0, endpos=None):
    # Match: r'(.*?)(["\\\x00-\x1f])'
    #
    # Used heavily by Lib/json/decoder.py. A backtracking implementation of
    # `.*?` can be extremely slow; keep this linear-time.
    pos, endpos = _normalize_bounds(string, pos, endpos)
    i = pos
    while i < endpos:
        ch = string[i]
        if ch == '"' or ch == "\\" or ord(ch) <= 0x1F:
            content = string[pos:i]
            return Match(string, pos, i + 1, groups=(content, ch))
        i += 1
    return None


def _subn_remove_non_base64_bytes(repl, string, count=0):
    # Used by Lib/test/test_binascii.py to count valid base64 characters:
    #   re.sub(br'[^A-Za-z0-9/+]', br'', data)
    if not isinstance(string, (bytes, bytearray)):
        raise NotImplementedError("regex engine not available")
    if not isinstance(repl, (bytes, bytearray)):
        raise TypeError("replacement must be a bytes-like object")
    if repl not in (b"", bytearray(b"")):
        raise NotImplementedError("regex engine not available")
    allowed = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    out = bytearray()
    n = 0
    for b in bytes(string):
        if b in allowed:
            out.append(b)
        else:
            if count == 0 or n < count:
                n += 1
                # skip (remove)
            else:
                out.append(b)
    return (bytes(out), n)


def _select_matcher(pattern, flags):
    if isinstance(pattern, (bytes, bytearray)):
        if pattern == br'^[ \t\f]*(?:[#\r\n]|$)':
            return _match_tokenize_blank_re
        return None
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
    if (
        pattern.startswith("^(?P<pkg>")
        and "(?P<cln>:(?P<obj>" in pattern
        and pattern.endswith(")?$")
    ):
        return _match_pkgutil_resolve_name
    # json.decoder uses a few regular expressions heavily; special-case them to
    # avoid performance cliffs in the minimal regex engine.
    if pattern == r"[0-9A-Fa-f]{4}":
        return _match_json_hexdigits
    if pattern == r"[ \t\n\r]*":
        return _match_json_whitespace
    if pattern == r'(.*?)(["\\\x00-\x1f])':
        return _match_json_stringchunk
    return None


class Pattern:
    def __init__(self, pattern, flags=0, matcher=None, compiled=None):
        self.pattern = pattern
        self.flags = flags
        self._matcher = matcher
        self._compiled = compiled

    def scanner(self, string, pos=0, endpos=None):
        # CPython exposes Pattern.scanner() which returns a stateful scanner
        # object. Most stdlib usage only relies on `.pattern` and `.match()`.
        return _PatternScanner(self, string, pos=pos, endpos=endpos)

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
        # textwrap.dedent() uses this pattern to collect line indents.
        if self.pattern == "(^[ \t]*)(?:[^ \t\n])":
            pos, endpos = _normalize_bounds(string, pos, endpos)
            out = []
            i = pos
            while i <= endpos:
                line_end = string.find("\n", i, endpos)
                if line_end == -1:
                    line_end = endpos
                    has_newline = False
                else:
                    has_newline = True
                line = string[i:line_end]
                j = 0
                while j < len(line) and line[j] in " \t":
                    j += 1
                if j < len(line):
                    out.append(line[:j])
                if not has_newline:
                    break
                i = line_end + 1
            return out
        # doctest uses this pattern to collect leading spaces on non-blank lines:
        #   re.compile(r'^([ ]*)(?=\\S)', re.MULTILINE)
        if self.pattern == r"^([ ]*)(?=\S)" and (self.flags & MULTILINE):
            pos, endpos = _normalize_bounds(string, pos, endpos)
            out = []
            i = pos
            while i <= endpos:
                line_end = string.find("\n", i, endpos)
                if line_end == -1:
                    line_end = endpos
                    has_newline = False
                else:
                    has_newline = True
                line = string[i:line_end]
                j = 0
                while j < len(line) and line[j] == " ":
                    j += 1
                if j < len(line) and line[j] not in " \t\r\n\v\f":
                    out.append(line[:j])
                if not has_newline:
                    break
                i = line_end + 1
            return out
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
        if self.pattern == br'[^A-Za-z0-9/+]':
            return _subn_remove_non_base64_bytes(repl, string, count=count)[0]
        if self.pattern == r"\s+":
            return _sub_whitespace(repl, string, count=count)
        if self.pattern == "^[ \t]+$":
            return _sub_whitespace_only_lines(repl, string, count=count)
        if self.pattern.startswith("(?m)^") and repl == "":
            prefix = self.pattern[len("(?m)^") :]
            if prefix and all(ch in " \t" for ch in prefix):
                return _sub_strip_line_prefix(prefix, string, count=count)
        if (self.flags & MULTILINE) and self.pattern.startswith("^") and repl == "":
            prefix = self.pattern[1:]
            if prefix and all(ch in " \t" for ch in prefix):
                return _sub_strip_line_prefix(prefix, string, count=count)
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
        if self.pattern == br'[^A-Za-z0-9/+]':
            return _subn_remove_non_base64_bytes(repl, string, count=count)
        if self.pattern == r"\s+":
            return _subn_whitespace(repl, string, count=count)
        if self.pattern == "^[ \t]+$":
            return _subn_whitespace_only_lines(repl, string, count=count)
        if self.pattern.startswith("(?m)^") and repl == "":
            prefix = self.pattern[len("(?m)^") :]
            if prefix and all(ch in " \t" for ch in prefix):
                return _subn_strip_line_prefix(prefix, string, count=count)
        if (self.flags & MULTILINE) and self.pattern.startswith("^") and repl == "":
            prefix = self.pattern[1:]
            if prefix and all(ch in " \t" for ch in prefix):
                return _subn_strip_line_prefix(prefix, string, count=count)
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


class _PatternScanner:
    def __init__(self, pattern, string, pos=0, endpos=None):
        self.pattern = pattern
        self.string = string
        self.pos, self.endpos = _normalize_bounds(string, pos, endpos)

    def match(self):
        m = self.pattern.match(self.string, pos=self.pos, endpos=self.endpos)
        if m is not None:
            self.pos = m.end()
        return m

    def search(self):
        m = self.pattern.search(self.string, pos=self.pos, endpos=self.endpos)
        if m is not None:
            self.pos = m.end()
        return m


class Scanner:
    def __init__(self, lexicon, flags=0):
        # `lexicon` is a list of (pattern, action) pairs.
        self._lexicon = [(compile(pat, flags=flags), action) for (pat, action) in lexicon]
        # CPython exposes `Scanner.scanner` as a Pattern-like object supporting
        # `.scanner(text)`. Keep this compatible enough for `test_re`.
        self.scanner = compile("")

    def scan(self, string):
        pos = 0
        tokens = []
        while pos < len(string):
            for pat, action in self._lexicon:
                m = pat.match(string, pos=pos)
                if m is None:
                    continue
                token = m.group(0)
                if action is not None:
                    out = action(self, token) if callable(action) else action
                    if out is not None:
                        tokens.append(out)
                end = m.end()
                if end == pos:
                    # Avoid infinite loops on patterns that can match empty strings.
                    return tokens, string[pos:]
                pos = end
                break
            else:
                break
        return tokens, string[pos:]


def compile(pattern, flags=0):
    if isinstance(pattern, Pattern):
        return pattern
    if (
        isinstance(pattern, str)
        and "|" in pattern
        and all(part.startswith("(?s:") and part.endswith(r")\Z") for part in pattern.split("|"))
    ):
        # Support the (undocumented but relied-upon) behavior that multiple
        # fnmatch.translate() results can be joined with "|" and compiled as one
        # regex. This shim does not implement full alternation, so special-case
        # this common shape.
        parts = [compile(part, flags=flags) for part in pattern.split("|")]

        def _match_any(s, pos=0, endpos=None):
            for p in parts:
                m = p.match(s, pos=pos, endpos=endpos)
                if m is not None:
                    return m
            return None

        return Pattern(pattern, flags=flags, matcher=_match_any, compiled=None)
    if isinstance(pattern, str) and pattern.startswith("(?s:") and pattern.endswith(r")\Z"):
        # Common output of fnmatch.translate(): `(?s:...)\Z`.
        # Normalize a few constructs that this shim doesn't fully support.
        flags |= DOTALL
        inner = pattern[len("(?s:") : -len(r")\Z")]
        # Atomic groups and non-greedy quantifiers appear in fnmatch's output.
        # Approximate them with the supported subset.
        inner = inner.replace("(?>", "(?:")
        inner = inner.replace("*?", "*").replace("+?", "+").replace("??", "?")
        pattern = inner + r"\Z"
    if isinstance(pattern, str) and pattern.startswith("(?"):
        # Support leading inline flags like `(?i)pattern` used throughout the
        # CPython stdlib (e.g. assertRaisesRegex patterns).
        #
        # This shim only supports a restricted subset of the re syntax, so we
        # only parse the simple `(?flags)` prefix (no `:(...)` scoped groups).
        j = 2
        while j < len(pattern) and pattern[j].isalpha():
            j += 1
        if j < len(pattern) and pattern[j] == ")" and j > 2:
            flag_text = pattern[2:j]
            valid = True
            for ch in flag_text:
                if ch not in "aiLmsux":
                    valid = False
                    break
            if valid:
                for ch in flag_text:
                    if ch == "i":
                        flags |= IGNORECASE
                    elif ch == "m":
                        flags |= MULTILINE
                    elif ch == "s":
                        flags |= DOTALL
                    elif ch == "x":
                        flags |= VERBOSE
                    elif ch == "a":
                        flags |= ASCII
                    elif ch == "u":
                        flags |= UNICODE
                    elif ch == "L":
                        flags |= LOCALE
                pattern = pattern[j + 1 :]
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
    # Minimal re.escape() implementation.
    #
    # This shim intentionally supports only a subset of `re`, but callers
    # (notably unittest) still rely on `re.escape` to turn arbitrary strings
    # into literal patterns.
    if isinstance(pattern, (bytes, bytearray)):
        out = bytearray()
        for b in pattern:
            ch = chr(b)
            if ch.isalnum() or ch == "_":
                out.append(b)
            else:
                out.append(ord("\\"))
                out.append(b)
        return bytes(out)
    s = str(pattern)
    out = []
    for ch in s:
        if ch.isalnum() or ch == "_":
            out.append(ch)
        else:
            out.append("\\")
            out.append(ch)
    return "".join(out)


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

    def _parse_hex_escape(start, digits):
        # Parse \xHH / \uHHHH escapes.
        # `start` points at the escape kind character ('x' or 'u') within `pattern`.
        if start + 1 + digits > len(pattern):
            raise error("dangling escape")
        text = pattern[start + 1 : start + 1 + digits]
        if len(text) != digits or any(ch not in "0123456789abcdefABCDEF" for ch in text):
            raise error("invalid escape")
        code = int(text, 16)
        return chr(code), start + 1 + digits

    def parse_seq(stop=None, stop_on_pipe=False):
        nonlocal i
        nodes = []
        while i < len(pattern) and (stop is None or pattern[i] != stop):
            if stop_on_pipe and pattern[i] == "|":
                break
            c = pattern[i]
            if c == "^" and not nodes:
                i += 1
                node = ("anchor_start",)
                nodes.append(node)
                continue
            if c == "$":
                # End anchor. We only support the simple "$" form (end of
                # string); the stdlib patterns we rely on use this heavily.
                i += 1
                node = ("anchor_end",)
                nodes.append(node)
                continue
            if c == "(":
                # capturing group or non-capturing group
                if pattern.startswith("(?:", i):
                    i += 3
                    inner = parse_alt(stop=")")
                    if i >= len(pattern) or pattern[i] != ")":
                        raise error("unbalanced group")
                    i += 1
                    node = ("group_nc", inner)
                else:
                    i += 1
                    inner = parse_alt(stop=")")
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
                def parse_class_char():
                    nonlocal i
                    if i >= len(pattern):
                        raise error("unbalanced char class")
                    ch = pattern[i]
                    if ch != "\\":
                        i += 1
                        return ch
                    # escape inside [...]
                    i += 1
                    if i >= len(pattern):
                        raise error("dangling escape")
                    esc = pattern[i]
                    if esc == "w":
                        i += 1
                        return ("__set__", WORD_CHARS)
                    if esc == "d":
                        i += 1
                        return ("__set__", DIGIT_CHARS)
                    if esc == "s":
                        i += 1
                        return ("__set__", SPACE_CHARS)
                    if esc == "n":
                        i += 1
                        return "\n"
                    if esc == "r":
                        i += 1
                        return "\r"
                    if esc == "t":
                        i += 1
                        return "\t"
                    if esc == "f":
                        i += 1
                        return "\f"
                    if esc == "v":
                        i += 1
                        return "\v"
                    if esc == "x":
                        ch2, next_i = _parse_hex_escape(i, 2)
                        i = next_i
                        return ch2
                    if esc == "u":
                        ch2, next_i = _parse_hex_escape(i, 4)
                        i = next_i
                        return ch2
                    # default: treat as a literal escape of the next char
                    i += 1
                    return esc

                while i < len(pattern) and pattern[i] != "]":
                    first = parse_class_char()
                    # Expand sets returned by \w/\d/\s.
                    if isinstance(first, tuple) and first and first[0] == "__set__":
                        chars |= set(first[1])
                        continue
                    # Ranges: a-b (where a/b are single characters, not sets).
                    if i + 1 < len(pattern) and pattern[i] == "-" and pattern[i + 1] != "]":
                        i += 1  # consume '-'
                        second = parse_class_char()
                        if isinstance(second, tuple) and second and second[0] == "__set__":
                            raise error("unsupported char class range")
                        lo = ord(first)
                        hi = ord(second)
                        if lo <= hi:
                            for code in range(lo, hi + 1):
                                chars.add(chr(code))
                        continue
                    chars.add(first)
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
                elif esc == "n":
                    node = ("lit", "\n")
                elif esc == "r":
                    node = ("lit", "\r")
                elif esc == "t":
                    node = ("lit", "\t")
                elif esc == "f":
                    node = ("lit", "\f")
                elif esc == "v":
                    node = ("lit", "\v")
                elif esc == "x":
                    # Two hex digits.
                    ch2, next_i = _parse_hex_escape(i - 1, 2)
                    i = next_i
                    node = ("lit", ch2)
                elif esc == "u":
                    # Four hex digits.
                    ch2, next_i = _parse_hex_escape(i - 1, 4)
                    i = next_i
                    node = ("lit", ch2)
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

    def parse_alt(stop=None):
        nonlocal i
        alts = []
        while True:
            alts.append(parse_seq(stop=stop, stop_on_pipe=True))
            if i < len(pattern) and pattern[i] == "|":
                i += 1
                continue
            break
        if len(alts) == 1:
            return alts[0]
        return [("alt", alts)]

    def parse_quant(node):
        nonlocal i
        if i >= len(pattern):
            return node
        nongreedy = False
        c = pattern[i]
        if c == "?":
            i += 1
            if i < len(pattern) and pattern[i] == "?":
                nongreedy = True
                i += 1
            return ("repeat", 0, 1, node, nongreedy)
        if c == "*":
            i += 1
            if i < len(pattern) and pattern[i] == "?":
                nongreedy = True
                i += 1
            return ("repeat", 0, None, node, nongreedy)
        if c == "+":
            i += 1
            if i < len(pattern) and pattern[i] == "?":
                nongreedy = True
                i += 1
            return ("repeat", 1, None, node, nongreedy)
        if c == "{":
            j = pattern.find("}", i)
            if j == -1:
                raise error("unbalanced quantifier")
            n_text = pattern[i + 1 : j]
            if "," in n_text:
                left, right = n_text.split(",", 1)
                if left and not left.isdigit():
                    raise error("unsupported quantifier")
                if right and not right.isdigit():
                    raise error("unsupported quantifier")
                min_n = int(left) if left else 0
                max_n = int(right) if right else None
            else:
                if not n_text.isdigit():
                    raise error("unsupported quantifier")
                min_n = int(n_text)
                max_n = min_n
            i = j + 1
            if i < len(pattern) and pattern[i] == "?":
                nongreedy = True
                i += 1
            return ("repeat", min_n, max_n, node, nongreedy)
        return node

    ast = parse_alt()
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
        if kind == "alt":
            # Try each alternative (leftmost-first), threading the rest of the
            # nodes after the alternation.
            for opt in node[1]:
                res = match_nodes(opt + rest, si, captures)
                if res is not None:
                    return res
            return None
        if kind == "group_nc":
            # Inline the group so quantifiers inside can backtrack against the
            # following nodes.
            inner = node[1]
            return match_nodes(inner + rest, si, captures)
        if kind == "group":
            # Inline the group's inner nodes with a sentinel that records the
            # capture boundary. This allows `.*` inside groups to backtrack
            # against the nodes that follow the group.
            gid, inner = node[1], node[2]
            start = si
            return match_nodes(inner + [("cap_end", gid, start)] + rest, si, captures)
        if kind == "cap_end":
            gid, start = node[1], node[2]
            caps3 = list(captures)
            caps3[gid] = string[start:si]
            return match_nodes(rest, si, tuple(caps3))
        if kind == "repeat":
            min_n, max_n, inner = node[1], node[2], node[3]
            nongreedy = bool(node[4]) if len(node) >= 5 else False
            # Try greedy (default) or non-greedy, backtrack to satisfy the rest.
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
            if nongreedy:
                take_iter = range(0, len(matches) + 1)
            else:
                take_iter = range(len(matches), -1, -1)
            for take in take_iter:
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


def _sub_whitespace_only_lines(repl, string, count=0):
    out, _ = _subn_whitespace_only_lines(repl, string, count=count)
    return out


def _subn_whitespace_only_lines(repl, string, count=0):
    if repl != "" and not isinstance(repl, str):
        raise NotImplementedError("regex engine not available")
    out = []
    i = 0
    n = 0
    while i <= len(string):
        line_end = string.find("\n", i)
        if line_end == -1:
            line_end = len(string)
            has_newline = False
        else:
            has_newline = True
        line = string[i:line_end]
        if line and all(ch in " \t" for ch in line) and (count == 0 or n < count):
            out.append(repl)
            n += 1
        else:
            out.append(line)
        if not has_newline:
            break
        out.append("\n")
        i = line_end + 1
    return "".join(out), n


def _sub_strip_line_prefix(prefix, string, count=0):
    out, _ = _subn_strip_line_prefix(prefix, string, count=count)
    return out


def _subn_strip_line_prefix(prefix, string, count=0):
    out = []
    i = 0
    n = 0
    while i <= len(string):
        line_end = string.find("\n", i)
        if line_end == -1:
            line_end = len(string)
            has_newline = False
        else:
            has_newline = True
        line = string[i:line_end]
        if line.startswith(prefix) and (count == 0 or n < count):
            out.append(line[len(prefix) :])
            n += 1
        else:
            out.append(line)
        if not has_newline:
            break
        out.append("\n")
        i = line_end + 1
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
