///|
/// Iterable and comprehension evaluation helpers.

///|
fn iterable_values(value : Value) -> Result[Array[Value], RuntimeError] {
  match value {
    Value::List(values) => Ok(values)
    Value::Tuple(values) => Ok(values)
    Value::Set(values) => Ok(values)
    Value::Dict(values) => {
      let keys : Array[Value] = []
      for pair in values {
        keys.push(pair.0)
      }
      Ok(keys)
    }
    Value::Str(text) => {
      let items : Array[Value] = []
      for ch in text.to_array() {
        items.push(Value::Str(char_to_string(ch)))
      }
      Ok(items)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object is not iterable".to_string(),
        ),
      )
  }
}

///|
fn eval_comp_filters(
  filters : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  for filter in filters {
    let cond = match eval_expr_with_env(filter, locals, globals, builtins, io) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if !bool_from_value(cond) {
      return Ok(false)
    }
  }
  Ok(true)
}

///|
fn bind_comp_targets(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  targets : Array[String],
  item : Value,
) -> Result[Unit, RuntimeError] {
  if targets.length() == 1 {
    if targets[0] != "_" {
      set_local_value(locals, targets[0], item)
      set_global_value(globals, targets[0], item)
    }
    return Ok(())
  }
  if targets.length() == 2 {
    match item {
      Value::Tuple(values) =>
        if values.length() != 2 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "cannot unpack".to_string(),
            ),
          )
        } else {
          if targets[0] != "_" {
            set_local_value(locals, targets[0], values[0])
            set_global_value(globals, targets[0], values[0])
          }
          if targets[1] != "_" {
            set_local_value(locals, targets[1], values[1])
            set_global_value(globals, targets[1], values[1])
          }
          Ok(())
        }
      Value::List(values) =>
        if values.length() != 2 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "cannot unpack".to_string(),
            ),
          )
        } else {
          if targets[0] != "_" {
            set_local_value(locals, targets[0], values[0])
            set_global_value(globals, targets[0], values[0])
          }
          if targets[1] != "_" {
            set_local_value(locals, targets[1], values[1])
            set_global_value(globals, targets[1], values[1])
          }
          Ok(())
        }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "cannot unpack".to_string(),
          ),
        )
    }
  } else {
    Err(make_runtime_error(RuntimeErrorKind::Type, "cannot unpack".to_string()))
  }
}

///|
fn eval_list_comp_walk(
  index : Int,
  elt : Expr,
  clauses : Array[(Array[String], Expr)],
  filters : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  results : Array[Value],
) -> Result[Unit, RuntimeError] {
  if index >= clauses.length() {
    let ok = match eval_comp_filters(filters, locals, globals, builtins, io) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if ok {
      let value = match eval_expr_with_env(elt, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      results.push(value)
    }
    return Ok(())
  }
  let clause = clauses[index]
  let iter_value = match
    eval_expr_with_env(clause.1, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let items = match iterable_values(iter_value) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for item in items {
    let _ = match bind_comp_targets(locals, globals, clause.0, item) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    let _ = match
      eval_list_comp_walk(
        index + 1,
        elt,
        clauses,
        filters,
        locals,
        globals,
        builtins,
        io,
        results,
      ) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }

  }
  Ok(())
}

///|
fn eval_dict_comp_walk(
  index : Int,
  key : Expr,
  value : Expr,
  clauses : Array[(Array[String], Expr)],
  filters : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  results : Array[(Value, Value)],
) -> Result[Unit, RuntimeError] {
  if index >= clauses.length() {
    let ok = match eval_comp_filters(filters, locals, globals, builtins, io) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if ok {
      let k = match eval_expr_with_env(key, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let v = match eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      results.push((k, v))
    }
    return Ok(())
  }
  let clause = clauses[index]
  let iter_value = match
    eval_expr_with_env(clause.1, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let items = match iterable_values(iter_value) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for item in items {
    let _ = match bind_comp_targets(locals, globals, clause.0, item) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    let _ = match
      eval_dict_comp_walk(
        index + 1,
        key,
        value,
        clauses,
        filters,
        locals,
        globals,
        builtins,
        io,
        results,
      ) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }

  }
  Ok(())
}
