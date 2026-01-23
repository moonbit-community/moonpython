"""Minimal pure-Python stub for _signal."""

SIG_DFL = 0
SIG_IGN = 1

SIGINT = 2
SIGTERM = 15
SIGKILL = 9

_handlers = {}


def signal(signalnum, handler):
    prev = _handlers.get(signalnum, SIG_DFL)
    _handlers[signalnum] = handler
    return prev


def getsignal(signalnum):
    return _handlers.get(signalnum, SIG_DFL)


def default_int_handler(signum, frame):
    raise KeyboardInterrupt()
