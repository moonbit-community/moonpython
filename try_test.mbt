///|
/// Try/except/else/finally tests.

///|
fn run_stdout_try(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "try/except NameError" {
  let source =
    #|flag = 0
    #|try:
    #|  x
    #|except NameError:
    #|  flag = 1
  inspect(test_exec_global(source, "flag"), content="1")
}

///|
test "try/finally runs after handler error" {
  let source =
    #|log = []
    #|try:
    #|  try:
    #|    x
    #|  except:
    #|    y
    #|  finally:
    #|    log = [1]
    #|except:
    #|  pass
  inspect(test_exec_global(source, "log"), content="[1]")
}

///|
test "try/finally runs after else error" {
  let source =
    #|log = []
    #|try:
    #|  try:
    #|    pass
    #|  except:
    #|    pass
    #|  else:
    #|    y
    #|  finally:
    #|    log = [1]
    #|except:
    #|  pass
  inspect(test_exec_global(source, "log"), content="[1]")
}

///|
test "try requires except or finally" {
  let source =
    #|try:
    #|  pass
  inspect(test_exec_error(source), content="line 1:1 invalid syntax")
}

///|
test "try else requires except" {
  let source =
    #|try:
    #|  pass
    #|else:
    #|  pass
    #|finally:
    #|  pass
  inspect(test_exec_error(source), content="line 3:1 invalid syntax")
}

///|
test "raise/from_none_is_parsed_and_runs" {
  let source =
    #|flag = 0
    #|try:
    #|  raise ValueError("x") from None
    #|except ValueError:
    #|  flag = 1
  inspect(test_exec_global(source, "flag"), content="1")
}

///|
test "raise/from_requires_cause_expression" {
  inspect(
    test_exec_error("raise ValueError from"),
    content="line 1:1 invalid syntax",
  )
}

///|
test "raise/bare_reraises_in_except" {
  let source =
    #|flag = 0
    #|try:
    #|  try:
    #|    1 / 0
    #|  except ZeroDivisionError:
    #|    raise
    #|except ZeroDivisionError:
    #|  flag = 1
  inspect(test_exec_global(source, "flag"), content="1")
}

///|
test "except/tuple_matches" {
  let source =
    #|flag = 0
    #|try:
    #|  1 / 0
    #|except (ValueError, ZeroDivisionError):
    #|  flag = 1
  inspect(test_exec_global(source, "flag"), content="1")
}

///|
test "except/subclass_matches" {
  let source =
    #|flag = 0
    #|try:
    #|  raise IndentationError("x")
    #|except SyntaxError:
    #|  flag = 1
  inspect(test_exec_global(source, "flag"), content="1")
}

///|
test "raise/from_sets_context_and_suppresses" {
  let source =
    #|try:
    #|  try:
    #|    1 / 0
    #|  except ZeroDivisionError:
    #|    raise ValueError("x") from None
    #|except ValueError as e:
    #|  print(e.__cause__)
    #|  print(e.__context__)
    #|  print(e.__suppress_context__)
  inspect(run_stdout_try(source), content="None\ndivision by zero\nTrue\n")
}

///|
test "raise/from_explicit_cause_sets_cause" {
  let source =
    #|try:
    #|  try:
    #|    1 / 0
    #|  except ZeroDivisionError:
    #|    raise ValueError("x") from KeyError("k")
    #|except ValueError as e:
    #|  print(e.__cause__)
    #|  print(e.__context__)
    #|  print(e.__suppress_context__)
  inspect(run_stdout_try(source), content="k\ndivision by zero\nTrue\n")
}

///|
test "raise/from_rejects_non_exception_cause" {
  let source =
    #|try:
    #|  raise ValueError("x") from 5
    #|except ValueError:
    #|  pass
  inspect(
    test_exec_error(source),
    content="TypeError: exceptions must derive from BaseException",
  )
}

///|
test "except_star_handles_groups" {
  let source =
    #|log = []
    #|try:
    #|  raise ExceptionGroup("boom", [ValueError("a"), KeyError("b")])
    #|except* ValueError:
    #|  log.append("value")
    #|except* KeyError:
    #|  log.append("key")
    #|print(log)
  inspect(run_stdout_try(source), content="[value, key]\n")
}

///|
test "except_star_reraises_remaining" {
  let source =
    #|log = []
    #|try:
    #|  try:
    #|    raise ExceptionGroup("boom", [ValueError("a"), KeyError("b")])
    #|  except* ValueError:
    #|    log.append("value")
    #|except* KeyError:
    #|  log.append("key")
    #|print(log)
  inspect(run_stdout_try(source), content="[value, key]\n")
}

///|
test "except_star_binds_group" {
  let source =
    #|count = 0
    #|try:
    #|  raise ExceptionGroup("boom", [ValueError("a"), ValueError("b")])
    #|except* ValueError as eg:
    #|  count = len(eg.exceptions)
  inspect(test_exec_global(source, "count"), content="2")
}

///|
test "except_star_requires_type" {
  let source =
    #|try:
    #|  pass
    #|except*:
    #|  pass
  inspect(test_exec_error(source), content="line 3:1 invalid syntax")
}

///|
test "except_star_cannot_mix_with_except" {
  let source =
    #|try:
    #|  pass
    #|except* ValueError:
    #|  pass
    #|except Exception:
    #|  pass
  inspect(test_exec_error(source), content="line 5:1 invalid syntax")
}
