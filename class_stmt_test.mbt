///|
/// Class statement semantics tests (bases, metaclass kwargs, etc).

///|
test "class/accepts starred bases" {
  let source =
    #|class A:
    #|  x = 1
    #|class B:
    #|  y = 2
    #|bases = (A, B)
    #|class C(*bases):
    #|  pass
    #|val = [C.x, C.y]
  inspect(test_exec_global(source, "val"), content="[1, 2]")
}

///|
test "class/forwards **kwargs to __init_subclass__" {
  let source =
    #|log = []
    #|class Base:
    #|  def __init_subclass__(cls, **kw):
    #|    global log
    #|    log = [kw.get("a")]
    #|opts = {"a": 2}
    #|class C(Base, a=1, **opts):
    #|  pass
  inspect(test_exec_global(source, "log"), content="[2]")
}

///|
test "class/accepts metaclass and kwargs via **mapping" {
  let source =
    #|class Meta(type):
    #|  def __new__(mcls, name, bases, ns, **kw):
    #|    ns["seen"] = kw.get("tag")
    #|    return type.__new__(mcls, name, bases, ns)
    #|opts = {"metaclass": Meta, "tag": 9}
    #|class C(**opts):
    #|  pass
    #|val = C.seen
  inspect(test_exec_global(source, "val"), content="9")
}
