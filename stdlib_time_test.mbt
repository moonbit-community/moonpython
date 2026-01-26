///|
/// Stdlib import shims.

///|
test "stdlib/time_get_clock_info" {
  let config = Config::for_cli(["Lib"], None, [""])
  let interp = Interpreter::with_config(config)
  let source =
    #|import time
    #|impl = time.get_clock_info("time").implementation
    #|mono = time.get_clock_info("monotonic").monotonic
  match interp.exec_source(source) {
    Ok(run) => {
      let impl_value = match test_get_global(run.globals, "impl") {
        Some(v) => test_value_repr(v)
        None => "<missing>"
      }
      let mono = match test_get_global(run.globals, "mono") {
        Some(v) => test_value_repr(v)
        None => "<missing>"
      }
      inspect(impl_value, content="moonpython")
      inspect(mono, content="True")
    }
    Err(err) => fail("unexpected error: " + format_runtime_error(err))
  }
}
