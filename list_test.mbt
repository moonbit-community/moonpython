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

///|
test "list/extend" {
  let source =
    #|xs = [1]
    #|r1 = xs.extend([2, 3])
    #|r2 = xs.extend("ab")
  inspect(test_exec_global(source, "xs"), content="[1, 2, 3, a, b]")
  inspect(test_exec_global(source, "r1"), content="None")
  inspect(test_exec_global(source, "r2"), content="None")
}

///|
test "list/insert" {
  let source =
    #|xs = [1, 2, 3]
    #|r1 = xs.insert(-1, 9)
    #|r2 = xs.insert(-100, 8)
    #|r3 = xs.insert(100, 7)
  inspect(test_exec_global(source, "xs"), content="[8, 1, 2, 9, 3, 7]")
  inspect(test_exec_global(source, "r1"), content="None")
  inspect(test_exec_global(source, "r2"), content="None")
  inspect(test_exec_global(source, "r3"), content="None")
}

///|
test "list/remove" {
  let source =
    #|xs = [1, 2, 3, 2]
    #|r = xs.remove(2)
  inspect(test_exec_global(source, "xs"), content="[1, 3, 2]")
  inspect(test_exec_global(source, "r"), content="None")
}

///|
test "list/remove missing raises" {
  let source =
    #|xs = [1, 2]
    #|xs.remove(9)
  inspect(
    test_exec_error(source),
    content="ValueError: list.remove(x): x not in list",
  )
}

///|
test "list/clear" {
  let source =
    #|xs = [1, 2]
    #|r = xs.clear()
  inspect(test_exec_global(source, "xs"), content="[]")
  inspect(test_exec_global(source, "r"), content="None")
}

///|
test "list/reverse" {
  let source =
    #|xs = [1, 2, 3]
    #|r = xs.reverse()
  inspect(test_exec_global(source, "xs"), content="[3, 2, 1]")
  inspect(test_exec_global(source, "r"), content="None")
}

///|
test "list-subclass/reverse" {
  let source =
    #|class L(list):
    #|  pass
    #|x = L()
    #|x.append(1)
    #|x.append(2)
    #|x.append(3)
    #|x.reverse()
    #|out = list(x)
  inspect(test_exec_global(source, "out"), content="[3, 2, 1]")
}
