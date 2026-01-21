"""Minimal errno constants for mpython stdlib."""

ENOENT = 2
ENOTDIR = 20
EBADF = 9
ELOOP = 40

errorcode = {
    ENOENT: "ENOENT",
    ENOTDIR: "ENOTDIR",
    EBADF: "EBADF",
    ELOOP: "ELOOP",
}
