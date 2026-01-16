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

///|
test "e2e/comprehension_unpack_n" {
  let source =
    #|print(",".join([str(a) + str(b) + str(c) for a, b, c in zip([1, 2], [3, 4], [5, 6])]))
    #|print(",".join([str(a) for a, _, _ in zip([1], [2], [3])]))
  inspect(e2e_stdout([], source), content="135,246\n1\n")
  inspect(
    test_exec_error("[a for a, b, c in [(1, 2)]]"),
    content="TypeError: cannot unpack",
  )
}

///|
test "e2e/builtin_reversed" {
  let source =
    #|print(",".join([str(x) for x in reversed([1, 2, 3])]))
    #|print(",".join([x for x in reversed("ab")]))
    #|print(len(reversed([])))
  inspect(e2e_stdout([], source), content="3,2,1\nb,a\n0\n")
  inspect(
    test_exec_error("reversed()"),
    content="TypeError: reversed() takes exactly one argument",
  )
  inspect(
    test_exec_error("reversed(1)"),
    content="TypeError: object is not iterable",
  )
}

///|
test "e2e/builtin_sorted" {
  let source =
    #|xs = [3, 1, 2]
    #|ys = sorted(xs)
    #|print(",".join([str(x) for x in ys]))
    #|print(",".join([str(x) for x in xs]))
    #|print(",".join([str(x) for x in sorted([True, False, 2])]))
    #|print(",".join([str(x) for x in sorted([1, 2.5, 2])]))
    #|print("".join(sorted("cba")))
    #|print(",".join(sorted({"b": 1, "a": 2})))
    #|print(",".join([str(x) for x in sorted([1, 2, 3], True)]))
  inspect(
    e2e_stdout([], source),
    content="1,2,3\n3,1,2\nFalse,True,2\n1,2,2.5\nabc\na,b\n3,2,1\n",
  )
  inspect(
    test_exec_error("sorted()"),
    content="TypeError: sorted() takes 1 or 2 arguments",
  )
  inspect(
    test_exec_error("sorted(1)"),
    content="TypeError: object is not iterable",
  )
  inspect(
    test_exec_error("sorted([1, 'a'])"),
    content="TypeError: sorted() cannot compare values",
  )
  inspect(
    test_exec_error("sorted([1, 2], 1)"),
    content="TypeError: sorted() reverse must be bool",
  )
}

///|
test "e2e/builtin_iter_next" {
  let source =
    #|it = iter([1, 2])
    #|print(next(it))
    #|print(next(it))
    #|print(next(it, 99))
    #|it2 = iter("ab")
    #|print(next(it2), next(it2), next(it2, "Z"))
  inspect(e2e_stdout([], source), content="1\n2\n99\na b Z\n")
  inspect(
    test_exec_error("it = iter([1]); next(it); next(it)"),
    content="StopIteration",
  )
  inspect(
    test_exec_error("next([1])"),
    content="TypeError: 'list' object is not an iterator",
  )
  inspect(
    test_exec_error("iter(1)"),
    content="TypeError: object is not iterable",
  )
  inspect(
    e2e_stdout([], "it = iter([1]); print(iter(it) == it)"),
    content="True\n",
  )
}

///|
test "e2e/builtin_more_cpython" {
  let source =
    #|print(bool(), bool(0), bool(1), bool(""), bool("a"))
    #|print(repr("a\"b"))
    #|print(abs(-3), abs(-2.5))
    #|print(round(1.2), round(1.8), round(-1.2))
    #|print(pow(2, 3), pow(2, -1))
    #|print(pow(2, 5, 5))
    #|print(divmod(7, 3))
    #|print(chr(65), ord("A"))
    #|print(bin(10), oct(10), hex(10))
    #|print(callable(print), callable(1))
    #|print(isinstance(1, int), isinstance(True, int), isinstance(True, bool), isinstance([], list))
    #|print(type(1), type("a"), type([1]))
    #|print(id(7), id(True))
    #|print(hash("ab"))
    #|class C:
    #|  pass
    #|c = C()
    #|c.x = 1
    #|d = {"b": 1, "a": 2}
    #|print(",".join(sorted(dir(c))))
    #|print(",".join(sorted(dir(d))))
    #|print(",".join(sorted(dir(C))))
  inspect(
    e2e_stdout([], source),
    content=(
      #|False False True False True
      #|"a\"b"
      #|3 2.5
      #|1 2 -1
      #|8 0.5
      #|2
      #|(2, 1)
      #|A 65
      #|0b1010 0o12 0xa
      #|True False
      #|True True True True
      #|int str list
      #|7 1
      #|12805
      #|x
      #|a,b
      #|
      #|
    ),
  )
  inspect(
    test_exec_error("chr(-1)"),
    content="ValueError: chr() arg not in range(0x110000)",
  )
  inspect(
    test_exec_error("ord(\"ab\")"),
    content="TypeError: ord() expected a character",
  )
  inspect(
    test_exec_error("bin(1.2)"),
    content="TypeError: bin() argument must be int",
  )
  inspect(
    test_exec_error("pow(2, 3, 0)"),
    content="ZeroDivisionError: integer modulo by zero",
  )
}

///|
test "e2e/raise_class" {
  inspect(test_exec_error("raise ValueError"), content="ValueError")
  inspect(
    test_exec_error("raise 1"),
    content="TypeError: exceptions must derive from BaseException",
  )
  let source =
    #|try:
    #|  raise ValueError
    #|except ValueError as e:
    #|  print("caught", e)
  inspect(e2e_stdout([], source), content="caught ValueError\n")
  let source2 =
    #|try:
    #|  raise ValueError("x")
    #|except ValueError as e:
    #|  print(e)
  inspect(e2e_stdout([], source2), content="ValueError: x\n")
}
