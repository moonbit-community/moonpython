///|
/// Try/except/else/finally tests.

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
