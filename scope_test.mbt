///|
/// Scoping and locals tests.

///|
test "function assignment uses locals" {
  let source =
    #|x = 1
    #|def f():
    #|  x = 2
    #|  return x
    #|f()
  inspect(test_exec_global(source, "x"), content="1")
}

///|
test "nested function definition is local" {
  let source =
    #|def outer():
    #|  def inner():
    #|    return 1
    #|  return inner()
    #|res = outer()
  inspect(test_exec_global(source, "res"), content="1")
  inspect(test_exec_global(source, "inner"), content="<missing>")
}

///|
test "list comprehension target does not leak to globals" {
  let source =
    #|xs = [1, 2]
    #|ys = [x for x in xs]
  inspect(test_exec_global(source, "x"), content="<missing>")
  inspect(test_exec_global(source, "ys"), content="[1, 2]")
}

///|
test "comprehension target does not leak inside function" {
  let source =
    #|def f():
    #|  xs = [1, 2]
    #|  ys = [x for x in xs]
    #|  try:
    #|    x
    #|    return 1
    #|  except NameError:
    #|    return 0
    #|res = f()
  inspect(test_exec_global(source, "res"), content="0")
  inspect(test_exec_global(source, "x"), content="<missing>")
}

///|
test "with/as binds in current scope" {
  let source =
    #|class C:
    #|  def __enter__(self):
    #|    return 1
    #|  def __exit__(self, a, b, c):
    #|    pass
    #|with C() as x:
    #|  pass
  inspect(test_exec_global(source, "x"), content="1")
}

///|
test "match capture binds locals not globals" {
  let source =
    #|def f():
    #|  match (1, 2):
    #|    case (a, b):
    #|      return a + b
    #|res = f()
  inspect(test_exec_global(source, "res"), content="3")
  inspect(test_exec_global(source, "a"), content="<missing>")
  inspect(test_exec_global(source, "b"), content="<missing>")
}

///|
test "nonlocal assignment updates outer binding" {
  let source =
    #|def outer():
    #|  x = 1
    #|  def inner():
    #|    nonlocal x
    #|    x = 2
    #|  inner()
    #|  return x
    #|res = outer()
  inspect(test_exec_global(source, "res"), content="2")
}

///|
test "nonlocal missing binding is syntax error" {
  let source =
    #|def outer():
    #|  def inner():
    #|    nonlocal x
    #|    x = 1
    #|  inner()
    #|outer()
  inspect(
    test_exec_error(source),
    content="SyntaxError: no binding for nonlocal 'x' found",
  )
}

///|
test "closure captures outer name (read-only)" {
  let source =
    #|def outer():
    #|  x = 1
    #|  def inner():
    #|    return x
    #|  return inner()
    #|res = outer()
  inspect(test_exec_global(source, "res"), content="1")
}

///|
test "closure sees outer assignment after def" {
  let source =
    #|def outer():
    #|  x = 1
    #|  def inner():
    #|    return x
    #|  x = 2
    #|  return inner()
    #|res = outer()
  inspect(test_exec_global(source, "res"), content="2")
}

///|
test "closure captures from grandparent" {
  let source =
    #|def outer():
    #|  x = 1
    #|  def mid():
    #|    def inner():
    #|      return x
    #|    return inner()
    #|  return mid()
    #|res = outer()
  inspect(test_exec_global(source, "res"), content="1")
}

///|
test "unbound local read raises UnboundLocalError" {
  let source =
    #|def f():
    #|  x
    #|  x = 1
    #|f()
  inspect(
    test_exec_error(source),
    content="UnboundLocalError: local variable 'x' referenced before assignment",
  )
}
