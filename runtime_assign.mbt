///|
/// Assignment and deletion for statement targets.

///|
fn replace_array_values(values : Array[Value], next : Array[Value]) -> Unit {
  let mut i = values.length()
  while i > 0 {
    i = i - 1
    let _ = values.remove(i)

  }
  for item in next {
    values.push(item)
  }
}

///|
fn collect_unpack_items(
  assigned : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Value], RuntimeError] {
  match assigned {
    Value::Tuple(values) => Ok(values)
    Value::List(values) => Ok(values)
    _ => {
      let iterator = match
        iter_value_to_iterator(assigned, globals, builtins, io) {
        Ok(value) => value
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Type =>
              if err.message == "object is not iterable" {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "cannot unpack non-iterable".to_string(),
                  ),
                )
              } else {
                return Err(err)
              }
            _ => return Err(err)
          }
      }
      let items : Array[Value] = []
      while true {
        match iterator_next(iterator, None, globals, builtins, io) {
          Ok(value) => items.push(value)
          Err(err) =>
            if err.exc_type == "StopIteration" {
              break
            } else {
              return Err(err)
            }
        }
      }
      Ok(items)
    }
  }
}

///|
fn assign_target_with_env(
  target : Target,
  assigned : Value,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  match target {
    Target::Name(name) => {
      set_scoped_value(locals, globals, name, assigned)
      Ok(())
    }
    Target::Starred(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: starred assignment target must be in a list or tuple".to_string(),
        ),
      )
    Target::Tuple(targets) | Target::List(targets) => {
      let items = match collect_unpack_items(assigned, globals, builtins, io) {
        Ok(values) => values
        Err(err) => return Err(err)
      }
      // Extended iterable unpacking (PEP 3132): a, *rest, b = iterable
      let mut star_index : Int? = None
      for i = 0; i < targets.length(); i = i + 1 {
        match targets[i] {
          Target::Starred(_) =>
            match star_index {
              Some(_) =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "SyntaxError: multiple starred expressions in assignment".to_string(),
                  ),
                )
              None => star_index = Some(i)
            }
          _ => ()
        }
      }
      match star_index {
        None => {
          if items.length() != targets.length() {
            let expected = targets.length()
            if items.length() < expected {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "ValueError: not enough values to unpack (expected " +
                  expected.to_string() +
                  ")",
                ),
              )
            }
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: too many values to unpack (expected " +
                expected.to_string() +
                ")",
              ),
            )
          }
          for i = 0; i < targets.length(); i = i + 1 {
            let _ = match
              assign_target_with_env(
                targets[i],
                items[i],
                locals,
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          Ok(())
        }
        Some(k) => {
          let left_count = k
          let right_count = targets.length() - k - 1
          let expected_min = targets.length() - 1
          if items.length() < expected_min {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: not enough values to unpack (expected at least " +
                expected_min.to_string() +
                ")",
              ),
            )
          }
          for i = 0; i < left_count; i = i + 1 {
            let _ = match
              assign_target_with_env(
                targets[i],
                items[i],
                locals,
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          for i = 0; i < right_count; i = i + 1 {
            let src = items.length() - right_count + i
            let dst = k + 1 + i
            let _ = match
              assign_target_with_env(
                targets[dst],
                items[src],
                locals,
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          let mid : Array[Value] = []
          let end_mid = items.length() - right_count
          for i = left_count; i < end_mid; i = i + 1 {
            mid.push(items[i])
          }
          match targets[k] {
            Target::Starred(inner) =>
              assign_target_with_env(
                inner,
                Value::List(mid),
                locals,
                globals,
                builtins,
                io,
              )
            _ => Ok(()) // unreachable
          }
        }
      }
    }
    Target::Attribute(value~, attr~) => {
      let target_value = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match
        set_attr_on_value(target_value, attr, assigned, globals, builtins, io) {
        Ok(_) => Ok(())
        Err(err) => Err(err)
      }
    }
    Target::Subscript(value~, index~) => {
      let container = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      fn assign_list_subscript(
        values : Array[Value],
      ) -> Result[Unit, RuntimeError] {
        match index {
          Expr::Slice(start~, end~, step~) => {
            let start_value = match start {
              Some(expr) =>
                match eval_expr_with_env(expr, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
              None => Value::None
            }
            let end_value = match end {
              Some(expr) =>
                match eval_expr_with_env(expr, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
              None => Value::None
            }
            let step_value = match step {
              Some(expr) =>
                match eval_expr_with_env(expr, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
              None => Value::None
            }
            let new_items = match iterable_values(assigned) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let (start, end, step) = match
              slice_params_from_values(
                values.length(),
                start_value,
                end_value,
                step_value,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            if step == 1 {
              let merged : Array[Value] = []
              for i = 0; i < start; i = i + 1 {
                merged.push(values[i])
              }
              for item in new_items {
                merged.push(item)
              }
              for i = end; i < values.length(); i = i + 1 {
                merged.push(values[i])
              }
              replace_array_values(values, merged)
              Ok(())
            } else {
              let indices = match
                slice_indices_from_values(
                  values.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              if new_items.length() != indices.length() {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: attempt to assign sequence of size " +
                    new_items.length().to_string() +
                    " to extended slice of size " +
                    indices.length().to_string(),
                  ),
                )
              }
              for i = 0; i < indices.length(); i = i + 1 {
                values[indices[i]] = new_items[i]
              }
              Ok(())
            }
          }
          _ => {
            let index_value = match
              eval_expr_with_env(index, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let idx = match index_from_value(index_value, 0) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let norm = normalize_index(idx, values.length())
            if norm < 0 || norm >= values.length() {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Index,
                  "index out of range".to_string(),
                ),
              )
            }
            values[norm] = assigned
            Ok(())
          }
        }
      }

      match container {
        Value::List(values) => assign_list_subscript(values)
        Value::Instance(inst) =>
          match get_named_value(inst.dict, list_storage_name) {
            Some(Value::List(values)) => assign_list_subscript(values)
            _ => {
              let index_arg = match index {
                Expr::Slice(start~, end~, step~) => {
                  let start_value = match start {
                    Some(expr) =>
                      match
                        eval_expr_with_env(expr, locals, globals, builtins, io) {
                        Ok(value) => value
                        Err(err) => return Err(err)
                      }
                    None => Value::None
                  }
                  let end_value = match end {
                    Some(expr) =>
                      match
                        eval_expr_with_env(expr, locals, globals, builtins, io) {
                        Ok(value) => value
                        Err(err) => return Err(err)
                      }
                    None => Value::None
                  }
                  let step_value = match step {
                    Some(expr) =>
                      match
                        eval_expr_with_env(expr, locals, globals, builtins, io) {
                        Ok(value) => value
                        Err(err) => return Err(err)
                      }
                    None => Value::None
                  }
                  let dict : Array[(String, Value)] = []
                  dict.push(("start", start_value))
                  dict.push(("stop", end_value))
                  dict.push(("step", step_value))
                  let klass = builtin_class_from_name("slice", builtins)
                  Value::Instance(InstanceValue::{ class: klass, dict })
                }
                _ =>
                  match
                    eval_expr_with_env(index, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
              }
              match
                get_attr_from_value(
                  container, "__setitem__", globals, builtins, io,
                ) {
                Ok(setitem) => {
                  let _ = match
                    call_callable_with_env(
                      setitem,
                      [index_arg, assigned],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  Ok(())
                }
                Err(err) =>
                  match err.kind {
                    RuntimeErrorKind::Attribute =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "object does not support item assignment".to_string(),
                        ),
                      )
                    _ => Err(err)
                  }
              }
            }
          }
        Value::ByteArray(_) => {
          let index_arg = match index {
            Expr::Slice(start~, end~, step~) => {
              let start_value = match start {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let end_value = match end {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let step_value = match step {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let dict : Array[(String, Value)] = []
              dict.push(("start", start_value))
              dict.push(("stop", end_value))
              dict.push(("step", step_value))
              let klass = builtin_class_from_name("slice", builtins)
              Value::Instance(InstanceValue::{ class: klass, dict })
            }
            _ =>
              match eval_expr_with_env(index, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
          }
          match
            get_attr_from_value(container, "__setitem__", globals, builtins, io) {
            Ok(setitem) => {
              let _ = match
                call_callable_with_env(
                  setitem,
                  [index_arg, assigned],
                  [],
                  globals,
                  builtins,
                  io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(())
            }
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "object does not support item assignment".to_string(),
                    ),
                  )
                _ => Err(err)
              }
          }
        }
        Value::Dict(pairs) => {
          let index_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let _ = match dict_set_item(pairs, index_value, assigned) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(())
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "object does not support item assignment".to_string(),
            ),
          )
      }
    }
  }
}

///|
fn delete_target_with_env(
  target : Target,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  match target {
    Target::Name(name) => {
      if scope_name_is_nonlocal(name) {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: can't delete nonlocal".to_string(),
          ),
        )
      }
      match delete_scoped_value(locals, globals, name) {
        Ok(true) => Ok(())
        Ok(false) =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Name,
              "name '" + name + "' is not defined",
            ),
          )
        Err(err) => Err(err)
      }
    }
    Target::Starred(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: can't use starred expression here".to_string(),
        ),
      )
    Target::Tuple(items) | Target::List(items) => {
      for item in items {
        let _ = match
          delete_target_with_env(item, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }

      }
      Ok(())
    }
    Target::Attribute(value~, attr~) => {
      let target_value = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      delete_attr_on_value(target_value, attr, globals, builtins, io)
    }
    Target::Subscript(value~, index~) => {
      let container = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match container {
        Value::List(values) =>
          match index {
            Expr::Slice(start~, end~, step~) => {
              let start_value = match start {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let end_value = match end {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let step_value = match step {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let indices = match
                slice_indices_from_values(
                  values.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              if indices.length() == 0 {
                return Ok(())
              }
              let remove_mask : Array[Bool] = []
              for i = 0; i < values.length(); i = i + 1 {
                remove_mask.push(false)
              }
              for idx in indices {
                if idx >= 0 && idx < remove_mask.length() {
                  remove_mask[idx] = true
                }
              }
              let next : Array[Value] = []
              for i = 0; i < values.length(); i = i + 1 {
                if !remove_mask[i] {
                  next.push(values[i])
                }
              }
              replace_array_values(values, next)
              Ok(())
            }
            _ => {
              let index_value = match
                eval_expr_with_env(index, locals, globals, builtins, io) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              let idx = match index_from_value(index_value, 0) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              let norm = normalize_index(idx, values.length())
              if norm < 0 || norm >= values.length() {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              }
              let _ = values.remove(norm)
              Ok(())
            }
          }
        Value::Instance(_) | Value::ByteArray(_) => {
          let index_arg = match index {
            Expr::Slice(start~, end~, step~) => {
              let start_value = match start {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let end_value = match end {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let step_value = match step {
                Some(expr) =>
                  match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                None => Value::None
              }
              let dict : Array[(String, Value)] = []
              dict.push(("start", start_value))
              dict.push(("stop", end_value))
              dict.push(("step", step_value))
              let klass = builtin_class_from_name("slice", builtins)
              Value::Instance(InstanceValue::{ class: klass, dict })
            }
            _ =>
              match eval_expr_with_env(index, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
          }
          match
            get_attr_from_value(container, "__delitem__", globals, builtins, io) {
            Ok(delitem) => {
              let _ = match
                call_callable_with_env(
                  delitem,
                  [index_arg],
                  [],
                  globals,
                  builtins,
                  io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(())
            }
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "object does not support item deletion".to_string(),
                    ),
                  )
                _ => Err(err)
              }
          }
        }
        Value::Dict(pairs) => {
          let index_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let removed = match dict_delete_key(pairs, index_value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if removed {
            Ok(())
          } else {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Key,
                "key not found".to_string(),
              ),
            )
          }
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "object does not support item deletion".to_string(),
            ),
          )
      }
    }
  }
}
