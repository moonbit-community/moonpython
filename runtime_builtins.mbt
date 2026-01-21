///|
/// Builtin function implementations for the mpython runtime.
///
/// This file centralizes builtin dispatch so `mpython.mbt` can focus on
/// expression evaluation and general call semantics.

///|
fn unexpected_keywords_error(name : String) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() got unexpected keyword arguments".to_string(),
  )
}

///|
fn ensure_no_keywords(
  name : String,
  keywords : Array[(String, Value)],
) -> Result[Unit, RuntimeError] {
  if keywords.length() > 0 {
    Err(unexpected_keywords_error(name))
  } else {
    Ok(())
  }
}

///|
fn touch_env(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Unit {
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io

}

///|
fn unexpected_keyword_argument_error(
  name : String,
  key : String,
) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() got an unexpected keyword argument '" + key + "'",
  )
}

///|
fn multiple_values_error(name : String, key : String) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() got multiple values for argument '" + key + "'",
  )
}

///|
fn missing_required_argument_error(
  name : String,
  arg_name : String,
) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() missing required argument '" + arg_name + "'",
  )
}

///|
fn too_many_arguments_error(name : String, given : Int) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() takes at most 3 arguments (" + given.to_string() + " given)",
  )
}

///|
fn dict_env_from_value(
  name : String,
  kind : String,
  value : Value,
) -> Result[(Array[(String, Value)], Array[(Value, Value)]), RuntimeError] {
  match value {
    Value::Dict(pairs) => {
      let env : Array[(String, Value)] = []
      for pair in pairs {
        match pair.0 {
          Value::Str(key) => set_global_value(env, key, pair.1)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                name + "() " + kind + " keys must be str".to_string(),
              ),
            )
        }
      }
      Ok((env, pairs))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() " + kind + " must be a dict".to_string(),
        ),
      )
  }
}

///|
fn dict_pairs_from_value(
  name : String,
  value : Value,
) -> Result[Array[(Value, Value)], RuntimeError] {
  match value {
    Value::Dict(pairs) => Ok(pairs)
    Value::Instance(inst) =>
      if class_includes_dict(inst.class) {
        match get_named_value(inst.dict, dict_storage_name) {
          Some(Value::Dict(pairs)) => Ok(pairs)
          Some(_) =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                name + "() expects a dict".to_string(),
              ),
            )
          None => {
            let pairs : Array[(Value, Value)] = []
            set_named_value(inst.dict, dict_storage_name, Value::Dict(pairs))
            Ok(pairs)
          }
        }
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            name + "() expects a dict".to_string(),
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() expects a dict".to_string(),
        ),
      )
  }
}

///|
fn sync_env_to_dict(
  env : Array[(String, Value)],
  pairs : Array[(Value, Value)],
) -> Unit {
  while pairs.length() > 0 {
    let _ = pairs.pop()

  }
  for pair in env {
    pairs.push((Value::Str(pair.0), pair.1))
  }
}

///|
fn normalize_exec_eval_arg(value_opt : Value?) -> Value? {
  match value_opt {
    Some(Value::None) => None
    _ => value_opt
  }
}

///|
fn resolve_exec_eval_env(
  name : String,
  globals_arg : Value?,
  locals_arg : Value?,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
) -> Result[
  (
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(Value, Value)]?,
    Array[(Value, Value)]?,
  ),
  RuntimeError,
] {
  let globals_value = normalize_exec_eval_arg(globals_arg)
  let locals_value = normalize_exec_eval_arg(locals_arg)
  let mut globals_env = globals
  let mut locals_env = locals
  let mut globals_pairs : Array[(Value, Value)]? = None
  let mut locals_pairs : Array[(Value, Value)]? = None
  match globals_value {
    Some(value) => {
      let (env, pairs) = match dict_env_from_value(name, "globals", value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      globals_env = env
      globals_pairs = Some(pairs)
    }
    None => ()
  }
  match locals_value {
    Some(value) => {
      let (env, pairs) = match dict_env_from_value(name, "locals", value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      locals_env = env
      locals_pairs = Some(pairs)
    }
    None => ()
  }
  if globals_value is Some(_) && locals_value is None {
    locals_env = globals_env
    locals_pairs = globals_pairs
  }
  Ok((locals_env, globals_env, locals_pairs, globals_pairs))
}

///|
fn parse_exec_eval_args(
  name : String,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  required_label : String,
) -> Result[(Value, Value?, Value?), RuntimeError] {
  if positional.length() == 0 {
    return Err(missing_required_argument_error(name, required_label))
  }
  if positional.length() > 3 {
    return Err(too_many_arguments_error(name, positional.length()))
  }
  let mut globals_arg : Value? = None
  let mut locals_arg : Value? = None
  if positional.length() > 1 {
    globals_arg = Some(positional[1])
  }
  if positional.length() > 2 {
    locals_arg = Some(positional[2])
  }
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "globals" =>
        if globals_arg is Some(_) {
          return Err(multiple_values_error(name, "globals"))
        } else {
          globals_arg = Some(value)
        }
      "locals" =>
        if locals_arg is Some(_) {
          return Err(multiple_values_error(name, "locals"))
        } else {
          locals_arg = Some(value)
        }
      _ => return Err(unexpected_keyword_argument_error(name, key))
    }
  }
  Ok((positional[0], globals_arg, locals_arg))
}

///|
fn reverse_values(items : Array[Value]) -> Array[Value] {
  let out : Array[Value] = []
  let mut i = items.length()
  while i > 0 {
    i = i - 1
    out.push(items[i])
  }
  out
}

///|
fn collect_items_from_iterable(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Value], RuntimeError] {
  let iterator = match iter_value_to_iterator(value, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => out.push(item)
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(out)
}

///|
fn sort_kind_for_sorted(value : Value) -> Bool? {
  match value {
    Value::Int(_) | Value::Float(_) | Value::Bool(_) => Some(true)
    Value::Str(_) => Some(false)
    _ => None
  }
}

///|
fn cmp_string_for_sorted(a : String, b : String) -> Int {
  let aa = a.to_array()
  let bb = b.to_array()
  let mut i = 0
  while i < aa.length() && i < bb.length() {
    let ca = aa[i]
    let cb = bb[i]
    if ca < cb {
      return -1
    }
    if ca > cb {
      return 1
    }
    i = i + 1
  }
  if aa.length() < bb.length() {
    -1
  } else if aa.length() > bb.length() {
    1
  } else {
    0
  }
}

///|
fn cmp_value_for_sorted(
  is_number : Bool,
  a : Value,
  b : Value,
) -> Result[Int, RuntimeError] {
  if is_number {
    let (_, an) = match number_value(a) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let (_, bn) = match number_value(b) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if an < bn {
      Ok(-1)
    } else if an > bn {
      Ok(1)
    } else {
      Ok(0)
    }
  } else {
    match (a, b) {
      (Value::Str(aa), Value::Str(bb)) => Ok(cmp_string_for_sorted(aa, bb))
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "sorted() cannot compare values".to_string(),
          ),
        )
    }
  }
}

///|
fn stable_sort_for_sorted(
  items : Array[Value],
  is_number : Bool,
) -> Result[Array[Value], RuntimeError] {
  let mut out : Array[Value] = []
  for item in items {
    let mut inserted = false
    let next : Array[Value] = []
    for existing in out {
      if !inserted {
        let cmp = match cmp_value_for_sorted(is_number, item, existing) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp < 0 {
          next.push(item)
          inserted = true
        }
      }
      next.push(existing)
    }
    if !inserted {
      next.push(item)
    }
    out = next
  }
  Ok(out)
}

///|
fn builtin_print(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut sep = " ".to_string()
  let mut end = "\n".to_string()
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "sep" =>
        match value {
          Value::Str(text) => sep = text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "print() sep must be str".to_string(),
              ),
            )
        }
      "end" =>
        match value {
          Value::Str(text) => end = text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "print() end must be str".to_string(),
              ),
            )
        }
      "file" =>
        match value {
          Value::None => ()
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::NotImplemented,
                "print() file is not supported".to_string(),
              ),
            )
        }
      "flush" =>
        match value {
          Value::Bool(_) => ()
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "print() flush must be bool".to_string(),
              ),
            )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "print() got an unexpected keyword argument '" + key + "'",
          ),
        )
    }
  }
  let buf = StringBuilder::new()
  for i = 0; i < positional.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(sep)
    }
    buf.write_string(value_to_string(positional[i]))
  }
  buf.write_string(end)
  io.write_stdout(buf.to_string())
  Ok(Value::None)
}

///|
fn builtin_len(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("len", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "len() takes exactly one argument".to_string(),
      ),
    )
  }
  let target = positional[0]
  match target {
    Value::Str(text) => Ok(Value::Int(@bigint.BigInt::from_int(text.length())))
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) =>
      Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
    Value::List(values) =>
      Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
    Value::Tuple(values) =>
      Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
    Value::Dict(pairs) =>
      Ok(Value::Int(@bigint.BigInt::from_int(pairs.length())))
    Value::Set(values) =>
      Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
    Value::Instance(inst) => {
      let _ = locals
      let len_method = match
        get_attr_from_value(
          Value::Instance(inst),
          "__len__",
          globals,
          builtins,
          io,
        ) {
        Ok(v) => v
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "object has no len()".to_string(),
                ),
              )
            _ => return Err(err)
          }
      }
      let value = match
        call_callable_with_env(len_method, [], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match value {
        Value::Int(v) =>
          if v < 0N {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: __len__() should return >= 0".to_string(),
              ),
            )
          } else {
            Ok(Value::Int(v))
          }
        Value::Bool(b) => Ok(Value::Int(if b { 1N } else { 0N }))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__len__() should return an int".to_string(),
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object has no len()".to_string(),
        ),
      )
  }
}

///|
fn builtin_range(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("range", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  fn to_int(value : Value) -> Result[@bigint.BigInt, RuntimeError] {
    match value {
      Value::Int(v) => Ok(v)
      Value::Bool(v) => Ok(if v { 1N } else { 0N })
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "range() integer argument expected".to_string(),
          ),
        )
    }
  }

  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range() takes 1 to 3 arguments".to_string(),
      ),
    )
  }
  let mut start = 0N
  let mut stop = 0N
  let mut step = 1N
  if positional.length() == 1 {
    stop = match to_int(positional[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else if positional.length() == 2 {
    start = match to_int(positional[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    stop = match to_int(positional[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    start = match to_int(positional[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    stop = match to_int(positional[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    step = match to_int(positional[2]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  if step == 0N {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range() arg 3 must not be zero".to_string(),
      ),
    )
  }
  let items : Array[Value] = []
  // NOTE: still returns a realized list (mpython simplification).
  // Convert to Int for looping; raise if it doesn't fit.
  let start_i = match bigint_to_int_checked(start) {
    Ok(v) => v
    Err(_) => return Ok(Value::List([]))
  }
  let stop_i = match bigint_to_int_checked(stop) {
    Ok(v) => v
    Err(_) => return Ok(Value::List([]))
  }
  let step_i = match bigint_to_int_checked(step) {
    Ok(v) => v
    Err(_) => return Ok(Value::List([]))
  }
  if step_i == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range() arg 3 must not be zero".to_string(),
      ),
    )
  }
  let mut i = start_i
  if step_i > 0 {
    while i < stop_i {
      items.push(Value::Int(@bigint.BigInt::from_int(i)))
      i = i + step_i
    }
  } else {
    while i > stop_i {
      items.push(Value::Int(@bigint.BigInt::from_int(i)))
      i = i + step_i
    }
  }
  Ok(Value::List(items))
}

///|
fn builtin_sum(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sum", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sum() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut is_float = false
  let mut total = 0.0
  if positional.length() == 2 {
    let (start_is_float, start_num) = match number_value(positional[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    is_float = start_is_float
    total = start_num
  }
  for item in items {
    let (item_is_float, item_num) = match number_value(item) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if item_is_float {
      is_float = true
    }
    total = total + item_num
  }
  if is_float {
    Ok(Value::Float(total))
  } else {
    Ok(Value::Int(@bigint.BigInt::from_int64(total.to_int64())))
  }
}

///|
fn builtin_max(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("max", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "max() takes at least 1 argument".to_string(),
      ),
    )
  }
  let items = if positional.length() == 1 {
    match iterable_values(positional[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    positional
  }
  if items.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "max() arg is an empty sequence".to_string(),
      ),
    )
  }
  let mut best = items[0]
  let (_, first_num) = match number_value(best) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut best_num = first_num
  for i = 1; i < items.length(); i = i + 1 {
    let item = items[i]
    let (_, item_num) = match number_value(item) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if item_num > best_num {
      best = item
      best_num = item_num
    }
  }
  Ok(best)
}

///|
fn builtin_min(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("min", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "min() takes at least 1 argument".to_string(),
      ),
    )
  }
  let items = if positional.length() == 1 {
    match iterable_values(positional[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    positional
  }
  if items.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "min() arg is an empty sequence".to_string(),
      ),
    )
  }
  let mut best = items[0]
  let (_, first_num) = match number_value(best) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut best_num = first_num
  for i = 1; i < items.length(); i = i + 1 {
    let item = items[i]
    let (_, item_num) = match number_value(item) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if item_num < best_num {
      best = item
      best_num = item_num
    }
  }
  Ok(best)
}

///|
fn builtin_any(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("any", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "any() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for item in items {
    if bool_from_value(item) {
      return Ok(Value::Bool(true))
    }
  }
  Ok(Value::Bool(false))
}

///|
fn builtin_all(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("all", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "all() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for item in items {
    if !bool_from_value(item) {
      return Ok(Value::Bool(false))
    }
  }
  Ok(Value::Bool(true))
}

///|
fn builtin_enumerate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("enumerate", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "enumerate() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut start = 0N
  if positional.length() == 2 {
    match positional[1] {
      Value::Int(v) => start = v
      Value::Bool(v) => start = if v { 1N } else { 0N }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "enumerate() integer argument expected".to_string(),
          ),
        )
    }
  }
  let pairs : Array[Value] = []
  let mut i = start
  for item in items {
    pairs.push(Value::Tuple([Value::Int(i), item]))
    i = i + 1N
  }
  Ok(Value::List(pairs))
}

///|
fn builtin_zip(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let iterables : Array[Array[Value]] = []
  let _ = match ensure_no_keywords("zip", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for value in positional {
    let items = match iterable_values(value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    iterables.push(items)
  }
  if iterables.length() == 0 {
    return Ok(Value::List([]))
  }
  let mut min_len = iterables[0].length()
  for i = 1; i < iterables.length(); i = i + 1 {
    let n = iterables[i].length()
    if n < min_len {
      min_len = n
    }
  }
  let result : Array[Value] = []
  for i = 0; i < min_len; i = i + 1 {
    let tuple_items : Array[Value] = []
    for items in iterables {
      tuple_items.push(items[i])
    }
    result.push(Value::Tuple(tuple_items))
  }
  Ok(Value::List(result))
}

///|
fn builtin_map(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("map", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "map() takes exactly two arguments".to_string(),
      ),
    )
  }
  let func = positional[0]
  let items = match iterable_values(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  for item in items {
    let mapped = match
      call_callable_with_env(func, [item], [], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    results.push(mapped)
  }
  Ok(make_iterator(results))
}

///|
fn builtin_filter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("filter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "filter() takes exactly two arguments".to_string(),
      ),
    )
  }
  let predicate = positional[0]
  let items = match iterable_values(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  for item in items {
    let keep = if predicate is Value::None {
      bool_from_value(item)
    } else {
      let test_value = match
        call_callable_with_env(predicate, [item], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      bool_from_value(test_value)
    }
    if keep {
      results.push(item)
    }
  }
  Ok(make_iterator(results))
}

///|
fn builtin_reversed(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("reversed", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "reversed() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::List(reverse_values(items)))
}

///|
fn builtin_sorted(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sorted", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sorted() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let mut reverse = false
  if positional.length() == 2 {
    match positional[1] {
      Value::Bool(v) => reverse = v
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "sorted() reverse must be bool".to_string(),
          ),
        )
    }
  }
  let items_in = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items : Array[Value] = []
  for item in items_in {
    items.push(item)
  }
  if items.length() == 0 {
    return Ok(Value::List([]))
  }
  let mut kind_opt : Bool? = None
  for item in items {
    match sort_kind_for_sorted(item) {
      Some(kind) =>
        match kind_opt {
          None => kind_opt = Some(kind)
          Some(prev) =>
            if prev != kind {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "sorted() cannot compare values".to_string(),
                ),
              )
            }
        }
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "sorted() cannot compare values".to_string(),
          ),
        )
    }
  }
  let is_number = match kind_opt {
    Some(kind) => kind
    None => return Ok(Value::List([]))
  }
  let mut out = match stable_sort_for_sorted(items, is_number) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if reverse {
    out = reverse_values(out)
  }
  Ok(Value::List(out))
}

///|
fn builtin_input(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("input", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 0 {
    io.write_stdout(value_to_string(positional[0]))
  }
  let line = io.read_line()
  if line is Some(line) {
    Ok(Value::Str(line))
  } else {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "EOF when reading a line".to_string(),
      ),
    )
  }
}

///|
fn builtin_str(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("str", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Str(""))
  } else {
    Ok(Value::Str(value_to_string(positional[0])))
  }
}

///|
fn builtin_str_maketrans(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("str.maketrans", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "maketrans() takes 1 to 3 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Dict(pairs) => {
        let out : Array[(Value, Value)] = []
        for pair in pairs {
          let key = match pair.0 {
            Value::Int(v) => Value::Int(v)
            Value::Bool(v) =>
              Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
            Value::Str(text) =>
              if text.length() != 1 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "string keys in maketrans() must be length 1".to_string(),
                  ),
                )
              } else {
                let code = text.to_array()[0].to_int()
                Value::Int(@bigint.BigInt::from_int(code))
              }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "maketrans() keys must be int or str".to_string(),
                ),
              )
          }
          let value = match pair.1 {
            Value::Int(v) => Value::Int(v)
            Value::Bool(v) =>
              Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
            Value::Str(text) => Value::Str(text)
            Value::None => Value::None
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "maketrans() values must be int, str, or None".to_string(),
                ),
              )
          }
          let _ = match dict_set_item(out, key, value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        }
        Ok(Value::Dict(out))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "maketrans() expects a dict".to_string(),
          ),
        )
    }
  } else {
    let from_text = match positional[0] {
      Value::Str(text) => text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "maketrans() expects string arguments".to_string(),
          ),
        )
    }
    let to_text = match positional[1] {
      Value::Str(text) => text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "maketrans() expects string arguments".to_string(),
          ),
        )
    }
    if from_text.length() != to_text.length() {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: the first two maketrans arguments must have equal length".to_string(),
        ),
      )
    }
    let out : Array[(Value, Value)] = []
    let from_chars = from_text.to_array()
    let to_chars = to_text.to_array()
    for i = 0; i < from_chars.length(); i = i + 1 {
      let key = Value::Int(@bigint.BigInt::from_int(from_chars[i].to_int()))
      let value = Value::Int(@bigint.BigInt::from_int(to_chars[i].to_int()))
      let _ = match dict_set_item(out, key, value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
    }
    if positional.length() == 3 {
      let delete_text = match positional[2] {
        Value::Str(text) => text
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "maketrans() expects string arguments".to_string(),
            ),
          )
      }
      let delete_chars = delete_text.to_array()
      for ch in delete_chars {
        let key = Value::Int(@bigint.BigInt::from_int(ch.to_int()))
        let _ = match dict_set_item(out, key, Value::None) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
      }
    }
    Ok(Value::Dict(out))
  }
}

///|
fn builtin_sys_intern(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.intern", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "intern() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(_) => Ok(positional[0])
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "intern() argument must be str".to_string(),
        ),
      )
  }
}

///|
fn builtin_sys_getfilesystemencoding(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.getfilesystemencoding", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getfilesystemencoding() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Str("utf-8"))
}

///|
fn builtin_sys_getfilesystemencodeerrors(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match
    ensure_no_keywords("sys.getfilesystemencodeerrors", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getfilesystemencodeerrors() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Str("surrogateescape"))
}

///|
fn copy_ints(values : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for value in values {
    out.push(value)
  }
  out
}

///|
fn encode_string_utf8(text : String) -> Array[Int] {
  let out : Array[Int] = []
  for ch in text.to_array() {
    let code = ch.to_int()
    if code <= 0x7F {
      out.push(code)
    } else if code <= 0x7FF {
      out.push(0xC0 | (code >> 6))
      out.push(0x80 | (code & 0x3F))
    } else if code <= 0xFFFF {
      out.push(0xE0 | (code >> 12))
      out.push(0x80 | ((code >> 6) & 0x3F))
      out.push(0x80 | (code & 0x3F))
    } else {
      out.push(0xF0 | (code >> 18))
      out.push(0x80 | ((code >> 12) & 0x3F))
      out.push(0x80 | ((code >> 6) & 0x3F))
      out.push(0x80 | (code & 0x3F))
    }
  }
  out
}

///|
fn encode_string_ascii(text : String) -> Result[Array[Int], RuntimeError] {
  let out : Array[Int] = []
  for ch in text.to_array() {
    let code = ch.to_int()
    if code > 0x7F {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "UnicodeEncodeError: 'ascii' codec can't encode character".to_string(),
        ),
      )
    }
    out.push(code)
  }
  Ok(out)
}

///|
fn encode_string_with_encoding(
  name : String,
  text : String,
  encoding_value : Value,
  errors_value : Value?,
) -> Result[Array[Int], RuntimeError] {
  let encoding = match encoding_value {
    Value::Str(value) => value
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() encoding must be str".to_string(),
        ),
      )
  }
  match errors_value {
    Some(Value::Str(errs)) =>
      if errs != "strict" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "LookupError: unknown error handler".to_string(),
          ),
        )
      }
    Some(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() errors must be str".to_string(),
        ),
      )
    None => ()
  }
  if encoding == "utf-8" || encoding == "utf8" {
    Ok(encode_string_utf8(text))
  } else if encoding == "ascii" {
    encode_string_ascii(text)
  } else {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "LookupError: unknown encoding".to_string(),
      ),
    )
  }
}

///|
fn byte_from_value(name : String, value : Value) -> Result[Int, RuntimeError] {
  match value {
    Value::Int(v) => {
      let int_val = match bigint_to_int_checked(v) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if int_val < 0 || int_val > 255 {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: byte must be in range(0, 256)".to_string(),
          ),
        )
      } else {
        Ok(int_val)
      }
    }
    Value::Bool(v) => Ok(if v { 1 } else { 0 })
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() an integer is required".to_string(),
        ),
      )
  }
}

///|
fn bytes_from_iterable(
  name : String,
  value : Value,
) -> Result[Array[Int], RuntimeError] {
  let items = match iterable_values(value) {
    Ok(values) => values
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  for item in items {
    let byte = match byte_from_value(name, item) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    out.push(byte)
  }
  Ok(out)
}

///|
fn bytes_from_count(
  name : String,
  count : @bigint.BigInt,
) -> Result[Array[Int], RuntimeError] {
  let _ = name
  if count < 0N {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: negative count".to_string(),
      ),
    )
  }
  let count_i = match bigint_to_int_checked(count) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  for i = 0; i < count_i; i = i + 1 {
    out.push(0)
  }
  Ok(out)
}

///|
fn builtin_bytes(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytes", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::Bytes([]))
  }
  if positional.length() > 3 {
    return Err(too_many_arguments_error("bytes", positional.length()))
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Int(count) =>
        return Ok(
          Value::Bytes(
            match bytes_from_count("bytes", count) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
      Value::Bytes(values) => return Ok(Value::Bytes(copy_ints(values)))
      Value::ByteArray(values) => return Ok(Value::Bytes(copy_ints(values)))
      Value::MemoryView(values) => return Ok(Value::Bytes(copy_ints(values)))
      Value::Str(_) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "string argument without an encoding".to_string(),
          ),
        )
      other =>
        return Ok(
          Value::Bytes(
            match bytes_from_iterable("bytes", other) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
    }
  }
  match positional[0] {
    Value::Str(text) => {
      let encoding = positional[1]
      let errors_value = if positional.length() > 2 {
        Some(positional[2])
      } else {
        None
      }
      let bytes = match
        encode_string_with_encoding("bytes", text, encoding, errors_value) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Value::Bytes(bytes))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "encoding without a string argument".to_string(),
        ),
      )
  }
}

///|
fn builtin_bytearray(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytearray", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::ByteArray([]))
  }
  if positional.length() > 3 {
    return Err(too_many_arguments_error("bytearray", positional.length()))
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Int(count) =>
        return Ok(
          Value::ByteArray(
            match bytes_from_count("bytearray", count) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
      Value::Bytes(values) => return Ok(Value::ByteArray(copy_ints(values)))
      Value::ByteArray(values) => return Ok(Value::ByteArray(copy_ints(values)))
      Value::MemoryView(values) =>
        return Ok(Value::ByteArray(copy_ints(values)))
      Value::Str(_) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "string argument without an encoding".to_string(),
          ),
        )
      other =>
        return Ok(
          Value::ByteArray(
            match bytes_from_iterable("bytearray", other) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
    }
  }
  match positional[0] {
    Value::Str(text) => {
      let encoding = positional[1]
      let errors_value = if positional.length() > 2 {
        Some(positional[2])
      } else {
        None
      }
      let bytes = match
        encode_string_with_encoding("bytearray", text, encoding, errors_value) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Value::ByteArray(bytes))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "encoding without a string argument".to_string(),
        ),
      )
  }
}

///|
fn builtin_memoryview(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("memoryview", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "memoryview() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Bytes(values) => Ok(Value::MemoryView(copy_ints(values)))
    Value::ByteArray(values) => Ok(Value::MemoryView(copy_ints(values)))
    Value::MemoryView(values) => Ok(Value::MemoryView(copy_ints(values)))
    other =>
      Ok(
        Value::MemoryView(
          match bytes_from_iterable("memoryview", other) {
            Ok(value) => value
            Err(err) => return Err(err)
          },
        ),
      )
  }
}

///|
fn builtin_int(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Int(0N))
  } else {
    match positional[0] {
      Value::Int(v) => Ok(Value::Int(v))
      Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
      Value::Float(v) =>
        Ok(Value::Int(@bigint.BigInt::from_int64(v.to_int64())))
      Value::Str(text) => {
        let parsed = @strconv.parse_int(text) catch {
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: invalid literal for int()".to_string(),
              ),
            )
        }
        Ok(Value::Int(@bigint.BigInt::from_int(parsed)))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "int() argument must be a string or a number".to_string(),
          ),
        )
    }
  }
}

///|
fn builtin_int_new(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.__new__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__new__() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 1 {
    return Ok(Value::Int(0N))
  }
  match positional[1] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(v.to_int64())))
    Value::Str(text) => {
      let parsed = @strconv.parse_int(text) catch {
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "ValueError: invalid literal for int()".to_string(),
            ),
          )
      }
      Ok(Value::Int(@bigint.BigInt::from_int(parsed)))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.__new__() argument must be a string or a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_float(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("float", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Float(0.0))
  } else {
    match positional[0] {
      Value::Float(v) => Ok(Value::Float(v))
      Value::Int(v) => {
        let d = match bigint_to_double_checked(v) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Float(d))
      }
      Value::Bool(v) => Ok(Value::Float(if v { 1.0 } else { 0.0 }))
      Value::Str(text) => {
        let parsed = @strconv.parse_double(text) catch {
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: could not convert string to float".to_string(),
              ),
            )
        }
        Ok(Value::Float(parsed))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "float() argument must be a string or a number".to_string(),
          ),
        )
    }
  }
}

///|
fn builtin_complex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("complex", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::Complex(0.0, 0.0))
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "complex() takes at most two arguments".to_string(),
      ),
    )
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Complex(real, imag) => Ok(Value::Complex(real, imag))
      Value::Float(v) => Ok(Value::Complex(v, 0.0))
      Value::Int(v) =>
        match bigint_to_double_checked(v) {
          Ok(value) => Ok(Value::Complex(value, 0.0))
          Err(err) => Err(err)
        }
      Value::Bool(v) => Ok(Value::Complex(if v { 1.0 } else { 0.0 }, 0.0))
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "complex() argument must be a number".to_string(),
          ),
        )
    }
  } else {
    let real = match positional[0] {
      Value::Complex(_, _) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "complex() can't take second arg if first is complex".to_string(),
          ),
        )
      _ =>
        match number_value(positional[0]) {
          Ok((_, value)) => value
          Err(err) => return Err(err)
        }
    }
    let imag = match positional[1] {
      Value::Complex(_, _) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "complex() second argument must be a real number".to_string(),
          ),
        )
      _ =>
        match number_value(positional[1]) {
          Ok((_, value)) => value
          Err(err) => return Err(err)
        }
    }
    Ok(Value::Complex(real, imag))
  }
}

///|
fn builtin_list(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("list", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::List([]))
  } else {
    let items = match
      collect_items_from_iterable(positional[0], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Value::List(items))
  }
}

///|
fn builtin_tuple(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("tuple", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Tuple([]))
  } else {
    let items = match
      collect_items_from_iterable(positional[0], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Value::Tuple(items))
  }
}

///|
fn builtin_tuple_new(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("tuple.__new__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "tuple.__new__() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 1 {
    Ok(Value::Tuple([]))
  } else {
    let items = match
      collect_items_from_iterable(positional[1], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Value::Tuple(items))
  }
}

///|
fn builtin_set(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("set", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Set([]))
  } else {
    let items = match
      collect_items_from_iterable(positional[0], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let unique : Array[Value] = []
    for item in items {
      let _ = match set_add_unique(unique, item) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }

    }
    Ok(Value::Set(unique))
  }
}

///|
fn builtin_frozenset(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("frozenset", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Set([]))
  } else {
    let items = match
      collect_items_from_iterable(positional[0], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let unique : Array[Value] = []
    for item in items {
      let _ = match set_add_unique(unique, item) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    Ok(Value::Set(unique))
  }
}

///|
fn builtin_dict(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("dict", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Dict([]))
  } else {
    match positional[0] {
      Value::Dict(pairs) => Ok(Value::Dict(pairs))
      Value::List(items) | Value::Tuple(items) => {
        let pairs : Array[(Value, Value)] = []
        for item in items {
          match item {
            Value::Tuple(values) | Value::List(values) =>
              if values.length() == 2 {
                let _ = match dict_set_item(pairs, values[0], values[1]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }

              } else {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: dictionary update sequence element has wrong length".to_string(),
                  ),
                )
              }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "cannot convert to dict".to_string(),
                ),
              )
          }
        }
        Ok(Value::Dict(pairs))
      }
      other => {
        let items = match
          collect_items_from_iterable(other, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let pairs : Array[(Value, Value)] = []
        for item in items {
          match item {
            Value::Tuple(values) | Value::List(values) =>
              if values.length() == 2 {
                let _ = match dict_set_item(pairs, values[0], values[1]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }

              } else {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: dictionary update sequence element has wrong length".to_string(),
                  ),
                )
              }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "cannot convert to dict".to_string(),
                ),
              )
          }
        }
        Ok(Value::Dict(pairs))
      }
    }
  }
}

///|

///|
fn builtin_dict_get(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("get", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "get() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("get", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let key = positional[1]
  let default_value = if positional.length() == 3 {
    positional[2]
  } else {
    Value::None
  }
  let index = match dict_find_index(pairs, key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match index {
    Some(i) => Ok(pairs[i].1)
    None => Ok(default_value)
  }
}

///|
fn builtin_dict_pop(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("pop", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "pop() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("pop", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let key = positional[1]
  let index = match dict_find_index(pairs, key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if index is Some(i) {
    let removed = pairs.remove(i)
    return Ok(removed.1)
  }
  if positional.length() == 3 {
    return Ok(positional[2])
  }
  Err(
    make_runtime_error(
      RuntimeErrorKind::Key,
      "key not found".to_string(),
    ),
  )
}

///|
fn builtin_dict_setdefault(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("setdefault", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "setdefault() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("setdefault", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let key = positional[1]
  let default_value = if positional.length() == 3 {
    positional[2]
  } else {
    Value::None
  }
  let index = match dict_find_index(pairs, key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if index is Some(i) {
    return Ok(pairs[i].1)
  }
  let _ = match dict_set_item(pairs, key, default_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(default_value)
}

///|
fn builtin_dict_keys(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("keys", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "keys() takes no arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("keys", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(make_dict_view_instance("dict_keys", Value::Dict(pairs)))
}

///|
fn builtin_dict_values(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("values", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "values() takes no arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("values", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(make_dict_view_instance("dict_values", Value::Dict(pairs)))
}

///|
fn builtin_dict_items(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("items", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "items() takes no arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("items", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(make_dict_view_instance("dict_items", Value::Dict(pairs)))
}

///|
fn builtin_dict_update(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("update", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "update() takes at least one argument".to_string(),
      ),
    )
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "update() takes at most one argument".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("update", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 1 || positional[1] is Value::None {
    return Ok(Value::None)
  }
  let other = positional[1]
  let entries : Array[(Value, Value)] = []
  match other {
    Value::Dict(values) => {
      for entry in values {
        entries.push(entry)
      }
    }
    Value::List(values) | Value::Tuple(values) =>
      for item in values {
        match item {
          Value::Tuple(inner) | Value::List(inner) =>
            if inner.length() != 2 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "update() sequence element has wrong length".to_string(),
                ),
              )
            } else {
              entries.push((inner[0], inner[1]))
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "update() expects (key, value) pairs".to_string(),
              ),
            )
        }
      }
    _ => {
      let iterator = match
        iter_value_to_iterator(other, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      while true {
        let item = match
          iterator_next(iterator, None, globals, builtins, io) {
          Ok(v) => v
          Err(err) =>
            if err.exc_type == "StopIteration" {
              break
            } else {
              return Err(err)
            }
        }
        match item {
          Value::Tuple(values) | Value::List(values) =>
            if values.length() != 2 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "update() sequence element has wrong length".to_string(),
                ),
              )
            } else {
              entries.push((values[0], values[1]))
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "update() expects (key, value) pairs".to_string(),
              ),
            )
        }
      }
    }
  }
  for entry in entries {
    let key = entry.0
    let value = entry.1
    let _ = match dict_set_item(pairs, key, value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  Ok(Value::None)
}

///|
fn builtin_dict_clear(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("clear", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "clear() takes no arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("clear", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut i = pairs.length()
  while i > 0 {
    i = i - 1
    let _ = pairs.remove(i)
  }
  Ok(Value::None)
}

///|
fn builtin_dict_contains(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__contains__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__contains__() takes exactly one argument".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("__contains__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let index = match dict_find_index(pairs, positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(index is Some(_)))
}

///|
fn builtin_dict_getitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__getitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__getitem__() takes exactly one argument".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("__getitem__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let key = positional[1]
  let index = match dict_find_index(pairs, key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match index {
    Some(i) => Ok(pairs[i].1)
    None =>
      Err(
        make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()),
      )
  }
}

///|
fn builtin_dict_setitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__setitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__setitem__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("__setitem__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = match dict_set_item(pairs, positional[1], positional[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_dict_delitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__delitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__delitem__() takes exactly one argument".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("__delitem__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let removed = match dict_delete_key(pairs, positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if !removed {
    return Err(
      make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_dict_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__iter__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__iter__() takes no arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("__iter__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys : Array[Value] = []
  for pair in pairs {
    keys.push(pair.0)
  }
  Ok(make_iterator(keys))
}

///|
fn builtin_dict_len(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__len__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__len__() takes no arguments".to_string(),
      ),
    )
  }
  let pairs = match dict_pairs_from_value("__len__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Int(@bigint.BigInt::from_int(pairs.length())))
}

///|
fn builtin_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("iter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "iter() takes exactly one argument".to_string(),
      ),
    )
  }
  let _ = locals
  iter_value_to_iterator(positional[0], globals, builtins, io)
}

///|
fn builtin_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "next() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let default_value : Value? = if positional.length() == 2 {
    Some(positional[1])
  } else {
    None
  }
  let _ = locals
  iterator_next(positional[0], default_value, globals, builtins, io)
}

///|
fn bigint_to_base_string(
  value_in : @bigint.BigInt,
  base : Int,
  prefix : String,
) -> String {
  // NOTE: BigInt already provides `to_string()` for decimal.
  // For non-decimal, we implement a simple base conversion using div/mod.
  if value_in == 0N {
    return prefix + "0"
  }
  let digits = if base == 2 {
    "01"
  } else if base == 8 {
    "01234567"
  } else {
    "0123456789abcdef"
  }
  let mut value = value_in
  let mut sign = ""
  if value < 0N {
    sign = "-"
    value = -value
  }
  let b = @bigint.BigInt::from_int(base)
  let chars : Array[Char] = []
  let mut n = value
  while n > 0N {
    let d = (n % b).to_int()
    chars.push(digits.to_array()[d])
    n = n / b
  }
  let buf = StringBuilder::new()
  buf.write_string(sign)
  buf.write_string(prefix)
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(chars[i])
    if i == 0 {
      break
    }
  }
  buf.to_string()
}

///|
fn escape_string_for_repr(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text.to_array() {
    if ch == '\\' {
      buf.write_string("\\\\")
    } else if ch == '"' {
      buf.write_string("\\\"")
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else if ch == '\r' {
      buf.write_string("\\r")
    } else if ch == '\t' {
      buf.write_string("\\t")
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|

///|
fn builtin_property(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  if positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "property() takes at most 4 arguments".to_string(),
      ),
    )
  }
  let mut fget = if positional.length() >= 1 {
    positional[0]
  } else {
    Value::None
  }
  let mut fset = if positional.length() >= 2 {
    positional[1]
  } else {
    Value::None
  }
  let mut fdel = if positional.length() >= 3 {
    positional[2]
  } else {
    Value::None
  }
  let mut doc = if positional.length() >= 4 {
    positional[3]
  } else {
    Value::None
  }
  let mut has_fget = positional.length() >= 1
  let mut has_fset = positional.length() >= 2
  let mut has_fdel = positional.length() >= 3
  let mut has_doc = positional.length() >= 4
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "fget" =>
        if has_fget {
          return Err(multiple_values_error("property", "fget"))
        } else {
          fget = value
          has_fget = true
        }
      "fset" =>
        if has_fset {
          return Err(multiple_values_error("property", "fset"))
        } else {
          fset = value
          has_fset = true
        }
      "fdel" =>
        if has_fdel {
          return Err(multiple_values_error("property", "fdel"))
        } else {
          fdel = value
          has_fdel = true
        }
      "doc" =>
        if has_doc {
          return Err(multiple_values_error("property", "doc"))
        } else {
          doc = value
          has_doc = true
        }
      _ => return Err(unexpected_keyword_argument_error("property", key))
    }
  }
  let dict : Array[(String, Value)] = []
  dict.push(("fget", fget))
  dict.push(("fset", fset))
  dict.push(("fdel", fdel))
  dict.push(("doc", doc))
  Ok(
    Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "property", bases: [], dict: [] },
      dict,
    }),
  )
}

///|
fn builtin_staticmethod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("staticmethod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "staticmethod() takes exactly one argument".to_string(),
      ),
    )
  }
  let dict : Array[(String, Value)] = []
  dict.push(("func", positional[0]))
  Ok(
    Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "staticmethod", bases: [], dict: [] },
      dict,
    }),
  )
}

///|
fn builtin_classmethod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("classmethod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "classmethod() takes exactly one argument".to_string(),
      ),
    )
  }
  let dict : Array[(String, Value)] = []
  dict.push(("func", positional[0]))
  Ok(
    Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "classmethod", bases: [], dict: [] },
      dict,
    }),
  )
}

///|
fn builtin_register(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("register", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "register() takes exactly two arguments".to_string(),
      ),
    )
  }
  Ok(positional[1])
}

///|
fn builtin_bool(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("bool", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::Bool(false))
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "bool() takes at most one argument".to_string(),
      ),
    )
  }
  Ok(Value::Bool(bool_from_value(positional[0])))
}

///|
fn builtin_repr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("repr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "repr() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(text) =>
      Ok(Value::Str("\"" + escape_string_for_repr(text) + "\""))
    other => Ok(Value::Str(value_to_string(other)))
  }
}

///|
fn builtin_abs(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("abs", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "abs() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(if v < 0N { -v } else { v }))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) => Ok(Value::Float(if v < 0.0 { -v } else { v }))
    Value::Complex(real, imag) =>
      Ok(Value::Float(@math.pow(real * real + imag * imag, 0.5)))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "bad operand type for abs()".to_string(),
        ),
      )
  }
}

///|
fn round_float_to_int(value : Double) -> Int64 {
  if value >= 0.0 {
    @math.floor(value + 0.5).to_int64()
  } else {
    @math.ceil(value - 0.5).to_int64()
  }
}

///|
fn builtin_round(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("round", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "round() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  // `ndigits` is accepted but ignored for now.
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(round_float_to_int(v))))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "round() argument must be a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_pow(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("pow", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "pow() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let modulus_opt : @bigint.BigInt? = if positional.length() == 3 {
    match positional[2] {
      Value::Int(v) => Some(v)
      Value::Bool(v) => Some(if v { 1N } else { 0N })
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "pow() 3rd argument must be int".to_string(),
          ),
        )
    }
  } else {
    None
  }
  match (positional[0], positional[1], modulus_opt) {
    (Value::Int(a), Value::Int(b), Some(m)) =>
      if b < 0N {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "pow() exponent must be >= 0 when modulus is provided".to_string(),
          ),
        )
      } else if m == 0N {
        Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "integer modulo by zero".to_string(),
          ),
        )
      } else {
        Ok(Value::Int(a.pow(b, modulus=m)))
      }
    (Value::Int(a), Value::Int(b), None) =>
      if b < 0N {
        let aa = match bigint_to_double_checked(a) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let bb = match bigint_to_double_checked(b) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Float(@math.pow(aa, bb)))
      } else {
        Ok(Value::Int(a.pow(b)))
      }
    _ => {
      let (_, aa) = match number_value(positional[0]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let (_, bb) = match number_value(positional[1]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Value::Float(@math.pow(aa, bb)))
    }
  }
}

///|
fn builtin_math_sqrt(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.sqrt", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.sqrt() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.pow(x, 0.5)))
}

///|
fn builtin_math_pow(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.pow", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.pow() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (_, a) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (_, b) = match number_value(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.pow(a, b)))
}

///|
fn floor_divmod_int(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt) {
  // Python-style floor division adjustment.
  let mut q = a / b
  let mut r = a % b
  if r != 0N && (r > 0N) != (b > 0N) {
    q = q - 1N
    r = r + b
  }
  (q, r)
}

///|
fn builtin_divmod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("divmod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "divmod() takes exactly two arguments".to_string(),
      ),
    )
  }
  match (positional[0], positional[1]) {
    (Value::Int(a), Value::Int(b)) =>
      if b == 0N {
        Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "integer division or modulo by zero".to_string(),
          ),
        )
      } else {
        let (q, r) = floor_divmod_int(a, b)
        Ok(Value::Tuple([Value::Int(q), Value::Int(r)]))
      }
    _ => {
      let (_, aa) = match number_value(positional[0]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let (_, bb) = match number_value(positional[1]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if bb == 0.0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "division by zero".to_string(),
          ),
        )
      }
      let q = @math.floor(aa / bb)
      let r = aa - q * bb
      Ok(Value::Tuple([Value::Float(q), Value::Float(r)]))
    }
  }
}

///|
fn builtin_chr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("chr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "chr() takes exactly one argument".to_string(),
      ),
    )
  }
  let codepoint = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "chr() argument must be int".to_string(),
        ),
      )
  }
  if codepoint < 0N || codepoint > @bigint.BigInt::from_int(0x10FFFF) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: chr() arg not in range(0x110000)".to_string(),
      ),
    )
  }
  Ok(
    Value::Str(
      char_to_string(Int::unsafe_to_char(codepoint.to_int64().to_int())),
    ),
  )
}

///|
fn builtin_ord(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("ord", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "ord() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(text) => {
      let chars = text.to_array()
      if chars.length() != 1 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "ord() expected a character".to_string(),
          ),
        )
      }
      Ok(Value::Int(@bigint.BigInt::from_int(chars[0].to_int())))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "ord() expected a character".to_string(),
        ),
      )
  }
}

///|
fn builtin_bin(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("bin", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "bin() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "bin() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(bigint_to_base_string(value, 2, "0b")))
}

///|
fn builtin_oct(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("oct", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "oct() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "oct() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(bigint_to_base_string(value, 8, "0o")))
}

///|
fn builtin_hex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("hex", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "hex() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "hex() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(bigint_to_base_string(value, 16, "0x")))
}

///|
fn builtin_callable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("callable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "callable() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Function(_) | Value::Class(_) | Value::BoundMethod(_) => true
    Value::Instance(inst) =>
      get_named_value(inst.class.dict, "__call__") is Some(_)
    _ => false
  }
  Ok(Value::Bool(value))
}

///|
fn value_matches_builtin_class(obj : Value, name : String) -> Bool {
  match name {
    "int" =>
      match obj {
        Value::Int(_) | Value::Bool(_) => true
        _ => false
      }
    "bool" =>
      match obj {
        Value::Bool(_) => true
        _ => false
      }
    "float" =>
      match obj {
        Value::Float(_) => true
        _ => false
      }
    "complex" =>
      match obj {
        Value::Complex(_, _) => true
        _ => false
      }
    "str" =>
      match obj {
        Value::Str(_) => true
        _ => false
      }
    "bytes" =>
      match obj {
        Value::Bytes(_) => true
        _ => false
      }
    "bytearray" =>
      match obj {
        Value::ByteArray(_) => true
        _ => false
      }
    "memoryview" =>
      match obj {
        Value::MemoryView(_) => true
        _ => false
      }
    "list" =>
      match obj {
        Value::List(_) => true
        _ => false
      }
    "tuple" =>
      match obj {
        Value::Tuple(_) => true
        _ => false
      }
    "dict" =>
      match obj {
        Value::Dict(_) => true
        _ => false
      }
    "set" =>
      match obj {
        Value::Set(_) => true
        _ => false
      }
    "NoneType" =>
      match obj {
        Value::None => true
        _ => false
      }
    _ => false
  }
}

///|
fn builtin_isinstance(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("isinstance", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "isinstance() takes exactly two arguments".to_string(),
      ),
    )
  }
  let obj = positional[0]
  let cls = positional[1]
  match cls {
    Value::Function(func) =>
      if func.body.length() == 0 {
        let ok = value_matches_builtin_class(obj, func.name)
        Ok(Value::Bool(ok))
      } else {
        Ok(Value::Bool(false))
      }
    Value::Class(klass) =>
      if klass.name == "type" {
        match obj {
          Value::Class(_) => Ok(Value::Bool(true))
          _ => Ok(Value::Bool(false))
        }
      } else if value_matches_builtin_class(obj, klass.name) {
        Ok(Value::Bool(true))
      } else {
        match obj {
          Value::Instance(inst) => {
            let mro = match class_mro(inst.class) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for c in mro {
              if c.name == klass.name {
                return Ok(Value::Bool(true))
              }
            }
            Ok(Value::Bool(false))
          }
          Value::Class(c) => Ok(Value::Bool(c.name == klass.name))
          _ => Ok(Value::Bool(false))
        }
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "isinstance() arg 2 must be a type".to_string(),
        ),
      )
  }
}

///|
fn issubclass_type_error_arg1() -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    "issubclass() arg 1 must be a class".to_string(),
  )
}

///|
fn issubclass_type_error_arg2() -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    "issubclass() arg 2 must be a class or tuple of classes".to_string(),
  )
}

///|
fn issubclass_matches_builtin_names(
  cls_name : String,
  base_name : String,
) -> Bool {
  if cls_name == base_name {
    true
  } else {
    cls_name == "bool" && base_name == "int"
  }
}

///|
fn issubclass_pair(
  cls : Value,
  base : Value,
) -> Result[Bool, RuntimeError] {
  match base {
    Value::Tuple(values) => {
      for entry in values {
        let ok = match issubclass_pair(cls, entry) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if ok {
          return Ok(true)
        }
      }
      Ok(false)
    }
    Value::Class(base_class) => {
      if base_class.name == "type" {
        match cls {
          Value::Class(_) => Ok(true)
          Value::Function(func) => Ok(func.body.length() == 0)
          _ => Ok(false)
        }
      } else {
        match cls {
          Value::Class(klass) => {
            let mro = match class_mro(klass) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for c in mro {
              if c.name == base_class.name {
                return Ok(true)
              }
            }
            Ok(false)
          }
          Value::Function(func) =>
            if func.body.length() == 0 {
              Ok(func.name == base_class.name)
            } else {
              Err(issubclass_type_error_arg1())
            }
          _ => Err(issubclass_type_error_arg1())
        }
      }
    }
    Value::Function(base_func) =>
      if base_func.body.length() == 0 {
        if base_func.name == "type" {
          match cls {
            Value::Class(_) => Ok(true)
            Value::Function(func) => Ok(func.body.length() == 0)
            _ => Ok(false)
          }
        } else {
          match cls {
            Value::Class(klass) => Ok(klass.name == base_func.name)
            Value::Function(func) =>
              if func.body.length() == 0 {
                Ok(issubclass_matches_builtin_names(func.name, base_func.name))
              } else {
                Err(issubclass_type_error_arg1())
              }
            _ => Err(issubclass_type_error_arg1())
          }
        }
      } else {
        Err(issubclass_type_error_arg2())
      }
    _ => Err(issubclass_type_error_arg2())
  }
}

///|
fn builtin_issubclass(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("issubclass", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "issubclass() takes exactly two arguments".to_string(),
      ),
    )
  }
  let cls = positional[0]
  let base = positional[1]
  let ok = match issubclass_pair(cls, base) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(ok))
}

///|
fn builtin_type(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("type", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 1 {
    let value = positional[0]
    return match value {
      Value::Instance(inst) => Ok(Value::Class(inst.class))
      Value::Class(_) =>
        Ok(Value::Class(builtin_class_from_name("type", builtins)))
      _ =>
        Ok(
          Value::Class(
            builtin_class_from_name(type_name_from_value(value), builtins),
          ),
        )
    }
  }
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "type() takes 1 or 3 arguments".to_string(),
      ),
    )
  }
  let name = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type() argument 1 must be str".to_string(),
        ),
      )
  }
  let base_values : Array[Value] = []
  let raw_bases = match positional[1] {
    Value::Tuple(values) => values
    Value::List(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type() argument 2 must be a tuple of classes".to_string(),
        ),
      )
  }
  for base in raw_bases {
    match base {
      Value::Class(_) => base_values.push(base)
      Value::Function(func) =>
        if func.body.length() == 0 && is_builtin_class_name(func.name) {
          base_values.push(
            Value::Class(builtin_class_from_name(func.name, builtins)),
          )
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "type() argument 2 must be a tuple of classes".to_string(),
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "type() argument 2 must be a tuple of classes".to_string(),
          ),
        )
    }
  }
  if base_values.length() == 0 {
    match get_named_value(builtins, "object") {
      Some(Value::Class(object_class)) =>
        base_values.push(Value::Class(object_class))
      _ => ()
    }
  }
  let class_dict : Array[(String, Value)] = []
  let pairs = match positional[2] {
    Value::Dict(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type() argument 3 must be a dict".to_string(),
        ),
      )
  }
  for pair in pairs {
    match pair.0 {
      Value::Str(key) => class_dict.push((key, pair.1))
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "type() argument 3 must be a dict with str keys".to_string(),
          ),
        )
    }
  }
  if get_named_value(class_dict, "__name__") is None {
    class_dict.push(("__name__", Value::Str(name)))
  }
  if get_named_value(class_dict, "__qualname__") is None {
    class_dict.push(("__qualname__", Value::Str(name)))
  }
  if get_named_value(class_dict, "__module__") is None {
    match get_named_value(globals, "__name__") {
      Some(Value::Str(module_name)) =>
        class_dict.push(("__module__", Value::Str(module_name)))
      _ => ()
    }
  }
  let klass = ClassValue::{ name, bases: base_values, dict: class_dict }
  let _ = match class_mro(klass) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Class(klass))
}

///|
fn builtin_id(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("id", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "id() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = positional[0]
  match value {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Str(text) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(hash_string(text))))
    _ =>
      Ok(
        Value::Int(
          @bigint.BigInt::from_int64(hash_string(value_to_string(value))),
        ),
      )
  }
}

///|
fn builtin_hash(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("hash", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "hash() takes exactly one argument".to_string(),
      ),
    )
  }
  match hash_value(positional[0]) {
    Ok(hash) => Ok(Value::Int(hash))
    Err(err) => Err(err)
  }
}

///|
fn builtin_globals(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = io
  let _ = locals
  let _ = builtins
  let _ = match ensure_no_keywords("globals", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "globals() takes no arguments".to_string(),
      ),
    )
  }
  let pairs : Array[(Value, Value)] = []
  for pair in globals {
    pairs.push((Value::Str(pair.0), pair.1))
  }
  Ok(Value::Dict(pairs))
}

///|
fn builtin_locals(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = io
  let _ = globals
  let _ = builtins
  let _ = match ensure_no_keywords("locals", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "locals() takes no arguments".to_string(),
      ),
    )
  }
  let pairs : Array[(Value, Value)] = []
  for pair in locals {
    pairs.push((Value::Str(pair.0), pair.1))
  }
  Ok(Value::Dict(pairs))
}

///|
fn builtin_eval(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let (expr_value, globals_arg, locals_arg) = match
    parse_exec_eval_args("eval", positional, keywords, "expression") {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let expr_text = match expr_value {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "eval() arg 1 must be a string".to_string(),
        ),
      )
  }
  let (locals_env, globals_env, locals_pairs, globals_pairs) = match
    resolve_exec_eval_env("eval", globals_arg, locals_arg, locals, globals) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let expr = match parse_expr(expr_text) {
    Ok(v) => v
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  push_traceback_frame("<eval>".to_string(), "<eval>".to_string())
  let result = eval_expr_with_env(expr, locals_env, globals_env, builtins, io)
  pop_traceback_frame()
  match globals_pairs {
    Some(pairs) => sync_env_to_dict(globals_env, pairs)
    None => ()
  }
  match locals_pairs {
    Some(pairs) => sync_env_to_dict(locals_env, pairs)
    None => ()
  }
  result
}

///|
fn builtin_exec(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let (source_value, globals_arg, locals_arg) = match
    parse_exec_eval_args("exec", positional, keywords, "source") {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let source_text = match source_value {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "exec() arg 1 must be a string".to_string(),
        ),
      )
  }
  let (locals_env, globals_env, locals_pairs, globals_pairs) = match
    resolve_exec_eval_env("exec", globals_arg, locals_arg, locals, globals) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let program = match parse(source_text) {
    Ok(v) => v
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  push_traceback_frame("<exec>".to_string(), "<exec>".to_string())
  let result = eval_block(
    program.body,
    locals_env,
    globals_env,
    builtins,
    io,
    current_config(),
  )
  pop_traceback_frame()
  match globals_pairs {
    Some(pairs) => sync_env_to_dict(globals_env, pairs)
    None => ()
  }
  match locals_pairs {
    Some(pairs) => sync_env_to_dict(locals_env, pairs)
    None => ()
  }
  match result {
    Ok(_) => Ok(Value::None)
    Err(err) => Err(err)
  }
}

///|
fn builtin_import(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = match ensure_no_keywords("__import__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Err(missing_required_argument_error("__import__", "name"))
  }
  if positional.length() > 5 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__import__() takes at most 5 arguments (" +
        positional.length().to_string() +
        " given)",
      ),
    )
  }
  let name = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "__import__() name must be str".to_string(),
        ),
      )
  }
  if positional.length() == 5 {
    match positional[4] {
      Value::None => ()
      Value::Int(v) =>
        match bigint_to_int_checked(v) {
          Ok(level) =>
            if level != 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "ImportError: relative import level not supported".to_string(),
                ),
              )
            }
          Err(err) => return Err(err)
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "__import__() level must be int".to_string(),
          ),
        )
    }
  }
  let module_value = match
    import_module(name, globals, builtins, io, current_config()) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let mut has_fromlist = false
  if positional.length() >= 4 {
    match positional[3] {
      Value::None => ()
      Value::List(values) => has_fromlist = values.length() > 0
      Value::Tuple(values) => has_fromlist = values.length() > 0
      _ => has_fromlist = true
    }
  }
  if has_fromlist || !name.contains(".") {
    return Ok(module_value)
  }
  let top_name = module_top_name(name)
  match module_cache_get(top_name) {
    Some(value) => Ok(value)
    None => Ok(module_value)
  }
}

///|
fn builtin_dir(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = io
  let _ = match ensure_no_keywords("dir", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    let names : Array[Value] = []
    for pair in globals {
      names.push(Value::Str(pair.0))
    }
    return Ok(Value::List(names))
  }
  let _ = builtins
  let _ = locals
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "dir() takes 0 or 1 arguments".to_string(),
      ),
    )
  }
  let value = positional[0]

  // __dir__ hook
  match value {
    Value::Instance(_) | Value::Class(_) => {
      let hook = match
        get_attr_from_value(value, "__dir__", globals, builtins, io) {
        Ok(v) => v
        Err(_err) => Value::None
      }
      match hook {
        Value::None => ()
        _ => {
          let result = match
            call_callable_with_env(hook, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match result {
            Value::List(_) => return Ok(result)
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__dir__ must return a list".to_string(),
                ),
              )
          }
        }
      }
    }
    _ => ()
  }

  // Default listing: include inherited names, sort, dedup.
  let names : Array[String] = []
  fn push_name(names : Array[String], name : String) -> Unit {
    if name == "__class__" {
      // Hide implementation detail used to support zero-arg super().
      return
    }
    for existing in names {
      if existing == name {
        return
      }
    }
    names.push(name)
  }

  match value {
    Value::Dict(pairs) =>
      for pair in pairs {
        match pair.0 {
          Value::Str(name) => push_name(names, name)
          _ => ()
        }
      }
    Value::Instance(inst) => {
      for pair in inst.dict {
        push_name(names, pair.0)
      }
      let mro = match class_mro(inst.class) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for cls in mro {
        for pair in cls.dict {
          if pair.0 != "__getattribute__" &&
            pair.0 != "__setattr__" &&
            pair.0 != "__delattr__" {
            push_name(names, pair.0)
          }
        }
      }
    }
    Value::Class(klass) => {
      let mro = match class_mro(klass) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for cls in mro {
        for pair in cls.dict {
          if pair.0 != "__getattribute__" &&
            pair.0 != "__setattr__" &&
            pair.0 != "__delattr__" {
            push_name(names, pair.0)
          }
        }
      }
    }
    _ => ()
  }
  names.sort()
  let out : Array[Value] = []
  for name in names {
    out.push(Value::Str(name))
  }
  Ok(Value::List(out))
}

///|
fn builtin_getattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("getattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io
  let _ = locals
  let _ = globals
  let _ = builtins
  if positional.length() != 2 && positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getattr() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let obj = positional[0]
  let name = match positional[1] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "attribute name must be str".to_string(),
        ),
      )
  }
  match get_attr_from_value(obj, name, globals, builtins, io) {
    Ok(value) => Ok(value)
    Err(err) =>
      if positional.length() == 3 {
        Ok(positional[2])
      } else {
        Err(err)
      }
  }
}

///|
fn builtin_hasattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("hasattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io
  let _ = locals
  let _ = globals
  let _ = builtins
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "hasattr() takes exactly two arguments".to_string(),
      ),
    )
  }
  let obj = positional[0]
  let name = match positional[1] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "attribute name must be str".to_string(),
        ),
      )
  }
  match get_attr_from_value(obj, name, globals, builtins, io) {
    Ok(_) => Ok(Value::Bool(true))
    Err(_err) => Ok(Value::Bool(false))
  }
}

///|
fn builtin_setattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("setattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io
  let _ = locals
  let _ = globals
  let _ = builtins
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "setattr() takes exactly three arguments".to_string(),
      ),
    )
  }
  let target = positional[0]
  let name = match positional[1] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "attribute name must be str".to_string(),
        ),
      )
  }
  let value = positional[2]
  let _ = match set_attr_on_value(target, name, value, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_super(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("super", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io

  // Support:
  // - super(type, obj)
  // - super() best-effort: uses closure __class__ and locals "self" / "cls"
  let mut thisclass_value : Value = Value::None
  let mut self_value : Value = Value::None
  if positional.length() == 0 {
    let cls_opt = match
      lookup_name_value("__class__", locals, globals, builtins) {
      Ok(v) => Some(v)
      Err(err) =>
        if err.exc_type == "NameError" {
          None
        } else {
          return Err(err)
        }
    }
    if cls_opt is None {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: super(): no __class__ in scope".to_string(),
        ),
      )
    }
    thisclass_value = cls_opt.unwrap()
    let self_opt = match lookup_name_value("self", locals, globals, builtins) {
      Ok(v) => Some(v)
      Err(err) =>
        if err.exc_type == "NameError" {
          None
        } else {
          return Err(err)
        }
    }
    let cls_opt2 = match lookup_name_value("cls", locals, globals, builtins) {
      Ok(v) => Some(v)
      Err(err) =>
        if err.exc_type == "NameError" {
          None
        } else {
          return Err(err)
        }
    }
    if self_opt is Some(v) {
      self_value = v
    } else if cls_opt2 is Some(v) {
      self_value = v
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: super(): no self/cls in scope".to_string(),
        ),
      )
    }
  } else if positional.length() == 2 {
    thisclass_value = positional[0]
    self_value = positional[1]
  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "super() takes 0 or 2 arguments".to_string(),
      ),
    )
  }
  let thisclass = match thisclass_value {
    Value::Class(k) => k
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "super() arg 1 must be a type".to_string(),
        ),
      )
  }

  // Determine the dynamic class to do MRO search on
  let self_class = match self_value {
    Value::Instance(inst) => inst.class
    Value::Class(k) => k
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "super() arg 2 must be an instance or type".to_string(),
        ),
      )
  }

  // Ensure thisclass is in self_class mro
  let mro = match class_mro(self_class) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut found = false
  for c in mro {
    if c.name == thisclass.name {
      found = true
      break
    }
  }
  if !found {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "super() arguments are inconsistent".to_string(),
      ),
    )
  }
  let dict : Array[(String, Value)] = []
  dict.push(("__thisclass__", Value::Class(thisclass)))
  dict.push(("__self__", self_value))
  dict.push(("__self_class__", Value::Class(self_class)))
  Ok(
    Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "super", bases: [], dict: [] },
      dict,
    }),
  )
}

///|
fn builtin_delattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("delattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = locals
  let _ = builtins
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "delattr() takes exactly two arguments".to_string(),
      ),
    )
  }
  let target = positional[0]
  let name = match positional[1] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "attribute name must be str".to_string(),
        ),
      )
  }
  let _ = match delete_attr_on_value(target, name, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_mpython_run(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_run", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_run() takes exactly one argument".to_string(),
      ),
    )
  }
  coroutine_await(positional[0])
}

///|
fn builtin_mpython_asyncgenexp_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgenexp_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgenexp_next() takes exactly one argument".to_string(),
      ),
    )
  }
  async_genexp_next(positional[0])
}

///|
fn builtin_mpython_asyncgen_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_next() takes exactly one argument".to_string(),
      ),
    )
  }
  async_generator_next(positional[0])
}

///|
fn builtin_mpython_asyncgen_send(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_send", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_send() takes exactly two arguments".to_string(),
      ),
    )
  }
  async_generator_send(positional[0], positional[1])
}

///|
fn builtin_mpython_asyncgen_throw(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_throw", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_throw() takes exactly two arguments".to_string(),
      ),
    )
  }
  async_generator_throw(positional[0], positional[1])
}

///|
fn builtin_mpython_asyncgen_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_close", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_close() takes exactly one argument".to_string(),
      ),
    )
  }
  async_generator_close(positional[0])
}

///|
fn builtin_asyncio_run(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("asyncio.run", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "asyncio.run() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "coroutine" {
        coroutine_await(positional[0])
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" +
            type_name_from_value(positional[0]) +
            "' object can't be used in 'await' expression",
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" +
          type_name_from_value(positional[0]) +
          "' object can't be used in 'await' expression",
        ),
      )
  }
}

///|
fn builtin_asyncio_gather(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("asyncio.gather", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  for coro in positional {
    let value = match coro {
      Value::Instance(inst) =>
        if inst.class.name == "coroutine" {
          match coroutine_await(coro) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "'" +
              type_name_from_value(coro) +
              "' object can't be used in 'await' expression",
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" +
            type_name_from_value(coro) +
            "' object can't be used in 'await' expression",
          ),
        )
    }
    results.push(value)
  }
  Ok(Value::List(results))
}

///|
fn builtin_thread_get_ident(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.get_ident", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.get_ident() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(1N))
}

///|
fn builtin_thread_allocate_lock(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.allocate_lock", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.allocate_lock() takes no arguments".to_string(),
      ),
    )
  }
  let klass = thread_rlock_class(builtins)
  Ok(Value::Instance(InstanceValue::{ class: klass, dict: [] }))
}

///|
fn make_weakref_instance(value : Value) -> Value {
  let hash = @bigint.BigInt::from_int64(hash_string(value_to_string(value)))
  let dict : Array[(String, Value)] = [
    ("value", value),
    ("hashvalue", Value::Int(hash)),
  ]
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "weakref", bases: [], dict: [] },
    dict,
  })
}

///|
fn builtin_weakref_ref(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.ref", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "ref() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(make_weakref_instance(positional[0]))
}

///|
fn builtin_weakref_proxy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.proxy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "proxy() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_code_replace(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "code.replace() missing code object".to_string(),
      ),
    )
  }
  let mut flags = 0N
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "code" {
        match get_named_value(inst.dict, "co_flags") {
          Some(Value::Int(v)) => flags = v
          Some(Value::Bool(v)) => flags = if v { 1N } else { 0N }
          _ => ()
        }
      }
    _ => ()
  }
  for kw in keywords {
    if kw.0 == "co_flags" {
      let value = match index_from_value(kw.1, 0) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      flags = @bigint.BigInt::from_int(value)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "code.replace() got an unexpected keyword '" + kw.0 + "'",
        ),
      )
    }
  }
  Ok(make_code_instance(flags))
}

///|
fn builtin_coroutine_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("coroutine.close", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "coroutine.close() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_itertools_chain(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.chain", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items : Array[Value] = []
  for iter_value in positional {
    let values = match iterable_values(iter_value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    for item in values {
      items.push(item)
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_chain_from_iterable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.chain.from_iterable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "chain.from_iterable() takes exactly one argument".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        let values = match iterable_values(item) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        for value in values {
          items.push(value)
        }
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_repeat(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.repeat", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "repeat() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let value = positional[0]
  if positional.length() == 1 || positional[1] is Value::None {
    return Ok(make_repeat_iterator(value, None))
  }
  let times = match index_from_value(positional[1], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = if times < 0 { 0 } else { times }
  Ok(make_repeat_iterator(value, Some(@bigint.BigInt::from_int(count))))
}

///|
fn builtin_itertools_starmap(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.starmap", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "starmap() takes exactly two arguments".to_string(),
      ),
    )
  }
  let func = positional[0]
  let iterator = match
    iter_value_to_iterator(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        let args = match item {
          Value::Tuple(values) => values
          Value::List(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "starmap() argument must yield tuples".to_string(),
              ),
            )
        }
        let value = match
          call_callable_with_env(func, args, [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        results.push(value)
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_islice(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.islice", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "islice() takes 2 to 4 arguments".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let start = if positional.length() >= 3 {
    match index_from_value(positional[1], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    0
  }
  let stop_value = if positional.length() >= 3 {
    positional[2]
  } else {
    positional[1]
  }
  let stop = match index_from_value(stop_value, 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let step = if positional.length() == 4 {
    match index_from_value(positional[3], 1) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    1
  }
  if step <= 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: step must be positive".to_string(),
      ),
    )
  }
  let items : Array[Value] = []
  let mut idx = 0
  while idx < stop {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        if idx >= start && ((idx - start) % step == 0) {
          items.push(item)
        }
        idx += 1
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(items))
}

///|
priv struct BuiltinDef {
  name : String
  run : (
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError]
}

///|
let builtin_defs_ref : Ref[Array[BuiltinDef]] = { val: [] }

///|
let builtin_defs_ready : Ref[Bool] = { val: false }

///|
fn ensure_builtin_defs_ready() -> Unit {
  if builtin_defs_ready.val {
    return
  }
  builtin_defs_ref.val = [
    BuiltinDef::{ name: "__mpython_run", run: builtin_mpython_run },
    BuiltinDef::{
      name: "__mpython_asyncgenexp_next",
      run: builtin_mpython_asyncgenexp_next,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_next",
      run: builtin_mpython_asyncgen_next,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_send",
      run: builtin_mpython_asyncgen_send,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_throw",
      run: builtin_mpython_asyncgen_throw,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_close",
      run: builtin_mpython_asyncgen_close,
    },
    BuiltinDef::{ name: "asyncio.run", run: builtin_asyncio_run },
    BuiltinDef::{ name: "asyncio.gather", run: builtin_asyncio_gather },
    BuiltinDef::{ name: "_thread.get_ident", run: builtin_thread_get_ident },
    BuiltinDef::{ name: "_thread.allocate_lock", run: builtin_thread_allocate_lock },
    BuiltinDef::{ name: "_weakref.ref", run: builtin_weakref_ref },
    BuiltinDef::{ name: "_weakref.proxy", run: builtin_weakref_proxy },
    BuiltinDef::{ name: "code.replace", run: builtin_code_replace },
    BuiltinDef::{ name: "coroutine.close", run: builtin_coroutine_close },
    BuiltinDef::{ name: "itertools.chain", run: builtin_itertools_chain },
    BuiltinDef::{
      name: "itertools.chain.from_iterable",
      run: builtin_itertools_chain_from_iterable,
    },
    BuiltinDef::{ name: "itertools.repeat", run: builtin_itertools_repeat },
    BuiltinDef::{ name: "itertools.starmap", run: builtin_itertools_starmap },
    BuiltinDef::{ name: "itertools.islice", run: builtin_itertools_islice },
    BuiltinDef::{ name: "print", run: builtin_print },
    BuiltinDef::{ name: "len", run: builtin_len },
    BuiltinDef::{ name: "range", run: builtin_range },
    BuiltinDef::{ name: "sum", run: builtin_sum },
    BuiltinDef::{ name: "max", run: builtin_max },
    BuiltinDef::{ name: "min", run: builtin_min },
    BuiltinDef::{ name: "any", run: builtin_any },
    BuiltinDef::{ name: "all", run: builtin_all },
    BuiltinDef::{ name: "enumerate", run: builtin_enumerate },
    BuiltinDef::{ name: "zip", run: builtin_zip },
    BuiltinDef::{ name: "map", run: builtin_map },
    BuiltinDef::{ name: "filter", run: builtin_filter },
    BuiltinDef::{ name: "reversed", run: builtin_reversed },
    BuiltinDef::{ name: "sorted", run: builtin_sorted },
    BuiltinDef::{ name: "input", run: builtin_input },
    BuiltinDef::{ name: "str", run: builtin_str },
    BuiltinDef::{ name: "str.maketrans", run: builtin_str_maketrans },
    BuiltinDef::{ name: "bytes", run: builtin_bytes },
    BuiltinDef::{ name: "bytearray", run: builtin_bytearray },
    BuiltinDef::{ name: "memoryview", run: builtin_memoryview },
    BuiltinDef::{ name: "int", run: builtin_int },
    BuiltinDef::{ name: "int.__new__", run: builtin_int_new },
    BuiltinDef::{ name: "float", run: builtin_float },
    BuiltinDef::{ name: "complex", run: builtin_complex },
    BuiltinDef::{ name: "list", run: builtin_list },
    BuiltinDef::{ name: "tuple", run: builtin_tuple },
    BuiltinDef::{ name: "tuple.__new__", run: builtin_tuple_new },
    BuiltinDef::{ name: "set", run: builtin_set },
    BuiltinDef::{ name: "frozenset", run: builtin_frozenset },
    BuiltinDef::{ name: "dict", run: builtin_dict },
    BuiltinDef::{ name: "dict.get", run: builtin_dict_get },
    BuiltinDef::{ name: "dict.pop", run: builtin_dict_pop },
    BuiltinDef::{ name: "dict.setdefault", run: builtin_dict_setdefault },
    BuiltinDef::{ name: "dict.keys", run: builtin_dict_keys },
    BuiltinDef::{ name: "dict.values", run: builtin_dict_values },
    BuiltinDef::{ name: "dict.items", run: builtin_dict_items },
    BuiltinDef::{ name: "dict.update", run: builtin_dict_update },
    BuiltinDef::{ name: "dict.clear", run: builtin_dict_clear },
    BuiltinDef::{ name: "dict.__contains__", run: builtin_dict_contains },
    BuiltinDef::{ name: "dict.__getitem__", run: builtin_dict_getitem },
    BuiltinDef::{ name: "dict.__setitem__", run: builtin_dict_setitem },
    BuiltinDef::{ name: "dict.__delitem__", run: builtin_dict_delitem },
    BuiltinDef::{ name: "dict.__iter__", run: builtin_dict_iter },
    BuiltinDef::{ name: "dict.__len__", run: builtin_dict_len },
    BuiltinDef::{ name: "iter", run: builtin_iter },
    BuiltinDef::{ name: "next", run: builtin_next },
    BuiltinDef::{ name: "bool", run: builtin_bool },
    BuiltinDef::{ name: "property", run: builtin_property },
    BuiltinDef::{ name: "staticmethod", run: builtin_staticmethod },
    BuiltinDef::{ name: "classmethod", run: builtin_classmethod },
    BuiltinDef::{ name: "register", run: builtin_register },
    BuiltinDef::{ name: "repr", run: builtin_repr },
    BuiltinDef::{ name: "abs", run: builtin_abs },
    BuiltinDef::{ name: "round", run: builtin_round },
    BuiltinDef::{ name: "pow", run: builtin_pow },
    BuiltinDef::{ name: "math.sqrt", run: builtin_math_sqrt },
    BuiltinDef::{ name: "math.pow", run: builtin_math_pow },
    BuiltinDef::{ name: "divmod", run: builtin_divmod },
    BuiltinDef::{ name: "chr", run: builtin_chr },
    BuiltinDef::{ name: "ord", run: builtin_ord },
    BuiltinDef::{ name: "bin", run: builtin_bin },
    BuiltinDef::{ name: "oct", run: builtin_oct },
    BuiltinDef::{ name: "hex", run: builtin_hex },
    BuiltinDef::{ name: "callable", run: builtin_callable },
    BuiltinDef::{ name: "isinstance", run: builtin_isinstance },
    BuiltinDef::{ name: "issubclass", run: builtin_issubclass },
    BuiltinDef::{ name: "type", run: builtin_type },
    BuiltinDef::{ name: "id", run: builtin_id },
    BuiltinDef::{ name: "hash", run: builtin_hash },
    BuiltinDef::{ name: "globals", run: builtin_globals },
    BuiltinDef::{ name: "locals", run: builtin_locals },
    BuiltinDef::{ name: "eval", run: builtin_eval },
    BuiltinDef::{ name: "exec", run: builtin_exec },
    BuiltinDef::{ name: "__import__", run: builtin_import },
    BuiltinDef::{ name: "sys.intern", run: builtin_sys_intern },
    BuiltinDef::{
      name: "sys.getfilesystemencoding",
      run: builtin_sys_getfilesystemencoding,
    },
    BuiltinDef::{
      name: "sys.getfilesystemencodeerrors",
      run: builtin_sys_getfilesystemencodeerrors,
    },
    BuiltinDef::{ name: "dir", run: builtin_dir },
    BuiltinDef::{ name: "getattr", run: builtin_getattr },
    BuiltinDef::{ name: "hasattr", run: builtin_hasattr },
    BuiltinDef::{ name: "setattr", run: builtin_setattr },
    BuiltinDef::{ name: "delattr", run: builtin_delattr },
    BuiltinDef::{ name: "super", run: builtin_super },
  ]
  builtin_defs_ready.val = true
}

///|
/// Evaluate a builtin call `name(args...)` with pre-evaluated arguments.
///
/// Returns `Ok(Some(value))` if handled as a builtin, `Ok(None)` if not a builtin.
fn eval_builtin_call(
  name : String,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value?, RuntimeError] {
  ensure_builtin_defs_ready()
  for def in builtin_defs_ref.val {
    if def.name == name {
      let value = match
        (def.run)(positional, keywords, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      return Ok(Some(value))
    }
  }
  Ok(None)
}
