"""Minimal _imp stub for moonpython (no C extensions or frozen modules)."""

import sys

check_hash_based_pycs = "never"

_multi_interp_extensions_check = 0


def extension_suffixes():
    return []


def acquire_lock():
    return None


def release_lock():
    return None


def is_builtin(name):
    for item in sys.builtin_module_names:
        if item == name:
            return True
    return False


def create_builtin(spec):
    name = getattr(spec, "name", spec)
    __import__(name)
    return sys.modules[name]


def exec_builtin(module):
    return None


def is_frozen(name):
    return False


def is_frozen_package(name):
    return False


def find_frozen(name):
    return None


def get_frozen_object(name):
    raise ImportError(f"{name!r} is not a frozen module", name=name)


def _fix_co_filename(code, path):
    return None


def create_dynamic(spec):
    raise ImportError("C extensions are not supported", name=spec.name)


def exec_dynamic(module):
    raise ImportError("C extensions are not supported", name=module.__name__)


def _override_multi_interp_extensions_check(override):
    global _multi_interp_extensions_check
    old = _multi_interp_extensions_check
    _multi_interp_extensions_check = override
    return old


def source_hash(magic_number, source_bytes):
    h = int(magic_number) & 0xFFFFFFFFFFFFFFFF
    for b in source_bytes:
        h = (h * 1315423911 + b) & 0xFFFFFFFFFFFFFFFF
    return bytes([
        h & 0xFF,
        (h >> 8) & 0xFF,
        (h >> 16) & 0xFF,
        (h >> 24) & 0xFF,
        (h >> 32) & 0xFF,
        (h >> 40) & 0xFF,
        (h >> 48) & 0xFF,
        (h >> 56) & 0xFF,
    ])
