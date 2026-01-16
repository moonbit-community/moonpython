///|
/// End-to-end tests exercising multiple language features together.

///|
fn e2e_run(
  stdin : Array[String],
  source : String,
) -> Result[RunResult, RuntimeError] {
  let io = MockIO::new(stdin)
  Interpreter::with_io(Config::default(), io).exec_source(source)
}

///|
fn e2e_stdout(stdin : Array[String], source : String) -> String {
  match e2e_run(stdin, source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
fn e2e_global(stdin : Array[String], source : String, name : String) -> String {
  match e2e_run(stdin, source) {
    Ok(run) =>
      match test_get_global(run.globals, name) {
        Some(value) => test_value_repr(value)
        None => "<missing>"
      }
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "e2e/io_while_function" {
  let source =
    #|def fib(n):
    #|  if n <= 1:
    #|    return n
    #|  a = 0
    #|  b = 1
    #|  i = 2
    #|  while i <= n:
    #|    c = a + b
    #|    a = b
    #|    b = c
    #|    i = i + 1
    #|  return b
    #|n = int(input("n="))
    #|print("fib=", fib(n))
  inspect(
    e2e_stdout(["7"], source),
    content=(
      #|n=fib= 13
      #|
    ),
  )
}

///|
test "e2e/comprehension_match_fstring" {
  let source =
    #|xs = [2, 4]
    #|ys = [x * x for x in xs]
    #|pair = (ys[0], ys[1])
    #|match pair:
    #|  case (4, 16):
    #|    ok = True
    #|  case _:
    #|    ok = False
    #|text = ",".join([str(y) for y in ys])
    #|print(f"{text}:{ok}")
  inspect(e2e_stdout([], source), content="4,16:True\n")
}

///|
test "e2e/try_except_finally_raise_del" {
  let source =
    #|log = []
    #|def boom():
    #|  raise RuntimeError("x")
    #|x = 1
    #|del x
    #|try:
    #|  x
    #|except NameError:
    #|  log = log + ["del"]
    #|try:
    #|  boom()
    #|except RuntimeError as e:
    #|  log = log + [str(e)]
    #|finally:
    #|  log = log + ["finally"]
    #|print(",".join(log))
  inspect(e2e_stdout([], source), content="del,RuntimeError: x,finally\n")
  inspect(
    e2e_global([], source, "log"),
    content="[del, RuntimeError: x, finally]",
  )
}

///|
test "e2e/class_with_suppresses" {
  let source =
    #|log = []
    #|class CM:
    #|  def __init__(self):
    #|    self.v = 7
    #|  def __enter__(self):
    #|    global log
    #|    log = log + ["enter"]
    #|    return self.v
    #|  def __exit__(self, t, v, tb):
    #|    global log
    #|    log = log + ["exit:" + t]
    #|    return True
    #|cm = CM()
    #|with cm as v:
    #|  log = log + ["v=" + str(v)]
    #|  x
    #|log = log + ["after"]
    #|print(",".join(log))
  inspect(e2e_stdout([], source), content="enter,v=7,exit:NameError,after\n")
}

///|
test "e2e/inheritance_inherited_init" {
  let source =
    #|class A:
    #|  def __init__(self):
    #|    self.x = 1
    #|class B(A):
    #|  pass
    #|b = B()
    #|print(b.x)
  inspect(e2e_stdout([], source), content="1\n")
}

///|
test "e2e/mro_multiple_inheritance" {
  let source =
    #|class A:
    #|  def f(self):
    #|    return "A"
    #|class B(A):
    #|  pass
    #|class C(A):
    #|  def f(self):
    #|    return "C"
    #|class D(B, C):
    #|  pass
    #|print(D().f())
  inspect(e2e_stdout([], source), content="C\n")
}

///|
test "e2e/mro_conflict_errors" {
  let source =
    #|class X:
    #|  pass
    #|class Y:
    #|  pass
    #|class A(X, Y):
    #|  pass
    #|class B(Y, X):
    #|  pass
    #|class C(A, B):
    #|  pass
  inspect(
    test_exec_error(source),
    content="TypeError: cannot create a consistent method resolution order",
  )
}

///|
test "e2e/builtin_len" {
  let source =
    #|print(len([1, 2, 3]))
    #|print(len("hi"))
    #|print(len({"a": 1, "b": 2}))
  inspect(e2e_stdout([], source), content="3\n2\n2\n")
  inspect(test_exec_error("len(1)"), content="TypeError: object has no len()")
}

///|
test "e2e/builtin_range" {
  let source =
    #|xs = []
    #|for i in range(5):
    #|  xs = xs + [i]
    #|ys = []
    #|for j in range(5, 0, -2):
    #|  ys = ys + [j]
    #|print(",".join([str(x) for x in xs]))
    #|print(",".join([str(y) for y in ys]))
  inspect(e2e_stdout([], source), content="0,1,2,3,4\n5,3,1\n")
  inspect(
    test_exec_error("range(1, 2, 0)"),
    content="TypeError: range() arg 3 must not be zero",
  )
}

///|
test "e2e/builtin_sum" {
  let source =
    #|print(sum([1, 2, 3]))
    #|print(sum(range(5)))
    #|print(sum([], 10))
  inspect(e2e_stdout([], source), content="6\n10\n10\n")
  inspect(test_exec_error("sum(['x'])"), content="TypeError: expected number")
}

///|
test "e2e/builtin_max" {
  let source =
    #|print(max([1, 2, 3]))
    #|print(max(range(5)))
    #|print(max(1, 9, 3, 9))
    #|print(max([1, 2.5, 2]))
    #|print(max([True, False, 2]))
  inspect(e2e_stdout([], source), content="3\n4\n9\n2.5\n2\n")
  inspect(
    test_exec_error("max()"),
    content="TypeError: max() takes at least 1 argument",
  )
  inspect(
    test_exec_error("max([])"),
    content="TypeError: max() arg is an empty sequence",
  )
  inspect(test_exec_error("max(['x'])"), content="TypeError: expected number")
}

///|
test "e2e/builtin_min" {
  let source =
    #|print(min([1, 2, 3]))
    #|print(min(range(5)))
    #|print(min(1, -9, 3, -9))
    #|print(min([1, 2.5, -2]))
    #|print(min([True, False, 2]))
  inspect(e2e_stdout([], source), content="1\n0\n-9\n-2\nFalse\n")
  inspect(
    test_exec_error("min()"),
    content="TypeError: min() takes at least 1 argument",
  )
  inspect(
    test_exec_error("min([])"),
    content="TypeError: min() arg is an empty sequence",
  )
  inspect(test_exec_error("min(['x'])"), content="TypeError: expected number")
}

///|
test "e2e/builtin_any" {
  let source =
    #|print(any([]))
    #|print(any([0, False, "", None]))
    #|print(any([0, 1, 2]))
    #|print(any("hi"))
    #|print(any(""))
    #|print(any({"": 1}))
    #|print(any({"a": 0}))
  inspect(
    e2e_stdout([], source),
    content="False\nFalse\nTrue\nTrue\nFalse\nFalse\nTrue\n",
  )
  inspect(
    test_exec_error("any()"),
    content="TypeError: any() takes exactly one argument",
  )
  inspect(
    test_exec_error("any(1)"),
    content="TypeError: object is not iterable",
  )
}

///|
test "e2e/builtin_all" {
  let source =
    #|print(all([]))
    #|print(all([1, 2, 3]))
    #|print(all([1, 0, 3]))
    #|print(all("hi"))
    #|print(all(""))
    #|print(all({"": 1}))
    #|print(all({"a": 0}))
  inspect(
    e2e_stdout([], source),
    content="True\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue\n",
  )
  inspect(
    test_exec_error("all()"),
    content="TypeError: all() takes exactly one argument",
  )
  inspect(
    test_exec_error("all(1)"),
    content="TypeError: object is not iterable",
  )
}

///|
test "e2e/builtin_enumerate" {
  let source =
    #|pairs = enumerate(["a", "b"])
    #|print(pairs[0][0], pairs[0][1])
    #|print(pairs[1][0], pairs[1][1])
    #|print(len(enumerate([], 10)))
    #|print(",".join([str(i) for i, _ in enumerate(range(3), 1)]))
  inspect(e2e_stdout([], source), content="0 a\n1 b\n0\n1,2,3\n")
  inspect(
    test_exec_error("enumerate()"),
    content="TypeError: enumerate() takes 1 or 2 arguments",
  )
  inspect(
    test_exec_error("enumerate(1)"),
    content="TypeError: object is not iterable",
  )
  inspect(
    test_exec_error("enumerate([], 'x')"),
    content="TypeError: enumerate() integer argument expected",
  )
}

///|
test "e2e/builtin_zip" {
  let source =
    #|print(len(zip()))
    #|print(",".join([str(a) + ":" + str(b) for a, b in zip([1, 2], [3, 4, 5])]))
    #|print(",".join([a + b for a, b in zip("ab", "XY")]))
    #|triples = zip([1, 2], [3], [4, 5, 6])
    #|print(len(triples))
    #|print(triples[0][0], triples[0][1], triples[0][2])
  inspect(e2e_stdout([], source), content="0\n1:3,2:4\naX,bY\n1\n1 3 4\n")
  inspect(
    test_exec_error("zip(1)"),
    content="TypeError: object is not iterable",
  )
}
