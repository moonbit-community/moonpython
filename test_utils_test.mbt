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
fn bytes_hex_digit(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).to_char().unwrap()
  } else {
    ('a'.to_int() + (n - 10)).to_char().unwrap()
  }
}

///|
fn bytes_hex_byte(value : Int) -> String {
  let buf = StringBuilder::new()
  let hi = (value >> 4) & 0xF
  let lo = value & 0xF
  buf.write_char(bytes_hex_digit(hi))
  buf.write_char(bytes_hex_digit(lo))
  buf.to_string()
}

///|
fn bytes_repr(values : Array[Int]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("b'")
  for byte in values {
    let v = byte & 0xFF
    if v == 0x5c {
      buf.write_string("\\\\")
    } else if v == 0x27 {
      buf.write_string("\\'")
    } else if v == 0x09 {
      buf.write_string("\\t")
    } else if v == 0x0a {
      buf.write_string("\\n")
    } else if v == 0x0d {
      buf.write_string("\\r")
    } else if v >= 0x20 && v <= 0x7e {
      buf.write_char(v.to_char().unwrap())
    } else {
      buf.write_string("\\x")
      buf.write_string(bytes_hex_byte(v))
    }
  }
  buf.write_char('\'')
  buf.to_string()
}

///|
fn test_value_repr(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Str(v) => v
    Value::Bytes(values) => bytes_repr(values)
    Value::ByteArray(values) => "bytearray(" + bytes_repr(values) + ")"
    Value::MemoryView(values) => "memoryview(" + bytes_repr(values) + ")"
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
