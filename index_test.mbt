///|
/// Subscript/indexing tests.

///|
test "subscript/negative index list" {
  let source =
    #|xs = [1, 2, 3]
    #|v = xs[-1]
  inspect(test_exec_global(source, "v"), content="3")
}

///|
test "subscript/negative index tuple" {
  let source =
    #|xs = (1, 2, 3)
    #|v = xs[-2]
  inspect(test_exec_global(source, "v"), content="2")
}

///|
test "subscript/negative index str" {
  let source =
    #|s = "abc"
    #|v = s[-2]
  inspect(test_exec_global(source, "v"), content="b")
}

///|
test "subscript/negative out of range" {
  let source =
    #|xs = [1]
    #|x = xs[-2]
  inspect(test_exec_error(source), content="IndexError: index out of range")
}
