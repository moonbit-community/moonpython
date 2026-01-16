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
