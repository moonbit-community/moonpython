///|
test "generator comprehension targets remain local under enclosing global declarations" {
  let source =
    #|x = 99
    #|def g():
    #|    global x
    #|    yield [x for x in [1, 2]]
    #|print(list(g()), x)
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[[1, 2]] 99\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "generator comprehensions isolate nonlocal and underscore iteration cells" {
  let source =
    #|def outer():
    #|    x = 99
    #|    _ = 77
    #|    def g():
    #|        nonlocal x
    #|        yield {x: x + 1 for x in [1, 2]}
    #|        yield {_ for _ in [3, 4]}
    #|        yield list(_ for _ in [5, 6])
    #|    print(list(g()), x, _)
    #|outer()
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[{1: 2, 2: 3}, {3, 4}, [5, 6]] 99 77\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "comprehensions preserve free global and walrus bindings and restore scope after errors" {
  let source =
    #|x = 99
    #|result = 0
    #|def g():
    #|    global x, result
    #|    yield [(result := x) for x in [1, 2]]
    #|    try:
    #|        yield [1 // x for x in [0]]
    #|    except ZeroDivisionError:
    #|        yield x
    #|    yield [x for item in [0]]
    #|print(list(g()), x, result)
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[[1, 2], 99, [99]] 99 2\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "class comprehension validation traverses f-string expressions and format fields" {
  for
    source in [
      "class C:\n    values = [f'{(y := x)}' for x in range(2)]", "class C:\n    values = [f'{x:{(y := 2)}}' for x in range(2)]",
    ] {
    match @moonpython.parse(source) {
      Err(_) => ()
      Ok(_) => fail("class comprehension assignment expression was accepted")
    }
  }
  let source =
    #|class C:
    #|    values = [f'{(lambda: (y := x))()}' for x in range(2)]
    #|print(C.values)
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "['0', '1']\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "bytecode generator expressions retain separate target cells" {
  let source =
    #|def f():
    #|    x = 99
    #|    _ = 77
    #|    values = list(x for x in [1, 2])
    #|    other = list(_ for _ in [3, 4])
    #|    print(values, other, x, _)
    #|f()
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[1, 2] [3, 4] 99 77\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "async generator expression target scope survives suspension" {
  let source =
    #|x = 99
    #|result = 0
    #|async def items():
    #|    yield 1
    #|    yield 2
    #|async def make():
    #|    global x, result
    #|    return ((result := x) async for x in items())
    #|async def run():
    #|    global x
    #|    gen = await make()
    #|    values = [value async for value in gen]
    #|    return values, x, result
    #|print(__mpython_run(run()))
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "([1, 2], 99, 2)\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}

///|
test "suspended generator expressions keep enclosing global and nonlocal walrus bindings" {
  let source =
    #|result = 0
    #|def make_sync():
    #|    global result
    #|    return ((result := x) for x in [1, 2])
    #|print(list(make_sync()), result)
    #|def outer():
    #|    result = 0
    #|    async def items():
    #|        yield 3
    #|        yield 4
    #|    async def make():
    #|        nonlocal result
    #|        return ((result := x) async for x in items())
    #|    def read():
    #|        return result
    #|    return make, read
    #|make, read = outer()
    #|async def consume():
    #|    gen = await make()
    #|    return [value async for value in gen]
    #|print(__mpython_run(consume()), read())
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) => assert_eq(run.stdout, "[1, 2] 2\n[3, 4] 4\n")
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}
