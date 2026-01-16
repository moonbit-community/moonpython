///|
/// Statement execution.

///|
priv enum BlockFlow {
  Normal(Value)
  Return(Value)
  Break
  Continue
}

///|
fn eval_block_flow(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  loop_depth : Int,
) -> Result[BlockFlow, RuntimeError] {
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
        let _ = match
          assign_target_with_env(
            target, eval_value, locals, globals, builtins, io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
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
          return Ok(BlockFlow::Return(value))
        }
        return Ok(BlockFlow::Return(Value::None))
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
            None => "AssertionError: ".to_string()
          }
          return Err(make_runtime_error(RuntimeErrorKind::Runtime, text))
        }
        last = Value::None
      }
      Stmt::Raise(expr) => {
        if expr is Some(expr) {
          let raised_value = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match raised_value {
            Value::Instance(inst) => {
              let mut message = "".to_string()
              match get_named_value(inst.dict, "message") {
                Some(Value::Str(text)) => message = text
                Some(value) => message = value_to_string(value)
                None => ()
              }
              let mut full = inst.class.name
              if message.length() > 0 {
                full = full + ": " + message
              }
              return Err(make_runtime_error(RuntimeErrorKind::Runtime, full))
            }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "RuntimeError: raised".to_string(),
                ),
              )
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
          let _ = match
            delete_target_with_env(target, locals, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }

        }
        last = Value::None
      }
      Stmt::Import(module~) =>
        if module == "math" {
          last = Value::None
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "ImportError: module " + module + " is not allowed",
            ),
          )
        }
      Stmt::With(context~, target~, body~) => {
        let ctx_value = match
          eval_expr_with_env(context, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let enter_value = match get_attr_from_value(ctx_value, "__enter__") {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let entered = match
          call_callable_with_env(enter_value, [], [], globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Some(name) => set_global_value(globals, name, entered)
          None => ()
        }
        let exit_value = match get_attr_from_value(ctx_value, "__exit__") {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let body_result = eval_block_flow(
          body, locals, globals, builtins, io, loop_depth,
        )
        match body_result {
          Ok(flow) => {
            let _ = match
              call_callable_with_env(
                exit_value,
                [Value::None, Value::None, Value::None],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match flow {
              BlockFlow::Normal(_) => {
                last = Value::None
                ()
              }
              BlockFlow::Return(value) => return Ok(BlockFlow::Return(value))
              BlockFlow::Break => return Ok(BlockFlow::Break)
              BlockFlow::Continue => return Ok(BlockFlow::Continue)
            }
          }
          Err(err) => {
            let exit_result = match
              call_callable_with_env(
                exit_value,
                [
                  Value::Str(err.exc_type),
                  Value::Str(format_runtime_error(err)),
                  Value::None,
                ],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(value) => value
              Err(e) => return Err(e)
            }
            if bool_from_value(exit_result) {
              last = Value::None
              ()
            } else {
              return Err(err)
            }
          }
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        let outcome : Result[BlockFlow, RuntimeError] = match
          eval_block_flow(body, locals, globals, builtins, io, loop_depth) {
          Ok(flow) =>
            if flow is BlockFlow::Normal(_) && else_body.length() > 0 {
              eval_block_flow(
                else_body, locals, globals, builtins, io, loop_depth,
              )
            } else {
              Ok(flow)
            }
          Err(err) => {
            let mut handled = false
            let mut handled_result : Result[BlockFlow, RuntimeError] = Err(err)
            for handler in handlers {
              let exc_expr_opt = handler.0
              let name_opt = handler.1
              let handler_body = handler.2
              let mut matches = false
              match exc_expr_opt {
                None => matches = true
                Some(expr) => {
                  let exc_value = match
                    eval_expr_with_env(expr, locals, globals, builtins, io) {
                    Ok(value) => value
                    Err(e) => {
                      handled = true
                      handled_result = Err(e)
                      break
                    }
                  }
                  match exc_value {
                    Value::Class(klass) =>
                      if klass.name == "Exception" ||
                        klass.name == "BaseException" ||
                        klass.name == err.exc_type {
                        matches = true
                      }
                    _ => ()
                  }
                }
              }
              if !matches {
                continue
              }
              handled = true
              match name_opt {
                Some(name) =>
                  set_global_value(
                    globals,
                    name,
                    Value::Str(format_runtime_error(err)),
                  )
                None => ()
              }
              handled_result = eval_block_flow(
                handler_body, locals, globals, builtins, io, loop_depth,
              )
              break
            }
            if handled {
              handled_result
            } else {
              Err(err)
            }
          }
        }

        // Always run finally when leaving the try statement.
        if finally_body.length() > 0 {
          match
            eval_block_flow(
              finally_body, locals, globals, builtins, io, loop_depth,
            ) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Ok(BlockFlow::Break) => return Ok(BlockFlow::Break)
            Ok(BlockFlow::Continue) => return Ok(BlockFlow::Continue)
            Err(err) => return Err(err)
          }
        }
        match outcome {
          Ok(flow) =>
            match flow {
              BlockFlow::Normal(_) => {
                last = Value::None
                ()
              }
              BlockFlow::Return(value) => return Ok(BlockFlow::Return(value))
              BlockFlow::Break => return Ok(BlockFlow::Break)
              BlockFlow::Continue => return Ok(BlockFlow::Continue)
            }
          Err(err) => return Err(err)
        }
      }
      Stmt::Class(name~, bases~, body~) => {
        let base_values : Array[Value] = []
        for base in bases {
          let value = match
            eval_expr_with_env(base, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match value {
            Value::Class(_) => base_values.push(value)
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "base class must be a class".to_string(),
                ),
              )
          }
        }
        let class_dict : Array[(String, Value)] = []
        let module_globals_for_lookup = globals
        let flow = match
          eval_block_flow(
            body, module_globals_for_lookup, class_dict, builtins, io, loop_depth,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match flow {
          BlockFlow::Normal(_) => ()
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "SyntaxError: invalid class body".to_string(),
              ),
            )
        }
        let klass = ClassValue::{ name, bases: base_values, dict: class_dict }
        set_global_value(globals, name, Value::Class(klass))
        last = Value::None
      }
      Stmt::While(condition~, body~) => {
        while true {
          let cond_value = match
            eval_expr_with_env(condition, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if !bool_from_value(cond_value) {
            break
          }
          match
            eval_block_flow(body, locals, globals, builtins, io, loop_depth + 1) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Continue) => continue
            Ok(BlockFlow::Break) => break
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Err(err) => return Err(err)
          }
        }
        last = Value::None
      }
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
          match
            eval_block_flow(body, locals, globals, builtins, io, loop_depth + 1) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Continue) => continue
            Ok(BlockFlow::Break) => break
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Err(err) => return Err(err)
          }
        }
        last = Value::None
      }
      Stmt::Break => {
        if loop_depth > 0 {
          return Ok(BlockFlow::Break)
        }
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'break' outside loop".to_string(),
          ),
        )
      }
      Stmt::Continue => {
        if loop_depth > 0 {
          return Ok(BlockFlow::Continue)
        }
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'continue' not properly in loop".to_string(),
          ),
        )
      }
      Stmt::Match(subject~, cases~) => {
        let subject_value = match
          eval_expr_with_env(subject, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for case in cases {
          let pattern = case.0
          let guard_expr_opt : Expr? = case.1
          let case_body = case.2
          match match_pattern(subject_value, pattern) {
            Some(bindings) => {
              let previous : Array[(String, Value?)] = []
              for binding in bindings {
                previous.push((binding.0, get_global_value(globals, binding.0)))
                set_global_value(globals, binding.0, binding.1)
              }
              let mut guard_ok = true
              if guard_expr_opt is Some(guard_expr) {
                let guard_value = match
                  eval_expr_with_env(guard_expr, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                guard_ok = bool_from_value(guard_value)
              }
              if guard_ok {
                match
                  eval_block_flow(
                    case_body, locals, globals, builtins, io, loop_depth,
                  ) {
                  Ok(BlockFlow::Normal(_)) => ()
                  Ok(BlockFlow::Return(value)) =>
                    return Ok(BlockFlow::Return(value))
                  Ok(BlockFlow::Break) => return Ok(BlockFlow::Break)
                  Ok(BlockFlow::Continue) => return Ok(BlockFlow::Continue)
                  Err(err) => return Err(err)
                }
                break
              }
              for prev in previous {
                if prev.1 is Some(value) {
                  set_global_value(globals, prev.0, value)
                } else {
                  delete_global_value(globals, prev.0)
                }
              }
            }
            None => ()
          }
        }
        last = Value::None
      }
      Stmt::If(condition~, body~, else_body~) => {
        let cond_value = match
          eval_expr_with_env(condition, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if bool_from_value(cond_value) {
          match
            eval_block_flow(body, locals, globals, builtins, io, loop_depth) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Ok(BlockFlow::Break) => return Ok(BlockFlow::Break)
            Ok(BlockFlow::Continue) => return Ok(BlockFlow::Continue)
            Err(err) => return Err(err)
          }
        } else {
          match
            eval_block_flow(
              else_body, locals, globals, builtins, io, loop_depth,
            ) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Ok(BlockFlow::Break) => return Ok(BlockFlow::Break)
            Ok(BlockFlow::Continue) => return Ok(BlockFlow::Continue)
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
  Ok(BlockFlow::Normal(last))
}

///|
fn eval_block(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match eval_block_flow(body, locals, globals, builtins, io, 0) {
    Ok(BlockFlow::Normal(value)) => Ok(value)
    Ok(BlockFlow::Return(value)) => Ok(value)
    Ok(BlockFlow::Break) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: 'break' outside loop".to_string(),
        ),
      )
    Ok(BlockFlow::Continue) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: 'continue' not properly in loop".to_string(),
        ),
      )
    Err(err) => Err(err)
  }
}
