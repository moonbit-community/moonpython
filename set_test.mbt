///|
/// Set behavior tests.

///|
test "set/numeric_dedupe" {
  let source =
    #|print(len({1, True, 1.0}))
  inspect(run_stdout(source), content="1\n")
}

///|
test "set/methods" {
  let source =
    #|s = set()
    #|s.add(1)
    #|s.add(1)
    #|print(len(s))
    #|s.discard(2)
    #|print(1 in s)
    #|s.remove(1)
    #|print(len(s))
  inspect(run_stdout(source), content="1\nTrue\n0\n")
}

///|
test "set/update" {
  let source =
    #|s = {1}
    #|s.update([2, 2, 3])
    #|print(s)
  inspect(run_stdout(source), content="{1, 2, 3}\n")
}

///|
test "set/unhashable_item" {
  let source =
    #|s = set()
    #|s.add([])
  inspect(test_exec_error(source), content="TypeError: unhashable type: 'list'")
}
