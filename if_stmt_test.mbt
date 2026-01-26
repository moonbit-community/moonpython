///|
/// `if` statement parsing (including single-line suites with elif/else).

///|
test "if/single_line_with_elif_else" {
  let source =
    #|x = 0
    #|for k in [2, 4, 8]:
    #|  if k == 2: x = 1
    #|  elif k == 4: x = 2
    #|  else: x = 3
  inspect(test_exec_global(source, "x"), content="3")
}

///|
test "if/single_line_chain_without_block" {
  let source =
    #|x = 0
    #|if False: x = 1
    #|elif True: x = 2
    #|else: x = 3
  inspect(test_exec_global(source, "x"), content="2")
}
