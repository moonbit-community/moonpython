///|
/// Stdlib import shims.

///|
test "stdlib/hashlib_sha2_shims" {
  let config = Config::for_cli(["Lib"], None, [""])
  let interp = Interpreter::with_config(config)
  let source =
    #|import hashlib
    #|h = hashlib.sha224(b"")
    #|dlen = len(h.digest())
    #|hlen = len(h.hexdigest())
    #|name = h.name
  match interp.exec_source(source) {
    Ok(run) => {
      inspect(
        test_value_repr(test_get_global(run.globals, "dlen").unwrap()),
        content="28",
      )
      inspect(
        test_value_repr(test_get_global(run.globals, "hlen").unwrap()),
        content="56",
      )
      inspect(
        test_value_repr(test_get_global(run.globals, "name").unwrap()),
        content="sha224",
      )
    }
    Err(err) => fail("unexpected error: " + format_runtime_error(err))
  }
}
