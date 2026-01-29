///|
/// Bytecode coverage tests for literal unpacking and varargs/kwargs calls.

///|
fn bc2_run_stdout(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
fn bc2_compile_ok(source : String) -> String {
  let program = match parse(source) {
    Ok(v) => v
    Err(err) => return "ERR: " + format_parse_error(err)
  }
  match compile_module_to_bc(program, "<test>".to_string()) {
    Ok(_) => "ok"
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "bytecode/compile_literal_unpack_and_calls" {
  let fstring =
    #|print(f"x={1}")
  let ifexpr =
    #|x = 1
    #|print("a" if x else "b")
  let walrus =
    #|print((x := 3) + x)
  let list_star =
    #|xs = [1, *[2, 3], 4]
    #|print(xs)
  let tuple_star =
    #|t = (1, *[2, 3], 4)
    #|print(t[0] + t[1] + t[2] + t[3])
  let set_star =
    #|s = {1, *[2, 2, 3]}
    #|print(len(s))
  let dict_dupe =
    #|d = {"a": 1, "a": 2}
    #|print(d["a"])
  let dict_starstar =
    #|d = {**{"a": 1}, "b": 2, **{"a": 3}}
    #|print(d["a"], d["b"])
  let call_starstar =
    #|def f(*a, **k):
    #|  print(len(a))
    #|  print(a[0] + a[1] + a[2])
    #|  print(k["x"] + k["y"])
    #|f(1, *[2, 3], x=4, **{"y": 5})
  let sources = [
    fstring, ifexpr, walrus, list_star, tuple_star, set_star, dict_dupe, dict_starstar,
    call_starstar,
  ]
  for s in sources {
    inspect(bc2_compile_ok(s), content="ok")
  }
}

///|
test "bytecode/run_literal_unpack_and_calls" {
  let fstring =
    #|print(f"x={1}")
  let ifexpr =
    #|x = 1
    #|print("a" if x else "b")
  let walrus =
    #|print((x := 3) + x)
  let list_star =
    #|xs = [1, *[2, 3], 4]
    #|print(xs)
  let tuple_star =
    #|t = (1, *[2, 3], 4)
    #|print(t[0] + t[1] + t[2] + t[3])
  let set_star =
    #|s = {1, *[2, 2, 3]}
    #|print(len(s))
  let dict_dupe =
    #|d = {"a": 1, "a": 2}
    #|print(d["a"])
  let dict_starstar =
    #|d = {**{"a": 1}, "b": 2, **{"a": 3}}
    #|print(d["a"], d["b"])
  let call_starstar =
    #|def f(*a, **k):
    #|  print(len(a))
    #|  print(a[0] + a[1] + a[2])
    #|  print(k["x"] + k["y"])
    #|f(1, *[2, 3], x=4, **{"y": 5})
  inspect(bc2_run_stdout(fstring), content="x=1\n")
  inspect(bc2_run_stdout(ifexpr), content="a\n")
  inspect(bc2_run_stdout(walrus), content="6\n")
  inspect(bc2_run_stdout(list_star), content="[1, 2, 3, 4]\n")
  inspect(bc2_run_stdout(tuple_star), content="10\n")
  // Set order is unspecified; assert via length.
  inspect(bc2_run_stdout(set_star), content="3\n")
  inspect(bc2_run_stdout(dict_dupe), content="2\n")
  inspect(bc2_run_stdout(dict_starstar), content="3 2\n")
  inspect(bc2_run_stdout(call_starstar), content="3\n6\n9\n")
}
