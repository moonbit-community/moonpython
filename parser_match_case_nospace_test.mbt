///|
fn parser_match_case_run_stdout(source : String) -> String {
  let io = @moonpython.MockIO::new([])
  match
    @moonpython.Interpreter::with_io(@moonpython.Config::default(), io).exec_source(
      source,
    ) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + @moonpython.format_runtime_error(err)
  }
}

///|
test "parser/match_case_no_space" {
  let source =
    #|match():
    #|  case():
    #|    print("ok")
  inspect(parser_match_case_run_stdout(source), content="ok\n")
}
