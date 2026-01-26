///|
/// PEP 562 module __getattr__/__dir__ behavior (subset).

///|
test "module/__getattr__ is used for missing attributes" {
  let config = Config::for_cli(["Lib", "testdata"], None, [""])
  let interp = Interpreter::with_config(config)
  let source =
    #|import mod_getattr
    #|v = mod_getattr.y
  match interp.exec_source(source) {
    Ok(run) =>
      match test_get_global(run.globals, "v") {
        Some(value) => inspect(test_value_repr(value), content="2")
        None => fail("missing v")
      }
    Err(err) => fail("unexpected error: " + format_runtime_error(err))
  }
}
