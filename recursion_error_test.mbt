///|
/// Builtin exception coverage for stdlib compatibility.

///|
test "exceptions/RecursionError" {
  let source =
    #|ok = 0
    #|ok2 = 0
    #|try:
    #|  raise RecursionError("x")
    #|except RecursionError:
    #|  ok = 1
    #|try:
    #|  raise RecursionError("x")
    #|except RuntimeError:
    #|  ok2 = 1
  inspect(test_exec_global(source, "ok"), content="1")
  inspect(test_exec_global(source, "ok2"), content="1")
}
