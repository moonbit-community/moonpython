///|
test "valueless function annotations evaluate targets but not annotations or attribute lookup" {
  let source =
    #|__name__ = "annotation_review"
    #|events = []
    #|class Box:
    #|    @property
    #|    def value(self):
    #|        raise RuntimeError('attribute lookup must not run')
    #|obj = Box()
    #|def base():
    #|    events.append('base')
    #|    return obj
    #|def index():
    #|    events.append('index')
    #|    return 0
    #|def f():
    #|    base().value: Missing
    #|    base()[index()]: Missing
    #|def g():
    #|    base().value: Missing
    #|    base()[index()]: Missing
    #|    yield 1
    #|f()
    #|print(events)
    #|events.clear()
    #|print(list(g()), events)
  for
    interpreter in [
      @moonpython.Interpreter::new(),
      @moonpython.Interpreter::new_spec(),
    ] {
    match interpreter.exec_source(source) {
      Ok(run) =>
        assert_eq(
          run.stdout,
          "['base', 'base', 'index']\n[1] ['base', 'base', 'index']\n",
        )
      Err(err) => fail(@moonpython.format_runtime_error(err))
    }
  }
}

///|
test "module and class attribute annotations retain eager target and annotation ordering" {
  let source =
    #|__name__ = "annotation_review"
    #|events = []
    #|class Box: pass
    #|obj = Box()
    #|def base():
    #|    events.append('base')
    #|    return obj
    #|def index():
    #|    events.append('index')
    #|    return 0
    #|def annotation():
    #|    events.append('annotation')
    #|    return int
    #|def value():
    #|    events.append('value')
    #|    return 7
    #|base().missing: annotation()
    #|base()[index()]: annotation()
    #|base().assigned: annotation() = value()
    #|class C:
    #|    base().missing: annotation()
    #|    base()[index()]: annotation()
    #|    base().assigned: annotation() = value()
    #|print(events)
    #|print(obj.assigned)
  match @moonpython.Interpreter::new().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "['base', 'annotation', 'base', 'index', 'annotation', 'value', 'base', 'annotation', 'base', 'annotation', 'base', 'index', 'annotation', 'value', 'base', 'annotation']\n7\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
  match @moonpython.Interpreter::new_spec().exec_source(source) {
    Ok(run) =>
      assert_eq(
        run.stdout,
        "['base', 'base', 'index', 'value', 'base', 'base', 'base', 'index', 'value', 'base']\n7\n",
      )
    Err(err) => fail(@moonpython.format_runtime_error(err))
  }
}
