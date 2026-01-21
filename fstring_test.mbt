///|
/// f-string tests.

///|
fn run_stdout_fstring(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "fstring/conversion_r_s_a" {
  let source =
    #|x = "a"
    #|y = "\u30c6"
    #|print(f"{x!r}")
    #|print(f"{x!s}")
    #|print(f"{y!a}")
  inspect(run_stdout_fstring(source), content="\"a\"\na\n\"\\u30c6\"\n")
}

///|
test "fstring/debug_equal" {
  let source =
    #|x = 1
    #|print(f"{x=}")
    #|print(f"{ x = }")
    #|print(f"{x=!r}")
  inspect(run_stdout_fstring(source), content="x=1\n x = 1\nx=1\n")
}

///|
test "fstring/format_width_and_align" {
  let source =
    #|line = "abc"
    #|print(f"{line:5}")
    #|print(f"{line:>5}")
    #|print(f"{line:*^5}")
  inspect(run_stdout_fstring(source), content="abc  \n  abc\n*abc*\n")
}

///|
test "fstring/int_format_hex_and_padding" {
  let source =
    #|n = 1024
    #|print(f"{n:#0x}")
    #|print(f"{n:06x}")
    #|print(f"{n:#06x}")
  inspect(run_stdout_fstring(source), content="0x400\n000400\n0x0400\n")
}

///|
test "fstring/escaped_braces" {
  let source =
    #|print(f"{{}}")
    #|print(f"{{x}}")
    #|print(f"{{{{}}}}")
    #|print(f"{{{1}}}")
  inspect(run_stdout_fstring(source), content="{}\n{x}\n{{}}\n{1}\n")
}

///|
test "fstring/nested_format_spec" {
  let source =
    #|width = 4
    #|print(f"{1:{width}}")
  inspect(run_stdout_fstring(source), content="   1\n")
}

///|
test "fstring/errors" {
  let empty_expr =
    #|print(f"{ }")
  let missing_close =
    #|print(f"{1")
  let stray_close =
    #|print(f"}")
  inspect(
    run_stdout_fstring(empty_expr),
    content="ERR: line 1:1 invalid syntax",
  )
  inspect(
    run_stdout_fstring(missing_close),
    content="ERR: SyntaxError: f-string: expecting '}'",
  )
  inspect(
    run_stdout_fstring(stray_close),
    content="ERR: SyntaxError: f-string: single '}' is not allowed",
  )
}
