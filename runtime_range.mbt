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
fn range_member_value_to_bigint(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[@bigint.BigInt?, RuntimeError] {
  match value {
    Value::Int(v) => Ok(Some(v))
    Value::Bool(v) => Ok(Some(if v { 1N } else { 0N }))
    Value::Float(v) =>
      if v.is_nan() || v.is_inf() || v != v.floor() {
        Ok(None)
      } else {
        let abs_v = if v < 0.0 { -v } else { v }
        if abs_v > 9.223372036854776e18 {
          Ok(None)
        } else {
          Ok(Some(@bigint.BigInt::from_int64(v.to_int64())))
        }
      }
    Value::Instance(_) =>
      match get_attr_from_value(value, "__index__", globals, builtins, io) {
        Ok(index_method) =>
          match
            call_callable_with_env(index_method, [], [], globals, builtins, io) {
            Ok(Value::Int(v)) => Ok(Some(v))
            Ok(Value::Bool(v)) => Ok(Some(if v { 1N } else { 0N }))
            Ok(_) =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__index__ returned non-int".to_string(),
                ),
              )
            Err(err) => Err(err)
          }
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute => Ok(None)
            _ => Err(err)
          }
      }
    _ => Ok(None)
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
  let needle = match
    range_member_value_to_bigint(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
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
fn range_index_of_value(
  start : @bigint.BigInt,
  stop : @bigint.BigInt,
  step : @bigint.BigInt,
  needle : @bigint.BigInt,
) -> @bigint.BigInt? {
  if range_is_empty(start, stop, step) {
    return None
  }
  if step > 0N {
    if needle < start || needle >= stop {
      None
    } else if (needle - start) % step != 0N {
      None
    } else {
      Some((needle - start) / step)
    }
  } else {
    let step_abs = -step
    if needle > start || needle <= stop {
      None
    } else if (start - needle) % step_abs != 0N {
      None
    } else {
      Some((start - needle) / step_abs)
    }
  }
}

///|
fn builtin_range_count(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.count", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.count() takes exactly one argument".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let needle = match
    range_member_value_to_bigint(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match needle {
    Some(n) =>
      match range_index_of_value(start, stop, step, n) {
        Some(_) => Ok(Value::Int(1N))
        None => Ok(Value::Int(0N))
      }
    None => Ok(Value::Int(0N))
  }
}

///|
fn builtin_range_index(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range.index", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range.index() takes from 1 to 3 arguments".to_string(),
      ),
    )
  }
  let (start, stop, step) = match range_fields_from_self(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let len = range_length_bigint(start, stop, step)
  let needle = match
    range_member_value_to_bigint(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let needle = match needle {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: sequence.index(x): x not in sequence".to_string(),
        ),
      )
  }
  let idx = match range_index_of_value(start, stop, step, needle) {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: sequence.index(x): x not in sequence".to_string(),
        ),
      )
  }
  let mut start_idx = if positional.length() >= 3 {
    match intlike_to_bigint("range.index", positional[2]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    0N
  }
  let mut stop_idx = if positional.length() == 4 {
    match intlike_to_bigint("range.index", positional[3]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    len
  }
  if start_idx < 0N {
    start_idx = start_idx + len
  }
  if stop_idx < 0N {
    stop_idx = stop_idx + len
  }
  if start_idx < 0N {
    start_idx = 0N
  }
  if start_idx > len {
    start_idx = len
  }
  if stop_idx < 0N {
    stop_idx = 0N
  }
  if stop_idx > len {
    stop_idx = len
  }
  if idx < start_idx || idx >= stop_idx {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: sequence.index(x): x not in sequence".to_string(),
      ),
    )
  }
  Ok(Value::Int(idx))
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
