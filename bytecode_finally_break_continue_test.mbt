///|
/// Bytecode coverage tests for `break`/`continue` inside `finally` suites.

///|
fn bc_finally_run_stdout(source : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "bytecode/finally_break_suppresses_exception" {
  let source =
    #|def f():
    #|  out = []
    #|  for i in [0, 1]:
    #|    try:
    #|      raise RuntimeError("x")
    #|    finally:
    #|      out = out + ["finally"]
    #|      break
    #|  print(",".join(out))
    #|f()
  inspect(bc_finally_run_stdout(source), content="finally\n")
}

///|
test "bytecode/finally_continue_suppresses_exception" {
  let source =
    #|def f():
    #|  out = []
    #|  for i in [0, 1]:
    #|    try:
    #|      raise RuntimeError("x")
    #|    finally:
    #|      out = out + [str(i)]
    #|      continue
    #|  print(",".join(out))
    #|f()
  inspect(bc_finally_run_stdout(source), content="0,1\n")
}
