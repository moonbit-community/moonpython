///|
/// Bytecode VM (stack machine), inspired by MicroPython's `py/vm.c`.
///
/// This VM reuses MoonPython's existing runtime helpers (`Value`, builtins,
/// attribute lookup, call protocol, etc.) for semantics.

///|
priv enum VmBlockKind {
  Except(Int)
  ExceptHandler
  Finally(Int)
  FinallyHandler
}

///|
priv struct VmBlock {
  kind : VmBlockKind
  stack_height : Int
}

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
fn vm_make_frame_value(frame : TracebackFrame) -> Value {
  let code_value = Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "code", bases: [], dict: [] },
    dict: [
      ("co_filename", Value::Str(frame.filename)),
      ("co_name", Value::Str(frame.name)),
      ("co_firstlineno", Value::Int(@bigint.BigInt::from_int(frame.line))),
    ],
  })
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "frame", bases: [], dict: [] },
    dict: [
      ("f_name", Value::Str(frame.name)),
      ("f_filename", Value::Str(frame.filename)),
      ("f_lineno", Value::Int(@bigint.BigInt::from_int(frame.line))),
      ("f_colno", Value::Int(@bigint.BigInt::from_int(frame.column))),
      ("f_code", code_value),
      ("f_back", Value::None),
      ("f_globals", Value::Dict([])),
      ("f_locals", Value::Dict([])),
    ],
  })
}

///|
fn vm_make_traceback_value(frames : Array[TracebackFrame]) -> Value {
  if frames.length() == 0 {
    let frame_value = vm_make_frame_value(TracebackFrame::{
      name: "<module>",
      filename: "<module>",
      line: 1,
      column: 1,
    })
    return Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "traceback", bases: [], dict: [] },
      dict: [
        ("tb_frame", frame_value),
        ("tb_lineno", Value::Int(1N)),
        ("tb_colno", Value::Int(1N)),
        ("tb_next", Value::None),
        ("tb_lasti", Value::Int(-1N)),
      ],
    })
  }
  let mut next_value : Value = Value::None
  let mut i = frames.length()
  while i > 0 {
    i = i - 1
    let frame = frames[i]
    let frame_value = vm_make_frame_value(frame)
    let tb_value = Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "traceback", bases: [], dict: [] },
      dict: [
        ("tb_frame", frame_value),
        ("tb_lineno", Value::Int(@bigint.BigInt::from_int(frame.line))),
        ("tb_colno", Value::Int(@bigint.BigInt::from_int(frame.column))),
        ("tb_next", next_value),
        ("tb_lasti", Value::Int(@bigint.BigInt::from_int(i))),
      ],
    })
    next_value = tb_value
  }
  next_value
}

///|
fn vm_unwind_return(stack : Array[Value], blocks : Array[VmBlock]) -> Int? {
  while blocks.length() > 0 {
    let blk = blocks.remove(blocks.length() - 1)
    while stack.length() > blk.stack_height {
      let _ = stack.remove(stack.length() - 1)

    }
    match blk.kind {
      VmBlockKind::Finally(target) => {
        // Mark as active so exceptions inside the finally do not re-enter it.
        blocks.push(VmBlock::{
          kind: VmBlockKind::FinallyHandler,
          stack_height: stack.length(),
        })
        return Some(target)
      }
      // A return bypasses exception handlers; just drop them.
      VmBlockKind::Except(_)
      | VmBlockKind::ExceptHandler
      | VmBlockKind::FinallyHandler => continue
    }
  }
  None
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
  let blocks : Array[VmBlock] = []
  let mut pending_exc : RuntimeError? = None
  let mut pending_return : Value? = None
  let mut pending_jump_target : Int? = None
  let mut pending_jump_count = 0
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
      BcOp::DupTop =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          stack.push(stack[stack.length() - 1])
          Ok(())
        }
      BcOp::RotTwo =>
        if stack.length() < 2 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let b = stack.remove(stack.length() - 1)
          let a = stack.remove(stack.length() - 1)
          // [a, b] -> [b, a]
          stack.push(b)
          stack.push(a)
          Ok(())
        }
      BcOp::RotThree =>
        if stack.length() < 3 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let c = stack.remove(stack.length() - 1)
          let b = stack.remove(stack.length() - 1)
          let a = stack.remove(stack.length() - 1)
          // [a, b, c] -> [c, a, b]
          stack.push(c)
          stack.push(a)
          stack.push(b)
          Ok(())
        }
      BcOp::LoadConst(i) => {
        stack.push(code.consts[i])
        Ok(())
      }
      BcOp::LoadName(i) => {
        let name = code.names[i]
        match lookup_name_value(name, locals, globals, builtins) {
          Ok(v) => {
            stack.push(v)
            Ok(())
          }
          Err(err) => Err(err)
        }
      }
      BcOp::StoreName(i) => {
        let name = code.names[i]
        match pop_stack(stack) {
          Ok(v) => {
            set_scoped_value(locals, globals, name, v)
            Ok(())
          }
          Err(err) => Err(err)
        }
      }
      BcOp::DeleteName(i) => {
        let name = code.names[i]
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
      BcOp::LoadAttr(i) => {
        let attr = code.names[i]
        match pop_stack(stack) {
          Ok(target) =>
            match get_attr_from_value(target, attr, globals, builtins, io) {
              Ok(v) => {
                stack.push(v)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      }
      BcOp::StoreAttr(i) => {
        let attr = code.names[i]
        match pop_stack(stack) {
          Ok(value) =>
            match pop_stack(stack) {
              Ok(target) =>
                match
                  set_attr_on_value(target, attr, value, globals, builtins, io) {
                  Ok(_) => Ok(())
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      }
      BcOp::LoadSubscr =>
        match pop_stack(stack) {
          Ok(index) =>
            match pop_stack(stack) {
              Ok(target) =>
                match get_subscr_value(target, index, globals, builtins, io) {
                  Ok(v) => {
                    stack.push(v)
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::StoreSubscr =>
        match pop_stack(stack) {
          Ok(value) =>
            match pop_stack(stack) {
              Ok(index) =>
                match pop_stack(stack) {
                  Ok(target) =>
                    match
                      set_subscr_value(
                        target, index, value, globals, builtins, io,
                      ) {
                      Ok(_) => Ok(())
                      Err(err) => Err(err)
                    }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
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
      BcOp::BuildMap(pair_count) =>
        match pop_n(stack, pair_count * 2) {
          Ok(values) => {
            let out : Array[(Value, Value)] = []
            for i = 0; i < values.length(); i = i + 2 {
              out.push((values[i], values[i + 1]))
            }
            stack.push(Value::Dict(out))
            Ok(())
          }
          Err(err) => Err(err)
        }
      BcOp::GetIter =>
        match pop_stack(stack) {
          Ok(value) =>
            match iter_value_to_iterator(value, globals, builtins, io) {
              Ok(iter) => {
                stack.push(iter)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::ForIter(target) =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
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
      BcOp::Unary(op) =>
        match pop_stack(stack) {
          Ok(value) =>
            match unary_op_value(op, value, globals, builtins, io) {
              Ok(out) => {
                stack.push(out)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Binary(op) =>
        match pop_stack(stack) {
          Ok(right) =>
            match pop_stack(stack) {
              Ok(left) =>
                match
                  eval_binary_op_values(op, left, right, globals, builtins, io) {
                  Ok(out) => {
                    stack.push(out)
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Compare(op) =>
        match pop_stack(stack) {
          Ok(right) =>
            match pop_stack(stack) {
              Ok(left) =>
                match
                  compare_values_with_env(
                    op, left, right, globals, builtins, io,
                  ) {
                  Ok(ok) => {
                    stack.push(Value::Bool(ok))
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Jump(target) => {
        next_pc = target
        Ok(())
      }
      BcOp::UnwindJump(target, n) =>
        if n <= 0 {
          next_pc = target
          Ok(())
        } else {
          pending_jump_target = Some(target)
          pending_jump_count = n
          match vm_unwind_return(stack, blocks) {
            Some(handler) => {
              next_pc = handler
              Ok(())
            }
            None => {
              pending_jump_target = None
              pending_jump_count = 0
              next_pc = target
              Ok(())
            }
          }
        }
      BcOp::JumpIfFalse(target) =>
        match pop_stack(stack) {
          Ok(v) =>
            match truthy_from_value_with_env(v, globals, builtins, io) {
              Ok(ok) => {
                if !ok {
                  next_pc = target
                }
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::JumpIfTrue(target) =>
        match pop_stack(stack) {
          Ok(v) =>
            match truthy_from_value_with_env(v, globals, builtins, io) {
              Ok(ok) => {
                if ok {
                  next_pc = target
                }
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::JumpIfFalseOrPop(target) =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let v = stack[stack.length() - 1]
          match truthy_from_value_with_env(v, globals, builtins, io) {
            Ok(ok) => {
              if !ok {
                next_pc = target
              } else {
                let _ = stack.remove(stack.length() - 1)

              }
              Ok(())
            }
            Err(err) => Err(err)
          }
        }
      BcOp::JumpIfTrueOrPop(target) =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let v = stack[stack.length() - 1]
          match truthy_from_value_with_env(v, globals, builtins, io) {
            Ok(ok) => {
              if ok {
                next_pc = target
              } else {
                let _ = stack.remove(stack.length() - 1)

              }
              Ok(())
            }
            Err(err) => Err(err)
          }
        }
      BcOp::SetupExcept(target) => {
        blocks.push(VmBlock::{
          kind: VmBlockKind::Except(target),
          stack_height: stack.length(),
        })
        Ok(())
      }
      BcOp::SetupFinally(target) => {
        blocks.push(VmBlock::{
          kind: VmBlockKind::Finally(target),
          stack_height: stack.length(),
        })
        Ok(())
      }
      BcOp::PopExcept =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::Except(_) => Ok(())
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: PopExcept on non-except block".to_string(),
                ),
              )
          }
        }
      BcOp::EnterFinally(target) =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::Finally(_) => {
              blocks.push(VmBlock::{
                kind: VmBlockKind::FinallyHandler,
                stack_height: blk.stack_height,
              })
              next_pc = target
              Ok(())
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: EnterFinally on non-finally block".to_string(),
                ),
              )
          }
        }
      BcOp::EndExcept =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::ExceptHandler => {
              pending_exc = None
              Ok(())
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: EndExcept on non-handler block".to_string(),
                ),
              )
          }
        }
      BcOp::EndFinally =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::FinallyHandler =>
              match pending_return {
                Some(v) =>
                  match vm_unwind_return(stack, blocks) {
                    Some(target) => {
                      next_pc = target
                      Ok(())
                    }
                    None => {
                      pending_return = None
                      if span is Some(_) {
                        pop_active_span()
                      }
                      return Ok(v)
                    }
                  }
                None =>
                  match pending_jump_target {
                    Some(target) => {
                      pending_jump_count = pending_jump_count - 1
                      if pending_jump_count <= 0 {
                        pending_jump_target = None
                        pending_jump_count = 0
                        next_pc = target
                        Ok(())
                      } else {
                        match vm_unwind_return(stack, blocks) {
                          Some(handler) => {
                            next_pc = handler
                            Ok(())
                          }
                          None => {
                            // Inconsistent unwind count; fall back to the jump.
                            pending_jump_target = None
                            pending_jump_count = 0
                            next_pc = target
                            Ok(())
                          }
                        }
                      }
                    }
                    None =>
                      match pending_exc {
                        Some(err) => Err(err)
                        None => Ok(())
                      }
                  }
              }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: EndFinally on non-handler block".to_string(),
                ),
              )
          }
        }
      BcOp::CheckExceptionMatch =>
        match pop_stack(stack) {
          Ok(exc_value) =>
            match pending_exc {
              Some(err) =>
                match handler_classes_from_value(exc_value, builtins) {
                  Ok(handler_classes) => {
                    let mut matches = false
                    let mut match_error : RuntimeError? = None
                    for klass in handler_classes {
                      match exception_matches_handler(err, klass, builtins) {
                        Ok(true) => {
                          matches = true
                          break
                        }
                        Ok(false) => ()
                        Err(e) => {
                          match_error = Some(e)
                          break
                        }
                      }
                    }
                    match match_error {
                      Some(e) => Err(e)
                      None => {
                        stack.push(Value::Bool(matches))
                        Ok(())
                      }
                    }
                  }
                  Err(e) => Err(e)
                }
              None =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: no pending exception".to_string(),
                  ),
                )
            }
          Err(err) => Err(err)
        }
      BcOp::LoadException =>
        match pending_exc {
          Some(err) => {
            let v = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            stack.push(v)
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::HasPendingException => {
        stack.push(Value::Bool(pending_exc is Some(_)))
        Ok(())
      }
      BcOp::ClearPendingException => {
        pending_exc = None
        Ok(())
      }
      BcOp::LoadExceptionType =>
        match pending_exc {
          Some(err) => {
            let exc_value = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            let exc_type_value = match exc_value {
              Value::Instance(inst) => Value::Class(inst.class)
              _ => Value::Str(err.exc_type)
            }
            stack.push(exc_type_value)
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::LoadExceptionTypeName =>
        match pending_exc {
          Some(err) => {
            stack.push(Value::Str(err.exc_type))
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::LoadExceptionTraceback =>
        match pending_exc {
          Some(err) => {
            stack.push(vm_make_traceback_value(err.traceback))
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::Reraise =>
        match pending_exc {
          Some(e) => Err(e)
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::Await =>
        match pop_stack(stack) {
          Ok(coro) =>
            match coroutine_await(coro) {
              Ok(v) => {
                stack.push(v)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::CallFunction(argc) =>
        match pop_n(stack, argc) {
          Ok(args) =>
            match pop_stack(stack) {
              Ok(callee) =>
                match callee {
                  // Builtins need access to the caller's locals for features like
                  // zero-arg `super()`. The AST evaluator special-cases this via
                  // `eval_builtin_call`, so mirror that here.
                  Value::Function(func) if func.body.length() == 0 =>
                    match
                      eval_builtin_call(
                        func.name,
                        args,
                        [],
                        locals,
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(Some(out)) => {
                        stack.push(out)
                        Ok(())
                      }
                      Ok(None) =>
                        match
                          call_callable_with_env(
                            Value::Function(func),
                            args,
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(out) => {
                            stack.push(out)
                            Ok(())
                          }
                          Err(err) => Err(err)
                        }
                      Err(err) => Err(err)
                    }
                  _ =>
                    match
                      call_callable_with_env(
                        callee,
                        args,
                        [],
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(out) => {
                        stack.push(out)
                        Ok(())
                      }
                      Err(err) => Err(err)
                    }
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::MakeFunction(template, default_count, decorator_count) =>
        match pop_n(stack, default_count) {
          Ok(defaults) =>
            match pop_n(stack, decorator_count) {
              Ok(decorators) => {
                let template_value = code.consts[template]
                match template_value {
                  Value::Function(template_func) =>
                    match
                      make_function_from_template_with_env(
                        template_func, defaults, decorators, locals, globals, builtins,
                        io,
                      ) {
                      Ok(defined) => {
                        stack.push(defined)
                        Ok(())
                      }
                      Err(err) => Err(err)
                    }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "bytecode vm: MakeFunction template is not a function".to_string(),
                      ),
                    )
                }
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::ReturnValue =>
        match pop_stack(stack) {
          Ok(v) =>
            match vm_unwind_return(stack, blocks) {
              Some(target) => {
                pending_return = Some(v)
                next_pc = target
                Ok(())
              }
              None => {
                if span is Some(_) {
                  pop_active_span()
                }
                return Ok(v)
              }
            }
          Err(err) => Err(err)
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
      Err(err) => {
        // An exception overrides any pending return (including one in-flight from
        // an inner finally handler).
        pending_return = None
        pending_jump_target = None
        pending_jump_count = 0
        let mut handler_pc : Int? = None
        let exc = err
        // Unwind blocks until we find a handler.
        while blocks.length() > 0 {
          let blk = blocks.remove(blocks.length() - 1)
          while stack.length() > blk.stack_height {
            let _ = stack.remove(stack.length() - 1)

          }
          match blk.kind {
            VmBlockKind::Except(target) => {
              pending_exc = Some(exc)
              blocks.push(VmBlock::{
                kind: VmBlockKind::ExceptHandler,
                stack_height: stack.length(),
              })
              handler_pc = Some(target)
              break
            }
            VmBlockKind::Finally(target) => {
              pending_exc = Some(exc)
              blocks.push(VmBlock::{
                kind: VmBlockKind::FinallyHandler,
                stack_height: stack.length(),
              })
              handler_pc = Some(target)
              break
            }
            VmBlockKind::ExceptHandler => {
              // An exception raised while already in an except path.
              pending_exc = None
              continue
            }
            VmBlockKind::FinallyHandler => {
              // An exception raised while already in a finally path.
              pending_exc = None
              continue
            }
          }
        }
        match handler_pc {
          Some(target) => pc = target
          None => return Err(exc)
        }
      }
    }
  }

  // If bytecode falls off the end, return None.
  Ok(Value::None)
}
