///|
fn parser_match_case_run_stdout(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
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
