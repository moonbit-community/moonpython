///|
/// Stdlib import shims.

///|
test "stdlib/array_module_import_and_basic_api" {
  let config = Config::for_cli(["Lib"], None, [""])
  let interp = Interpreter::with_config(config)
  let source =
    #|import array
    #|a = array.array("i", [1, 2, 3])
    #|n = len(a)
    #|itemsize = a.itemsize
  match interp.exec_source(source) {
    Ok(run) => {
      let n = match test_get_global(run.globals, "n") {
        Some(v) => test_value_repr(v)
        None => "<missing>"
      }
      let itemsize = match test_get_global(run.globals, "itemsize") {
        Some(v) => test_value_repr(v)
        None => "<missing>"
      }
      inspect(n, content="3")
      inspect(itemsize, content="4")
    }
    Err(err) => fail("unexpected error: " + format_runtime_error(err))
  }
}
