///|
/// Helpers shared by black-box tests.

///|
fn test_get_global(globals : Array[(String, Value)], name : String) -> Value? {
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn test_value_repr(value : Value) -> String {
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
        buf.write_string(test_value_repr(values[i]))
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
fn test_exec_global(source : String, name : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(run) =>
      match test_get_global(run.globals, name) {
        Some(value) => test_value_repr(value)
        None => "<missing>"
      }
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
fn test_exec_error(source : String) -> String {
  match Interpreter::new().exec_source(source) {
    Ok(_) => "ok"
    Err(err) => format_runtime_error(err)
  }
}
