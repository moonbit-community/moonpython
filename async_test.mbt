///|
/// Async/await baseline tests.

///|
fn run_stdout_allow_imports(source : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

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
test "async/with_return_runs_exit" {
  let source =
    #|log = []
    #|class CM:
    #|  async def __aenter__(self):
    #|    global log
    #|    log = log + ["enter"]
    #|    return 0
    #|  async def __aexit__(self, t, v, tb):
    #|    global log
    #|    log = log + ["exit"]
    #|    return False
    #|async def f():
    #|  async with CM():
    #|    return 5
    #|print(__mpython_run(f()))
    #|print(",".join(log))
  inspect(run_stdout(source), content="5\nenter,exit\n")
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

///|
test "async/listcomp" {
  let source =
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
    #|  return [x async for x in It()]
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[1, 2]\n")
}

///|
test "async/setcomp_dictcomp" {
  let source =
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
    #|  s = {x async for x in It()}
    #|  d = {x: x + 1 async for x in It()}
    #|  return (s, d)
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="({1, 2}, {1: 2, 2: 3})\n")
}

///|
test "async/comp_outside_async_function_is_syntax_error" {
  let source =
    #|class It:
    #|  def __aiter__(self):
    #|    return self
    #|  async def __anext__(self):
    #|    raise StopAsyncIteration
    #|xs = [x async for x in It()]
  inspect(test_exec_error(source), content="line 6:1 invalid syntax")
}

///|
test "async/genexpr" {
  let source =
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
    #|  out = []
    #|  async for x in (x async for x in It()):
    #|    out = out + [x]
    #|  return out
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[1, 2]\n")
}

///|
test "async/genexpr_outside_async_function" {
  let source =
    #|class It:
    #|  def __aiter__(self):
    #|    return self
    #|  async def __anext__(self):
    #|    raise StopAsyncIteration
    #|xs = (x async for x in It())
    #|async def f():
    #|  return [x async for x in xs]
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[]\n")
}

///|
test "async/async_generator_basic" {
  let source =
    #|async def gen():
    #|  yield 1
    #|  yield 2
    #|async def f():
    #|  out = []
    #|  async for x in gen():
    #|    out = out + [x]
    #|  return out
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[1, 2]\n")
}

///|
test "async/genexpr_with_await_outside_async_function" {
  let source =
    #|async def wrap(x):
    #|  return x
    #|def make(n):
    #|  return (i for i in range(n) if await wrap(i))
    #|async def f():
    #|  out = []
    #|  async for i in make(3):
    #|    out = out + [i]
    #|  return out
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[1, 2]\n")
}

///|
test "async/async_generator_awaits" {
  let source =
    #|async def inner():
    #|  return 3
    #|async def gen():
    #|  v = await inner()
    #|  yield v
    #|async def f():
    #|  out = []
    #|  async for x in gen():
    #|    out = out + [x]
    #|  return out
    #|print(__mpython_run(f()))
  inspect(run_stdout(source), content="[3]\n")
}

///|
test "async/asyncio_run" {
  let source =
    #|import asyncio
    #|async def f():
    #|  return 9
    #|print(asyncio.run(f()))
  inspect(run_stdout_allow_imports(source), content="9\n")
}

///|
test "async/asyncio_gather" {
  let source =
    #|import asyncio
    #|async def f():
    #|  return 1
    #|async def g():
    #|  return 2
    #|print(asyncio.gather(f(), g()))
  inspect(run_stdout_allow_imports(source), content="[1, 2]\n")
}
