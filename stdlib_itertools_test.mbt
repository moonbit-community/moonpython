///|
/// Stdlib import shims.

///|
test "stdlib/itertools_cycle_basic" {
  let config = Config::for_cli(["Lib"], None, [""])
  let interp = Interpreter::with_config(config)
  let source =
    #|import itertools
    #|it = itertools.cycle([1, 2])
    #|out = [next(it), next(it), next(it), next(it), next(it)]
  match interp.exec_source(source) {
    Ok(run) => {
      let out = match test_get_global(run.globals, "out") {
        Some(v) => test_value_repr(v)
        None => "<missing>"
      }
      inspect(out, content="[1, 2, 1, 2, 1]")
    }
    Err(err) => fail("unexpected error: " + format_runtime_error(err))
  }
}
