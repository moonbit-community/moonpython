///|
test "comprehensions preserve nested unpacking attribute and subscript targets" {
  let source =
    #|items = [0]
    #|print([items[0] for items[0] in [3, 4]])
    #|print(items)
    #|print([a + b + c for (a, [b, c]) in [(1, [2, 3])]])
    #|print([1 for () in [(), ()]])
    #|print([_ for _ in [1, 2]])
    #|print(list(a + b for (a, b) in [(2, 3), (4, 5)]))
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(run.stdout, "[3, 4]\n[4]\n[6]\n[1, 1]\n[1, 2]\n[5, 9]\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
  let source =
    #|class Box: pass
    #|box = Box()
    #|print([box.value for box.value in [5, 6]])
    #|print(box.value)
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[5, 6]\n6\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "comprehension filters execute at their own loop depth" {
  let source =
    #|events = []
    #|def outer(x):
    #|    events.append(x)
    #|    return x != 0
    #|def inner(x):
    #|    events.append(x + 10)
    #|    return [1, 2]
    #|print([(x, y) for x in [0, 1] if outer(x) for y in inner(x) if y == 2])
    #|print(events)
    #|events = []
    #|print(list((x, y) for x in [0, 1] if outer(x) for y in inner(x) if y == 2))
    #|print(events)
    #|events = []
    #|print({x: y for x in [0, 1] if outer(x) for y in inner(x) if y == 2})
    #|print(events)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "[(1, 2)]\n[0, 1, 11]\n[(1, 2)]\n[0, 1, 11]\n{1: 2}\n[0, 1, 11]\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "postponed annotation strings preserve comprehension target and filter structure" {
  let source =
    #|a: {k: v for k in outer if k for v in inner if v}
    #|b: [x for () in source]
    #|c: [x for box[0] in source]
    #|d: {**mapping}
    #|e: tuple[()]
    #|f: 2 ** -1
    #|print(__annotations__)
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "{'a': '{k: v for k in outer if k for v in inner if v}', 'b': '[x for () in source]', 'c': '[x for box[0] in source]', 'd': '{**mapping}', 'e': 'tuple[()]', 'f': '2 ** -1'}\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "class scope validation respects methods and lambda bodies" {
  for
    source in [
      "class C:\n  nonlocal x", "class C:\n  [(y := x) for x in range(2)]", "class C: [(y := x) for x in range(2)]",
    ] {
    match @moonpython.Interpreter::new_spec().exec_source(source) {
      Err(err) =>
        assert_true(
          @moonpython.format_runtime_error(err).contains("invalid syntax"),
        )
      Ok(_) => fail("invalid class scope was accepted")
    }
  }
  let source =
    #|class C:
    #|    f = lambda: [(y := x) for x in range(2)]
    #|    def g(self): return [(y := x) for x in range(2)]
    #|print(C.f(), C().g())
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[0, 1] [0, 1]\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "unpacked parameter annotations and source positions are retained" {
  let source =
    #|def f(*args: *Ts): pass
    #|print(f.__annotations__)
    #|positions = list(f.__code__.co_positions())
    #|print(any(column is not None for line, end_line, column, end_column in positions))
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "{'args': '*Ts'}\nTrue\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "earlier list syntax errors take precedence over later invalid tokens" {
  for source in ["[\nfirst\nsecond\n]!", "[\nfirst\nsecond\n]"] {
    match @moonpython.parse(source) {
      Err(err) =>
        assert_eq(
          @moonpython.format_parse_error(err),
          "line 2:1 invalid syntax",
        )
      Ok(_) => fail("missing comma was accepted")
    }
  }
  match @moonpython.parse("[first]!") {
    Err(err) =>
      assert_eq(@moonpython.format_parse_error(err), "line 1:1 invalid syntax")
    Ok(_) => fail("invalid trailing token was accepted")
  }
}
