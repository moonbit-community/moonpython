///|
/// Decorator parsing (including implicit line continuation).

///|
test "decorator/multiline_call" {
  let source =
    #|log = []
    #|def deco(a, b):
    #|  def inner(fn):
    #|    global log
    #|    log = [a, b]
    #|    return fn
    #|  return inner
    #|@deco(
    #|  1,
    #|  2,
    #|)
    #|def f():
    #|  return 0
    #|f()
  inspect(test_exec_global(source, "log"), content="[1, 2]")
}

///|
test "decorator/allows_blank_lines_and_comments_between_decorators" {
  let source =
    #|log = []
    #|def mark(x):
    #|  global log
    #|  log = log + [x]
    #|  def inner(fn):
    #|    return fn
    #|  return inner
    #|@mark(1)
    #|
    #|# comment between decorators
    #|@mark(2)
    #|def f():
    #|  return 0
    #|f()
  inspect(test_exec_global(source, "log"), content="[1, 2]")
}
