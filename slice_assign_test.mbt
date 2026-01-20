///|
/// Slice assignment tests.

///|
test "slice_assign/step_replace" {
  let source =
    #|xs = [0, 1, 2, 3, 4]
    #|xs[1:4:2] = [9, 8]
    #|print(xs)
  inspect(run_stdout(source), content="[0, 9, 2, 8, 4]\n")
}

///|
test "slice_assign/replace_extend" {
  let source =
    #|xs = [1, 2, 3, 4]
    #|xs[1:3] = [9, 8, 7]
    #|print(xs)
  inspect(run_stdout(source), content="[1, 9, 8, 7, 4]\n")
}

///|
test "slice_assign/negative_step" {
  let source =
    #|xs = [0, 1, 2, 3, 4]
    #|xs[4:0:-2] = [9, 8]
    #|print(xs)
  inspect(run_stdout(source), content="[0, 1, 8, 3, 9]\n")
}

///|
test "slice_assign/step_length_mismatch" {
  let source =
    #|xs = [0, 1, 2, 3]
    #|xs[::2] = [1]
  inspect(
    test_exec_error(source),
    content="ValueError: attempt to assign sequence of size 1 to extended slice of size 2",
  )
}

///|
test "slice_assign/step_zero" {
  let source =
    #|xs = [1, 2, 3]
    #|xs[::0] = [1]
  inspect(
    test_exec_error(source),
    content="ValueError: slice step cannot be zero",
  )
}
