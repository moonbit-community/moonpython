///|
/// Try/except/else/finally tests.

///|
fn get_global(globals : Array[(String, Value)], name : String) -> Value? {
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn value_repr(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Str(v) => v
    Value::List(values) => {
      let buf = StringBuilder::new()
      buf.write_char('[')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_repr(values[i]))
      }
      buf.write_char(']')
      buf.to_string()
    }
    Value::Tuple(_) => "<tuple>"
    Value::Dict(_) => "<dict>"
    Value::Set(_) => "<set>"
    Value::Function(func) => "<function " + func.name + ">"
    Value::Class(klass) => "<class '" + klass.name + "'>"
    Value::Instance(inst) => "<" + inst.class.name + " object>"
    Value::BoundMethod(_) => "<bound method>"
  }
}

///|
fn exec_global(source : String, name : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(run) =>
      match get_global(run.globals, name) {
        Some(value) => value_repr(value)
        None => "<missing>"
      }
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
fn exec_error(source : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(_) => "ok"
    Err(err) => format_runtime_error(err)
  }
}

///|
test "try/except NameError" {
  let source =
    #|flag = 0
    #|try:
    #|  x
    #|except NameError:
    #|  flag = 1
  inspect(exec_global(source, "flag"), content="1")
}

///|
test "try/finally runs after handler error" {
  let source =
    #|log = []
    #|try:
    #|  try:
    #|    x
    #|  except:
    #|    y
    #|  finally:
    #|    log = [1]
    #|except:
    #|  pass
  inspect(exec_global(source, "log"), content="[1]")
}

///|
test "try/finally runs after else error" {
  let source =
    #|log = []
    #|try:
    #|  try:
    #|    pass
    #|  except:
    #|    pass
    #|  else:
    #|    y
    #|  finally:
    #|    log = [1]
    #|except:
    #|  pass
  inspect(exec_global(source, "log"), content="[1]")
}

///|
test "try requires except or finally" {
  let source =
    #|try:
    #|  pass
  inspect(exec_error(source), content="line 1:1 invalid syntax")
}

///|
test "try else requires except" {
  let source =
    #|try:
    #|  pass
    #|else:
    #|  pass
    #|finally:
    #|  pass
  inspect(exec_error(source), content="line 3:1 invalid syntax")
}
