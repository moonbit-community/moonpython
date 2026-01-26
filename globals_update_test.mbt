///|
/// `globals()` behaviors needed by CPython stdlib imports.

///|
test "globals/update_accepts_iterable_pairs" {
  let source =
    #|globals().update([("a", 1), ("b", 2)])
  inspect(test_exec_global(source, "a"), content="1")
  inspect(test_exec_global(source, "b"), content="2")
}
