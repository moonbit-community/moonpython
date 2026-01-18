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
fn maybe_index_from_value(value : Value) -> Result[Int?, RuntimeError] {
  match value {
    Value::None => Ok(None)
    _ =>
      match index_from_value(value, 0) {
        Ok(v) => Ok(Some(v))
        Err(err) => Err(err)
      }
  }
}

///|
fn step_from_value(value : Value) -> Result[Int, RuntimeError] {
  match value {
    Value::None => Ok(1)
    _ => index_from_value(value, 1)
  }
}

///|
fn slice_params_from_values(
  length : Int,
  start_value : Value,
  end_value : Value,
  step_value : Value,
) -> Result[(Int, Int, Int), RuntimeError] {
  let step = match step_from_value(step_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if step == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: slice step cannot be zero".to_string(),
      ),
    )
  }
  let start_opt = match maybe_index_from_value(start_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let end_opt = match maybe_index_from_value(end_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if step > 0 {
    let mut start = match start_opt {
      Some(v) => v
      None => 0
    }
    let mut end = match end_opt {
      Some(v) => v
      None => length
    }
    if start < 0 {
      start += length
    }
    if start < 0 {
      start = 0
    }
    if start > length {
      start = length
    }
    if end < 0 {
      end += length
    }
    if end < 0 {
      end = 0
    }
    if end > length {
      end = length
    }
    Ok((start, end, step))
  } else {
    let mut start = match start_opt {
      Some(v) => v
      None => length - 1
    }
    let mut end = match end_opt {
      Some(v) => v
      None => -1
    }
    if start < 0 {
      start += length
    }
    if start < 0 {
      start = -1
    }
    if start >= length {
      start = length - 1
    }
    // For negative-step slices, CPython treats `stop=None` specially:
    // `xs[::-1]` uses `stop=-1` (not normalized), but `xs[:-1:-1]` uses
    // `stop=length-1` (because -1 was explicit).
    if end_opt is Some(_) && end < 0 {
      end += length
    }
    if end < 0 {
      end = -1
    }
    if end >= length {
      end = length - 1
    }
    Ok((start, end, step))
  }
}

///|
fn slice_indices_from_values(
  length : Int,
  start_value : Value,
  end_value : Value,
  step_value : Value,
) -> Result[Array[Int], RuntimeError] {
  if length <= 0 {
    return Ok([])
  }
  let (start, end, step) = match
    slice_params_from_values(length, start_value, end_value, step_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  if step > 0 {
    let mut i = start
    while i < end {
      out.push(i)
      i += step
    }
  } else {
    let mut i = start
    while i > end {
      out.push(i)
      i += step
    }
  }
  Ok(out)
}

///|
fn slice_values_by_indices(
  values : Array[Value],
  indices : Array[Int],
) -> Array[Value] {
  let out : Array[Value] = []
  for idx in indices {
    if idx >= 0 && idx < values.length() {
      out.push(values[idx])
    }
  }
  out
}

///|
fn slice_string_by_indices(chars : Array[Char], indices : Array[Int]) -> String {
  let buf = StringBuilder::new()
  for idx in indices {
    if idx >= 0 && idx < chars.length() {
      buf.write_char(chars[idx])
    }
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
