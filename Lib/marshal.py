"""Minimal marshal stub for mpython (bytecode marshal unsupported)."""

version = 0


def dump(value, file, version=version):
    raise NotImplementedError("marshal.dump is not supported")


def dumps(value, version=version):
    raise NotImplementedError("marshal.dumps is not supported")


def load(file):
    raise NotImplementedError("marshal.load is not supported")


def loads(data):
    raise NotImplementedError("marshal.loads is not supported")
