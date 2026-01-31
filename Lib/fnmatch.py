"""Filename matching with shell patterns.

fnmatch(FILENAME, PATTERN) matches according to the local convention.
fnmatchcase(FILENAME, PATTERN) always takes case in account.

The functions operate by translating the pattern into a regular
expression.  They cache the compiled regular expressions for speed.

The function translate(PATTERN) returns a regular expression
corresponding to PATTERN.  (It does not compile it.)
"""
import os
import posixpath
import re
import functools

__all__ = ["filter", "fnmatch", "fnmatchcase", "translate"]

def fnmatch(name, pat):
    """Test whether FILENAME matches PATTERN.

    Patterns are Unix shell style:

    *       matches everything
    ?       matches any single character
    [seq]   matches any character in seq
    [!seq]  matches any char not in seq

    An initial period in FILENAME is not special.
    Both FILENAME and PATTERN are first case-normalized
    if the operating system requires it.
    If you don't want this, use fnmatchcase(FILENAME, PATTERN).
    """
    name = os.path.normcase(name)
    pat = os.path.normcase(pat)
    return fnmatchcase(name, pat)

@functools.lru_cache(maxsize=32768, typed=True)
def _compile_pattern(pat):
    # MoonPython note:
    # The stdlib `fnmatch` implementation translates shell globs into a regular
    # expression and relies on CPython's fast C regex engine. MoonPython ships a
    # minimal `re` shim that is not intended to handle large backtracking-heavy
    # patterns efficiently, which can make `test.test_fnmatch` extremely slow.
    #
    # Implement glob matching directly (with memoization) to keep it fast and
    # avoid depending on the regex engine.
    def _latin1_decode(data):
        # Avoid relying on the encodings machinery; map bytes 0..255 directly.
        out = []
        for b in bytes(data):
            out.append(chr(b))
        return "".join(out)

    is_bytes = isinstance(pat, bytes)
    if is_bytes:
        pat_s = _latin1_decode(pat)
    else:
        pat_s = pat

    def _parse_char_class(p, i):
        # Parse [...], returning (next_index, negate, allowed_set).
        # If no closing ']' exists, treat '[' as a literal.
        n = len(p)
        j = i + 1
        if j >= n:
            return None
        negate = False
        if p[j] == "!":
            negate = True
            j += 1
        if j < n and p[j] == "]":
            # ']' is a literal if it appears first.
            j += 1

        chars = set()
        if j > i + 1 and p[j - 1] == "]":
            # Leading ']' is a literal member of the class.
            chars.add("]")
        last = None
        while j < n and p[j] != "]":
            start = p[j]
            j += 1
            # Handle ranges like a-z. If the upper bound is smaller than the
            # lower bound, treat it as an empty range (matches nothing).
            if j + 1 < n and p[j] == "-" and p[j + 1] != "]":
                j += 1  # consume '-'
                end = p[j]
                j += 1
                if start <= end:
                    for code in range(ord(start), ord(end) + 1):
                        chars.add(chr(code))
                else:
                    # Descending/empty range: ignore both endpoints.
                    pass
                last = None
                continue
            chars.add(start)
            last = start

        if j >= n or p[j] != "]":
            return None
        return (j + 1, negate, chars)

    def _match(name):
        if is_bytes:
            if isinstance(name, str):
                raise TypeError("cannot use a bytes pattern on a string-like object")
            if not isinstance(name, (bytes, bytearray)):
                raise TypeError("expected a bytes-like object")
            s = _latin1_decode(name)
        else:
            if isinstance(name, (bytes, bytearray)):
                raise TypeError("cannot use a string pattern on a bytes-like object")
            s = name

        p = pat_s
        n_s = len(s)
        n_p = len(p)
        memo = {}

        def go(pi, si):
            key = (pi, si)
            if key in memo:
                return memo[key]

            if pi == n_p:
                ok = si == n_s
                memo[key] = ok
                return ok

            c = p[pi]
            if c == "*":
                # Compress consecutive '*' into one.
                while pi < n_p and p[pi] == "*":
                    pi += 1
                if pi == n_p:
                    memo[key] = True
                    return True
                # Try to match the rest of the pattern at each suffix.
                for sj in range(si, n_s + 1):
                    if go(pi, sj):
                        memo[key] = True
                        return True
                memo[key] = False
                return False
            if c == "?":
                ok = si < n_s and go(pi + 1, si + 1)
                memo[key] = ok
                return ok
            if c == "[":
                parsed = _parse_char_class(p, pi)
                if parsed is None:
                    ok = si < n_s and s[si] == "[" and go(pi + 1, si + 1)
                    memo[key] = ok
                    return ok
                next_pi, negate, chars = parsed
                if si >= n_s:
                    memo[key] = False
                    return False
                hit = s[si] in chars
                if negate:
                    hit = not hit
                ok = hit and go(next_pi, si + 1)
                memo[key] = ok
                return ok

            ok = si < n_s and s[si] == c and go(pi + 1, si + 1)
            memo[key] = ok
            return ok

        return go(0, 0)

    return _match

def filter(names, pat):
    """Construct a list from those elements of the iterable NAMES that match PAT."""
    result = []
    pat = os.path.normcase(pat)
    match = _compile_pattern(pat)
    if os.path is posixpath:
        # normcase on posix is NOP. Optimize it away from the loop.
        for name in names:
            if match(name):
                result.append(name)
    else:
        for name in names:
            if match(os.path.normcase(name)):
                result.append(name)
    return result

def fnmatchcase(name, pat):
    """Test whether FILENAME matches PATTERN, including case.

    This is a version of fnmatch() which doesn't case-normalize
    its arguments.
    """
    match = _compile_pattern(pat)
    return match(name)


def translate(pat):
    """Translate a shell PATTERN to a regular expression.

    There is no way to quote meta-characters.
    """

    STAR = object()
    res = []
    add = res.append
    i, n = 0, len(pat)
    while i < n:
        c = pat[i]
        i = i+1
        if c == '*':
            # compress consecutive `*` into one
            if (not res) or res[-1] is not STAR:
                add(STAR)
        elif c == '?':
            add('.')
        elif c == '[':
            j = i
            if j < n and pat[j] == '!':
                j = j+1
            if j < n and pat[j] == ']':
                j = j+1
            while j < n and pat[j] != ']':
                j = j+1
            if j >= n:
                add('\\[')
            else:
                stuff = pat[i:j]
                if '-' not in stuff:
                    stuff = stuff.replace('\\', r'\\')
                else:
                    chunks = []
                    k = i+2 if pat[i] == '!' else i+1
                    while True:
                        k = pat.find('-', k, j)
                        if k < 0:
                            break
                        chunks.append(pat[i:k])
                        i = k+1
                        k = k+3
                    chunk = pat[i:j]
                    if chunk:
                        chunks.append(chunk)
                    else:
                        chunks[-1] += '-'
                    # Remove empty ranges -- invalid in RE.
                    for k in range(len(chunks)-1, 0, -1):
                        if chunks[k-1][-1] > chunks[k][0]:
                            chunks[k-1] = chunks[k-1][:-1] + chunks[k][1:]
                            del chunks[k]
                    # Escape backslashes and hyphens for set difference (--).
                    # Hyphens that create ranges shouldn't be escaped.
                    stuff = '-'.join(s.replace('\\', r'\\').replace('-', r'\-')
                                     for s in chunks)
                # Escape set operations (&&, ~~ and ||). Do it manually to
                # avoid depending on a full regex engine.
                stuff = "".join("\\" + ch if ch in "&~|" else ch for ch in stuff)
                i = j+1
                if not stuff:
                    # Empty range: never match.
                    add('(?!)')
                elif stuff == '!':
                    # Negated empty range: match any character.
                    add('.')
                else:
                    if stuff[0] == '!':
                        stuff = '^' + stuff[1:]
                    elif stuff[0] in ('^', '['):
                        stuff = '\\' + stuff
                    add(f'[{stuff}]')
        else:
            add(re.escape(c))
    assert i == n

    # Deal with STARs.
    inp = res
    res = []
    add = res.append
    i, n = 0, len(inp)
    # Fixed pieces at the start?
    while i < n and inp[i] is not STAR:
        add(inp[i])
        i += 1
    # Now deal with STAR fixed STAR fixed ...
    # For an interior `STAR fixed` pairing, we want to do a minimal
    # .*? match followed by `fixed`, with no possibility of backtracking.
    # Atomic groups ("(?>...)") allow us to spell that directly.
    # Note: people rely on the undocumented ability to join multiple
    # translate() results together via "|" to build large regexps matching
    # "one of many" shell patterns.
    while i < n:
        assert inp[i] is STAR
        i += 1
        if i == n:
            add(".*")
            break
        assert inp[i] is not STAR
        fixed = []
        while i < n and inp[i] is not STAR:
            fixed.append(inp[i])
            i += 1
        fixed = "".join(fixed)
        if i == n:
            add(".*")
            add(fixed)
        else:
            add(f"(?>.*?{fixed})")
    assert i == n
    res = "".join(res)
    return fr'(?s:{res})\Z'
