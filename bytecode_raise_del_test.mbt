///|
/// Bytecode coverage tests for `raise` and `del`.

///|
fn bc_run_stdout(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
fn bc_compile_ok(source : String) -> String {
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
test "bytecode/compile_raise_del_programs" {
  let del_paren =
    #|x = 1
    #|del(x)
  let raise_and_del =
    #|log = []
    #|def boom():
    #|  raise RuntimeError("x")
    #|x = 1
    #|del x
    #|try:
    #|  x
    #|except NameError:
    #|  log = log + ["del"]
    #|try:
    #|  boom()
    #|except RuntimeError as e:
    #|  log = log + [str(e)]
    #|finally:
    #|  log = log + ["finally"]
    #|print(",".join(log))
  let del_subscr_list =
    #|xs = [1, 2, 3]
    #|del xs[1]
    #|print(xs)
  let sources = [del_paren, raise_and_del, del_subscr_list]
  for s in sources {
    inspect(bc_compile_ok(s), content="ok")
  }
}

///|
test "bytecode/del_subscript_list" {
  let source =
    #|xs = [1, 2, 3]
    #|del xs[1]
    #|print(xs)
  inspect(bc_run_stdout(source), content="[1, 3]\n")
}

///|
test "bytecode/del_subscript_dict" {
  let source =
    #|d = {"a": 1, "b": 2}
    #|del d["a"]
    #|print(len(d))
  inspect(bc_run_stdout(source), content="1\n")
}

///|
test "bytecode/raise_simple" {
  let source =
    #|try:
    #|  raise RuntimeError("x")
    #|except RuntimeError as e:
    #|  print(str(e))
  inspect(bc_run_stdout(source), content="x\n")
}

///|
test "bytecode/raise_no_active_exception" {
  inspect(
    bc_run_stdout("raise\n"),
    content="ERR: RuntimeError: No active exception to reraise",
  )
}
