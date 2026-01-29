///|
/// Bytecode coverage tests for (sync) comprehensions.

///|
fn bc3_run_stdout(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
fn bc3_compile_ok(source : String) -> String {
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
test "bytecode/compile_comprehensions" {
  let list_comp =
    #|xs = [x for x in [1, 2, 3] if x > 1]
    #|print(xs)
  let nested_comp =
    #|xs = [x + y for x in [1, 2] for y in [10, 20] if y > 10]
    #|print(xs)
  let underscore_target =
    #|_ = 100
    #|xs = [x for _ in [1, 2] for x in [3]]
    #|print(_, xs)
  let set_comp =
    #|s = {x for x in [1, 2, 2, 3]}
    #|print(len(s))
  let dict_comp =
    #|d = {x: x + 1 for x in [1, 2]}
    #|print(d[1], d[2])
  let sources = [list_comp, nested_comp, underscore_target, set_comp, dict_comp]
  for s in sources {
    inspect(bc3_compile_ok(s), content="ok")
  }
}

///|
test "bytecode/run_comprehensions" {
  let list_comp =
    #|xs = [x for x in [1, 2, 3] if x > 1]
    #|print(xs)
  let nested_comp =
    #|xs = [x + y for x in [1, 2] for y in [10, 20] if y > 10]
    #|print(xs)
  let underscore_target =
    #|_ = 100
    #|xs = [x for _ in [1, 2] for x in [3]]
    #|print(_, xs)
  let set_comp =
    #|s = {x for x in [1, 2, 2, 3]}
    #|print(len(s))
  let dict_comp =
    #|d = {x: x + 1 for x in [1, 2]}
    #|print(d[1], d[2])
  inspect(bc3_run_stdout(list_comp), content="[2, 3]\n")
  inspect(bc3_run_stdout(nested_comp), content="[21, 22]\n")
  inspect(bc3_run_stdout(underscore_target), content="100 [3, 3]\n")
  inspect(bc3_run_stdout(set_comp), content="3\n")
  inspect(bc3_run_stdout(dict_comp), content="2 3\n")
}
