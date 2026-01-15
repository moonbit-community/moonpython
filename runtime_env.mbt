///|
/// Environment and container helpers.

///|
fn normalize_index(index : Int, length : Int) -> Int {
  if index < 0 {
    length + index
  } else {
    index
  }
}

///|
fn index_from_value(value : Value, default : Int) -> Result[Int, RuntimeError] {
  match value {
    Value::None => Ok(default)
    Value::Int(v) => Ok(v.to_int())
    Value::Bool(v) => Ok(if v { 1 } else { 0 })
    Value::Float(v) => Ok(v.to_int())
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, "invalid index".to_string()),
      )
  }
}

///|
fn slice_values(values : Array[Value], start : Int, end : Int) -> Array[Value] {
  let result : Array[Value] = []
  let len = values.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 {
    s = 0
  }
  if e < 0 {
    e = 0
  }
  if s > len {
    s = len
  }
  if e > len {
    e = len
  }
  for i = s; i < e; i = i + 1 {
    result.push(values[i])
  }
  result
}

///|
fn slice_string(chars : Array[Char], start : Int, end : Int) -> String {
  let len = chars.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 {
    s = 0
  }
  if e < 0 {
    e = 0
  }
  if s > len {
    s = len
  }
  if e > len {
    e = len
  }
  let buf = StringBuilder::new()
  for i = s; i < e; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn get_from_env(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Value? {
  for pair in locals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in builtins {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_global_value(
  globals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < globals.length(); i = i + 1 {
    if globals[i].0 == name {
      globals[i] = (name, value)
      return
    }
  }
  globals.push((name, value))
}

///|
fn get_global_value(globals : Array[(String, Value)], name : String) -> Value? {
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn delete_global_value(globals : Array[(String, Value)], name : String) -> Unit {
  for idx = 0; idx < globals.length(); idx = idx + 1 {
    if globals[idx].0 == name {
      let _ = globals.remove(idx)
      break
    }
  }
}

///|
fn clone_locals(locals : Array[(String, Value)]) -> Array[(String, Value)] {
  let result : Array[(String, Value)] = []
  for pair in locals {
    result.push(pair)
  }
  result
}

///|
fn set_local_value(
  locals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < locals.length(); i = i + 1 {
    if locals[i].0 == name {
      locals[i] = (name, value)
      return
    }
  }
  locals.push((name, value))
}
