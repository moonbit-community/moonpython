///|
/// Ordering comparisons for sequences (tuple/list lexicographic compare).

///|
test "compare/tuple_lexicographic" {
  let source =
    #|a = (3, 12)
    #|b = (3, 13)
    #|lt = a < b
    #|gt = a > b
    #|eq = a <= a
  inspect(test_exec_global(source, "lt"), content="True")
  inspect(test_exec_global(source, "gt"), content="False")
  inspect(test_exec_global(source, "eq"), content="True")
}

///|
test "compare/list_lexicographic" {
  let source =
    #|a = [1, 2]
    #|b = [1, 3]
    #|lt = a < b
    #|gt = a > b
  inspect(test_exec_global(source, "lt"), content="True")
  inspect(test_exec_global(source, "gt"), content="False")
}
