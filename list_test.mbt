///|
/// List method tests.

///|
test "list/append mutates and returns none" {
  let source =
    #|xs = []
    #|r = xs.append(1)
    #|xs.append(2)
  inspect(test_exec_global(source, "xs"), content="[1, 2]")
  inspect(test_exec_global(source, "r"), content="None")
}

///|
test "list/pop default index" {
  let source =
    #|xs = [1, 2, 3]
    #|a = xs.pop()
    #|b = xs.pop()
  inspect(test_exec_global(source, "a"), content="3")
  inspect(test_exec_global(source, "b"), content="2")
  inspect(test_exec_global(source, "xs"), content="[1]")
}

///|
test "list/pop explicit index" {
  let source =
    #|xs = [1, 2, 3]
    #|v = xs.pop(0)
  inspect(test_exec_global(source, "v"), content="1")
  inspect(test_exec_global(source, "xs"), content="[2, 3]")
}

///|
test "list/pop negative index" {
  let source =
    #|xs = [1, 2, 3]
    #|v = xs.pop(-2)
  inspect(test_exec_global(source, "v"), content="2")
  inspect(test_exec_global(source, "xs"), content="[1, 3]")
}

///|
test "list/pop empty raises" {
  let source =
    #|xs = []
    #|xs.pop()
  inspect(test_exec_error(source), content="IndexError: pop from empty list")
}
