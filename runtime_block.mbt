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
let active_exception_stack : Ref[Array[RuntimeError]] = { val: [] }

///|
fn active_exception() -> RuntimeError? {
  if active_exception_stack.val.length() == 0 {
    None
  } else {
    Some(active_exception_stack.val[active_exception_stack.val.length() - 1])
  }
}

///|
fn is_base_exception_class(klass : ClassValue) -> Result[Bool, RuntimeError] {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for cls in mro {
    if cls.name == "BaseException" {
      return Ok(true)
    }
  }
  Ok(false)
}

///|
fn ensure_exception_instance_from_value(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match value {
    Value::Instance(inst) => {
      let ok = match is_base_exception_class(inst.class) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if ok {
        Ok(Value::Instance(inst))
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "exceptions must derive from BaseException".to_string(),
          ),
        )
      }
    }
    Value::Class(klass) => {
      let ok = match is_base_exception_class(klass) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if !ok {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "exceptions must derive from BaseException".to_string(),
          ),
        )
      }
      let inst_value = match
        call_callable_with_env(
          Value::Class(klass),
          [],
          [],
          globals,
          builtins,
          io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match inst_value {
        Value::Instance(_) => Ok(inst_value)
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "exceptions must derive from BaseException".to_string(),
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "exceptions must derive from BaseException".to_string(),
        ),
      )
  }
}

///|
fn exception_matches_handler(
  err : RuntimeError,
  handler_class : ClassValue,
  builtins : Array[(String, Value)],
) -> Result[Bool, RuntimeError] {
  if handler_class.name == "Exception" || handler_class.name == "BaseException" {
    return Ok(true)
  }
  match get_named_value(builtins, err.exc_type) {
    Some(Value::Class(err_class)) => {
      let mro = match class_mro(err_class) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      for cls in mro {
        if cls.name == handler_class.name {
          return Ok(true)
        }
      }
      Ok(false)
    }
    _ => Ok(handler_class.name == err.exc_type)
  }
}

///|
fn runtime_error_from_exception_instance(inst : InstanceValue) -> RuntimeError {
  let mut message = "".to_string()
  match get_named_value(inst.dict, "message") {
    Some(Value::Str(text)) => message = text
    Some(value) => message = value_to_string(value)
    None => ()
  }
  let printed = if message.length() > 0 {
    inst.class.name + ": " + message
  } else {
    inst.class.name
  }
  let args : Array[String] = if message.length() > 0 { [message] } else { [] }
  let exc_value = if inst.class.name == "StopIteration" {
    match get_named_value(inst.dict, "args") {
      Some(Value::Tuple(values)) =>
        if values.length() > 0 {
          Some(values[0])
        } else {
          Some(Value::None)
        }
      _ => Some(Value::None)
    }
  } else {
    None
  }
  let exc_cause = match get_named_value(inst.dict, "__cause__") {
    Some(Value::None) => (None : Value?)
    Some(value) => Some(value)
    None => (None : Value?)
  }
  let exc_context = match get_named_value(inst.dict, "__context__") {
    Some(Value::None) => (None : Value?)
    Some(value) => Some(value)
    None => (None : Value?)
  }
  let exc_suppress_context = match
    get_named_value(inst.dict, "__suppress_context__") {
    Some(Value::Bool(v)) => v
    _ => false
  }
  RuntimeError::{
    kind: RuntimeErrorKind::Runtime,
    message: printed,
    span: None,
    exc_type: inst.class.name,
    exc_args: args,
    exc_value,
    exc_cause,
    exc_context,
    exc_suppress_context,
  }
}

///|
fn make_traceback_value() -> Value {
  let frame_value = Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "frame", bases: [], dict: [] },
    dict: [],
  })
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "traceback", bases: [], dict: [] },
    dict: [("tb_frame", frame_value)],
  })
}

///|
fn exception_value_from_runtime_error(
  err : RuntimeError,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let positional : Array[Value] = []
  if err.exc_type == "StopIteration" {
    match err.exc_value {
      Some(value) => positional.push(value)
      None => ()
    }
  } else {
    for arg in err.exc_args {
      positional.push(Value::Str(arg))
    }
  }
  match get_named_value(builtins, err.exc_type) {
    Some(Value::Class(klass)) =>
      match
        call_callable_with_env(
          Value::Class(klass),
          positional,
          [],
          globals,
          builtins,
          io,
        ) {
        Ok(Value::Instance(inst)) => {
          set_named_value(inst.dict, "__traceback__", make_traceback_value())
          set_named_value(
            inst.dict,
            "__cause__",
            match err.exc_cause {
              Some(v) => v
              None => Value::None
            },
          )
          set_named_value(
            inst.dict,
            "__context__",
            match err.exc_context {
              Some(v) => v
              None => Value::None
            },
          )
          set_named_value(
            inst.dict,
            "__suppress_context__",
            Value::Bool(err.exc_suppress_context),
          )
          Value::Instance(inst)
        }
        _ => Value::Str(format_runtime_error(err))
      }
    _ => Value::Str(format_runtime_error(err))
  }
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
      Stmt::AugAssign(target~, op~, value~) => {
        let right_val = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Target::Name(name) => {
            let current = if scope_name_is_global(name) {
              match get_global_value(globals, name) {
                Some(value) => value
                None =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Name,
                      "name '" + name + "' is not defined",
                    ),
                  )
              }
            } else {
              match get_from_env(name, locals, globals, builtins) {
                Some(value) => value
                None =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Name,
                      "name '" + name + "' is not defined",
                    ),
                  )
              }
            }
            let next = match
              eval_binary_op_values(
                op, current, right_val, globals, builtins, io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            set_scoped_value(locals, globals, name, next)
          }
          Target::Attribute(value~, attr~) => {
            let base = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let current = match get_attr_from_value(base, attr) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let next = match
              eval_binary_op_values(
                op, current, right_val, globals, builtins, io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = match set_attr_on_value(base, attr, next) {
              Ok(value) => value
              Err(err) => return Err(err)
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
                let current = values[norm]
                let next = match
                  eval_binary_op_values(
                    op, current, right_val, globals, builtins, io,
                  ) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                values[norm] = next
              }
              Value::Dict(pairs) => {
                let mut found : Int? = None
                for i = 0; i < pairs.length(); i = i + 1 {
                  if eq_value(pairs[i].0, index_value) {
                    found = Some(i)
                    break
                  }
                }
                if found is None {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Key,
                      "key not found".to_string(),
                    ),
                  )
                }
                let i = found.unwrap()
                let current = pairs[i].1
                let next = match
                  eval_binary_op_values(
                    op, current, right_val, globals, builtins, io,
                  ) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                pairs[i] = (pairs[i].0, next)
              }
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "object does not support item assignment".to_string(),
                  ),
                )
            }
          }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "unsupported augmented assignment target".to_string(),
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
          return Ok(BlockFlow::Return(value))
        }
        return Ok(BlockFlow::Return(Value::None))
      }
      Stmt::Yield(_) | Stmt::YieldFrom(_) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'yield' outside function".to_string(),
          ),
        )
      Stmt::Function(
        name~,
        decorators~,
        params~,
        defaults~,
        body~,
        is_generator~,
        is_async~
      ) => {
        let default_values : Array[Value] = []
        for expr in defaults {
          let value = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          default_values.push(value)
        }
        let func = FunctionValue::{
          name,
          params,
          defaults: default_values,
          body,
          is_generator,
          is_async,
          closure: capture_cell_closure(locals),
        }
        let decorator_values : Array[Value] = []
        for dec_expr in decorators {
          let dec_value = match
            eval_expr_with_env(dec_expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          decorator_values.push(dec_value)
        }
        let mut defined : Value = Value::Function(func)
        for i = decorator_values.length(); i > 0; i = i - 1 {
          defined = match
            call_callable_with_env(
              decorator_values[i - 1],
              [defined],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        set_scoped_value(locals, globals, name, defined)
        last = Value::None
      }
      Stmt::Pass => last = Value::None
      Stmt::Global(_) => last = Value::None
      Stmt::Nonlocal(_) => last = Value::None
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
      Stmt::Raise(exc~, cause~) =>
        match exc {
          None =>
            match active_exception() {
              Some(err) => return Err(err)
              None =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "RuntimeError: No active exception to reraise".to_string(),
                  ),
                )
            }
          Some(expr) => {
            let context_err_opt = active_exception()
            let raised_value = match
              eval_expr_with_env(expr, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let inst_value = match
              ensure_exception_instance_from_value(
                raised_value, globals, builtins, io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let err0 = match inst_value {
              Value::Instance(inst) =>
                runtime_error_from_exception_instance(inst)
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "RuntimeError: invalid exception".to_string(),
                  ),
                )
            }
            let err1 = match (context_err_opt, err0.exc_context) {
              (Some(ctx_err), None) => {
                let ctx_value = exception_value_from_runtime_error(
                  ctx_err, globals, builtins, io,
                )
                RuntimeError::{
                  kind: err0.kind,
                  message: err0.message,
                  span: err0.span,
                  exc_type: err0.exc_type,
                  exc_args: err0.exc_args,
                  exc_value: err0.exc_value,
                  exc_cause: err0.exc_cause,
                  exc_context: Some(ctx_value),
                  exc_suppress_context: err0.exc_suppress_context,
                }
              }
              _ => err0
            }
            let err2 = match cause {
              None => err1
              Some(cause_expr) => {
                let cause_value = match
                  eval_expr_with_env(cause_expr, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(e) => return Err(e)
                }
                let cause_inst = match cause_value {
                  Value::None => Value::None
                  _ =>
                    match
                      ensure_exception_instance_from_value(
                        cause_value, globals, builtins, io,
                      ) {
                      Ok(v) => v
                      Err(e) => return Err(e)
                    }
                }
                RuntimeError::{
                  kind: err1.kind,
                  message: err1.message,
                  span: err1.span,
                  exc_type: err1.exc_type,
                  exc_args: err1.exc_args,
                  exc_value: err1.exc_value,
                  exc_cause: Some(cause_inst),
                  exc_context: err1.exc_context,
                  exc_suppress_context: true,
                }
              }
            }
            return Err(err2)
          }
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
          Some(name) => set_scoped_value(locals, globals, name, entered)
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
                      match exception_matches_handler(err, klass, builtins) {
                        Ok(true) => matches = true
                        Ok(false) => ()
                        Err(e) => {
                          handled = true
                          handled_result = Err(e)
                          break
                        }
                      }
                    Value::Tuple(items) =>
                      for item in items {
                        match item {
                          Value::Class(klass) =>
                            match
                              exception_matches_handler(err, klass, builtins) {
                              Ok(true) => {
                                matches = true
                                break
                              }
                              Ok(false) => ()
                              Err(e) => {
                                handled = true
                                handled_result = Err(e)
                                break
                              }
                            }
                          _ => ()
                        }
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
                  set_scoped_value(
                    locals,
                    globals,
                    name,
                    exception_value_from_runtime_error(
                      err, globals, builtins, io,
                    ),
                  )
                None => ()
              }
              active_exception_stack.val.push(err)
              let next_result = eval_block_flow(
                handler_body, locals, globals, builtins, io, loop_depth,
              )
              let _ = active_exception_stack.val.pop()
              handled_result = next_result
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
      Stmt::Class(name~, decorators~, bases~, keywords~, body~) => {
        let decorator_values : Array[Value] = []
        for dec_expr in decorators {
          let dec_value = match
            eval_expr_with_env(dec_expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          decorator_values.push(dec_value)
        }
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
        for keyword in keywords {
          let _ = match
            eval_expr_with_env(keyword.1, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }

        }
        if base_values.length() == 0 {
          for pair in builtins {
            if pair.0 == "object" {
              match pair.1 {
                Value::Class(object_class) =>
                  base_values.push(Value::Class(object_class))
                _ => ()
              }
              break
            }
          }
        }
        let module_name_value = get_global_value(globals, "__name__")
        if module_name_value is None {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Name,
              "name '__name__' is not defined",
            ),
          )
        }
        let module_name = match module_name_value.unwrap() {
          Value::Str(text) => text
          other => value_to_string(other)
        }
        let class_dict : Array[(String, Value)] = []
        class_dict.push(("__module__", Value::Str(module_name)))
        let lookup_globals : Array[(String, Value)] = []
        for pair in locals {
          lookup_globals.push(pair)
        }
        for pair in globals {
          lookup_globals.push(pair)
        }
        let flow = match
          eval_block_flow(
            body, class_dict, lookup_globals, builtins, io, loop_depth,
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
        let _ = match class_mro(klass) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let mut defined : Value = Value::Class(klass)
        for i = decorator_values.length(); i > 0; i = i - 1 {
          defined = match
            call_callable_with_env(
              decorator_values[i - 1],
              [defined],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        set_scoped_value(locals, globals, name, defined)
        last = Value::None
      }
      Stmt::While(condition~, body~, else_body~) => {
        let mut broke = false
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
            Ok(BlockFlow::Break) => {
              broke = true
              break
            }
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Err(err) => return Err(err)
          }
        }
        if !broke && else_body.length() > 0 {
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
      Stmt::For(target~, iter~, body~, else_body~) => {
        let iter_value = match
          eval_expr_with_env(iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let mut broke = false
        let iterator = match iter_value_to_iterator(iter_value) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        while true {
          let item = match iterator_next(iterator, None) {
            Ok(value) => value
            Err(err) =>
              if err.exc_type == "StopIteration" {
                break
              } else {
                return Err(err)
              }
          }
          let _ = match
            assign_target_with_env(target, item, locals, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match
            eval_block_flow(body, locals, globals, builtins, io, loop_depth + 1) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Continue) => continue
            Ok(BlockFlow::Break) => {
              broke = true
              break
            }
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Err(err) => return Err(err)
          }
        }
        if !broke && else_body.length() > 0 {
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
                previous.push(
                  (binding.0, get_scoped_value(locals, globals, binding.0)),
                )
                set_scoped_value(locals, globals, binding.0, binding.1)
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
                  set_scoped_value(locals, globals, prev.0, value)
                } else {
                  let _ = delete_scoped_value(locals, globals, prev.0)

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
