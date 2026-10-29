///|
test "match validates unreachable and duplicate captures" {
  for
    source in [
      "match 1:\n  case x:\n    pass\n  case _:\n    pass", "match (1, 2):\n  case (x, x):\n    pass",
      "match 1:\n  case a + 1:\n    pass",
    ] {
    match @moonpython.Interpreter::new_spec().exec_source(source) {
      Err(err) =>
        assert_eq(
          @moonpython.format_runtime_error(err),
          "line 2:1 invalid syntax",
        )
      Ok(_) => fail("invalid pattern was accepted")
    }
  }
}

///|
test "match literal patterns compare values and guarded captures remain refutable" {
  let source =
    #|match 'b':
    #|    case 'a': print('wrong')
    #|    case x if False: print('wrong')
    #|    case 'b': print('right')
    #|match None:
    #|    case {}: print('wrong')
    #|    case _: print('none')
    #|match {'a': 1}:
    #|    case {}: print('mapping')
  let result = @moonpython.Interpreter::new_spec().exec_source(source)
  match result {
    Ok(run) => assert_eq(run.stdout, "right\nnone\nmapping\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "annotated assignment evaluates value before annotation" {
  let source =
    #|events = []
    #|def value():
    #|    events.append('value')
    #|    return 7
    #|def annotation():
    #|    events.append('annotation')
    #|    return int
    #|x: annotation() = value()
    #|print(events, x)
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "['value', 'annotation'] 7\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "scope declarations reject earlier assignment use and annotation" {
  for
    source in [
      "def f():\n  x = 1\n  global x", "def f():\n  print(x)\n  global x", "def f():\n  x: int\n  global x",
      "def f(x):\n  if True:\n    global x", "def outer():\n  x = 1\n  def inner():\n    print(x)\n    nonlocal x",
    ] {
    match @moonpython.Interpreter::new_spec().exec_source(source) {
      Err(err) =>
        assert_true(
          @moonpython.format_runtime_error(err).contains("invalid syntax"),
        )
      Ok(_) => fail("invalid scope declaration was accepted")
    }
  }
}

///|
test "scope validation respects nested function and comprehension scopes" {
  let source =
    #|def f():
    #|    def inner():
    #|        return x
    #|    [x for x in [1, 2]]
    #|    global x
    #|    x = 3
    #|f()
    #|print(x)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "3\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "standalone dict comprehension executes its body" {
  let source =
    #|seen = []
    #|{i: seen.append(i) for i in range(3)}
    #|print(seen)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[0, 1, 2]\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}
