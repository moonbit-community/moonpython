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
    Target::Tuple(targets) | Target::List(targets) => {
      let items = match assigned {
        Value::Tuple(values) => values
        Value::List(values) => values
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "cannot unpack non-iterable".to_string(),
            ),
          )
      }
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
        Value::Dict(pairs) => {
          let index_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let mut found = false
          for i = 0; i < pairs.length(); i = i + 1 {
            if eq_value(pairs[i].0, index_value) {
              pairs[i] = (pairs[i].0, assigned)
              found = true
              break
            }
          }
          if !found {
            pairs.push((index_value, assigned))
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
      if !delete_scoped_value(locals, globals, name) {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
      }
      Ok(())
    }
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
        Value::Dict(pairs) => {
          let index_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          for i = 0; i < pairs.length(); i = i + 1 {
            if eq_value(pairs[i].0, index_value) {
              let _ = pairs.remove(i)
              return Ok(())
            }
          }
          Err(
            make_runtime_error(
              RuntimeErrorKind::Key,
              "key not found".to_string(),
            ),
          )
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
