///|
/// Assignment and deletion for statement targets.

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
      set_global_value(globals, name, assigned)
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
      match set_attr_on_value(target_value, attr, assigned) {
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
      let index_value = match
        eval_expr_with_env(index, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match container {
        Value::List(values) => {
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
        Value::Dict(pairs) => {
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
      let mut found = false
      for idx = 0; idx < globals.length(); idx = idx + 1 {
        if globals[idx].0 == name {
          let _ = globals.remove(idx)
          found = true
          break
        }
      }
      if !found {
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
      match target_value {
        Value::Instance(inst) => {
          for i = 0; i < inst.dict.length(); i = i + 1 {
            if inst.dict[i].0 == attr {
              let _ = inst.dict.remove(i)
              return Ok(())
            }
          }
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "attribute not found".to_string(),
            ),
          )
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "attribute not supported".to_string(),
            ),
          )
      }
    }
    Target::Subscript(value~, index~) => {
      let container = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let index_value = match
        eval_expr_with_env(index, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match container {
        Value::List(values) => {
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
        Value::Dict(pairs) => {
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
