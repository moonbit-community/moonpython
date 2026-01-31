///|
/// Comparison semantics shared by the AST evaluator and the bytecode VM.

///|
fn compare_sequence_values(
  left : Array[Value],
  right : Array[Value],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Int, RuntimeError] {
  let min_len = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i = 0; i < min_len; i = i + 1 {
    if eq_value(left[i], right[i]) {
      continue
    }
    let lt = match
      compare_values_with_env(
        CompareOp::Lt,
        left[i],
        right[i],
        globals,
        builtins,
        io,
      ) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    return Ok(if lt { -1 } else { 1 })
  }
  if left.length() == right.length() {
    Ok(0)
  } else if left.length() < right.length() {
    Ok(-1)
  } else {
    Ok(1)
  }
}

///|
fn compare_bytes_like(left : Array[Int], right : Array[Int]) -> Int {
  let min_len = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i = 0; i < min_len; i = i + 1 {
    let a = left[i] & 0xFF
    let b = right[i] & 0xFF
    if a < b {
      return -1
    }
    if a > b {
      return 1
    }
  }
  if left.length() == right.length() {
    0
  } else if left.length() < right.length() {
    -1
  } else {
    1
  }
}

///|
fn is_intrinsic_default_compare(method_value : Value, name : String) -> Bool {
  match method_value {
    Value::BoundMethod(bound) =>
      bound.function.name == name && bound.function.body.length() == 0
    Value::Function(func) => func.name == name && func.body.length() == 0
    _ => false
  }
}

///|
fn call_compare_method(
  target : Value,
  method_name : String,
  other : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value?, RuntimeError] {
  if !(target is Value::Instance(_)) {
    return Ok(None)
  }
  let candidate = match
    get_attr_from_value(target, method_name, globals, builtins, io) {
    Ok(v) => v
    Err(err) =>
      match err.kind {
        RuntimeErrorKind::Attribute => return Ok(None)
        _ => return Err(err)
      }
  }
  if candidate is Value::None {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        method_name + " is not callable".to_string(),
      ),
    )
  }
  if is_intrinsic_default_compare(candidate, method_name) {
    return Ok(None)
  }
  match call_callable_with_env(candidate, [other], [], globals, builtins, io) {
    Ok(v) => Ok(Some(v))
    Err(err) => Err(err)
  }
}

///|
fn is_notimplemented(value : Value) -> Bool {
  match value {
    Value::Instance(inst) => inst.class.name == "NotImplementedType"
    _ => false
  }
}

///|
fn is_strict_subclass(left : Value, right : Value) -> Bool {
  match (left, right) {
    (Value::Instance(left_inst), Value::Instance(right_inst)) =>
      if left_inst.class.name == right_inst.class.name {
        false
      } else {
        match class_mro(right_inst.class) {
          Ok(mro) => {
            for cls in mro {
              if cls.name == left_inst.class.name {
                return true
              }
            }
            false
          }
          Err(_) => false
        }
      }
    _ => false
  }
}

///|
fn eq_bool(
  left : Value,
  right : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  fn as_list(value : Value) -> Array[Value]? {
    match value {
      Value::List(values) => Some(values)
      Value::Instance(inst) =>
        match get_named_value(inst.dict, list_storage_name) {
          Some(Value::List(values)) => Some(values)
          _ => None
        }
      _ => None
    }
  }

  fn as_tuple(value : Value) -> Array[Value]? {
    match value {
      Value::Tuple(values) => Some(values)
      Value::Instance(inst) =>
        match get_named_value(inst.dict, tuple_storage_name) {
          Some(Value::Tuple(values)) => Some(values)
          _ => None
        }
      _ => None
    }
  }

  match (as_list(left), as_list(right)) {
    (Some(xs), Some(ys)) =>
      if xs.length() != ys.length() {
        return Ok(false)
      } else {
        for i = 0; i < xs.length(); i = i + 1 {
          match eq_bool(xs[i], ys[i], globals, builtins, io) {
            Ok(true) => ()
            Ok(false) => return Ok(false)
            Err(err) => return Err(err)
          }
        }
        return Ok(true)
      }
    _ => ()
  }
  match (as_tuple(left), as_tuple(right)) {
    (Some(xs), Some(ys)) =>
      if xs.length() != ys.length() {
        return Ok(false)
      } else {
        for i = 0; i < xs.length(); i = i + 1 {
          match eq_bool(xs[i], ys[i], globals, builtins, io) {
            Ok(true) => ()
            Ok(false) => return Ok(false)
            Err(err) => return Err(err)
          }
        }
        return Ok(true)
      }
    _ => ()
  }
  let swapped = is_strict_subclass(left, right)
  let first = if swapped { right } else { left }
  let second = if swapped { left } else { right }
  match call_compare_method(first, "__eq__", second, globals, builtins, io) {
    Ok(Some(value)) =>
      if is_notimplemented(value) {
        match
          call_compare_method(second, "__eq__", first, globals, builtins, io) {
          Ok(Some(value2)) =>
            if is_notimplemented(value2) {
              Ok(eq_value(left, right))
            } else {
              truthy_from_value_with_env(value2, globals, builtins, io)
            }
          Ok(None) => Ok(eq_value(left, right))
          Err(err) => Err(err)
        }
      } else {
        truthy_from_value_with_env(value, globals, builtins, io)
      }
    Ok(None) =>
      match
        call_compare_method(second, "__eq__", first, globals, builtins, io) {
        Ok(Some(value2)) =>
          if is_notimplemented(value2) {
            Ok(eq_value(left, right))
          } else {
            truthy_from_value_with_env(value2, globals, builtins, io)
          }
        Ok(None) => Ok(eq_value(left, right))
        Err(err) => Err(err)
      }
    Err(err) => Err(err)
  }
}

///|
fn ne_bool(
  left : Value,
  right : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  if is_strict_subclass(left, right) {
    match call_compare_method(right, "__ne__", left, globals, builtins, io) {
      Ok(Some(value)) =>
        if is_notimplemented(value) {
          match
            call_compare_method(left, "__ne__", right, globals, builtins, io) {
            Ok(Some(value2)) =>
              if is_notimplemented(value2) {
                match eq_bool(left, right, globals, builtins, io) {
                  Ok(v) => Ok(!v)
                  Err(err) => Err(err)
                }
              } else {
                truthy_from_value_with_env(value2, globals, builtins, io)
              }
            Ok(None) =>
              match eq_bool(left, right, globals, builtins, io) {
                Ok(v) => Ok(!v)
                Err(err) => Err(err)
              }
            Err(err) => Err(err)
          }
        } else {
          truthy_from_value_with_env(value, globals, builtins, io)
        }
      Ok(None) =>
        match
          call_compare_method(left, "__ne__", right, globals, builtins, io) {
          Ok(Some(value2)) =>
            if is_notimplemented(value2) {
              match eq_bool(left, right, globals, builtins, io) {
                Ok(v) => Ok(!v)
                Err(err) => Err(err)
              }
            } else {
              truthy_from_value_with_env(value2, globals, builtins, io)
            }
          Ok(None) =>
            match eq_bool(left, right, globals, builtins, io) {
              Ok(v) => Ok(!v)
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      Err(err) => Err(err)
    }
  } else {
    match call_compare_method(left, "__ne__", right, globals, builtins, io) {
      Ok(Some(value)) =>
        if is_notimplemented(value) {
          match eq_bool(left, right, globals, builtins, io) {
            Ok(v) => Ok(!v)
            Err(err) => Err(err)
          }
        } else {
          truthy_from_value_with_env(value, globals, builtins, io)
        }
      Ok(None) =>
        match eq_bool(left, right, globals, builtins, io) {
          Ok(v) => Ok(!v)
          Err(err) => Err(err)
        }
      Err(err) => Err(err)
    }
  }
}

///|
fn ordering_bool(
  left : Value,
  right : Value,
  method_name : String,
  reverse_method_name : String,
  op_symbol : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  fn unsupported(
    op_symbol : String,
    left : Value,
    right : Value,
  ) -> RuntimeError {
    make_runtime_error(
      RuntimeErrorKind::Type,
      "'" +
      op_symbol +
      "' not supported between instances of '" +
      type_name_from_value(left) +
      "' and '" +
      type_name_from_value(right) +
      "'",
    )
  }

  if is_strict_subclass(left, right) {
    match
      call_compare_method(
        right, reverse_method_name, left, globals, builtins, io,
      ) {
      Ok(Some(value)) =>
        if is_notimplemented(value) {
          match
            call_compare_method(left, method_name, right, globals, builtins, io) {
            Ok(Some(value2)) =>
              if is_notimplemented(value2) {
                Err(unsupported(op_symbol, left, right))
              } else {
                truthy_from_value_with_env(value2, globals, builtins, io)
              }
            Ok(None) => Err(unsupported(op_symbol, left, right))
            Err(err) => Err(err)
          }
        } else {
          truthy_from_value_with_env(value, globals, builtins, io)
        }
      Ok(None) =>
        match
          call_compare_method(left, method_name, right, globals, builtins, io) {
          Ok(Some(value2)) =>
            if is_notimplemented(value2) {
              Err(unsupported(op_symbol, left, right))
            } else {
              truthy_from_value_with_env(value2, globals, builtins, io)
            }
          Ok(None) => Err(unsupported(op_symbol, left, right))
          Err(err) => Err(err)
        }
      Err(err) => Err(err)
    }
  } else {
    match call_compare_method(left, method_name, right, globals, builtins, io) {
      Ok(Some(value)) =>
        if is_notimplemented(value) {
          match
            call_compare_method(
              right, reverse_method_name, left, globals, builtins, io,
            ) {
            Ok(Some(value2)) =>
              if is_notimplemented(value2) {
                Err(unsupported(op_symbol, left, right))
              } else {
                truthy_from_value_with_env(value2, globals, builtins, io)
              }
            Ok(None) => Err(unsupported(op_symbol, left, right))
            Err(err) => Err(err)
          }
        } else {
          truthy_from_value_with_env(value, globals, builtins, io)
        }
      Ok(None) =>
        match
          call_compare_method(
            right, reverse_method_name, left, globals, builtins, io,
          ) {
          Ok(Some(value2)) =>
            if is_notimplemented(value2) {
              Err(unsupported(op_symbol, left, right))
            } else {
              truthy_from_value_with_env(value2, globals, builtins, io)
            }
          Ok(None) => Err(unsupported(op_symbol, left, right))
          Err(err) => Err(err)
        }
      Err(err) => Err(err)
    }
  }
}

///|
fn in_bool(
  needle : Value,
  haystack : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  match haystack {
    Value::List(values) | Value::Tuple(values) => {
      let mut found = false
      for item in values {
        if is_value_identity(item, needle) || eq_value(item, needle) {
          found = true
          break
        }
      }
      Ok(found)
    }
    Value::Set(values) =>
      match set_find_index(values, needle) {
        Ok(index) => Ok(index is Some(_))
        Err(err) => Err(err)
      }
    Value::Bytes(bytes) | Value::ByteArray(bytes) | Value::MemoryView(bytes) =>
      Ok(bytes_contains(bytes, needle))
    Value::Dict(pairs) =>
      match dict_find_index(pairs, needle) {
        Ok(index) => Ok(index is Some(_))
        Err(err) => Err(err)
      }
    Value::Str(text) =>
      match needle {
        Value::Str(needle) => Ok(text.contains(needle))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "'in <string>' requires string as left operand, not " +
              type_name_from_value(needle),
            ),
          )
      }
    _ =>
      match haystack {
        Value::Instance(_) =>
          match
            get_attr_from_value(haystack, "__contains__", globals, builtins, io) {
            Ok(contains_method) => {
              if contains_method is Value::None {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "argument of type '" +
                    type_name_from_value(haystack) +
                    "' is not iterable",
                  ),
                )
              }
              let result = match
                call_callable_with_env(
                  contains_method,
                  [needle],
                  [],
                  globals,
                  builtins,
                  io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(bool_from_value(result))
            }
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute => {
                  // Fall back to iteration.
                  let iterator = match
                    iter_value_to_iterator(haystack, globals, builtins, io) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                  let mut found = false
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        if is_value_identity(item, needle) ||
                          eq_value(item, needle) {
                          found = true
                          break
                        }
                      Err(e) =>
                        if e.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(e)
                        }
                    }
                  }
                  Ok(found)
                }
                _ => Err(err)
              }
          }
        _ => {
          let iterator = match
            iter_value_to_iterator(haystack, globals, builtins, io) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let mut found = false
          while true {
            match iterator_next(iterator, None, globals, builtins, io) {
              Ok(item) =>
                if is_value_identity(item, needle) || eq_value(item, needle) {
                  found = true
                  break
                }
              Err(e) =>
                if e.exc_type == "StopIteration" {
                  break
                } else {
                  return Err(e)
                }
            }
          }
          Ok(found)
        }
      }
  }
}

///|
fn compare_values_with_env(
  op : CompareOp,
  left : Value,
  right : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  fn tuple_items_for_compare(v : Value) -> Array[Value]? {
    match v {
      Value::Tuple(values) => Some(values)
      Value::Instance(inst) =>
        match get_named_value(inst.dict, tuple_storage_name) {
          Some(Value::Tuple(values)) => Some(values)
          _ => None
        }
      _ => None
    }
  }

  match op {
    CompareOp::Eq => eq_bool(left, right, globals, builtins, io)
    CompareOp::NotEq => ne_bool(left, right, globals, builtins, io)
    CompareOp::Lt =>
      match (tuple_items_for_compare(left), tuple_items_for_compare(right)) {
        (Some(left), Some(right)) =>
          match compare_sequence_values(left, right, globals, builtins, io) {
            Ok(cmp) => Ok(cmp < 0)
            Err(err) => Err(err)
          }
        _ =>
          match (left, right) {
            (Value::Tuple(left), Value::Tuple(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp < 0)
                Err(err) => Err(err)
              }
            (Value::List(left), Value::List(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp < 0)
                Err(err) => Err(err)
              }
            (Value::Set(left), Value::Set(right)) => {
              let mut ok = true
              for item in left {
                let hit = match set_find_index(right, item) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if hit is None {
                  ok = false
                  break
                }
              }
              Ok(ok && left.length() < right.length())
            }
            (Value::Int(left), Value::Int(right)) => Ok(left < right)
            (Value::Bool(left), Value::Bool(right)) =>
              Ok((if left { 1N } else { 0N }) < (if right { 1N } else { 0N }))
            (Value::Bool(left), Value::Int(right)) =>
              Ok((if left { 1N } else { 0N }) < right)
            (Value::Int(left), Value::Bool(right)) =>
              Ok(left < (if right { 1N } else { 0N }))
            (Value::Float(left), Value::Float(right)) => Ok(left < right)
            (Value::Float(left), Value::Int(right)) =>
              match bigint_to_double_checked(right) {
                Ok(v) => Ok(left < v)
                Err(err) => Err(err)
              }
            (Value::Int(left), Value::Float(right)) =>
              match bigint_to_double_checked(left) {
                Ok(v) => Ok(v < right)
                Err(err) => Err(err)
              }
            (Value::Float(left), Value::Bool(right)) =>
              Ok(left < (if right { 1.0 } else { 0.0 }))
            (Value::Bool(left), Value::Float(right)) =>
              Ok((if left { 1.0 } else { 0.0 }) < right)
            (Value::Str(left), Value::Str(right)) =>
              Ok(cmp_string_for_sorted(left, right) < 0)
            (
              Value::Bytes(left)
              | Value::ByteArray(left)
              | Value::MemoryView(left),
              Value::Bytes(right)
              | Value::ByteArray(right)
              | Value::MemoryView(right),
            ) => Ok(compare_bytes_like(left, right) < 0)
            _ =>
              ordering_bool(
                left, right, "__lt__", "__gt__", "<", globals, builtins, io,
              )
          }
      }
    CompareOp::Lte =>
      match (tuple_items_for_compare(left), tuple_items_for_compare(right)) {
        (Some(left), Some(right)) =>
          match compare_sequence_values(left, right, globals, builtins, io) {
            Ok(cmp) => Ok(cmp <= 0)
            Err(err) => Err(err)
          }
        _ =>
          match (left, right) {
            (Value::Tuple(left), Value::Tuple(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp <= 0)
                Err(err) => Err(err)
              }
            (Value::List(left), Value::List(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp <= 0)
                Err(err) => Err(err)
              }
            (Value::Set(left), Value::Set(right)) => {
              let mut ok = true
              for item in left {
                let hit = match set_find_index(right, item) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if hit is None {
                  ok = false
                  break
                }
              }
              Ok(ok)
            }
            (Value::Int(left), Value::Int(right)) => Ok(left <= right)
            (Value::Bool(left), Value::Bool(right)) =>
              Ok((if left { 1N } else { 0N }) <= (if right { 1N } else { 0N }))
            (Value::Bool(left), Value::Int(right)) =>
              Ok((if left { 1N } else { 0N }) <= right)
            (Value::Int(left), Value::Bool(right)) =>
              Ok(left <= (if right { 1N } else { 0N }))
            (Value::Float(left), Value::Float(right)) => Ok(left <= right)
            (Value::Float(left), Value::Int(right)) =>
              match bigint_to_double_checked(right) {
                Ok(v) => Ok(left <= v)
                Err(err) => Err(err)
              }
            (Value::Int(left), Value::Float(right)) =>
              match bigint_to_double_checked(left) {
                Ok(v) => Ok(v <= right)
                Err(err) => Err(err)
              }
            (Value::Float(left), Value::Bool(right)) =>
              Ok(left <= (if right { 1.0 } else { 0.0 }))
            (Value::Bool(left), Value::Float(right)) =>
              Ok((if left { 1.0 } else { 0.0 }) <= right)
            (Value::Str(left), Value::Str(right)) =>
              Ok(cmp_string_for_sorted(left, right) <= 0)
            (
              Value::Bytes(left)
              | Value::ByteArray(left)
              | Value::MemoryView(left),
              Value::Bytes(right)
              | Value::ByteArray(right)
              | Value::MemoryView(right),
            ) => Ok(compare_bytes_like(left, right) <= 0)
            _ =>
              ordering_bool(
                left, right, "__le__", "__ge__", "<=", globals, builtins, io,
              )
          }
      }
    CompareOp::Gt =>
      match (tuple_items_for_compare(left), tuple_items_for_compare(right)) {
        (Some(left), Some(right)) =>
          match compare_sequence_values(left, right, globals, builtins, io) {
            Ok(cmp) => Ok(cmp > 0)
            Err(err) => Err(err)
          }
        _ =>
          match (left, right) {
            (Value::Tuple(left), Value::Tuple(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp > 0)
                Err(err) => Err(err)
              }
            (Value::List(left), Value::List(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp > 0)
                Err(err) => Err(err)
              }
            (Value::Set(left), Value::Set(right)) => {
              let mut ok = true
              for item in right {
                let hit = match set_find_index(left, item) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if hit is None {
                  ok = false
                  break
                }
              }
              Ok(ok && left.length() > right.length())
            }
            (Value::Int(left), Value::Int(right)) => Ok(left > right)
            (Value::Bool(left), Value::Bool(right)) =>
              Ok((if left { 1N } else { 0N }) > (if right { 1N } else { 0N }))
            (Value::Bool(left), Value::Int(right)) =>
              Ok((if left { 1N } else { 0N }) > right)
            (Value::Int(left), Value::Bool(right)) =>
              Ok(left > (if right { 1N } else { 0N }))
            (Value::Float(left), Value::Float(right)) => Ok(left > right)
            (Value::Float(left), Value::Int(right)) =>
              match bigint_to_double_checked(right) {
                Ok(v) => Ok(left > v)
                Err(err) => Err(err)
              }
            (Value::Int(left), Value::Float(right)) =>
              match bigint_to_double_checked(left) {
                Ok(v) => Ok(v > right)
                Err(err) => Err(err)
              }
            (Value::Float(left), Value::Bool(right)) =>
              Ok(left > (if right { 1.0 } else { 0.0 }))
            (Value::Bool(left), Value::Float(right)) =>
              Ok((if left { 1.0 } else { 0.0 }) > right)
            (Value::Str(left), Value::Str(right)) =>
              Ok(cmp_string_for_sorted(left, right) > 0)
            (
              Value::Bytes(left)
              | Value::ByteArray(left)
              | Value::MemoryView(left),
              Value::Bytes(right)
              | Value::ByteArray(right)
              | Value::MemoryView(right),
            ) => Ok(compare_bytes_like(left, right) > 0)
            _ =>
              ordering_bool(
                left, right, "__gt__", "__lt__", ">", globals, builtins, io,
              )
          }
      }
    CompareOp::Gte =>
      match (tuple_items_for_compare(left), tuple_items_for_compare(right)) {
        (Some(left), Some(right)) =>
          match compare_sequence_values(left, right, globals, builtins, io) {
            Ok(cmp) => Ok(cmp >= 0)
            Err(err) => Err(err)
          }
        _ =>
          match (left, right) {
            (Value::Tuple(left), Value::Tuple(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp >= 0)
                Err(err) => Err(err)
              }
            (Value::List(left), Value::List(right)) =>
              match
                compare_sequence_values(left, right, globals, builtins, io) {
                Ok(cmp) => Ok(cmp >= 0)
                Err(err) => Err(err)
              }
            (Value::Set(left), Value::Set(right)) => {
              let mut ok = true
              for item in right {
                let hit = match set_find_index(left, item) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if hit is None {
                  ok = false
                  break
                }
              }
              Ok(ok)
            }
            (Value::Int(left), Value::Int(right)) => Ok(left >= right)
            (Value::Bool(left), Value::Bool(right)) =>
              Ok((if left { 1N } else { 0N }) >= (if right { 1N } else { 0N }))
            (Value::Bool(left), Value::Int(right)) =>
              Ok((if left { 1N } else { 0N }) >= right)
            (Value::Int(left), Value::Bool(right)) =>
              Ok(left >= (if right { 1N } else { 0N }))
            (Value::Float(left), Value::Float(right)) => Ok(left >= right)
            (Value::Float(left), Value::Int(right)) =>
              match bigint_to_double_checked(right) {
                Ok(v) => Ok(left >= v)
                Err(err) => Err(err)
              }
            (Value::Int(left), Value::Float(right)) =>
              match bigint_to_double_checked(left) {
                Ok(v) => Ok(v >= right)
                Err(err) => Err(err)
              }
            (Value::Float(left), Value::Bool(right)) =>
              Ok(left >= (if right { 1.0 } else { 0.0 }))
            (Value::Bool(left), Value::Float(right)) =>
              Ok((if left { 1.0 } else { 0.0 }) >= right)
            (Value::Str(left), Value::Str(right)) =>
              Ok(cmp_string_for_sorted(left, right) >= 0)
            (
              Value::Bytes(left)
              | Value::ByteArray(left)
              | Value::MemoryView(left),
              Value::Bytes(right)
              | Value::ByteArray(right)
              | Value::MemoryView(right),
            ) => Ok(compare_bytes_like(left, right) >= 0)
            _ =>
              ordering_bool(
                left, right, "__ge__", "__le__", ">=", globals, builtins, io,
              )
          }
      }
    CompareOp::Is => Ok(is_value_identity(left, right))
    CompareOp::IsNot => Ok(!is_value_identity(left, right))
    CompareOp::In => in_bool(left, right, globals, builtins, io)
    CompareOp::NotIn =>
      match in_bool(left, right, globals, builtins, io) {
        Ok(v) => Ok(!v)
        Err(err) => Err(err)
      }
  }
}
