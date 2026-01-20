///|
/// Container protocol tests (`__iter__`, `__next__`, `__contains__`, `__len__`).

///|
test "protocol/iter_next_custom_iterator" {
  let source =
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __iter__(self):
    #|    return self
    #|  def __next__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 3:
    #|      return self.i
    #|    raise StopIteration
    #|it = iter(It())
    #|print(next(it))
    #|print(next(it))
    #|print(next(it))
  inspect(run_stdout(source), content="1\n2\n3\n")
}

///|
test "protocol/for_loop_custom_iterable" {
  let source =
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __iter__(self):
    #|    return self
    #|  def __next__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 3:
    #|      return self.i
    #|    raise StopIteration
    #|out = []
    #|for x in It():
    #|  out.append(x)
    #|print(out)
  inspect(run_stdout(source), content="[1, 2, 3]\n")
}

///|
test "protocol/list_comprehension_custom_iterable" {
  let source =
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __iter__(self):
    #|    return self
    #|  def __next__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 3:
    #|      return self.i
    #|    raise StopIteration
    #|ys = [x for x in It()]
    #|print(ys)
  inspect(run_stdout(source), content="[1, 2, 3]\n")
}

///|
test "protocol/in_uses_contains_then_iteration" {
  let source =
    #|class Box:
    #|  def __contains__(self, x):
    #|    return x == 2
    #|print(2 in Box())
    #|print(3 in Box())
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __iter__(self):
    #|    return self
    #|  def __next__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 3:
    #|      return self.i
    #|    raise StopIteration
    #|print(2 in It())
    #|print(4 in It())
  inspect(run_stdout(source), content="True\nFalse\nTrue\nFalse\n")
}

///|
test "protocol/len_calls_dunder_len" {
  let source =
    #|class L:
    #|  def __len__(self):
    #|    return 5
    #|print(len(L()))
  inspect(run_stdout(source), content="5\n")
}

///|
test "protocol/constructors_accept_custom_iterable" {
  let source =
    #|class It:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __iter__(self):
    #|    return self
    #|  def __next__(self):
    #|    self.i = self.i + 1
    #|    if self.i <= 3:
    #|      return self.i
    #|    raise StopIteration
    #|print(list(It()))
    #|print(tuple(It()))
    #|print(set(It()))
    #|class Pairs:
    #|  def __init__(self):
    #|    self.i = 0
    #|  def __iter__(self):
    #|    return self
    #|  def __next__(self):
    #|    self.i = self.i + 1
    #|    if self.i == 1:
    #|      return ("a", 1)
    #|    if self.i == 2:
    #|      return ("b", 2)
    #|    raise StopIteration
    #|print(dict(Pairs()))
  inspect(
    run_stdout(source),
    content="[1, 2, 3]\n(1, 2, 3)\n{1, 2, 3}\n{a: 1, b: 2}\n",
  )
}
