value = 1


def __getattr__(name):
    if name == "y":
        return 2
    raise AttributeError(name)

