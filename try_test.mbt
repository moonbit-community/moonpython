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
