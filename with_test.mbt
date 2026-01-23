///|
/// With statement tests (context manager semantics).

///|

///|
test "with/exit runs on normal" {
  let source =
    #|log = []
    #|def enter():
    #|  pass
    #|def exit(a, b, c):
    #|  global log
    #|  log = [1]
    #|  return False
    #|ctx = object()
    #|ctx.__enter__ = enter
    #|ctx.__exit__ = exit
    #|with ctx:
    #|  pass
  inspect(test_exec_global(source, "log"), content="[1]")
}

///|
test "with/exit runs and can suppress" {
  let source =
    #|log = []
    #|after = 0
    #|def enter():
    #|  pass
    #|def exit(a, b, c):
    #|  global log
    #|  log = [a]
    #|  return True
    #|ctx = object()
    #|ctx.__enter__ = enter
    #|ctx.__exit__ = exit
    #|with ctx:
    #|  x
    #|after = 1
  inspect(test_exec_global(source, "log"), content="[<class 'NameError'>]")
  inspect(test_exec_global(source, "after"), content="1")
}

///|
test "with/exit runs before exception propagation" {
  let source =
    #|log = []
    #|def enter():
    #|  pass
    #|def exit(a, b, c):
    #|  global log
    #|  log = [1]
    #|  return False
    #|ctx = object()
    #|ctx.__enter__ = enter
    #|ctx.__exit__ = exit
    #|try:
    #|  with ctx:
    #|    x
    #|except NameError:
    #|  pass
  inspect(test_exec_global(source, "log"), content="[1]")
}
