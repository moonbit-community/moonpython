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
  match positional[0] {
    Value::Str(text) => Ok(Value::Int(text.length().to_int64()))
    Value::List(values) => Ok(Value::Int(values.length().to_int64()))
    Value::Tuple(values) => Ok(Value::Int(values.length().to_int64()))
    Value::Dict(pairs) => Ok(Value::Int(pairs.length().to_int64()))
    Value::Set(values) => Ok(Value::Int(values.length().to_int64()))
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
  let _ = match ensure_no_keywords("range", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  fn to_int(value : Value) -> Result[Int64, RuntimeError] {
    match value {
      Value::Int(v) => Ok(v)
      Value::Bool(v) => Ok(if v { 1L } else { 0L })
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
  let mut start = 0L
  let mut stop = 0L
  let mut step = 1L
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
  if step == 0L {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range() arg 3 must not be zero".to_string(),
      ),
    )
  }
  let items : Array[Value] = []
  let mut i = start
  if step > 0L {
    while i < stop {
      items.push(Value::Int(i))
      i = i + step
    }
  } else {
    while i > stop {
      items.push(Value::Int(i))
      i = i + step
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
    Ok(Value::Int(total.to_int64()))
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
  let mut start = 0L
  if positional.length() == 2 {
    match positional[1] {
      Value::Int(v) => start = v
      Value::Bool(v) => start = if v { 1L } else { 0L }
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
    i = i + 1L
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
fn builtin_int(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = match ensure_no_keywords("int", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Int(0L))
  } else {
    match positional[0] {
      Value::Int(v) => Ok(Value::Int(v))
      Value::Bool(v) => Ok(Value::Int(if v { 1L } else { 0L }))
      Value::Float(v) => Ok(Value::Int(v.to_int64()))
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
        Ok(Value::Int(parsed.to_int64()))
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
fn builtin_float(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = match ensure_no_keywords("float", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Float(0.0))
  } else {
    match positional[0] {
      Value::Float(v) => Ok(Value::Float(v))
      Value::Int(v) => Ok(Value::Float(v.to_double()))
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
fn builtin_list(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = match ensure_no_keywords("list", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::List([]))
  } else {
    let items = match iterable_values(positional[0]) {
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
  let _ = match ensure_no_keywords("tuple", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Tuple([]))
  } else {
    let items = match iterable_values(positional[0]) {
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
  let _ = match ensure_no_keywords("set", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Set([]))
  } else {
    let items = match iterable_values(positional[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let unique : Array[Value] = []
    for item in items {
      let mut exists = false
      for existing in unique {
        if eq_value(existing, item) {
          exists = true
          break
        }
      }
      if !exists {
        unique.push(item)
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
                pairs.push((values[0], values[1]))
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
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "cannot convert to dict".to_string(),
          ),
        )
    }
  }
}

///|
fn make_iterator(items_in : Array[Value]) -> Value {
  let items : Array[Value] = []
  for item in items_in {
    items.push(item)
  }
  let dict : Array[(String, Value)] = []
  dict.push(("items", Value::List(items)))
  dict.push(("pos", Value::Int(0L)))
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "iterator", bases: [], dict: [] },
    dict,
  })
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
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "iterator" {
        Ok(Value::Instance(inst))
      } else {
        let items = match iterable_values(Value::Instance(inst)) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(make_iterator(items))
      }
    other => {
      let items = match iterable_values(other) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(make_iterator(items))
    }
  }
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
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name != "iterator" {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not an iterator",
          ),
        )
      } else {
        let items_value = get_named_value(inst.dict, "items")
        let pos_value = get_named_value(inst.dict, "pos")
        let items = match items_value {
          Some(Value::List(items)) => items
          _ => []
        }
        let pos = match pos_value {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1L } else { 0L }
          _ => 0L
        }
        if pos < items.length().to_int64() {
          let item = items[pos.to_int()]
          set_named_value(inst.dict, "pos", Value::Int(pos + 1L))
          Ok(item)
        } else {
          match default_value {
            Some(v) => Ok(v)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "StopIteration".to_string(),
                ),
              )
          }
        }
      }
    other =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" + type_name_from_value(other) + "' object is not an iterator",
        ),
      )
  }
}

///|
fn int_to_base_string(value_in : Int64, base : Int, prefix : String) -> String {
  if value_in == 0L {
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
  if value < 0L {
    sign = "-"
    value = -value
  }
  let chars : Array[Char] = []
  let mut n = value
  while n > 0L {
    let d = (n % base.to_int64()).to_int()
    chars.push(digits.to_array()[d])
    n = n / base.to_int64()
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
fn hash_string(text : String) -> Int64 {
  let mut h : Int64 = 0L
  for ch in text.to_array() {
    h = h * 131L + ch.to_int().to_int64()
  }
  h
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
fn builtin_bool(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
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
    Value::Int(v) => Ok(Value::Int(if v < 0L { -v } else { v }))
    Value::Bool(v) => Ok(Value::Int(if v { 1L } else { 0L }))
    Value::Float(v) => Ok(Value::Float(if v < 0.0 { -v } else { v }))
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
    Value::Bool(v) => Ok(Value::Int(if v { 1L } else { 0L }))
    Value::Float(v) => Ok(Value::Int(round_float_to_int(v)))
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
fn pow_int(base : Int64, exp : Int64) -> Int64 {
  let mut out = 1L
  let mut i = 0L
  while i < exp {
    out = out * base
    i = i + 1L
  }
  out
}

///|
fn mod_pow_int(base : Int64, exp : Int64, modulus : Int64) -> Int64 {
  if modulus == 1L || modulus == -1L {
    return 0L
  }
  let mut result = 1L
  let mut b = base % modulus
  let mut e = exp
  while e > 0L {
    if e % 2L != 0L {
      result = result * b % modulus
    }
    e = e / 2L
    b = b * b % modulus
  }
  result
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
  let modulus_opt : Int64? = if positional.length() == 3 {
    match positional[2] {
      Value::Int(v) => Some(v)
      Value::Bool(v) => Some(if v { 1L } else { 0L })
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
      if b < 0L {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "pow() exponent must be >= 0 when modulus is provided".to_string(),
          ),
        )
      } else if m == 0L {
        Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "integer modulo by zero".to_string(),
          ),
        )
      } else {
        Ok(Value::Int(mod_pow_int(a, b, m)))
      }
    (Value::Int(a), Value::Int(b), None) =>
      if b < 0L {
        Ok(Value::Float(@math.pow(a.to_double(), b.to_double())))
      } else {
        Ok(Value::Int(pow_int(a, b)))
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
fn floor_divmod_int(a : Int64, b : Int64) -> (Int64, Int64) {
  let mut q = a / b
  let mut r = a % b
  if r != 0L && (r > 0L) != (b > 0L) {
    q = q - 1L
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
      if b == 0L {
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
    Value::Bool(v) => if v { 1L } else { 0L }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "chr() argument must be int".to_string(),
        ),
      )
  }
  if codepoint < 0L || codepoint > 0x10FFFFL {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: chr() arg not in range(0x110000)".to_string(),
      ),
    )
  }
  Ok(Value::Str(char_to_string(Char::from_int(codepoint.to_int()))))
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
      Ok(Value::Int(chars[0].to_int().to_int64()))
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
    Value::Bool(v) => if v { 1L } else { 0L }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "bin() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(int_to_base_string(value, 2, "0b")))
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
    Value::Bool(v) => if v { 1L } else { 0L }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "oct() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(int_to_base_string(value, 8, "0o")))
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
    Value::Bool(v) => if v { 1L } else { 0L }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "hex() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(int_to_base_string(value, 16, "0x")))
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
    _ => false
  }
  Ok(Value::Bool(value))
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
        let ok = match func.name {
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
          "str" =>
            match obj {
              Value::Str(_) => true
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
          _ => false
        }
        Ok(Value::Bool(ok))
      } else {
        Ok(Value::Bool(false))
      }
    Value::Class(klass) =>
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
fn builtin_type(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = match ensure_no_keywords("type", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "type() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::Str(type_name_from_value(positional[0])))
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
    Value::Bool(v) => Ok(Value::Int(if v { 1L } else { 0L }))
    Value::Str(text) => Ok(Value::Int(hash_string(text)))
    _ => Ok(Value::Int(hash_string(value_to_string(value))))
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
  match positional[0] {
    Value::None => Ok(Value::Int(0L))
    Value::Bool(v) => Ok(Value::Int(if v { 1L } else { 0L }))
    Value::Int(v) => Ok(Value::Int(v))
    Value::Float(v) => Ok(Value::Int(v.to_int64()))
    Value::Str(text) => Ok(Value::Int(hash_string(text)))
    other =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "unhashable type: '" + type_name_from_value(other) + "'",
        ),
      )
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
fn builtin_dir(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
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
  let out : Array[Value] = []
  match value {
    Value::Dict(pairs) =>
      for pair in pairs {
        match pair.0 {
          Value::Str(name) => out.push(Value::Str(name))
          _ => ()
        }
      }
    Value::Instance(inst) => {
      for pair in inst.dict {
        out.push(Value::Str(pair.0))
      }
      for pair in inst.class.dict {
        out.push(Value::Str(pair.0))
      }
    }
    Value::Class(klass) =>
      for pair in klass.dict {
        out.push(Value::Str(pair.0))
      }
    _ => ()
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
  match get_attr_from_value(obj, name) {
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
  match get_attr_from_value(obj, name) {
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
  let _ = match set_attr_on_value(target, name, value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
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
    BuiltinDef::{ name: "int", run: builtin_int },
    BuiltinDef::{ name: "float", run: builtin_float },
    BuiltinDef::{ name: "list", run: builtin_list },
    BuiltinDef::{ name: "tuple", run: builtin_tuple },
    BuiltinDef::{ name: "set", run: builtin_set },
    BuiltinDef::{ name: "dict", run: builtin_dict },
    BuiltinDef::{ name: "iter", run: builtin_iter },
    BuiltinDef::{ name: "next", run: builtin_next },
    BuiltinDef::{ name: "bool", run: builtin_bool },
    BuiltinDef::{ name: "repr", run: builtin_repr },
    BuiltinDef::{ name: "abs", run: builtin_abs },
    BuiltinDef::{ name: "round", run: builtin_round },
    BuiltinDef::{ name: "pow", run: builtin_pow },
    BuiltinDef::{ name: "divmod", run: builtin_divmod },
    BuiltinDef::{ name: "chr", run: builtin_chr },
    BuiltinDef::{ name: "ord", run: builtin_ord },
    BuiltinDef::{ name: "bin", run: builtin_bin },
    BuiltinDef::{ name: "oct", run: builtin_oct },
    BuiltinDef::{ name: "hex", run: builtin_hex },
    BuiltinDef::{ name: "callable", run: builtin_callable },
    BuiltinDef::{ name: "isinstance", run: builtin_isinstance },
    BuiltinDef::{ name: "type", run: builtin_type },
    BuiltinDef::{ name: "id", run: builtin_id },
    BuiltinDef::{ name: "hash", run: builtin_hash },
    BuiltinDef::{ name: "globals", run: builtin_globals },
    BuiltinDef::{ name: "locals", run: builtin_locals },
    BuiltinDef::{ name: "dir", run: builtin_dir },
    BuiltinDef::{ name: "getattr", run: builtin_getattr },
    BuiltinDef::{ name: "hasattr", run: builtin_hasattr },
    BuiltinDef::{ name: "setattr", run: builtin_setattr },
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
