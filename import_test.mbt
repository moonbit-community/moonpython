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
fn run_stdout_import_fs(source : String) -> String {
  match Interpreter::new().exec_source(source) {
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

///|
test "import/filesystem_module" {
  let source =
    #|import testdata.simple_mod as sm
    #|print(sm.value)
    #|print(sm.add_one(4))
  inspect(run_stdout_import_fs(source), content="10\n5\n")
}

///|
test "import/dotted_module_binds_top" {
  let source =
    #|import testdata.pkg.submod
    #|print(testdata.pkg.__name__)
    #|print(testdata.pkg.submod.name)
  inspect(run_stdout_import_fs(source), content="testdata.pkg\nsubmod\n")
}

///|
test "import/from_import_submodule" {
  let source =
    #|from testdata.pkg import submod as sm
    #|print(sm.value)
  inspect(run_stdout_import_fs(source), content="7\n")
}

///|
test "import/__import__returns_top" {
  let source =
    #|mod = __import__("testdata.simple_mod")
    #|print(mod.simple_mod.value)
  inspect(run_stdout_import_fs(source), content="10\n")
}

///|
test "import/__import__with_fromlist" {
  let source =
    #|mod = __import__("testdata.simple_mod", None, None, ["value"])
    #|print(mod.value)
  inspect(run_stdout_import_fs(source), content="10\n")
}
