///|
/// Range object semantics (lazy range + __len__/__contains__/__getitem__).

///|
let sys_maxsize_bigint = 9223372036854775807N

///|
fn intlike_to_bigint(
  name : String,
  value : Value,
) -> Result[@bigint.BigInt, RuntimeError] {
  match value {
    Value::Int(v) => Ok(v)
    Value::Bool(v) => Ok(if v { 1N } else { 0N })
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + " integer argument expected".to_string(),
        ),
      )
  }
}

///|
fn range_fields_from_self(
  self_value : Value,
) -> Result[(@bigint.BigInt, @bigint.BigInt, @bigint.BigInt), RuntimeError] {
  match self_value {
    Value::Instance(inst) if inst.class.name == "range" => {
      let start = match get_named_value(inst.dict, "start") {
        Some(Value::Int(v)) => v
        Some(Value::Bool(v)) => if v { 1N } else { 0N }
        _ => 0N
      }
      let stop = match get_named_value(inst.dict, "stop") {
        Some(Value::Int(v)) => v
        Some(Value::Bool(v)) => if v { 1N } else { 0N }
        _ => 0N
      }
      let step = match get_named_value(inst.dict, "step") {
        Some(Value::Int(v)) => v
        Some(Value::Bool(v)) => if v { 1N } else { 0N }
        _ => 1N
      }
      Ok((start, stop, step))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "range method expects a range object".to_string(),
        ),
      )
  }
}

///|
fn range_is_empty(
  start : @bigint.BigInt,
  stop : @bigint.BigInt,
  step : @bigint.BigInt,
) -> Bool {
  if step > 0N {
    start >= stop
  } else {
    start <= stop
  }
}

///|
fn range_length_bigint(
  start : @bigint.BigInt,
  stop : @bigint.BigInt,
  step : @bigint.BigInt,
) -> @bigint.BigInt {
  if step == 0N {
    0N
  } else if range_is_empty(start, stop, step) {
    0N
  } else if step > 0N {
    // 1 + (stop - start - 1) // step
    1N + (stop - start - 1N) / step
  } else {
    let step_abs = -step
    1N + (start - stop - 1N) / step_abs
  }
}

///|
fn make_range_instance(
  start : @bigint.BigInt,
  stop : @bigint.BigInt,
  step : @bigint.BigInt,
  builtins : Array[(String, Value)],
) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("start", Value::Int(start)))
  dict.push(("stop", Value::Int(stop)))
  dict.push(("step", Value::Int(step)))
  Value::Instance(InstanceValue::{
    class: builtin_class_from_name("range", builtins),
    dict,
  })
}

///|
fn range_element_at(
  start : @bigint.BigInt,
  step : @bigint.BigInt,
  idx : @bigint.BigInt,
) -> @bigint.BigInt {
  start + step * idx
}

///|
fn range_slice_indices(
  length : @bigint.BigInt,
  slice_start : Value,
  slice_stop : Value,
  slice_step : Value,
) -> Result[(@bigint.BigInt, @bigint.BigInt, @bigint.BigInt), RuntimeError] {
  let step = match slice_step {
    Value::None => 1N
    _ =>
      match intlike_to_bigint("slice", slice_step) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
  }
  if step == 0N {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: slice step cannot be zero".to_string(),
      ),
    )
  }
  if step > 0N {
    let mut start = match slice_start {
      Value::None => 0N
      _ =>
        match intlike_to_bigint("slice", slice_start) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
    }
    let mut stop = match slice_stop {
      Value::None => length
      _ =>
        match intlike_to_bigint("slice", slice_stop) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
    }
    if start < 0N {
      start = start + length
    }
    if stop < 0N {
      stop = stop + length
    }
    if start < 0N {
      start = 0N
    }
    if start > length {
      start = length
    }
    if stop < 0N {
      stop = 0N
    }
    if stop > length {
      stop = length
    }
    Ok((start, stop, step))
  } else {
    let mut start = match slice_start {
      Value::None => length - 1N
      _ =>
        match intlike_to_bigint("slice", slice_start) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
    }
    let mut stop = match slice_stop {
      Value::None => -1N
      _ =>
        match intlike_to_bigint("slice", slice_stop) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
    }
    if start < 0N {
      start = start + length
    }
    if stop < 0N {
      stop = stop + length
    }
    if start < 0N {
      start = -1N
    }
    if start >= length {
      start = length - 1N
    }
    if stop < -1N {
      stop = -1N
    }
    if stop >= length {
      stop = length - 1N
    }
    Ok((start, stop, step))
  }
}

///|
fn range_slice_length(
  start : @bigint.BigInt,
  stop : @bigint.BigInt,
  step : @bigint.BigInt,
) -> @bigint.BigInt {
  if step > 0N {
    if start >= stop {
      0N
    } else {
      1N + (stop - start - 1N) / step
    }
  } else {
    let step_abs = -step
    if start <= stop {
      0N
    } else {
      1N + (start - stop - 1N) / step_abs
    }
  }
}

///|
fn builtin_range_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.__iter__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.__iter__() takes exactly one argument".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(make_range_iterator(start, stop, step))
}

///|
fn builtin_range_len(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.__len__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.__len__() takes exactly one argument".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let len = range_length_bigint(start, stop, step)
  if len > sys_maxsize_bigint {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OverflowError: Python int too large to convert to C ssize_t".to_string(),
      ),
    )
  }
  Ok(Value::Int(len))
}

///|
fn builtin_range_bool(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.__bool__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.__bool__() takes exactly one argument".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(!range_is_empty(start, stop, step)))
}

///|
fn builtin_range_contains(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.__contains__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.__contains__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if range_is_empty(start, stop, step) {
    return Ok(Value::Bool(false))
  }
  let needle = match positional[1] {
    Value::Int(v) => Some(v)
    Value::Bool(v) => Some(if v { 1N } else { 0N })
    _ => None
  }
  match needle {
    None => Ok(Value::Bool(false))
    Some(n) =>
      if step > 0N {
        if n < start || n >= stop {
          Ok(Value::Bool(false))
        } else {
          Ok(Value::Bool((n - start) % step == 0N))
        }
      } else {
        let step_abs = -step
        if n > start || n <= stop {
          Ok(Value::Bool(false))
        } else {
          Ok(Value::Bool((start - n) % step_abs == 0N))
        }
      }
  }
}

///|
fn builtin_range_getitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.__getitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.__getitem__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let len = range_length_bigint(start, stop, step)
  let index_value = positional[1]
  match index_value {
    Value::Instance(slice_inst) if slice_inst.class.name == "slice" => {
      let slice_start = match get_named_value(slice_inst.dict, "start") {
        Some(v) => v
        None => Value::None
      }
      let slice_stop = match get_named_value(slice_inst.dict, "stop") {
        Some(v) => v
        None => Value::None
      }
      let slice_step = match get_named_value(slice_inst.dict, "step") {
        Some(v) => v
        None => Value::None
      }
      if len == 0N {
        return Ok(make_range_instance(0N, 0N, 1N, builtins))
      }
      let (istart, istop, istep) = match
        range_slice_indices(len, slice_start, slice_stop, slice_step) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let out_len = range_slice_length(istart, istop, istep)
      if out_len == 0N {
        return Ok(make_range_instance(0N, 0N, 1N, builtins))
      }
      let new_start = range_element_at(start, step, istart)
      let new_step = step * istep
      let new_stop = new_start + new_step * out_len
      Ok(make_range_instance(new_start, new_stop, new_step, builtins))
    }
    _ => {
      let mut idx = match intlike_to_bigint("range.__getitem__", index_value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if idx < 0N {
        idx = idx + len
      }
      if idx < 0N || idx >= len {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "IndexError: range object index out of range".to_string(),
          ),
        )
      }
      Ok(Value::Int(range_element_at(start, step, idx)))
    }
  }
}
