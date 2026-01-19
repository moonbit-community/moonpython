///|
/// Generator tests (`yield`, `yield from`) and iterator protocol integration.

///|
fn run_stdout(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "generator/lazy_incremental_next" {
  let source =
    #|def g():
    #|  print("a")
    #|  yield 1
    #|  print("b")
    #|  yield 2
    #|x = g()
    #|print("x")
    #|print(next(x))
    #|print("y")
    #|print(next(x))
  inspect(run_stdout(source), content="x\na\n1\ny\nb\n2\n")
}

///|
test "generator/for_loop_consumes_incrementally" {
  let source =
    #|def g():
    #|  print("a")
    #|  yield 1
    #|  print("b")
    #|  yield 2
    #|for x in g():
    #|  print("x=" + str(x))
  inspect(run_stdout(source), content="a\nx=1\nb\nx=2\n")
}

///|
test "generator/yield_from_sequence" {
  let source =
    #|def g():
    #|  yield from [1, 2]
    #|for x in g():
    #|  print(x)
  inspect(run_stdout(source), content="1\n2\n")
}

///|
test "generator/genexp_next_and_for" {
  let source =
    #|xs = (x * x for x in [1, 2, 3])
    #|print(next(xs))
    #|for v in xs:
    #|  print(v)
  inspect(run_stdout(source), content="1\n4\n9\n")
}

///|
test "generator/send_assigns_yield_expression_result" {
  let source =
    #|def g():
    #|  x = yield 1
    #|  yield x
    #|it = g()
    #|print(it.send(None))
    #|print(it.send(41))
  inspect(run_stdout(source), content="1\n41\n")
}

///|
test "generator/send_non_none_before_start_errors" {
  let source =
    #|def g():
    #|  yield 1
    #|it = g()
    #|it.send(1)
  inspect(
    run_stdout(source),
    content="ERR: TypeError: can't send non-None value to a just-started generator",
  )
}

///|
test "generator/close_stops_iteration" {
  let source =
    #|def g():
    #|  yield 1
    #|  yield 2
    #|it = g()
    #|print(next(it))
    #|print(it.close())
    #|print(next(it, 99))
  inspect(run_stdout(source), content="1\nNone\n99\n")
}

///|
test "generator/throw_raises_and_closes" {
  let source =
    #|def g():
    #|  yield 1
    #|  yield 2
    #|it = g()
    #|print(next(it))
    #|try:
    #|  it.throw(ValueError("bad"))
    #|except ValueError:
    #|  print("caught")
    #|print(next(it, 99))
  inspect(run_stdout(source), content="1\ncaught\n99\n")
}

///|
test "generator/return_sets_stopiteration_args" {
  let source =
    #|def g():
    #|  yield 1
    #|  return 5
    #|it = g()
    #|print(next(it))
    #|try:
    #|  next(it)
    #|except StopIteration as e:
    #|  print(e.args)
    #|  print(e.value)
  inspect(run_stdout(source), content="1\n(5,)\n5\n")
}

///|
test "generator/yield_from_expression_returns_subgenerator_return" {
  let source =
    #|def sub():
    #|  yield 1
    #|  return 7
    #|def g():
    #|  x = yield from sub()
    #|  print(x)
    #|it = g()
    #|print(next(it))
    #|print(next(it, 99))
  inspect(run_stdout(source), content="1\n7\n99\n")
}

///|
test "generator/yield_outside_function_is_syntax_error" {
  inspect(test_exec_error("yield 1"), content="line 1:1 invalid syntax")
}
