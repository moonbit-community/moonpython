///|
/// Collection builtins (list/tuple/slice/set/frozenset/dict + methods).

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
fn builtin_list_copy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("list.copy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "copy() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::List(values) => {
      let out : Array[Value] = []
      for item in values {
        out.push(item)
      }
      Ok(Value::List(out))
    }
    Value::Instance(inst) =>
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(values)) => {
          let out : Array[Value] = []
          for item in values {
            out.push(item)
          }
          Ok(Value::List(out))
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "copy() expects a list".to_string(),
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "copy() expects a list".to_string(),
        ),
      )
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
fn builtin_slice(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("slice", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "slice() takes 1 to 3 arguments".to_string(),
      ),
    )
  }
  let (start, stop, step) = if positional.length() == 1 {
    (Value::None, positional[0], Value::None)
  } else if positional.length() == 2 {
    (positional[0], positional[1], Value::None)
  } else {
    (positional[0], positional[1], positional[2])
  }
  let dict : Array[(String, Value)] = []
  dict.push(("start", start))
  dict.push(("stop", stop))
  dict.push(("step", step))
  let klass = builtin_class_from_name("slice", builtins)
  Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
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
fn builtin_set_copy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("set.copy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "copy() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Set(values) => {
      let out : Array[Value] = []
      for item in values {
        out.push(item)
      }
      Ok(Value::Set(out))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "copy() expects a set".to_string(),
        ),
      )
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
  if positional.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "dict() takes at most 1 positional argument".to_string(),
      ),
    )
  }
  let pairs : Array[(Value, Value)] = []
  if positional.length() == 1 {
    match positional[0] {
      Value::Dict(items) =>
        for pair in items {
          pairs.push(pair)
        }
      Value::List(items) | Value::Tuple(items) =>
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
      other => {
        let items = match
          collect_items_from_iterable(other, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
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
      }
    }
  }
  for item in keywords {
    let _ = match dict_set_item(pairs, Value::Str(item.0), item.1) {
      Ok(v) => v
      Err(err) => return Err(err)
    }

  }
  Ok(Value::Dict(pairs))
}

///|
fn builtin_dict_copy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("dict.copy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "copy() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Dict(pairs) => {
      let out : Array[(Value, Value)] = []
      for pair in pairs {
        out.push(pair)
      }
      Ok(Value::Dict(out))
    }
    Value::Instance(inst) =>
      match get_named_value(inst.dict, dict_storage_name) {
        Some(Value::Dict(pairs)) => {
          let out : Array[(Value, Value)] = []
          for pair in pairs {
            out.push(pair)
          }
          Ok(Value::Dict(out))
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "copy() expects a dict".to_string(),
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "copy() expects a dict".to_string(),
        ),
      )
  }
}

///|

///|
fn builtin_dict_fromkeys(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("dict.fromkeys", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "fromkeys() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let items = match
    collect_items_from_iterable(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let value = if positional.length() == 3 { positional[2] } else { Value::None }
  let pairs : Array[(Value, Value)] = []
  for item in items {
    let _ = match dict_set_item(pairs, item, value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }

  }
  Ok(Value::Dict(pairs))
}

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
  Err(make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()))
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
    Value::Dict(values) =>
      for entry in values {
        entries.push(entry)
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
        let item = match iterator_next(iterator, None, globals, builtins, io) {
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
