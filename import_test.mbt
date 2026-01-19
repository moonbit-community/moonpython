///|
/// Import + module tests.

///|
fn run_stdout_import(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "import/math_basic" {
  let source =
    #|import math
    #|print(math.__name__)
    #|print(int(math.sqrt(9)))
    #|print(int(math.pow(2, 3)))
    #|print(int(math.pi))
  inspect(run_stdout_import(source), content="math\n3\n8\n3\n")
}
