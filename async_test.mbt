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

///|
test "async/with_basic" {
  let source =
    #|log = []
    #|class CM:
    #|  async def __aenter__(self):
    #|    global log
    #|    log = log + ["enter"]
    #|    return 7
    #|  async def __aexit__(self, t, v, tb):
    #|    global log
    #|    log = log + ["exit"]
    #|    return False
    #|async def f():
    #|  global log
    #|  async with CM() as v:
    #|    log = log + ["v=" + str(v)]
    #|  return ",".join(log)
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="enter,v=7,exit\n")
}

///|
test "async/with_suppresses" {
  let source =
    #|log = []
    #|class CM:
    #|  async def __aenter__(self):
    #|    global log
    #|    log = log + ["enter"]
    #|    return 0
    #|  async def __aexit__(self, t, v, tb):
    #|    global log
    #|    log = log + ["exit:" + t]
    #|    return True
    #|async def f():
    #|  global log
    #|  async with CM():
    #|    missing
    #|  log = log + ["after"]
    #|  return ",".join(log)
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="enter,exit:NameError,after\n")
}

///|
test "async/for_basic" {
  let source =
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __aiter__(self):
    #|    return self
    #|  async def __anext__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 3:
    #|      return self.i
    #|    raise StopAsyncIteration
    #|async def f():
    #|  s = 0
    #|  async for x in It():
    #|    s = s + x
    #|  return s
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="6\n")
}

///|
test "async/for_else" {
  let source =
    #|log = []
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __aiter__(self):
    #|    return self
    #|  async def __anext__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 2:
    #|      return self.i
    #|    raise StopAsyncIteration
    #|async def f():
    #|  global log
    #|  async for x in It():
    #|    log = log + [x]
    #|  else:
    #|    log = log + ["done"]
    #|  return str(log)
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[1, 2, done]\n")
}
