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
test "e2e/while_else_and_for_else" {
  let source =
    #|out = []
    #|i = 0
    #|while i < 2:
    #|  i = i + 1
    #|else:
    #|  out = out + ["while-else"]
    #|for x in [1, 2, 3]:
    #|  if x == 2:
    #|    break
    #|else:
    #|  out = out + ["for-else"]
    #|for x in [1, 2, 3]:
    #|  if x == 9:
    #|    break
    #|else:
    #|  out = out + ["for-else-ran"]
    #|print(",".join(out))
  inspect(e2e_stdout([], source), content="while-else,for-else-ran\n")
}

///|
test "e2e/for_unpacking" {
  let source =
    #|out = []
    #|for a, b in [(1, 2), (3, 4)]:
    #|  out = out + [str(a) + ":" + str(b)]
    #|print(",".join(out))
  inspect(e2e_stdout([], source), content="1:2,3:4\n")
}

///|
test "e2e/function_defaults_and_kwargs" {
  let ok_source =
    #|def f(a, b=10, c=20):
    #|  return a + b + c
    #|print(f(1))
    #|print(f(1, 2))
    #|print(f(1, c=3))
  inspect(e2e_stdout([], ok_source), content="31\n23\n14\n")
  let missing_source =
    #|def f(a, b=10):
    #|  return a + b
    #|f()
  inspect(
    e2e_stdout([], missing_source),
    content="ERR: TypeError: f() missing 1 required positional argument: 'a'",
  )
  let too_many_source =
    #|def f(a, b=10):
    #|  return a + b
    #|f(1, 2, 3)
  inspect(
    e2e_stdout([], too_many_source),
    content="ERR: TypeError: f() takes 2 positional arguments but 3 were given",
  )
  let unexpected_kw_source =
    #|def f(a, b=10):
    #|  return a + b
    #|f(1, c=2)
  inspect(
    e2e_stdout([], unexpected_kw_source),
    content="ERR: TypeError: f() got an unexpected keyword argument 'c'",
  )
}

///|
test "e2e/backslash_newline_inside_string" {
  let source =
    #|a = ["line\
    #|break"]
    #|print(a[0])
  inspect(e2e_stdout([], source), content="linebreak\n")
}

///|
test "e2e/unicode_punctuation_is_lexical_error" {
  let source =
    #|This sentence is in ASCII.
    #|The next sentence is in GB.己所不欲，勿施於人。Bye.
  inspect(e2e_stdout([], source), content="ERR: line 2:1 invalid syntax")
}

///|
test "e2e/bracket_mismatch_can_outrank_earlier_syntax" {
  let source =
    #|a b
    #|[1)
  inspect(e2e_stdout([], source), content="ERR: line 2:1 invalid syntax")
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
  inspect(e2e_stdout([], source), content="del,x,finally\n")
  inspect(e2e_global([], source, "log"), content="[del, x, finally]")
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
    #|    log = log + ["exit:" + t.__name__]
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
test "e2e/decorators_function_and_class" {
  let source =
    #|log = []
    #|def d1(x):
    #|  global log
    #|  log = log + ["d1"]
    #|  return x
    #|def d2(x):
    #|  global log
    #|  log = log + ["d2"]
    #|  return x
    #|@d1
    #|@d2
    #|def f():
    #|  global log
    #|  log = log + ["f"]
    #|  return 0
    #|@d2
    #|class C:
    #|  pass
    #|f()
    #|print(",".join(log))
  inspect(e2e_stdout([], source), content="d2,d1,d2,f\n")
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
    content="ValueError: range() arg 3 must not be zero",
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
  inspect(e2e_stdout([], "print(max(['x']))"), content="x\n")
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
  inspect(e2e_stdout([], "print(min(['x']))"), content="x\n")
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
    #|pairs = list(enumerate(["a", "b"]))
    #|print(pairs[0][0], pairs[0][1])
    #|print(pairs[1][0], pairs[1][1])
    #|print(len(list(enumerate([], 10))))
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
    #|print(",".join([str(x) for x in sorted([1, 2, 3], reverse=True)]))
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
    test_exec_error("sorted([1, 2], reverse=1)"),
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
test "e2e/iterable_iterator_values" {
  let source =
    #|it = iter([1, 2, 3])
    #|print(",".join([str(x) for x in list(it)]))
    #|print(",".join([str(x) for x in list(it)]))
    #|print(",".join([str(x) for x in iter([4, 5])]))
  inspect(e2e_stdout([], source), content="1,2,3\n\n4,5\n")
}

///|
test "e2e/builtin_map_filter" {
  let source =
    #|def inc(x):
    #|  return x + 1
    #|def gt2(x):
    #|  return x > 2
    #|print(",".join([str(x) for x in map(inc, [1, 2, 3])]))
    #|print(",".join([str(x) for x in filter(gt2, [1, 2, 3, 4])]))
    #|print(",".join([str(x) for x in filter(None, [0, 1, "", "a"])]))
  inspect(e2e_stdout([], source), content="2,3,4\n3,4\n1,a\n")
  inspect(
    test_exec_error("map()"),
    content="TypeError: map() takes exactly two arguments",
  )
  inspect(
    test_exec_error("filter(1)"),
    content="TypeError: filter() takes exactly two arguments",
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
      #|<class 'int'> <class 'str'> <class 'list'>
      #|7 1
      #|12805
      #|__eq__,__hash__,__init__,__init_subclass__,__module__,__ne__,__new__,__str__,hashvalue,x
      #|a,b
      #|__eq__,__hash__,__init__,__init_subclass__,__module__,__ne__,__new__,__str__
      #|
    ),
  )

  // Rounding edge cases for CPython-style int -> float conversion.
  // These exercise round-to-nearest, ties-to-even and overflow behavior.
  let rounding_source =
    #|print(float(9007199254740993) == float(9007199254740992))
    #|print(float(9007199254740993) == float(9007199254740994))
    #|print(float(9007199254740995) == float(9007199254740996))
    #|print(float(9007199254740995) == float(9007199254740994))
  inspect(
    e2e_stdout([], rounding_source),
    content=(
      #|True
      #|False
      #|True
      #|False
      #|
    ),
  )
  inspect(
    e2e_stdout([], "print(float(10 ** 400))"),
    content="ERR: OverflowError: int too large to convert to float",
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
test "e2e/descriptor_get" {
  let source =
    #|class D:
    #|  def __get__(self, obj, typ):
    #|    if obj == None:
    #|      return "cls"
    #|    return "inst"
    #|class A:
    #|  x = D()
    #|print(A.x, A().x)
  inspect(e2e_stdout([], source), content="cls inst\n")
}

///|
test "e2e/builtin_getattr_hasattr_setattr" {
  let source =
    #|class C:
    #|  pass
    #|c = C()
    #|print(hasattr(c, "x"))
    #|setattr(c, "x", 1)
    #|print(getattr(c, "x"), hasattr(c, "x"))
    #|print(getattr(c, "y", 99))
    #|setattr(C, "k", 7)
    #|print(getattr(c, "k"))
  inspect(e2e_stdout([], source), content="False\n1 True\n99\n7\n")
  inspect(
    test_exec_error("getattr(1, 2)"),
    content="TypeError: attribute name must be str",
  )
  inspect(
    test_exec_error("hasattr(1, 2)"),
    content="TypeError: attribute name must be str",
  )
  inspect(
    test_exec_error("getattr(1, \"x\")"),
    content="AttributeError: 'int' object has no attribute 'x'",
  )
}

///|
test "e2e/builtin_property" {
  let source =
    #|class A:
    #|  def __init__(self):
    #|    self.v = 9
    #|  def getv(self):
    #|    return self.v
    #|  v2 = property(getv)
    #|a = A()
    #|print(a.v2)
  inspect(e2e_stdout([], source), content="9\n")
}

///|
test "e2e/instance_call" {
  let source =
    #|class A:
    #|  def __init__(self, x):
    #|    self.x = x
    #|  def __call__(self, y):
    #|    return self.x + y
    #|a = A(3)
    #|print(a(4))
  inspect(e2e_stdout([], source), content="7\n")
}

///|
test "e2e/builtin_staticmethod" {
  let source =
    #|class A:
    #|  def f(x):
    #|    return x
    #|  g = staticmethod(f)
    #|print(A.g(3))
    #|print(A().g(4))
  inspect(e2e_stdout([], source), content="3\n4\n")
}

///|
test "e2e/builtin_classmethod" {
  let source =
    #|class A:
    #|  def f(cls, x):
    #|    return x
    #|  g = classmethod(f)
    #|print(A.g(3))
    #|print(A().g(4))
  inspect(e2e_stdout([], source), content="3\n4\n")
}

///|
test "e2e/dunder_getattr" {
  let source =
    #|class A:
    #|  def __getattr__(self, name):
    #|    if name == "x":
    #|      return 7
    #|    return 0
    #|a = A()
    #|print(a.x, a.y)
  inspect(e2e_stdout([], source), content="7 0\n")
}

///|
test "e2e/dunder_getattribute" {
  let source =
    #|class A:
    #|  def __getattribute__(self, name):
    #|    return 3
    #|a = A()
    #|print(a.x)
  inspect(e2e_stdout([], source), content="3\n")
}

///|
test "e2e/object_dunder_getattribute_delegation" {
  let source =
    #|class A:
    #|  def __init__(self):
    #|    self.x = 1
    #|  def __getattribute__(self, name):
    #|    if name == "x":
    #|      return object.__getattribute__(self, name) + 1
    #|    return object.__getattribute__(self, name)
    #|a = A()
    #|print(a.x)
  inspect(e2e_stdout([], source), content="2\n")
}

///|
test "e2e/object_dunder_getattribute_falls_back_to_getattr" {
  let source =
    #|class A:
    #|  def __getattribute__(self, name):
    #|    return object.__getattribute__(self, name)
    #|  def __getattr__(self, name):
    #|    return 9
    #|a = A()
    #|print(a.missing)
  inspect(e2e_stdout([], source), content="9\n")
}

///|
test "e2e/dunder_setattr" {
  let source =
    #|log = []
    #|class A:
    #|  def __setattr__(self, name, value):
    #|    global log
    #|    log = log + [name + "=" + str(value)]
    #|a = A()
    #|a.x = 5
    #|print(",".join(log))
  inspect(e2e_stdout([], source), content="x=5\n")
}

///|
test "e2e/object_dunder_setattr_delegation" {
  let source =
    #|class A:
    #|  def __setattr__(self, name, value):
    #|    return object.__setattr__(self, name, value)
    #|a = A()
    #|a.x = 7
    #|print(a.x)
  inspect(e2e_stdout([], source), content="7\n")
}

///|
test "e2e/object_dunder_delattr_delegation" {
  let source =
    #|class A:
    #|  def __init__(self):
    #|    self.x = 1
    #|  def __delattr__(self, name):
    #|    return object.__delattr__(self, name)
    #|a = A()
    #|del a.x
    #|print(hasattr(a, "x"))
  inspect(e2e_stdout([], source), content="False\n")
}

///|
test "e2e/builtin_delattr" {
  let source =
    #|class A:
    #|  def __init__(self):
    #|    self.x = 1
    #|a = A()
    #|delattr(a, "x")
    #|print(hasattr(a, "x"))
  inspect(e2e_stdout([], source), content="False\n")
}

///|
test "e2e/dunder_delattr" {
  let source =
    #|log = []
    #|class A:
    #|  def __init__(self):
    #|    self.x = 1
    #|  def __delattr__(self, name):
    #|    global log
    #|    log = log + [name]
    #|a = A()
    #|delattr(a, "x")
    #|print(",".join(log))
  inspect(e2e_stdout([], source), content="x\n")
}

///|
test "e2e/builtin_super" {
  let source =
    #|class A:
    #|  def f(self):
    #|    return "A"
    #|class B(A):
    #|  def f(self):
    #|    return super(B, self).f() + "B"
    #|print(B().f())
  inspect(e2e_stdout([], source), content="AB\n")
}

///|
test "e2e/builtin_super_zero_arg" {
  let source =
    #|class A:
    #|  def f(self):
    #|    return "A"
    #|class B(A):
    #|  def f(self):
    #|    return super().f() + "B"
    #|print(B().f())
  inspect(e2e_stdout([], source), content="AB\n")
}

///|
test "e2e/descriptor_property_like" {
  let source =
    #|class P:
    #|  def __init__(self, f):
    #|    self.f = f
    #|  def __get__(self, obj, typ):
    #|    return self.f(obj)
    #|class A:
    #|  def __init__(self):
    #|    self.v = 5
    #|  def getv(self):
    #|    return self.v
    #|  v2 = P(getv)
    #|a = A()
    #|print(a.v2)
  inspect(e2e_stdout([], source), content="5\n")
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
    #|  print("caught", type(e).__name__, len(str(e)), type(e.__traceback__).__name__)
  inspect(e2e_stdout([], source), content="caught ValueError 0 traceback\n")
  let source2 =
    #|try:
    #|  raise ValueError("x")
    #|except ValueError as e:
    #|  print(type(e).__name__, str(e))
    #|  print(len(e.args), e.args[0])
    #|  print(type(e.__traceback__).__name__, type(e.__traceback__.tb_frame).__name__)
  inspect(
    e2e_stdout([], source2),
    content="ValueError x\n1 x\ntraceback frame\n",
  )
}

///|
test "e2e/except_binds_instance" {
  let source =
    #|try:
    #|  missing
    #|except NameError as e:
    #|  print(type(e).__name__)
    #|  print(str(e))
    #|  print(len(e.args), e.args[0])
    #|try:
    #|  1 / 0
    #|except ZeroDivisionError as e:
    #|  print(type(e).__name__)
    #|  print(str(e))
    #|  print(type(e.__traceback__).__name__, type(e.__traceback__.tb_frame).__name__)
  inspect(
    e2e_stdout([], source),
    content=(
      #|NameError
      #|name 'missing' is not defined
      #|1 name 'missing' is not defined
      #|ZeroDivisionError
      #|division by zero
      #|traceback frame
      #|
    ),
  )
}

///|
test "e2e/with_header_commas_in_call" {
  let source =
    #|class C:
    #|  def __enter__(self):
    #|    print("enter")
    #|    return self
    #|  def __exit__(self, exc_type, exc, tb):
    #|    print("exit")
    #|    return False
    #|class T:
    #|  def cm(self, a, b):
    #|    print("cm", a, b)
    #|    return C()
    #|  def go(self):
    #|    with self.cm(1, 2):
    #|      print("body")
    #|T().go()
  inspect(e2e_stdout([], source), content="cm 1 2\nenter\nbody\nexit\n")
}

///|
test "e2e/augassign_name_and_subscript" {
  let source =
    #|x = 2
    #|x += 5
    #|print(x)
    #|xs = [1, 2]
    #|xs[0] += 9
    #|print(xs[0])
    #|d = {"a": 1}
    #|d["a"] += 3
    #|print(d["a"])
  inspect(e2e_stdout([], source), content="7\n10\n4\n")
}

///|
fn parse_ok(source : String) -> String {
  match parse(source) {
    Ok(_) => "ok"
    Err(err) => format_parse_error(err)
  }
}

///|
test "e2e/parse_nonlocal_statement" {
  let source =
    #|def outer():
    #|  x = 0
    #|  def inner():
    #|    nonlocal x
    #|    x = x + 1
    #|  inner()
    #|  return x
    #|print(outer())
  inspect(parse_ok(source), content="ok")
}

///|
test "e2e/star_unpack_in_literals_and_kwargs" {
  let source =
    #|xs = [2, 3]
    #|ys = [1, *xs, 4]
    #|print(ys[0], ys[1], ys[2], ys[3])
    #|d1 = {"a": 1, "b": 2}
    #|d2 = {"b": 9, **d1, "c": 3}
    #|print(d2["a"], d2["b"], d2["c"])
    #|def f(a, b, c):
    #|  print(a, b, c)
    #|f(**{"a": 10, "b": 20, "c": 30})
  inspect(e2e_stdout([], source), content="1 2 3 4\n1 2 3\n10 20 30\n")
}

///|
test "e2e/slicing_step_read_del_assign" {
  let source =
    #|xs = [0, 1, 2, 3, 4, 5]
    #|ys = xs[::2]
    #|zs = xs[::-1]
    #|print(ys[0], ys[1], ys[2])
    #|print(zs[0], zs[5])
    #|s = "abcdef"
    #|print(s[::2])
    #|print(s[::-1])
    #|xs2 = [0, 1, 2, 3, 4, 5]
    #|del xs2[::2]
    #|print(xs2[0], xs2[1], xs2[2])
    #|xs3 = [0, 1, 2, 3, 4, 5]
    #|xs3[::2] = [10, 11, 12]
    #|print(xs3[0], xs3[2], xs3[4])
  inspect(
    e2e_stdout([], source),
    content="0 2 4\n5 0\nace\nfedcba\n1 3 5\n10 11 12\n",
  )
}

///|
test "e2e/slicing_step_assign_size_mismatch" {
  let source =
    #|xs = [0, 1, 2, 3, 4, 5]
    #|xs[::2] = [10, 11]
  inspect(
    e2e_stdout([], source),
    content="ERR: ValueError: attempt to assign sequence of size 2 to extended slice of size 3",
  )
}
