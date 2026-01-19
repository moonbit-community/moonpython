///|
/// Iterable and comprehension evaluation helpers.

///|
fn lookup_iterable_field(
  dict : Array[(String, Value)],
  name : String,
) -> Value? {
  for pair in dict {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_iterable_field(
  dict : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < dict.length(); i = i + 1 {
    if dict[i].0 == name {
      dict[i] = (name, value)
      return
    }
  }
  dict.push((name, value))
}

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
    Value::Instance(inst) =>
      if inst.class.name == "iterator" {
        let items = match lookup_iterable_field(inst.dict, "items") {
          Some(Value::List(items)) => items
          _ => []
        }
        let pos = match lookup_iterable_field(inst.dict, "pos") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let out : Array[Value] = []
        let start = match bigint_to_int_checked(pos) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let mut i = start
        while i < items.length() {
          out.push(items[i])
          i = i + 1
        }
        set_iterable_field(
          inst.dict,
          "pos",
          Value::Int(@bigint.BigInt::from_int(items.length())),
        )
        Ok(out)
      } else if inst.class.name == "generator" {
        let out : Array[Value] = []
        while true {
          match iterator_next(Value::Instance(inst), None) {
            Ok(v) => out.push(v)
            Err(err) =>
              if err.exc_type == "StopIteration" {
                break
              } else {
                return Err(err)
              }
          }
        }
        Ok(out)
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "object is not iterable".to_string(),
          ),
        )
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
  let _ = globals
  if targets.length() == 1 {
    if targets[0] != "_" {
      ensure_local_cell(locals, targets[0], Value::None)
      set_local_value(locals, targets[0], item)
    }
    return Ok(())
  }
  let values = match item {
    Value::Tuple(values) => values
    Value::List(values) => values
    _ =>
      return Err(
        make_runtime_error(RuntimeErrorKind::Type, "cannot unpack".to_string()),
      )
  }
  if values.length() != targets.length() {
    return Err(
      make_runtime_error(RuntimeErrorKind::Type, "cannot unpack".to_string()),
    )
  }
  for i = 0; i < targets.length(); i = i + 1 {
    if targets[i] != "_" {
      ensure_local_cell(locals, targets[i], Value::None)
      set_local_value(locals, targets[i], values[i])
    }
  }
  Ok(())
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
