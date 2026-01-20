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
  inspect(run_stdout(source), content="1\n{b: 2}\n9\n{b: 2}\n")
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
  inspect(run_stdout(source), content="1\n{a: 1}\n1\n{a: 1}\n")
}

///|
test "dict/keys_values_items" {
  let source =
    #|d = {"a": 1, "b": 2}
    #|print(list(d.keys()))
    #|print(list(d.values()))
    #|print(list(d.items()))
  inspect(run_stdout(source), content="[a, b]\n[1, 2]\n[(a, 1), (b, 2)]\n")
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
  inspect(run_stdout(source), content="None\n{a: 2, b: 3, c: 4}\n{}\n")
}

///|
test "dict/numeric_key_dedupe" {
  let source =
    #|d = {1: "a", True: "b", 1.0: "c"}
    #|print(d)
    #|print(d[1])
    #|print(d[True])
    #|print(d[1.0])
  inspect(run_stdout(source), content="{1: c}\nc\nc\nc\n")
}

///|
test "dict/unhashable_key" {
  let source =
    #|d = {}
    #|d[[1]] = 2
  inspect(test_exec_error(source), content="TypeError: unhashable type: 'list'")
}
