"""Minimal _warnings stub for mpython."""

filters = []
_defaultaction = "default"
_onceregistry = {}


def _filters_mutated():
    return None


def warn(message, category=None, stacklevel=1, source=None):
    return None


def warn_explicit(message, category, filename, lineno,
                  module=None, registry=None, module_globals=None,
                  source=None):
    return None
