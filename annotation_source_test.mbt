///|
test "spec interpreter inherits postponed annotations and stores normalized strings" {
  let source =
    #|events = []
    #|def touch():
    #|    events.append('called')
    #|    return int
    #|x: ((Missing | list[tuple[A, B]])) = 7
    #|y: touch()
    #|def f(arg: touch()) -> Missing: pass
    #|print(x, events)
    #|print(__annotations__)
    #|print(f.__annotations__)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "7 []\n{'x': 'Missing | list[tuple[A, B]]', 'y': 'touch()'}\n{'arg': 'touch()', 'return': 'Missing'}\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "future annotations validate forbidden expressions without evaluating them" {
  for
    source in [
      "def f(x: (yield)): pass", "def f(x: (yield from x)): pass", "def f(x: (y := 3)): pass",
      "x: (y := 3)", "def outer():\n  def f(x: (y := 3)): pass",
    ] {
    match @moonpython.Interpreter::new_spec().exec_source(source) {
      Err(err) =>
        assert_true(
          @moonpython.format_runtime_error(err).contains("invalid syntax"),
        )
      Ok(_) => fail("forbidden annotation expression was accepted")
    }
  }
  let source =
    #|x: (lambda: (y := 1))
    #|y: (lambda: (yield))
    #|z: [item async for item in Missing]
    #|print(__annotations__)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "{'x': 'lambda: (y := 1)', 'y': 'lambda: (yield)', 'z': '[item async for item in Missing]'}\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "ordinary interpreter retains eager annotations" {
  match @moonpython.Interpreter::new().exec_source("x: Missing") {
    Err(err) =>
      assert_eq(
        @moonpython.format_runtime_error(err),
        "NameError: name 'Missing' is not defined",
      )
    Ok(_) => fail("ordinary annotations became deferred")
  }
}

///|
test "postponed class and method annotations retain their strings" {
  let source =
    #|__name__ = 'example'
    #|class C:
    #|    x: Missing
    #|    def f(self, x: Missing) -> list[Missing]: pass
    #|print(C.__annotations__, C.f.__annotations__)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "{'x': 'Missing'} {'x': 'Missing', 'return': 'list[Missing]'}\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "local annotations do not execute or populate annotation dictionaries" {
  let source =
    #|events = []
    #|def touch():
    #|    events.append('annotation')
    #|    return int
    #|def f():
    #|    x: touch() = 7
    #|    if True:
    #|        y: Missing
    #|    return x
    #|def g():
    #|    x: touch() = 8
    #|    yield x
    #|print(f(), list(g()), events)
  for
    interpreter in [
      @moonpython.Interpreter::new(),
      @moonpython.Interpreter::new_spec(),
    ] {
    match interpreter.exec_source(source) {
      Ok(run) => assert_eq(run.stdout, "7 [8] []\n")
      Err(err) => fail(@moonpython.format_runtime_error(err))
    }
  }
}

///|
test "annotation expression normalization includes generator calls and f strings" {
  let source =
    #|a: list(x for x in source)
    #|b: 1 .real
    #|c: f"{x+1}"
    #|d: f"{x=}"
    #|print(__annotations__['a'], __annotations__['b'], __annotations__['c'], __annotations__['d'])
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "list(x for x in source) 1 .real f'{x + 1}' f'x={x!r}'\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
  for
    source in [
      "x: f'{(y:=3)}'", "x: f'{(yield)}'", "x: f'{value:{(width:=3)}}'",
    ] {
    match @moonpython.Interpreter::new_spec().exec_source(source) {
      Err(err) =>
        assert_true(
          @moonpython.format_runtime_error(err).contains("invalid syntax"),
        )
      Ok(_) => fail("forbidden expression in deferred f string")
    }
  }
}
