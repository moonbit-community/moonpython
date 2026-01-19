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

///|
test "import/from_import_binds_callables" {
  let source =
    #|from math import sqrt as s, pow
    #|print(int(s(16)))
    #|print(int(pow(2, 4)))
    #|from math import *
    #|print(int(sqrt(9)))
    #|print(int(pi))
  inspect(run_stdout_import(source), content="4\n16\n3\n3\n")
}

///|
test "import/import_as_and_multi_import" {
  let source =
    #|import math as m
    #|print(int(m.sqrt(9)))
    #|import math, math as n
    #|print(int(n.sqrt(16)))
  inspect(run_stdout_import(source), content="3\n4\n")
}
