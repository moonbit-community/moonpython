///|
/// Async/await baseline tests.

///|
test "async/call_returns_coroutine_does_not_run_body" {
  let source =
    #|async def f():
    #|  print("x")
    #|  return 1
    #|c = f()
    #|print(c)
  inspect(run_stdout(source), content="<coroutine object>\n")
}

///|
test "async/mpython_run_executes_coroutine" {
  let source =
    #|async def f():
    #|  print("start")
    #|  return 3
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="start\n3\n")
}

///|
test "async/await_nested_coroutine" {
  let source =
    #|async def f():
    #|  return 40
    #|async def g():
    #|  x = await f()
    #|  return x + 2
    #|print(__mpython_run(g()))
  inspect(run_stdout(source), content="42\n")
}

///|
test "async/await_non_coroutine_errors" {
  let source =
    #|async def g():
    #|  await 1
    #|__mpython_run(g())
  inspect(
    run_stdout(source),
    content="ERR: TypeError: 'int' object can't be used in 'await' expression",
  )
}

///|
test "async/await_outside_async_function_is_syntax_error" {
  inspect(test_exec_error("await 1"), content="line 1:1 invalid syntax")
}

///|
test "async/cannot_reuse_coroutine" {
  let source =
    #|async def f():
    #|  return 1
    #|c = f()
    #|__mpython_run(c)
    #|__mpython_run(c)
  inspect(
    test_exec_error(source),
    content="RuntimeError: cannot reuse already awaited coroutine",
  )
}
