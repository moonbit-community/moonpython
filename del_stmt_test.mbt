///|
/// `del` statement parsing.

///|
test "del/parenthesized_target" {
  let source =
    #|x = 1
    #|del(x)
  inspect(test_exec_global(source, "x"), content="<missing>")
}
