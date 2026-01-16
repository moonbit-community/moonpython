///|
/// Builtin function implementations for the mpython runtime.
///
/// This file centralizes builtin dispatch so `mpython.mbt` can focus on
/// expression evaluation and general call semantics.

///|
fn eval_positional_args(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Value], RuntimeError] {
  let values : Array[Value] = []
  for arg in args {
    let value = match eval_expr_with_env(arg, locals, globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    values.push(value)
  }
  Ok(values)
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let buf = StringBuilder::new()
  for i = 0; i < arg_values.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(" ")
    }
    let text = match
      stringify_value_with_env(arg_values[i], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    buf.write_string(text)
  }
  buf.write_string("\n")
  io.write_stdout(buf.to_string())
  Ok(Value::None)
}

///|
fn builtin_len(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "len() takes exactly one argument".to_string(),
      ),
    )
  }
  match arg_values[0] {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
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

  if arg_values.length() == 0 || arg_values.length() > 3 {
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
  if arg_values.length() == 1 {
    stop = match to_int(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else if arg_values.length() == 2 {
    start = match to_int(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    stop = match to_int(arg_values[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    start = match to_int(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    stop = match to_int(arg_values[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    step = match to_int(arg_values[2]) {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 || arg_values.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sum() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let items = match iterable_values(arg_values[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut is_float = false
  let mut total = 0.0
  if arg_values.length() == 2 {
    let (start_is_float, start_num) = match number_value(arg_values[1]) {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "max() takes at least 1 argument".to_string(),
      ),
    )
  }
  let items = if arg_values.length() == 1 {
    match iterable_values(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    arg_values
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "min() takes at least 1 argument".to_string(),
      ),
    )
  }
  let items = if arg_values.length() == 1 {
    match iterable_values(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    arg_values
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "any() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(arg_values[0]) {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "all() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(arg_values[0]) {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 || arg_values.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "enumerate() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let items = match iterable_values(arg_values[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut start = 0L
  if arg_values.length() == 2 {
    match arg_values[1] {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let iterables : Array[Array[Value]] = []
  for arg in args {
    let value = match eval_expr_with_env(arg, locals, globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
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
fn builtin_reversed(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "reversed() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(arg_values[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::List(reverse_values(items)))
}

///|
fn builtin_sorted(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 || arg_values.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sorted() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let mut reverse = false
  if arg_values.length() == 2 {
    match arg_values[1] {
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
  let items_in = match iterable_values(arg_values[0]) {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() > 0 {
    io.write_stdout(value_to_string(arg_values[0]))
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::Str(""))
  } else {
    let text = match
      stringify_value_with_env(arg_values[0], globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Value::Str(text))
  }
}

///|
fn builtin_int(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::Int(0L))
  } else {
    match arg_values[0] {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::Float(0.0))
  } else {
    match arg_values[0] {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::List([]))
  } else {
    let items = match iterable_values(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Value::List(items))
  }
}

///|
fn builtin_tuple(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::Tuple([]))
  } else {
    let items = match iterable_values(arg_values[0]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Value::Tuple(items))
  }
}

///|
fn builtin_set(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::Set([]))
  } else {
    let items = match iterable_values(arg_values[0]) {
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
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let arg_values = match
    eval_positional_args(args, locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if arg_values.length() == 0 {
    Ok(Value::Dict([]))
  } else {
    match arg_values[0] {
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
priv struct BuiltinDef {
  name : String
  run : (
    Array[Expr],
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
  ]
  builtin_defs_ready.val = true
}

///|
/// Evaluate a builtin call `name(args...)`.
///
/// Returns `Ok(Some(value))` if handled as a builtin, `Ok(None)` if not a builtin.
fn eval_builtin_call(
  name : String,
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value?, RuntimeError] {
  ensure_builtin_defs_ready()
  for def in builtin_defs_ref.val {
    if def.name == name {
      let value = match (def.run)(args, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      return Ok(Some(value))
    }
  }
  Ok(None)
}
