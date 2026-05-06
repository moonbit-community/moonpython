///|
/// Dict method tests.

///|
test "dict/get" {
  let source =
    #|d = {"a": 1, "b": 2}
    #|print(d.get("a"))
    #|print(d.get("c"))
    #|print(d.get("c", 7))
  inspect(run_stdout(source), content="1\nNone\n7\n")
}

///|
test "dict/pop" {
  let source =
    #|d = {"a": 1, "b": 2}
    #|print(d.pop("a"))
    #|print(d)
    #|print(d.pop("missing", 9))
    #|print(d)
  inspect(run_stdout(source), content=(
    #|1
    #|{'b': 2}
    #|9
    #|{'b': 2}
    #|
  ))
}

///|
test "dict/pop_missing_raises" {
  let source =
    #|d = {"a": 1}
    #|d.pop("missing")
  inspect(test_exec_error(source), content="KeyError: key not found")
}

///|
test "dict/setdefault" {
  let source =
    #|d = {}
    #|print(d.setdefault("a", 1))
    #|print(d)
    #|print(d.setdefault("a", 2))
    #|print(d)
  inspect(run_stdout(source), content=(
    #|1
    #|{'a': 1}
    #|1
    #|{'a': 1}
    #|
  ))
}

///|
test "dict/keys_values_items" {
  let source =
    #|d = {"a": 1, "b": 2}
    #|print(list(d.keys()))
    #|print(list(d.values()))
    #|print(list(d.items()))
  inspect(run_stdout(source), content=(
    #|['a', 'b']
    #|[1, 2]
    #|[('a', 1), ('b', 2)]
    #|
  ))
}

///|
test "dict/update_clear" {
  let source =
    #|d = {"a": 1}
    #|r = d.update()
    #|d.update({"a": 2, "b": 3})
    #|d.update([("c", 4)])
    #|print(r)
    #|print(d)
    #|d.clear()
    #|print(d)
  inspect(run_stdout(source), content=(
    #|None
    #|{'a': 2, 'b': 3, 'c': 4}
    #|{}
    #|
  ))
}

///|
test "dict/numeric_key_dedupe" {
  let source =
    #|d = {1: "a", True: "b", 1.0: "c"}
    #|print(d)
    #|print(d[1])
    #|print(d[True])
    #|print(d[1.0])
  inspect(run_stdout(source), content=(
    #|{1: 'c'}
    #|c
    #|c
    #|c
    #|
  ))
}

///|
test "dict/unhashable_key" {
  let source =
    #|d = {}
    #|d[[1]] = 2
  inspect(test_exec_error(source), content="TypeError: unhashable type: 'list'")
}
