///|
/// Bytecode VM (stack machine), inspired by MicroPython's `py/vm.c`.
///
/// This VM reuses MoonPython's existing runtime helpers (`Value`, builtins,
/// attribute lookup, call protocol, etc.) for semantics.

///|
fn pop_stack(stack : Array[Value]) -> Result[Value, RuntimeError] {
  if stack.length() == 0 {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "bytecode vm: stack underflow".to_string(),
      ),
    )
  } else {
    Ok(stack.remove(stack.length() - 1))
  }
}

///|
fn pop_n(stack : Array[Value], n : Int) -> Result[Array[Value], RuntimeError] {
  if n < 0 || stack.length() < n {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "bytecode vm: stack underflow".to_string(),
      ),
    )
  }
  let tmp : Array[Value] = []
  for _i = 0; _i < n; _i = _i + 1 {
    tmp.push(stack.remove(stack.length() - 1))
  }
  // Caller expects left-to-right order; we popped right-to-left.
  let out : Array[Value] = []
  for i = tmp.length() - 1; i >= 0; i = i - 1 {
    out.push(tmp[i])
    if i == 0 {
      break
    }
  }
  Ok(out)
}

///|
fn unary_op_value(
  op : UnaryOp,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  // Keep this small initially; extend by extracting the full logic from
  // `runtime_eval_expr.mbt` as the VM reaches parity.
  match op {
    UnaryOp::Not => {
      let ok = match truthy_from_value_with_env(value, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Value::Bool(!ok))
    }
    UnaryOp::Neg =>
      match value {
        Value::Int(v) => Ok(Value::Int(-v))
        Value::Float(v) => Ok(Value::Float(-v))
        Value::Bool(v) => Ok(Value::Int(-(if v { 1N } else { 0N })))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "bad operand type for unary -".to_string(),
            ),
          )
      }
    UnaryOp::Pos => Ok(value)
    UnaryOp::Invert =>
      match value {
        Value::Int(v) => Ok(Value::Int(-(v + 1N)))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "bad operand type for unary ~".to_string(),
            ),
          )
      }
  }
}

///|
fn get_subscr_value(
  target : Value,
  index : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  // Minimal implementation; `Expr::Subscript` in `runtime_eval_expr.mbt` has the
  // complete behavior (slice objects, negative indices, etc.).
  match target {
    Value::Dict(pairs) => {
      for pair in pairs {
        if is_value_identity(pair.0, index) || eq_value(pair.0, index) {
          return Ok(pair.1)
        }
      }
      Err(
        make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()),
      )
    }
    Value::List(items) =>
      match index_from_value(index, 0) {
        Ok(i) => {
          let idx = normalize_index(i, items.length())
          if idx < 0 || idx >= items.length() {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Index,
                "list index out of range".to_string(),
              ),
            )
          } else {
            Ok(items[idx])
          }
        }
        Err(err) => Err(err)
      }
    Value::Tuple(items) =>
      match index_from_value(index, 0) {
        Ok(i) => {
          let idx = normalize_index(i, items.length())
          if idx < 0 || idx >= items.length() {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Index,
                "tuple index out of range".to_string(),
              ),
            )
          } else {
            Ok(items[idx])
          }
        }
        Err(err) => Err(err)
      }
    Value::Instance(_) => {
      let getitem = match
        get_attr_from_value(target, "__getitem__", globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      call_callable_with_env(getitem, [index], [], globals, builtins, io)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object is not subscriptable".to_string(),
        ),
      )
  }
}

///|
fn set_subscr_value(
  target : Value,
  index : Value,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  match target {
    Value::List(items) =>
      match index_from_value(index, 0) {
        Ok(i) => {
          let idx = normalize_index(i, items.length())
          if idx < 0 || idx >= items.length() {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Index,
                "list assignment index out of range".to_string(),
              ),
            )
          } else {
            items[idx] = value
            Ok(())
          }
        }
        Err(err) => Err(err)
      }
    Value::Dict(pairs) => {
      // Insert/update.
      for i = 0; i < pairs.length(); i = i + 1 {
        if is_value_identity(pairs[i].0, index) || eq_value(pairs[i].0, index) {
          pairs[i] = (pairs[i].0, value)
          return Ok(())
        }
      }
      pairs.push((index, value))
      Ok(())
    }
    Value::Instance(_) => {
      let setitem = match
        get_attr_from_value(target, "__setitem__", globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let _ = match
        call_callable_with_env(
          setitem,
          [index, value],
          [],
          globals,
          builtins,
          io,
        ) {
        Ok(_) => ()
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

///|
fn compare_op_bool(
  op : CompareOp,
  left : Value,
  right : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  fn compare_sequence_values(
    left : Array[Value],
    right : Array[Value],
  ) -> Result[Int, RuntimeError] {
    let min_len = if left.length() < right.length() {
      left.length()
    } else {
      right.length()
    }
    for i = 0; i < min_len; i = i + 1 {
      if is_value_identity(left[i], right[i]) || eq_value(left[i], right[i]) {
        continue
      }
      fn compare_ordered(a : Value, b : Value) -> Result[Int, RuntimeError] {
        if is_value_identity(a, b) || eq_value(a, b) {
          return Ok(0)
        }
        match (a, b) {
          (Value::Str(x), Value::Str(y)) => Ok(if x < y { -1 } else { 1 })
          (Value::Tuple(xs), Value::Tuple(ys)) =>
            compare_sequence_values(xs, ys)
          (Value::List(xs), Value::List(ys)) => compare_sequence_values(xs, ys)
          _ => {
            let (_, left_num) = match number_value(a) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(b) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            Ok(if left_num < right_num { -1 } else { 1 })
          }
        }
      }

      return compare_ordered(left[i], right[i])
    }
    if left.length() == right.length() {
      Ok(0)
    } else if left.length() < right.length() {
      Ok(-1)
    } else {
      Ok(1)
    }
  }

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

  fn ordering_bool(
    left : Value,
    right : Value,
    left_method : String,
    right_method : String,
    op_text : String,
  ) -> Result[Bool, RuntimeError] {
    // 1) Try `left.__op__(right)` for instances.
    if left is Value::Instance(_) {
      match get_attr_from_value(left, left_method, globals, builtins, io) {
        Ok(callable) =>
          if callable is Value::None {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                left_method + " is not callable".to_string(),
              ),
            )
          } else {
            match
              call_callable_with_env(
                callable,
                [right],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => return Ok(bool_from_value(v))
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

    // 2) Try reflected op on right (e.g. `right.__gt__(left)` for `<`).
    if right is Value::Instance(_) {
      match get_attr_from_value(right, right_method, globals, builtins, io) {
        Ok(callable) =>
          if callable is Value::None {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                right_method + " is not callable".to_string(),
              ),
            )
          } else {
            match
              call_callable_with_env(
                callable,
                [left],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => return Ok(bool_from_value(v))
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
    Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        op_text +
        " not supported between instances of '" +
        type_name_from_value(left) +
        "' and '" +
        type_name_from_value(right) +
        "'",
      ),
    )
  }

  match op {
    CompareOp::Is => Ok(is_value_identity(left, right))
    CompareOp::IsNot => Ok(!is_value_identity(left, right))
    CompareOp::Eq => Ok(is_value_identity(left, right) || eq_value(left, right))
    CompareOp::NotEq =>
      Ok(!(is_value_identity(left, right) || eq_value(left, right)))
    CompareOp::Lt =>
      match (left, right) {
        (Value::Int(a), Value::Int(b)) => Ok(a < b)
        (Value::Bool(a), Value::Bool(b)) =>
          Ok((if a { 1N } else { 0N }) < (if b { 1N } else { 0N }))
        (Value::Bool(a), Value::Int(b)) => Ok((if a { 1N } else { 0N }) < b)
        (Value::Int(a), Value::Bool(b)) => Ok(a < (if b { 1N } else { 0N }))
        (Value::Float(a), Value::Float(b)) => Ok(a < b)
        (Value::Float(a), Value::Int(b)) =>
          match bigint_to_double_checked(b) {
            Ok(v) => Ok(a < v)
            Err(err) => Err(err)
          }
        (Value::Int(a), Value::Float(b)) =>
          match bigint_to_double_checked(a) {
            Ok(v) => Ok(v < b)
            Err(err) => Err(err)
          }
        (Value::Float(a), Value::Bool(b)) => Ok(a < (if b { 1.0 } else { 0.0 }))
        (Value::Bool(a), Value::Float(b)) => Ok((if a { 1.0 } else { 0.0 }) < b)
        (Value::Str(a), Value::Str(b)) => Ok(a < b)
        (
          Value::Bytes(a)
          | Value::ByteArray(a)
          | Value::MemoryView(a),
          Value::Bytes(b)
          | Value::ByteArray(b)
          | Value::MemoryView(b),
        ) => Ok(compare_bytes_like(a, b) < 0)
        (Value::Tuple(a), Value::Tuple(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v < 0)
            Err(err) => Err(err)
          }
        (Value::List(a), Value::List(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v < 0)
            Err(err) => Err(err)
          }
        _ => ordering_bool(left, right, "__lt__", "__gt__", "<")
      }
    CompareOp::Lte =>
      match (left, right) {
        (Value::Int(a), Value::Int(b)) => Ok(a <= b)
        (Value::Bool(a), Value::Bool(b)) =>
          Ok((if a { 1N } else { 0N }) <= (if b { 1N } else { 0N }))
        (Value::Bool(a), Value::Int(b)) => Ok((if a { 1N } else { 0N }) <= b)
        (Value::Int(a), Value::Bool(b)) => Ok(a <= (if b { 1N } else { 0N }))
        (Value::Float(a), Value::Float(b)) => Ok(a <= b)
        (Value::Float(a), Value::Int(b)) =>
          match bigint_to_double_checked(b) {
            Ok(v) => Ok(a <= v)
            Err(err) => Err(err)
          }
        (Value::Int(a), Value::Float(b)) =>
          match bigint_to_double_checked(a) {
            Ok(v) => Ok(v <= b)
            Err(err) => Err(err)
          }
        (Value::Float(a), Value::Bool(b)) =>
          Ok(a <= (if b { 1.0 } else { 0.0 }))
        (Value::Bool(a), Value::Float(b)) =>
          Ok((if a { 1.0 } else { 0.0 }) <= b)
        (Value::Str(a), Value::Str(b)) => Ok(a <= b)
        (
          Value::Bytes(a)
          | Value::ByteArray(a)
          | Value::MemoryView(a),
          Value::Bytes(b)
          | Value::ByteArray(b)
          | Value::MemoryView(b),
        ) => Ok(compare_bytes_like(a, b) <= 0)
        (Value::Tuple(a), Value::Tuple(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v <= 0)
            Err(err) => Err(err)
          }
        (Value::List(a), Value::List(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v <= 0)
            Err(err) => Err(err)
          }
        _ => ordering_bool(left, right, "__le__", "__ge__", "<=")
      }
    CompareOp::Gt =>
      match (left, right) {
        (Value::Int(a), Value::Int(b)) => Ok(a > b)
        (Value::Bool(a), Value::Bool(b)) =>
          Ok((if a { 1N } else { 0N }) > (if b { 1N } else { 0N }))
        (Value::Bool(a), Value::Int(b)) => Ok((if a { 1N } else { 0N }) > b)
        (Value::Int(a), Value::Bool(b)) => Ok(a > (if b { 1N } else { 0N }))
        (Value::Float(a), Value::Float(b)) => Ok(a > b)
        (Value::Float(a), Value::Int(b)) =>
          match bigint_to_double_checked(b) {
            Ok(v) => Ok(a > v)
            Err(err) => Err(err)
          }
        (Value::Int(a), Value::Float(b)) =>
          match bigint_to_double_checked(a) {
            Ok(v) => Ok(v > b)
            Err(err) => Err(err)
          }
        (Value::Float(a), Value::Bool(b)) => Ok(a > (if b { 1.0 } else { 0.0 }))
        (Value::Bool(a), Value::Float(b)) => Ok((if a { 1.0 } else { 0.0 }) > b)
        (Value::Str(a), Value::Str(b)) => Ok(a > b)
        (
          Value::Bytes(a)
          | Value::ByteArray(a)
          | Value::MemoryView(a),
          Value::Bytes(b)
          | Value::ByteArray(b)
          | Value::MemoryView(b),
        ) => Ok(compare_bytes_like(a, b) > 0)
        (Value::Tuple(a), Value::Tuple(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v > 0)
            Err(err) => Err(err)
          }
        (Value::List(a), Value::List(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v > 0)
            Err(err) => Err(err)
          }
        _ => ordering_bool(left, right, "__gt__", "__lt__", ">")
      }
    CompareOp::Gte =>
      match (left, right) {
        (Value::Int(a), Value::Int(b)) => Ok(a >= b)
        (Value::Bool(a), Value::Bool(b)) =>
          Ok((if a { 1N } else { 0N }) >= (if b { 1N } else { 0N }))
        (Value::Bool(a), Value::Int(b)) => Ok((if a { 1N } else { 0N }) >= b)
        (Value::Int(a), Value::Bool(b)) => Ok(a >= (if b { 1N } else { 0N }))
        (Value::Float(a), Value::Float(b)) => Ok(a >= b)
        (Value::Float(a), Value::Int(b)) =>
          match bigint_to_double_checked(b) {
            Ok(v) => Ok(a >= v)
            Err(err) => Err(err)
          }
        (Value::Int(a), Value::Float(b)) =>
          match bigint_to_double_checked(a) {
            Ok(v) => Ok(v >= b)
            Err(err) => Err(err)
          }
        (Value::Float(a), Value::Bool(b)) =>
          Ok(a >= (if b { 1.0 } else { 0.0 }))
        (Value::Bool(a), Value::Float(b)) =>
          Ok((if a { 1.0 } else { 0.0 }) >= b)
        (Value::Str(a), Value::Str(b)) => Ok(a >= b)
        (
          Value::Bytes(a)
          | Value::ByteArray(a)
          | Value::MemoryView(a),
          Value::Bytes(b)
          | Value::ByteArray(b)
          | Value::MemoryView(b),
        ) => Ok(compare_bytes_like(a, b) >= 0)
        (Value::Tuple(a), Value::Tuple(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v >= 0)
            Err(err) => Err(err)
          }
        (Value::List(a), Value::List(b)) =>
          match compare_sequence_values(a, b) {
            Ok(v) => Ok(v >= 0)
            Err(err) => Err(err)
          }
        _ => ordering_bool(left, right, "__ge__", "__le__", ">=")
      }
    CompareOp::In | CompareOp::NotIn => {
      let found = match right {
        Value::List(values) | Value::Tuple(values) => {
          let mut found = false
          for item in values {
            if is_value_identity(item, left) || eq_value(item, left) {
              found = true
              break
            }
          }
          found
        }
        Value::Set(values) =>
          match set_find_index(values, left) {
            Ok(index) => index is Some(_)
            Err(err) => return Err(err)
          }
        Value::Bytes(bytes)
        | Value::ByteArray(bytes)
        | Value::MemoryView(bytes) => bytes_contains(bytes, left)
        Value::Dict(pairs) =>
          match dict_find_index(pairs, left) {
            Ok(index) => index is Some(_)
            Err(err) => return Err(err)
          }
        Value::Str(text) =>
          match left {
            Value::Str(needle) => text.contains(needle)
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "'in <string>' requires string as left operand, not " +
                  type_name_from_value(left),
                ),
              )
          }
        _ =>
          // Prefer `__contains__` when available, else fall back to iteration.
          if right is Value::Instance(_) {
            match
              get_attr_from_value(right, "__contains__", globals, builtins, io) {
              Ok(contains_method) =>
                if contains_method is Value::None {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "argument of type '" +
                      type_name_from_value(right) +
                      "' is not iterable",
                    ),
                  )
                } else {
                  let result = match
                    call_callable_with_env(
                      contains_method,
                      [left],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  bool_from_value(result)
                }
              Err(err) =>
                match err.kind {
                  RuntimeErrorKind::Attribute => {
                    let iterator = match
                      iter_value_to_iterator(right, globals, builtins, io) {
                      Ok(v) => v
                      Err(e) => return Err(e)
                    }
                    let mut found = false
                    while true {
                      match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(item) =>
                          if is_value_identity(item, left) ||
                            eq_value(item, left) {
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
                    found
                  }
                  _ => return Err(err)
                }
            }
          } else {
            let iterator = match
              iter_value_to_iterator(right, globals, builtins, io) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let mut found = false
            while true {
              match iterator_next(iterator, None, globals, builtins, io) {
                Ok(item) =>
                  if is_value_identity(item, left) || eq_value(item, left) {
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
            found
          }
      }
      match op {
        CompareOp::In => Ok(found)
        CompareOp::NotIn => Ok(!found)
        _ => Ok(found)
      }
    }
  }
}

///|
pub fn bc_exec(
  code : BcCode,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let stack : Array[Value] = []
  let mut pc = 0
  while pc < code.ops.length() {
    let op = code.ops[pc]
    let span = code.spans[pc]
    match span {
      Some(s) => push_active_span(s)
      None => ()
    }
    let mut next_pc = pc + 1
    let step : Result[Unit, RuntimeError] = match op {
      BcOp::Nop => Ok(())
      BcOp::PopTop =>
        match pop_stack(stack) {
          Ok(_) => Ok(())
          Err(err) => Err(err)
        }
      BcOp::LoadConst(i) => {
        stack.push(code.consts[i])
        Ok(())
      }
      BcOp::LoadName(i) => {
        let name = code.names[i]
        let v = match lookup_name_value(name, locals, globals, builtins) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(v)
        Ok(())
      }
      BcOp::StoreName(i) => {
        let name = code.names[i]
        let v = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        set_scoped_value(locals, globals, name, v)
        Ok(())
      }
      BcOp::LoadAttr(i) => {
        let attr = code.names[i]
        let target = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let v = match get_attr_from_value(target, attr, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(v)
        Ok(())
      }
      BcOp::StoreAttr(i) => {
        let attr = code.names[i]
        let value = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let target = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match set_attr_on_value(target, attr, value, globals, builtins, io) {
          Ok(_) => Ok(())
          Err(err) => Err(err)
        }
      }
      BcOp::LoadSubscr => {
        let index = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let target = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let v = match get_subscr_value(target, index, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(v)
        Ok(())
      }
      BcOp::StoreSubscr => {
        let value = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let index = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let target = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match set_subscr_value(target, index, value, globals, builtins, io) {
          Ok(_) => Ok(())
          Err(err) => Err(err)
        }
      }
      BcOp::BuildTuple(n) =>
        match pop_n(stack, n) {
          Ok(values) => {
            stack.push(Value::Tuple(values))
            Ok(())
          }
          Err(err) => Err(err)
        }
      BcOp::BuildList(n) =>
        match pop_n(stack, n) {
          Ok(values) => {
            stack.push(Value::List(values))
            Ok(())
          }
          Err(err) => Err(err)
        }
      BcOp::BuildMap(pair_count) => {
        let values = match pop_n(stack, pair_count * 2) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let out : Array[(Value, Value)] = []
        for i = 0; i < values.length(); i = i + 2 {
          out.push((values[i], values[i + 1]))
        }
        stack.push(Value::Dict(out))
        Ok(())
      }
      BcOp::GetIter => {
        let value = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let iter = match iter_value_to_iterator(value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(iter)
        Ok(())
      }
      BcOp::ForIter(target) => {
        if stack.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        }
        let iter = stack[stack.length() - 1]
        match iterator_next(iter, None, globals, builtins, io) {
          Ok(item) => {
            // Keep iterator on stack; push current item.
            stack.push(item)
            Ok(())
          }
          Err(err) =>
            if err.exc_type == "StopIteration" {
              // Pop iterator and jump out of the loop.
              let _ = stack.remove(stack.length() - 1)
              next_pc = target
              Ok(())
            } else {
              Err(err)
            }
        }
      }
      BcOp::Unary(op) => {
        let value = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let out = match unary_op_value(op, value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(out)
        Ok(())
      }
      BcOp::Binary(op) => {
        let right = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let left = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let out = match
          eval_binary_op_values(op, left, right, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(out)
        Ok(())
      }
      BcOp::Compare(op) => {
        let right = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let left = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let ok = match compare_op_bool(op, left, right, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(Value::Bool(ok))
        Ok(())
      }
      BcOp::Jump(target) => {
        next_pc = target
        Ok(())
      }
      BcOp::JumpIfFalse(target) => {
        let v = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let ok = match truthy_from_value_with_env(v, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if !ok {
          next_pc = target
        }
        Ok(())
      }
      BcOp::JumpIfTrue(target) => {
        let v = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let ok = match truthy_from_value_with_env(v, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if ok {
          next_pc = target
        }
        Ok(())
      }
      BcOp::JumpIfFalseOrPop(target) => {
        if stack.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        }
        let v = stack[stack.length() - 1]
        let ok = match truthy_from_value_with_env(v, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if !ok {
          next_pc = target
        } else {
          let _ = stack.remove(stack.length() - 1)

        }
        Ok(())
      }
      BcOp::JumpIfTrueOrPop(target) => {
        if stack.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        }
        let v = stack[stack.length() - 1]
        let ok = match truthy_from_value_with_env(v, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if ok {
          next_pc = target
        } else {
          let _ = stack.remove(stack.length() - 1)

        }
        Ok(())
      }
      BcOp::CallFunction(argc) => {
        let args = match pop_n(stack, argc) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let callee = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let out = match
          call_callable_with_env(callee, args, [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        stack.push(out)
        Ok(())
      }
      BcOp::ReturnValue => {
        let v = match pop_stack(stack) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if span is Some(_) {
          pop_active_span()
        }
        return Ok(v)
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "bytecode vm: opcode not implemented".to_string(),
          ),
        )
    }
    match span {
      Some(_) => pop_active_span()
      None => ()
    }
    match step {
      Ok(_) => pc = next_pc
      Err(err) => return Err(err)
    }
  }

  // If bytecode falls off the end, return None.
  Ok(Value::None)
}
