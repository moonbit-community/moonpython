# Minimal pure-Python `termios` shim for moonpython.
#
# CPython's `termios` is a C extension. moonpython doesn't support C extensions,
# but modules like `tty` import `termios` unconditionally. This file provides
# just enough surface for stdlib imports and best-effort no-op behavior.

from __future__ import annotations

# Exception alias used by some callers.
error = OSError

# tcsetattr "when" constants.
TCSANOW = 0
TCSADRAIN = 1
TCSAFLUSH = 2

# POSIX cc indices used by `tty`.
VMIN = 6
VTIME = 5

# Flag constants used by `tty`. We don't model real terminal state, but these
# names must exist so `from termios import *` works.
IGNBRK = 0
BRKINT = 0
IGNPAR = 0
PARMRK = 0
INPCK = 0
ISTRIP = 0
INLCR = 0
IGNCR = 0
ICRNL = 0
IXON = 0
IXANY = 0
IXOFF = 0

OPOST = 0

PARENB = 0
CSIZE = 0
CS8 = 0

ECHO = 0
ECHOE = 0
ECHOK = 0
ECHONL = 0
ICANON = 0
IEXTEN = 0
ISIG = 0
NOFLSH = 0
TOSTOP = 0


def tcgetattr(fd):
    # Return a mutable "mode" list with the shape expected by `tty`.
    # [iflag, oflag, cflag, lflag, ispeed, ospeed, cc]
    return [0, 0, 0, 0, 0, 0, [0] * 32]


def tcsetattr(fd, when, attributes):
    # Best-effort no-op (no real terminal).
    return None

