"""Minimal errno constants for moonpython stdlib."""

ENOENT = 2
ENOTDIR = 20
EBADF = 9
ECHILD = 10
ELOOP = 40
EEXIST = 17
EACCES = 13
EPERM = 1
EINVAL = 22
ENOSYS = 38
ENOTSUP = 95

errorcode = {
    ENOENT: "ENOENT",
    ENOTDIR: "ENOTDIR",
    EBADF: "EBADF",
    ECHILD: "ECHILD",
    ELOOP: "ELOOP",
    EEXIST: "EEXIST",
    EACCES: "EACCES",
    EPERM: "EPERM",
    EINVAL: "EINVAL",
    ENOSYS: "ENOSYS",
    ENOTSUP: "ENOTSUP",
}
