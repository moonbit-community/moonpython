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
