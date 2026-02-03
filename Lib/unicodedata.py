"""
Minimal pure-Python fallback for CPython's ``unicodedata``.

MoonPython does not ship CPython's C extension modules, but parts of the
stdlib (e.g. ``traceback``) rely on ``unicodedata.east_asian_width`` to
calculate display width for caret rendering when source contains wide
Unicode characters and emojis.

This module intentionally implements only the small subset currently needed
by the bundled stdlib tests. Extend as required when more tests start
depending on additional APIs.
"""

from __future__ import annotations

__all__ = [
    "east_asian_width",
    "unidata_version",
]


# The exact value is not critical for the current test set; it exists because
# some code expects the attribute to be present.
unidata_version = "0.0.0"


def _is_fullwidth(cp: int) -> bool:
    # Fullwidth Forms
    # - U+FF01..U+FF60: Fullwidth ASCII variants and halfwidth kana.
    # - U+FFE0..U+FFE6: Fullwidth symbol variants.
    return (0xFF01 <= cp <= 0xFF60) or (0xFFE0 <= cp <= 0xFFE6)


def _is_wide(cp: int) -> bool:
    # This is an intentionally small approximation of Unicode East Asian Width.
    # It is sufficient for the stdlib traceback caret tests (CJK + emoji).
    #
    # Reference implementations typically follow Unicode's EastAsianWidth.txt,
    # but shipping the full database is out of scope here.
    return (
        # Miscellaneous Symbols + Dingbats (many render as wide in terminals and
        # are classified as wide by CPython's `unicodedata.east_asian_width`,
        # e.g. U+2728 "✨".
        (0x2600 <= cp <= 0x27BF)
        # Hangul Jamo init. consonants
        or (0x1100 <= cp <= 0x115F)
        # CJK Radicals Supplement .. Yi Radicals
        or (0x2E80 <= cp <= 0xA4CF)
        # Hangul Syllables
        or (0xAC00 <= cp <= 0xD7A3)
        # CJK Compatibility Ideographs
        or (0xF900 <= cp <= 0xFAFF)
        # CJK Unified Ideographs (common Chinese/Japanese/Korean)
        or (0x4E00 <= cp <= 0x9FFF)
        # Supplementary Ideographic Plane (CJK Extensions)
        or (0x20000 <= cp <= 0x3FFFD)
        # Common emoji blocks used by the tests.
        or (0x1F000 <= cp <= 0x1FAFF)
    )


def east_asian_width(unichr: str) -> str:
    """
    Return the East Asian Width property for a Unicode character.

    This implementation returns:
    - "F" for fullwidth codepoints
    - "W" for wide codepoints
    - "N" otherwise
    """

    if not isinstance(unichr, str):
        raise TypeError("east_asian_width() argument must be str")
    if len(unichr) == 0:
        raise TypeError("east_asian_width() argument must be a single character")
    # MoonPython may represent some non-BMP characters with len() == 2, but
    # `ord()` still accepts them as a single character.
    try:
        cp = ord(unichr)
    except TypeError:
        cp = ord(unichr[:1])
    if _is_fullwidth(cp):
        return "F"
    if _is_wide(cp):
        return "W"
    return "N"
