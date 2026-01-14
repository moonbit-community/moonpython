///|
/// Implementation for the mpython interpreter runtime.

///|
fn bool_from_value(value : Value) -> Bool {
  match value {
    Value::None => false
    Value::Bool(v) => v
    Value::Int(v) => v != 0L
    Value::Float(v) => v != 0.0
    Value::Str(v) => v.length() > 0
    Value::List(v) => v.length() > 0
    Value::Tuple(v) => v.length() > 0
    Value::Dict(v) => v.length() > 0
    Value::Set(v) => v.length() > 0
    Value::Function(_) => true
  }
}

///|
fn type_name_from_value(value : Value) -> String {
  match value {
    Value::None => "NoneType"
    Value::Bool(_) => "bool"
    Value::Int(_) => "int"
    Value::Float(_) => "float"
    Value::Str(_) => "str"
    Value::List(_) => "list"
    Value::Tuple(_) => "tuple"
    Value::Dict(_) => "dict"
    Value::Set(_) => "set"
    Value::Function(_) => "function"
  }
}

///|
fn not_callable_message(value : Value) -> String {
  "'" + type_name_from_value(value) + "' object is not callable"
}

///|
fn value_to_string(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Str(v) => v
    Value::List(values) => {
      let buf = StringBuilder::new()
      buf.write_char('[')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char(']')
      buf.to_string()
    }
    Value::Tuple(values) => {
      let buf = StringBuilder::new()
      buf.write_char('(')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      if values.length() == 1 {
        buf.write_string(",")
      }
      buf.write_char(')')
      buf.to_string()
    }
    Value::Dict(_) => "{}"
    Value::Set(values) => {
      let buf = StringBuilder::new()
      buf.write_char('{')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char('}')
      buf.to_string()
    }
    Value::Function(func) => "<function " + func.name + ">"
  }
}

///|
fn find_top_level_format_colon(inner : String) -> Int? {
  let chars = inner.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == ':' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      return Some(i)
    }
  }
  None
}

///|
fn eq_value(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::None, Value::None) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Int(a), Value::Int(b)) => a == b
    (Value::Float(a), Value::Float(b)) => a == b
    (Value::Str(a), Value::Str(b)) => a == b
    (Value::List(a), Value::List(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Tuple(a), Value::Tuple(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Set(a), Value::Set(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for item in a {
          let mut found = false
          for other in b {
            if eq_value(item, other) {
              found = true
              break
            }
          }
          if !found {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Dict(a), Value::Dict(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for pair in a {
          let mut found = false
          for other in b {
            if eq_value(pair.0, other.0) && eq_value(pair.1, other.1) {
              found = true
              break
            }
          }
          if !found {
            equal = false
            break
          }
        }
        equal
      }
    _ => false
  }
}

///|
fn number_value(value : Value) -> Result[(Bool, Double), RuntimeError] {
  match value {
    Value::Int(v) => Ok((false, v.to_double()))
    Value::Float(v) => Ok((true, v))
    Value::Bool(v) => Ok((false, if v { 1.0 } else { 0.0 }))
    _ =>
      Err(RuntimeError::{
        kind: RuntimeErrorKind::Type,
        message: "expected number".to_string(),
        span: None,
      })
  }
}

///|
fn make_runtime_error(
  kind : RuntimeErrorKind,
  message : String,
) -> RuntimeError {
  RuntimeError::{ kind, message, span: None }
}

///|
fn normalize_index(index : Int, length : Int) -> Int {
  if index < 0 {
    length + index
  } else {
    index
  }
}

///|
fn index_from_value(value : Value, default : Int) -> Result[Int, RuntimeError] {
  match value {
    Value::None => Ok(default)
    Value::Int(v) => Ok(v.to_int())
    Value::Bool(v) => Ok(if v { 1 } else { 0 })
    Value::Float(v) => Ok(v.to_int())
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, "invalid index".to_string()),
      )
  }
}

///|
fn slice_values(values : Array[Value], start : Int, end : Int) -> Array[Value] {
  let result : Array[Value] = []
  let len = values.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 {
    s = 0
  }
  if e < 0 {
    e = 0
  }
  if s > len {
    s = len
  }
  if e > len {
    e = len
  }
  for i = s; i < e; i = i + 1 {
    result.push(values[i])
  }
  result
}

///|
fn slice_string(chars : Array[Char], start : Int, end : Int) -> String {
  let len = chars.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 {
    s = 0
  }
  if e < 0 {
    e = 0
  }
  if s > len {
    s = len
  }
  if e > len {
    e = len
  }
  let buf = StringBuilder::new()
  for i = s; i < e; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn get_from_env(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Value? {
  for pair in locals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in builtins {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_global_value(
  globals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < globals.length(); i = i + 1 {
    if globals[i].0 == name {
      globals[i] = (name, value)
      return
    }
  }
  globals.push((name, value))
}

///|
fn clone_locals(locals : Array[(String, Value)]) -> Array[(String, Value)] {
  let result : Array[(String, Value)] = []
  for pair in locals {
    result.push(pair)
  }
  result
}

///|
fn set_local_value(
  locals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < locals.length(); i = i + 1 {
    if locals[i].0 == name {
      locals[i] = (name, value)
      return
    }
  }
  locals.push((name, value))
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
  targets : Array[String],
  item : Value,
) -> Result[Unit, RuntimeError] {
  if targets.length() == 1 {
    set_local_value(locals, targets[0], item)
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
          set_local_value(locals, targets[0], values[0])
          set_local_value(locals, targets[1], values[1])
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
          set_local_value(locals, targets[0], values[0])
          set_local_value(locals, targets[1], values[1])
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
    let _ = match bind_comp_targets(locals, clause.0, item) {
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
    let _ = match bind_comp_targets(locals, clause.0, item) {
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

///|
fn eval_expr_with_env(
  expr : Expr,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match expr {
    Expr::Literal(literal) =>
      match literal {
        Literal::None => Ok(Value::None)
        Literal::Bool(value) => Ok(Value::Bool(value))
        Literal::Int(value) => Ok(Value::Int(value))
        Literal::Float(value) => Ok(Value::Float(value))
        Literal::Str(value) => Ok(Value::Str(value))
      }
    Expr::Name(name) => {
      let value = get_from_env(name, locals, globals, builtins)
      if value is Some(value) {
        Ok(value)
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
      }
    }
    Expr::FString(text) => {
      let open = find_char(text, '{')
      let close = find_last_char(text, '}')
      if open is Some(open) && close is Some(close) && close > open {
        let prefix = substring(text, 0, open)
        let inner = substring(text, open + 1, close)
        let suffix = substring(text, close + 1, text.length())
        let expr = match parse_expr(inner) {
          Ok(value) => value
          Err(_) =>
            match find_top_level_format_colon(inner) {
              Some(pos) => {
                let expr_text = substring(inner, 0, pos)
                match parse_expr(expr_text) {
                  Ok(value) => value
                  Err(_) => return Ok(Value::Str(text))
                }
              }
              None => return Ok(Value::Str(text))
            }
        }
        let value = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        Ok(Value::Str(prefix + value_to_string(value) + suffix))
      } else {
        Ok(Value::Str(text))
      }
    }
    Expr::NamedExpr(name~, value~) => {
      let evaluated = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      set_global_value(globals, name, evaluated)
      Ok(evaluated)
    }
    Expr::List(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        values.push(value)
      }
      Ok(Value::List(values))
    }
    Expr::ListComp(elt~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
      let values : Array[Value] = []
      let _ = match
        eval_list_comp_walk(
          0, elt, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Ok(Value::List(values))
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      let iter_value = match
        eval_expr_with_env(clauses[0].1, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let _ = match iterable_values(iter_value) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: unsupported value".to_string(),
        ),
      )
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
      let values : Array[Value] = []
      let _ = match
        eval_list_comp_walk(
          0, elt, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let unique : Array[Value] = []
      for item in values {
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
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
      let values : Array[(Value, Value)] = []
      let _ = match
        eval_dict_comp_walk(
          0, key, value, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Ok(Value::Dict(values))
    }
    Expr::Dict(items) => {
      let values : Array[(Value, Value)] = []
      for item in items {
        let key = match
          eval_expr_with_env(item.0, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let value = match
          eval_expr_with_env(item.1, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        values.push((key, value))
      }
      Ok(Value::Dict(values))
    }
    Expr::Set(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let mut exists = false
        for existing in values {
          if eq_value(existing, value) {
            exists = true
            break
          }
        }
        if !exists {
          values.push(value)
        }
      }
      Ok(Value::Set(values))
    }
    Expr::Tuple(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        values.push(value)
      }
      Ok(Value::Tuple(values))
    }
    Expr::Lambda(params~, defaults~, body~) => {
      for expr in defaults {
        let _ = match eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }

      }
      let func_body : Array[Stmt] = [Stmt::Return(Some(body))]
      Ok(
        Value::Function(FunctionValue::{
          name: "<lambda>",
          params,
          body: func_body,
        }),
      )
    }
    Expr::Attribute(value~, attr~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if attr == "__class__" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: unsupported value".to_string(),
          ),
        )
      }
      match (target, attr) {
        (Value::Str(text), "upper") => Ok(Value::Str(text.to_upper()))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "attribute not supported".to_string(),
            ),
          )
      }
    }
    Expr::Subscript(value~, index~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match index {
        Expr::Slice(start~, end~) => {
          let start_index = match start {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::Int(0L)
          }
          let end_index = match end {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          let start = match index_from_value(start_index, 0) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match target {
            Value::List(values) => {
              let end = match index_from_value(end_index, values.length()) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::List(slice_values(values, start, end)))
            }
            Value::Tuple(values) => {
              let end = match index_from_value(end_index, values.length()) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::Tuple(slice_values(values, start, end)))
            }
            Value::Str(text) => {
              let chars = text.to_array()
              let end = match index_from_value(end_index, chars.length()) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::Str(slice_string(chars, start, end)))
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "subscript requires sequence".to_string(),
                ),
              )
          }
        }
        _ => {
          let idx_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match target {
            Value::Dict(values) => {
              for pair in values {
                if eq_value(pair.0, idx_value) {
                  return Ok(pair.1)
                }
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Key,
                  "key not found".to_string(),
                ),
              )
            }
            _ => {
              let idx = match index_from_value(idx_value, 0) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              match target {
                Value::List(values) =>
                  if idx >= 0 && idx < values.length() {
                    Ok(values[idx])
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                Value::Tuple(values) =>
                  if idx >= 0 && idx < values.length() {
                    Ok(values[idx])
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                Value::Str(text) => {
                  let chars = text.to_array()
                  if idx >= 0 && idx < chars.length() {
                    Ok(Value::Str(char_to_string(chars[idx])))
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "subscript requires sequence".to_string(),
                    ),
                  )
              }
            }
          }
        }
      }
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      let cond_value = match
        eval_expr_with_env(condition, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if bool_from_value(cond_value) {
        eval_expr_with_env(then_expr, locals, globals, builtins, io)
      } else {
        eval_expr_with_env(else_expr, locals, globals, builtins, io)
      }
    }
    Expr::Unary(op~, expr~) => {
      let value = match
        eval_expr_with_env(expr, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match op {
        UnaryOp::Neg => {
          let (is_float, num) = match number_value(value) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if is_float {
            Ok(Value::Float(-num))
          } else {
            Ok(Value::Int(-num.to_int64()))
          }
        }
        UnaryOp::Pos => Ok(value)
        UnaryOp::Not => Ok(Value::Bool(!bool_from_value(value)))
        UnaryOp::Invert =>
          match value {
            Value::Int(v) => Ok(Value::Int(-(v + 1L)))
            Value::Bool(v) => Ok(Value::Int(-((if v { 1L } else { 0L }) + 1L)))
            Value::Float(_) =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: 'float'".to_string(),
                ),
              )
            Value::Function(func) => {
              let type_name = if func.name == "int" ||
                func.name == "str" ||
                func.name == "bytes" ||
                func.name == "dict" {
                "type"
              } else {
                "function"
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: '" + type_name + "'",
                ),
              )
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: '" +
                  type_name_from_value(value) +
                  "'",
                ),
              )
          }
      }
    }
    Expr::Binary(op~, left~, right~) => {
      let left_val = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let right_val = match
        eval_expr_with_env(right, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match op {
        BinaryOp::Add =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
            (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
            (Value::Int(a), Value::Float(b)) =>
              Ok(Value::Float(a.to_double() + b))
            (Value::Float(a), Value::Int(b)) =>
              Ok(Value::Float(a + b.to_double()))
            (Value::Str(a), Value::Str(b)) => Ok(Value::Str(a + b))
            (Value::List(a), Value::List(b)) => {
              let merged : Array[Value] = []
              for item in a {
                merged.push(item)
              }
              for item in b {
                merged.push(item)
              }
              Ok(Value::List(merged))
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for +".to_string(),
                ),
              )
          }
        BinaryOp::Sub => {
          let (left_is_float, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (right_is_float, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let result = left_num - right_num
          if left_is_float || right_is_float {
            Ok(Value::Float(result))
          } else {
            Ok(Value::Int(result.to_int64()))
          }
        }
        BinaryOp::Mul =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a * b))
            (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a * b))
            (Value::Int(a), Value::Float(b)) =>
              Ok(Value::Float(a.to_double() * b))
            (Value::Float(a), Value::Int(b)) =>
              Ok(Value::Float(a * b.to_double()))
            (Value::Str(text), Value::Int(count)) =>
              if count <= 0L {
                Ok(Value::Str(""))
              } else {
                let buf = StringBuilder::new()
                for i = 0; i < count.to_int(); i = i + 1 {
                  buf.write_string(text)
                }
                Ok(Value::Str(buf.to_string()))
              }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for *".to_string(),
                ),
              )
          }
        BinaryOp::Div => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Float(left_num / right_num))
        }
        BinaryOp::FloorDiv => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Int((left_num / right_num).floor().to_int64()))
        }
        BinaryOp::Mod => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Float(left_num % right_num))
        }
        BinaryOp::Pow =>
          match (left_val, right_val) {
            (Value::Int(left), Value::Int(right)) =>
              if right < 0L {
                Ok(
                  Value::Float(Double::pow(left.to_double(), right.to_double())),
                )
              } else {
                let mut result = 1L
                for i = 0; i < right.to_int(); i = i + 1 {
                  result = result * left
                }
                Ok(Value::Int(result))
              }
            _ => {
              let (_, left_num) = match number_value(left_val) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              let (_, right_num) = match number_value(right_val) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::Float(Double::pow(left_num, right_num)))
            }
          }
        BinaryOp::MatMul =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for @".to_string(),
            ),
          )
        BinaryOp::ShiftLeft =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a << b.to_int()))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) << b.to_int()))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a << (if b { 1 } else { 0 })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int((if a { 1L } else { 0L }) << (if b { 1 } else { 0 })),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for <<".to_string(),
                ),
              )
          }
        BinaryOp::ShiftRight =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a >> b.to_int()))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) >> b.to_int()))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a >> (if b { 1 } else { 0 })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int((if a { 1L } else { 0L }) >> (if b { 1 } else { 0 })),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for >>".to_string(),
                ),
              )
          }
        BinaryOp::BitAnd =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a & b))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) & b))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a & (if b { 1L } else { 0L })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int(
                  (if a { 1L } else { 0L }) & (if b { 1L } else { 0L }),
                ),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for &".to_string(),
                ),
              )
          }
        BinaryOp::BitXor =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a ^ b))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) ^ b))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a ^ (if b { 1L } else { 0L })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int(
                  (if a { 1L } else { 0L }) ^ (if b { 1L } else { 0L }),
                ),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for ^".to_string(),
                ),
              )
          }
        BinaryOp::BitOr =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a | b))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) | b))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a | (if b { 1L } else { 0L })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int(
                  (if a { 1L } else { 0L }) | (if b { 1L } else { 0L }),
                ),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for |".to_string(),
                ),
              )
          }
      }
    }
    Expr::BoolOp(op~, values~) =>
      if values.length() == 0 {
        Ok(Value::Bool(false))
      } else {
        let mut result = match
          eval_expr_with_env(values[0], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for i = 1; i < values.length(); i = i + 1 {
          match op {
            BoolOp::And => if !bool_from_value(result) { return Ok(result) }
            BoolOp::Or => if bool_from_value(result) { return Ok(result) }
          }
          result = match
            eval_expr_with_env(values[i], locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        Ok(result)
      }
    Expr::Compare(left~, ops~, comparators~) => {
      let mut previous = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      for i = 0; i < ops.length(); i = i + 1 {
        let current = match
          eval_expr_with_env(comparators[i], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let ok = match ops[i] {
          CompareOp::Eq => eq_value(previous, current)
          CompareOp::NotEq => !eq_value(previous, current)
          CompareOp::Lt => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num < right_num
          }
          CompareOp::Lte => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num <= right_num
          }
          CompareOp::Gt => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num > right_num
          }
          CompareOp::Gte => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num >= right_num
          }
          _ => false
        }
        if !ok {
          return Ok(Value::Bool(false))
        }
        previous = current
      }
      Ok(Value::Bool(true))
    }
    Expr::Call(callee~, args~) =>
      match callee {
        Expr::Attribute(value~, attr~) =>
          if attr == "join" {
            let sep_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let sep = match sep_value {
              Value::Str(text) => text
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "join separator must be str".to_string(),
                  ),
                )
            }
            if args.length() != 1 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "join() takes exactly one argument".to_string(),
                ),
              )
            }
            let iter_value = match
              eval_expr_with_env(args[0], locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let parts : Array[String] = []
            match iter_value {
              Value::List(values) =>
                for v in values {
                  parts.push(value_to_string(v))
                }
              Value::Tuple(values) =>
                for v in values {
                  parts.push(value_to_string(v))
                }
              Value::Set(values) =>
                for v in values {
                  parts.push(value_to_string(v))
                }
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "can only join an iterable".to_string(),
                  ),
                )
            }
            let buf = StringBuilder::new()
            for i = 0; i < parts.length(); i = i + 1 {
              if i > 0 {
                buf.write_string(sep)
              }
              buf.write_string(parts[i])
            }
            Ok(Value::Str(buf.to_string()))
          } else {
            let callee_value = match
              eval_expr_with_env(
                Expr::Attribute(value~, attr~),
                locals,
                globals,
                builtins,
                io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let arg_values : Array[Value] = []
            for arg in args {
              let value = match
                eval_expr_with_env(arg, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              arg_values.push(value)
            }
            match callee_value {
              Value::Function(func) =>
                eval_function(func, arg_values, globals, builtins, io)
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    not_callable_message(callee_value),
                  ),
                )
            }
          }
        Expr::Name(name) =>
          match name {
            "print" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              let buf = StringBuilder::new()
              for i = 0; i < arg_values.length(); i = i + 1 {
                if i > 0 {
                  buf.write_string(" ")
                }
                buf.write_string(value_to_string(arg_values[i]))
              }
              buf.write_string("\n")
              io.write_stdout(buf.to_string())
              Ok(Value::None)
            }
            "input" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
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
            "str" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Str(""))
              } else {
                Ok(Value::Str(value_to_string(arg_values[0])))
              }
            }
            "len" => {
              if args.length() != 1 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "len() takes exactly one argument".to_string(),
                  ),
                )
              }
              let value = match
                eval_expr_with_env(args[0], locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              let length = match value {
                Value::Str(v) => v.length()
                Value::List(v) => v.length()
                Value::Tuple(v) => v.length()
                Value::Dict(v) => v.length()
                Value::Set(v) => v.length()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "object of type has no len()".to_string(),
                    ),
                  )
              }
              Ok(Value::Int(length.to_int64()))
            }
            "range" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              let (start, stop, step) = if arg_values.length() == 1 {
                (Value::Int(0L), arg_values[0], Value::Int(1L))
              } else if arg_values.length() == 2 {
                (arg_values[0], arg_values[1], Value::Int(1L))
              } else if arg_values.length() == 3 {
                (arg_values[0], arg_values[1], arg_values[2])
              } else {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "range() takes 1 to 3 arguments".to_string(),
                  ),
                )
              }
              let start_i = match start {
                Value::Int(v) => v.to_int()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "range() integer arguments expected".to_string(),
                    ),
                  )
              }
              let stop_i = match stop {
                Value::Int(v) => v.to_int()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "range() integer arguments expected".to_string(),
                    ),
                  )
              }
              let step_i = match step {
                Value::Int(v) => v.to_int()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "range() integer arguments expected".to_string(),
                    ),
                  )
              }
              if step_i == 0 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: range() arg 3 must not be zero".to_string(),
                  ),
                )
              }
              let values : Array[Value] = []
              let mut i = start_i
              if step_i > 0 {
                while i < stop_i {
                  values.push(Value::Int(i.to_int64()))
                  i += step_i
                }
              } else {
                while i > stop_i {
                  values.push(Value::Int(i.to_int64()))
                  i += step_i
                }
              }
              Ok(Value::List(values))
            }
            _ => {
              let value = get_from_env(name, locals, globals, builtins)
              if value is Some(value) {
                match value {
                  Value::Function(func) => {
                    let arg_values : Array[Value] = []
                    for arg in args {
                      let value = match
                        eval_expr_with_env(arg, locals, globals, builtins, io) {
                        Ok(value) => value
                        Err(err) => return Err(err)
                      }
                      arg_values.push(value)
                    }
                    eval_function(func, arg_values, globals, builtins, io)
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        not_callable_message(value),
                      ),
                    )
                }
              } else {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Name,
                    "name '" + name + "' is not defined",
                  ),
                )
              }
            }
          }
        _ => {
          let callee_value = match
            eval_expr_with_env(callee, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let arg_values : Array[Value] = []
          for arg in args {
            let value = match
              eval_expr_with_env(arg, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            arg_values.push(value)
          }
          match callee_value {
            Value::Function(func) =>
              eval_function(func, arg_values, globals, builtins, io)
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  not_callable_message(callee_value),
                ),
              )
          }
        }
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "expression not implemented".to_string(),
        ),
      )
  }
}

///|
fn eval_function(
  func : FunctionValue,
  args : Array[Value],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals : Array[(String, Value)] = []
  for i = 0; i < func.params.length(); i = i + 1 {
    let value = if i < args.length() { args[i] } else { Value::None }
    locals.push((func.params[i], value))
  }
  let result = match eval_block(func.body, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(result)
}

///|
fn eval_block(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let mut last = Value::None
  for stmt in body {
    match stmt {
      Stmt::ExprStmt(expr) => {
        let _ = match eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        last = Value::None
      }
      Stmt::Assign(target~, value~) => {
        let eval_value = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Target::Name(name) => set_global_value(globals, name, eval_value)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::NotImplemented,
                "assignment target not supported".to_string(),
              ),
            )
        }
        last = Value::None
      }
      Stmt::Return(expr) => {
        if expr is Some(expr) {
          let value = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          return Ok(value)
        }
        return Ok(Value::None)
      }
      Stmt::Function(name~, params~, body~) => {
        let func = FunctionValue::{ name, params, body }
        set_global_value(globals, name, Value::Function(func))
        last = Value::None
      }
      Stmt::Pass => last = Value::None
      Stmt::Global(_) => last = Value::None
      Stmt::Assert(condition~, message~) => {
        let value = match
          eval_expr_with_env(condition, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if !bool_from_value(value) {
          let text = match message {
            Some(expr) => {
              let msg_value = match
                eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              "AssertionError: " + value_to_string(msg_value)
            }
            None => "AssertionError".to_string()
          }
          return Err(make_runtime_error(RuntimeErrorKind::Runtime, text))
        }
        last = Value::None
      }
      Stmt::Raise(expr) => {
        if expr is Some(expr) {
          let _ = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }

        }
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "RuntimeError: raised".to_string(),
          ),
        )
      }
      Stmt::Del(targets) => {
        for target in targets {
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
            }
            Target::Attribute(value~, attr~) => {
              let _ = match
                eval_expr_with_env(value, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "attribute not supported".to_string(),
                ),
              )
            }
            Target::Subscript(value~, index~) => {
              let _ = match
                eval_expr_with_env(value, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              let _ = match
                eval_expr_with_env(index, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::NotImplemented,
                  "delete subscript not implemented".to_string(),
                ),
              )
            }
          }
        }
        last = Value::None
      }
      Stmt::Import(module~) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ImportError: module " + module + " is not allowed",
          ),
        )
      Stmt::With(context~, target~, body~) => {
        let ctx_value = match
          eval_expr_with_env(context, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Some(name) => set_global_value(globals, name, ctx_value)
          None => ()
        }
        let _ = match eval_block(body, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        last = Value::None
      }
      Stmt::Class(name~, body~) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "NameError: __build_class__ not found".to_string(),
          ),
        )
      Stmt::For(target~, iter~, body~) => {
        let iter_value = match
          eval_expr_with_env(iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let items = match iterable_values(iter_value) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for item in items {
          set_global_value(globals, target, item)
          let _ = match eval_block(body, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }

        }
        last = Value::None
      }
      Stmt::Break =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "break not implemented".to_string(),
          ),
        )
      Stmt::Continue =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "continue not implemented".to_string(),
          ),
        )
      Stmt::If(condition~, body~, else_body~) => {
        let cond_value = match
          eval_expr_with_env(condition, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if bool_from_value(cond_value) {
          let _ = match eval_block(body, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }

        } else {
          let _ = match eval_block(else_body, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }

        }
        last = Value::None
      }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "statement not implemented".to_string(),
          ),
        )
    }
  }
  Ok(last)
}

///|
pub fn Config::default() -> Config {
  Config::{ max_recursion: 1000, traceback_limit: 20, track_spans: true }
}

///|
pub fn MockIO::new(stdin : Array[String]) -> MockIO {
  MockIO::{
    stdin,
    stdin_pos: { val: 0 },
    stdout: StringBuilder::new(),
    stderr: StringBuilder::new(),
  }
}

///|
pub fn MockIO::read_line(self : MockIO) -> String? {
  if self.stdin_pos.val >= self.stdin.length() {
    None
  } else {
    let line = self.stdin[self.stdin_pos.val]
    self.stdin_pos.val += 1
    Some(line)
  }
}

///|
pub fn MockIO::write_stdout(self : MockIO, text : String) -> Unit {
  self.stdout.write_string(text)
}

///|
pub fn MockIO::write_stderr(self : MockIO, text : String) -> Unit {
  self.stderr.write_string(text)
}

///|
pub fn MockIO::take_stdout(self : MockIO) -> String {
  self.stdout.to_string()
}

///|
pub fn MockIO::take_stderr(self : MockIO) -> String {
  self.stderr.to_string()
}

///|
pub fn Interpreter::new() -> Interpreter {
  Interpreter::with_io(Config::default(), MockIO::new([]))
}

///|
pub fn Interpreter::with_config(config : Config) -> Interpreter {
  Interpreter::with_io(config, MockIO::new([]))
}

///|
pub fn Interpreter::with_builtins(
  builtins : Array[(String, Value)],
  config : Config,
) -> Interpreter {
  Interpreter::{ config, globals: [], builtins, io: MockIO::new([]) }
}

///|
pub fn Interpreter::with_io(config : Config, io : MockIO) -> Interpreter {
  let builtins : Array[(String, Value)] = [
    (
      "print",
      Value::Function(FunctionValue::{ name: "print", params: [], body: [] }),
    ),
    (
      "input",
      Value::Function(FunctionValue::{ name: "input", params: [], body: [] }),
    ),
    ("__debug__", Value::Bool(true)),
    (
      "str",
      Value::Function(FunctionValue::{ name: "str", params: [], body: [] }),
    ),
    (
      "bytes",
      Value::Function(FunctionValue::{ name: "bytes", params: [], body: [] }),
    ),
    (
      "dict",
      Value::Function(FunctionValue::{ name: "dict", params: [], body: [] }),
    ),
    (
      "int",
      Value::Function(FunctionValue::{ name: "int", params: [], body: [] }),
    ),
  ]
  Interpreter::{ config, globals: [], builtins, io }
}

///|
pub fn Interpreter::exec(
  self : Interpreter,
  program : Module,
) -> Result[RunResult, RuntimeError] {
  let value = match
    eval_block(program.body, [], self.globals, self.builtins, self.io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match value {
    Value::Function(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: unsupported value".to_string(),
        ),
      )
    _ => ()
  }
  Ok(RunResult::{
    value,
    stdout: self.io.take_stdout(),
    stderr: self.io.take_stderr(),
    globals: self.globals,
  })
}

///|
pub fn Interpreter::exec_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let program = match parse(source) {
    Ok(value) => value
    Err(err) =>
      return Err(RuntimeError::{
        kind: RuntimeErrorKind::Runtime,
        message: format_parse_error(err),
        span: None,
      })
  }
  self.exec(program)
}

///|
pub fn Interpreter::eval_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let expr = match parse_expr(source) {
    Ok(value) => value
    Err(err) =>
      return Err(RuntimeError::{
        kind: RuntimeErrorKind::Runtime,
        message: format_parse_error(err),
        span: None,
      })
  }
  let value = match
    eval_expr_with_env(expr, [], self.globals, self.builtins, self.io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match value {
    Value::Function(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: unsupported value".to_string(),
        ),
      )
    _ => ()
  }
  Ok(RunResult::{
    value,
    stdout: self.io.take_stdout(),
    stderr: self.io.take_stderr(),
    globals: self.globals,
  })
}

///|
pub fn Interpreter::eval(
  self : Interpreter,
  expr : Expr,
) -> Result[Value, RuntimeError] {
  eval_expr_with_env(expr, [], self.globals, self.builtins, self.io)
}

///|
pub fn Interpreter::get_global(self : Interpreter, name : String) -> Value? {
  for pair in self.globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
pub fn Interpreter::set_global(
  self : Interpreter,
  name : String,
  value : Value,
) -> Unit {
  set_global_value(self.globals, name, value)
}

///|
pub fn format_parse_error(error : ParseError) -> String {
  if error.message.has_prefix("ValueError:") ||
    error.message.has_prefix("ImportError:") ||
    error.message.has_prefix("NameError:") ||
    error.message.has_prefix("AssertionError:") {
    return error.message
  }
  "line " +
  error.span.line.to_string() +
  ":" +
  error.span.column.to_string() +
  " " +
  error.message
}

///|
pub fn format_runtime_error(error : RuntimeError) -> String {
  match error.kind {
    RuntimeErrorKind::ZeroDivision => "ZeroDivisionError: " + error.message
    RuntimeErrorKind::Name => "NameError: " + error.message
    RuntimeErrorKind::Type => "TypeError: " + error.message
    RuntimeErrorKind::Attribute => "AttributeError: " + error.message
    RuntimeErrorKind::Index => "IndexError: " + error.message
    RuntimeErrorKind::Key => "KeyError: " + error.message
    RuntimeErrorKind::NotImplemented => "NotImplementedError: " + error.message
    RuntimeErrorKind::Runtime => error.message
  }
}
