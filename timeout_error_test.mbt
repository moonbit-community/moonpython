///|
/// Builtin exception coverage for stdlib compatibility.

///|
test "exceptions/TimeoutError" {
  let source =
    #|ok = 0
    #|try:
    #|  raise TimeoutError("x")
    #|except TimeoutError:
    #|  ok = 1
  inspect(test_exec_global(source, "ok"), content="1")
}
