///|
/// Complex number tests.

///|
fn run_stdout_complex(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "complex/literals_and_ctor" {
  let source =
    #|print(1j)
    #|print(complex())
    #|print(complex(1, 2))
    #|print(complex(0, -3))
  inspect(run_stdout_complex(source), content="1j\n0j\n(1+2j)\n-3j\n")
}

///|
test "complex/ops" {
  let source =
    #|print(complex(1, 2) + 3)
    #|print(2 + complex(1, -1))
    #|print(-complex(1, 2))
    #|print(complex(1, 2) * complex(3, 4))
    #|print(complex(1, 0) == 1)
  inspect(
    run_stdout_complex(source),
    content="(4+2j)\n(3-1j)\n(-1-2j)\n(-5+10j)\nTrue\n",
  )
}
