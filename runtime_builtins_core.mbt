///|
/// Core builtins (print/len/range/sum/max/min/any/all/enumerate/zip/map/filter/reversed/sorted).

///|
fn builtin_internal_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__mpython.internal_iter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython.internal_iter() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_internal_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__mpython.internal_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython.internal_next() takes exactly one argument".to_string(),
      ),
    )
  }
  iterator_next(positional[0], None, globals, builtins, io)
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
  let mut file_value = Value::None
  let mut flush = false
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
      "file" => file_value = value
      "flush" =>
        match value {
          Value::Bool(v) => flush = v
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
  let text = buf.to_string()
  if file_value is Value::None {
    match module_cache_get("sys") {
      Some(sys_module) =>
        match get_attr_from_value(sys_module, "stdout", globals, builtins, io) {
          Ok(v) => file_value = v
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => ()
              _ => return Err(err)
            }
        }
      None => ()
    }
  }
  match file_value {
    Value::None => io.write_stdout(text)
    _ => {
      let write_method = match
        get_attr_from_value(file_value, "write", globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let _ = match
        call_callable_with_env(
          write_method,
          [Value::Str(text)],
          [],
          globals,
          builtins,
          io,
        ) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if flush {
        match get_attr_from_value(file_value, "flush", globals, builtins, io) {
          Ok(flush_method) => {
            let _ = match
              call_callable_with_env(
                flush_method,
                [],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => ()
              _ => return Err(err)
            }
        }
      }
    }
  }
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
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(values)) =>
          return Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
        _ => ()
      }
      match get_named_value(inst.dict, tuple_storage_name) {
        Some(Value::Tuple(values)) =>
          return Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
        _ => ()
      }
      match get_named_value(inst.dict, dict_storage_name) {
        Some(Value::Dict(pairs)) =>
          return Ok(Value::Int(@bigint.BigInt::from_int(pairs.length())))
        _ => ()
      }
      match get_named_value(inst.dict, set_storage_name) {
        Some(Value::Set(values)) =>
          return Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
        _ => ()
      }
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

  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range expected at least 1 argument, got 0".to_string(),
      ),
    )
  }
  if positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "range expected at most 3 arguments, got " +
        positional.length().to_string(),
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
        RuntimeErrorKind::Runtime,
        "ValueError: range() arg 3 must not be zero".to_string(),
      ),
    )
  }
  Ok(make_range_instance(start, stop, step, builtins))
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
  match best {
    Value::Str(best_text) => {
      let mut current = best_text
      for i = 1; i < items.length(); i = i + 1 {
        let item = items[i]
        match item {
          Value::Str(text) =>
            if cmp_string_for_sorted(text, current) > 0 {
              best = item
              current = text
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "max() expected strings".to_string(),
              ),
            )
        }
      }
    }
    Value::Bytes(best_bytes) => {
      fn cmp_bytes_for_sorted(a : Array[Int], b : Array[Int]) -> Int {
        let n = if a.length() < b.length() { a.length() } else { b.length() }
        for i = 0; i < n; i = i + 1 {
          let ai = a[i]
          let bi = b[i]
          if ai < bi {
            return -1
          }
          if ai > bi {
            return 1
          }
        }
        if a.length() < b.length() {
          -1
        } else if a.length() > b.length() {
          1
        } else {
          0
        }
      }

      let mut current = best_bytes
      for i = 1; i < items.length(); i = i + 1 {
        let item = items[i]
        match item {
          Value::Bytes(bytes) =>
            if cmp_bytes_for_sorted(bytes, current) > 0 {
              best = item
              current = bytes
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "max() expected bytes".to_string(),
              ),
            )
        }
      }
    }
    Value::List(_) | Value::Tuple(_) =>
      for i = 1; i < items.length(); i = i + 1 {
        let item = items[i]
        let cmp = match cmp_value_for_sorted_dynamic(item, best) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp > 0 {
          best = item
        }
      }
    _ => {
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
  match best {
    Value::Str(best_text) => {
      let mut current = best_text
      for i = 1; i < items.length(); i = i + 1 {
        let item = items[i]
        match item {
          Value::Str(text) =>
            if cmp_string_for_sorted(text, current) < 0 {
              best = item
              current = text
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "min() expected strings".to_string(),
              ),
            )
        }
      }
    }
    Value::Bytes(best_bytes) => {
      fn cmp_bytes_for_sorted(a : Array[Int], b : Array[Int]) -> Int {
        let n = if a.length() < b.length() { a.length() } else { b.length() }
        for i = 0; i < n; i = i + 1 {
          let ai = a[i]
          let bi = b[i]
          if ai < bi {
            return -1
          }
          if ai > bi {
            return 1
          }
        }
        if a.length() < b.length() {
          -1
        } else if a.length() > b.length() {
          1
        } else {
          0
        }
      }

      let mut current = best_bytes
      for i = 1; i < items.length(); i = i + 1 {
        let item = items[i]
        match item {
          Value::Bytes(bytes) =>
            if cmp_bytes_for_sorted(bytes, current) < 0 {
              best = item
              current = bytes
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "min() expected bytes".to_string(),
              ),
            )
        }
      }
    }
    Value::List(_) | Value::Tuple(_) =>
      for i = 1; i < items.length(); i = i + 1 {
        let item = items[i]
        let cmp = match cmp_value_for_sorted_dynamic(item, best) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp < 0 {
          best = item
        }
      }
    _ => {
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
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
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
  Ok(make_enumerate_iterator(iterator, start))
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
  let mut strict = false
  for pair in keywords {
    if pair.0 == "strict" {
      match pair.1 {
        Value::Bool(v) => strict = v
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "zip() strict must be bool".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "zip() got unexpected keyword arguments".to_string(),
        ),
      )
    }
  }
  let iterators : Array[Value] = []
  for value in positional {
    let it = match iter_value_to_iterator(value, globals, builtins, io) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    iterators.push(it)
  }
  Ok(make_zip_iterator(iterators, strict))
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
  // Prefer sequence fast-paths so `len(reversed(seq))` works (tests rely on it).
  match positional[0] {
    Value::List(values) => Ok(Value::List(reverse_values(values)))
    Value::Tuple(values) => Ok(Value::List(reverse_values(values)))
    Value::Str(text) => {
      let chars = text.to_array()
      let out : Array[Value] = []
      let mut i = chars.length()
      while i > 0 {
        i -= 1
        out.push(Value::Str(chars[i].to_string()))
      }
      Ok(Value::List(out))
    }
    other => {
      // Fallback: consume any iterable and return a reversed list.
      let iterator_value = match
        iter_value_to_iterator(other, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let items : Array[Value] = []
      while true {
        match iterator_next(iterator_value, None, globals, builtins, io) {
          Ok(item) => items.push(item)
          Err(err) =>
            if err.exc_type == "StopIteration" {
              break
            } else {
              return Err(err)
            }
        }
      }
      Ok(Value::List(reverse_values(items)))
    }
  }
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
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sorted() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let mut reverse = false
  let mut key_value : Value? = None
  for pair in keywords {
    if pair.0 == "key" {
      key_value = Some(pair.1)
    } else if pair.0 == "reverse" {
      match pair.1 {
        Value::Bool(v) => reverse = v
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "sorted() reverse must be bool".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "sorted() got unexpected keyword arguments".to_string(),
        ),
      )
    }
  }
  if positional.length() == 2 {
    if key_value is Some(_) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "sorted() got multiple values for argument 'key'".to_string(),
        ),
      )
    }
    key_value = Some(positional[1])
  }
  let items = match
    collect_items_from_iterable(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if items.length() == 0 {
    return Ok(Value::List([]))
  }
  fn lt_for_sort(
    a : Value,
    b : Value,
    globals : Array[(String, Value)],
    builtins : Array[(String, Value)],
    io : MockIO,
  ) -> Result[Bool, RuntimeError] {
    fn tuple_items_for_sort(v : Value) -> Array[Value]? {
      match v {
        Value::Tuple(items) => Some(items)
        Value::Instance(inst) =>
          match get_named_value(inst.dict, tuple_storage_name) {
            Some(Value::Tuple(items)) => Some(items)
            _ => None
          }
        _ => None
      }
    }

    match (a, b) {
      (Value::Str(x), Value::Str(y)) => Ok(cmp_string_for_sorted(x, y) < 0)
      _ =>
        match (tuple_items_for_sort(a), tuple_items_for_sort(b)) {
          (Some(xs), Some(ys)) =>
            match compare_sequence_values(xs, ys, globals, builtins, io) {
              Ok(cmp) => Ok(cmp < 0)
              Err(err) => Err(err)
            }
          _ =>
            match (a, b) {
              (Value::List(xs), Value::List(ys)) =>
                match compare_sequence_values(xs, ys, globals, builtins, io) {
                  Ok(cmp) => Ok(cmp < 0)
                  Err(err) => Err(err)
                }
              (Value::Int(_) | Value::Float(_) | Value::Bool(_), _)
              | (_, Value::Int(_) | Value::Float(_) | Value::Bool(_)) => {
                let (_, left_num) = match number_value(a) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let (_, right_num) = match number_value(b) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                Ok(left_num < right_num)
              }
              _ =>
                ordering_bool(
                  a, b, "__lt__", "__gt__", "<", globals, builtins, io,
                )
            }
        }
    }
  }

  let mut out : Array[Value] = []
  match key_value {
    Some(key_fn) => {
      let key_pairs : Array[(Value, Value)] = []
      for item in items {
        let key = if key_fn is Value::None {
          item
        } else {
          match
            call_callable_with_env(key_fn, [item], [], globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        key_pairs.push((key, item))
      }
      let mut kind_opt : SortKind? = None
      let mut can_use_fast = true
      for pair in key_pairs {
        match sort_kind_for_sorted(pair.0) {
          Some(kind) =>
            match kind_opt {
              None => kind_opt = Some(kind)
              Some(prev) => if prev != kind { can_use_fast = false }
            }
          None => can_use_fast = false
        }
        // Only use the fast comparator for simple scalar keys. For tuples/lists,
        // fall back to rich comparisons so wrappers like pprint._safe_key work.
        match kind_opt {
          Some(SortKind::Tuple) | Some(SortKind::List) => can_use_fast = false
          _ => ()
        }
      }
      let sorted_pairs = if can_use_fast {
        let kind = match kind_opt {
          Some(kind) => kind
          None => return Ok(Value::List([]))
        }
        match stable_sort_pairs_by_key(key_pairs, kind) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
      } else {
        // Stable insertion sort using __lt__ fallback.
        let out_pairs : Array[(Value, Value)] = []
        for pair in key_pairs {
          out_pairs.push(pair)
        }
        let mut i = 1
        while i < out_pairs.length() {
          let pair = out_pairs[i]
          let mut j = i
          while j > 0 {
            let less = match
              lt_for_sort(pair.0, out_pairs[j - 1].0, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            if !less {
              break
            }
            out_pairs[j] = out_pairs[j - 1]
            j -= 1
          }
          out_pairs[j] = pair
          i += 1
        }
        out_pairs
      }
      for pair in sorted_pairs {
        out.push(pair.1)
      }
    }
    None => {
      let mut kind_opt : SortKind? = None
      let mut can_use_fast = true
      for item in items {
        match sort_kind_for_sorted(item) {
          Some(kind) =>
            match kind_opt {
              None => kind_opt = Some(kind)
              Some(prev) => if prev != kind { can_use_fast = false }
            }
          None => can_use_fast = false
        }
        match kind_opt {
          Some(SortKind::Tuple) | Some(SortKind::List) => can_use_fast = false
          _ => ()
        }
      }
      out = if can_use_fast {
        let kind = match kind_opt {
          Some(kind) => kind
          None => return Ok(Value::List([]))
        }
        match stable_sort_for_sorted(items, kind) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
      } else {
        // Stable insertion sort using __lt__ fallback.
        let out : Array[Value] = []
        for item in items {
          out.push(item)
        }
        let mut i = 1
        while i < out.length() {
          let item = out[i]
          let mut j = i
          while j > 0 {
            let less = match
              lt_for_sort(item, out[j - 1], globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            if !less {
              break
            }
            out[j] = out[j - 1]
            j -= 1
          }
          out[j] = item
          i += 1
        }
        out
      }
    }
  }
  if reverse {
    out = reverse_values(out)
  }
  Ok(Value::List(out))
}

///|
fn builtin_sys_exit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.exit", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "exit() takes at most 1 argument".to_string(),
      ),
    )
  }
  let args : Array[Value] = []
  if positional.length() == 1 {
    args.push(positional[0])
  }
  let klass = match get_named_value(builtins, "SystemExit") {
    Some(Value::Class(klass)) => klass
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: SystemExit is not available".to_string(),
        ),
      )
  }
  let inst_value = match
    call_callable_with_env(Value::Class(klass), args, [], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match inst_value {
    Value::Instance(inst) => Err(runtime_error_from_exception_instance(inst))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: invalid SystemExit".to_string(),
        ),
      )
  }
}

///|
fn builtin_sys_audit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.audit", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sys.audit() missing required argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(_) => Ok(Value::None)
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "sys.audit() event must be str".to_string(),
        ),
      )
  }
}
