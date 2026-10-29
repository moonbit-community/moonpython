///|
// Python raises ValueError for arity mismatches, and preserves other failures
// from assignment targets. Comprehension lowering must not rewrite them all
// into TypeError.
test "bytecode/listcomp_unpack_mismatch_preserves_valueerror" {
  inspect(
    test_exec_error("[a for a, b, c in [(1, 2)]]"),
    content="ValueError: not enough values to unpack (expected 3)",
  )
  inspect(
    test_exec_error("[a for a, b in [(1, 2, 3)]]"),
    content="ValueError: too many values to unpack (expected 2)",
  )
  let source =
    #|class Box:
    #|    def __setattr__(self, name, value):
    #|        raise RuntimeError('setter failed')
    #|box = Box()
    #|[a for a, box.x in [(1, 2)]]
  inspect(test_exec_error(source), content="RuntimeError: setter failed")
}
