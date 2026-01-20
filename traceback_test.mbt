///|
/// Traceback and frame capture tests.

///|
fn run_traceback(source : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(_) => "ok"
    Err(err) => format_runtime_error_with_traceback(err, 10)
  }
}

///|
fn run_stdout_traceback(source : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "traceback/format_includes_frames" {
  let source =
    #|def boom():
    #|  1/0
    #|def wrap():
    #|  return boom()
    #|wrap()
  inspect(
    run_traceback(source),
    content=(
      #|Traceback (most recent call last):
      #|  File "<module>", line 5, column 1, in <module>
      #|  File "<module>", line 4, column 3, in wrap
      #|  File "<module>", line 2, column 3, in boom
      #|ZeroDivisionError: division by zero
    ),
  )
}

///|
test "traceback/exception_value_chain" {
  let source =
    #|def boom():
    #|  1/0
    #|def wrap():
    #|  return boom()
    #|try:
    #|  wrap()
    #|except Exception as e:
    #|  tb = e.__traceback__
    #|  print(tb.tb_frame.f_name)
    #|  print(tb.tb_next.tb_frame.f_name)
    #|  print(tb.tb_next.tb_next.tb_frame.f_name)
    #|  print(tb.tb_next.tb_next.tb_lineno)
    #|  print(tb.tb_next.tb_next.tb_colno)
  inspect(
    run_stdout_traceback(source),
    content=(
      #|<module>
      #|wrap
      #|boom
      #|2
      #|3
      #|
    ),
  )
}
