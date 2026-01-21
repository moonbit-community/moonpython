///|
/// Generator runtime (minimal, resumable).

///|
priv enum GenFrame {
  Block(body~ : Array[Stmt], index~ : Int, loop_depth~ : Int)
  AfterAssign(target~ : Target, value~ : Value)
  For(
    target~ : Target,
    iterator~ : Value,
    body~ : Array[Stmt],
    else_body~ : Array[Stmt],
    broke~ : Bool,
    done~ : Bool,
    loop_depth~ : Int
  )
  While(
    condition~ : Expr,
    body~ : Array[Stmt],
    else_body~ : Array[Stmt],
    broke~ : Bool,
    done~ : Bool,
    loop_depth~ : Int
  )
  YieldFrom(iterator~ : Value)
}

///|
priv struct GeneratorState {
  mut frames : Array[GenFrame]
  locals : Array[(String, Value)]
  globals : Array[(String, Value)]
  builtins : Array[(String, Value)]
  io : MockIO
  global_names : Array[String]
  nonlocal_names : Array[String]
  closure : Array[(String, Value)]
  name : String
  filename : String
  is_async : Bool
  mut started : Bool
  mut done : Bool
}

///|
let generator_registry : Ref[Array[Ref[GeneratorState]]] = { val: [] }

///|
fn make_generator_instance(id : Int) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "generator", bases: [], dict: [] },
    dict: [("id", Value::Int(@bigint.BigInt::from_int(id)))],
  })
}

///|
fn make_async_generator_instance(id : Int) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "async_generator", bases: [], dict: [] },
    dict: [("gen_id", Value::Int(@bigint.BigInt::from_int(id)))],
  })
}

///|
fn generator_id_from_instance(
  inst : InstanceValue,
) -> Result[Int?, RuntimeError] {
  match get_named_value(inst.dict, "id") {
    Some(Value::Int(v)) =>
      match bigint_to_int_checked(v) {
        Ok(i) => Ok(Some(i))
        Err(err) => Err(err)
      }
    Some(Value::Bool(v)) => Ok(Some(if v { 1 } else { 0 }))
    _ => Ok(None)
  }
}

///|
fn async_generator_id_from_instance(
  inst : InstanceValue,
) -> Result[Int?, RuntimeError] {
  match get_named_value(inst.dict, "gen_id") {
    Some(Value::Int(v)) =>
      match bigint_to_int_checked(v) {
        Ok(i) => Ok(Some(i))
        Err(err) => Err(err)
      }
    Some(Value::Bool(v)) => Ok(Some(if v { 1 } else { 0 }))
    _ => Ok(None)
  }
}

///|
fn generator_new(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  global_names : Array[String],
  nonlocal_names : Array[String],
  closure : Array[(String, Value)],
  name : String,
  filename : String,
) -> Value {
  let frames : Array[GenFrame] = [GenFrame::Block(body~, index=0, loop_depth=0)]
  let state : Ref[GeneratorState] = {
    val: GeneratorState::{
      frames,
      locals,
      globals,
      builtins,
      io,
      global_names,
      nonlocal_names,
      closure,
      name,
      filename,
      is_async: false,
      started: false,
      done: false,
    },
  }
  let id = generator_registry.val.length()
  generator_registry.val.push(state)
  make_generator_instance(id)
}

///|
fn async_generator_new(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  global_names : Array[String],
  nonlocal_names : Array[String],
  closure : Array[(String, Value)],
  name : String,
  filename : String,
) -> Value {
  let frames : Array[GenFrame] = [GenFrame::Block(body~, index=0, loop_depth=0)]
  let state : Ref[GeneratorState] = {
    val: GeneratorState::{
      frames,
      locals,
      globals,
      builtins,
      io,
      global_names,
      nonlocal_names,
      closure,
      name,
      filename,
      is_async: true,
      started: false,
      done: false,
    },
  }
  let id = generator_registry.val.length()
  generator_registry.val.push(state)
  make_async_generator_instance(id)
}

///|
fn is_stop_iteration(err : RuntimeError) -> Bool {
  err.exc_type == "StopIteration"
}

///|
fn generator_stop_iteration() -> RuntimeError {
  make_runtime_error(RuntimeErrorKind::Runtime, "StopIteration".to_string())
}

///|
fn generator_stop_iteration_with_value(value : Value) -> RuntimeError {
  let err = generator_stop_iteration()
  RuntimeError::{
    kind: err.kind,
    message: err.message,
    span: err.span,
    traceback: err.traceback,
    exc_type: err.exc_type,
    exc_args: err.exc_args,
    exc_value: Some(value),
    exc_cause: err.exc_cause,
    exc_context: err.exc_context,
    exc_suppress_context: err.exc_suppress_context,
  }
}

///|
fn generator_state_from_value(
  generator_value : Value,
) -> Result[Ref[GeneratorState], RuntimeError] {
  match generator_value {
    Value::Instance(inst) =>
      if inst.class.name != "generator" {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not a generator",
          ),
        )
      } else {
        let id_opt = match generator_id_from_instance(inst) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let id = match id_opt {
          Some(id) => id
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: invalid generator".to_string(),
              ),
            )
        }
        if id < 0 || id >= generator_registry.val.length() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "RuntimeError: invalid generator id".to_string(),
            ),
          )
        }
        Ok(generator_registry.val[id])
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object is not a generator".to_string(),
        ),
      )
  }
}

///|
fn async_generator_state_from_value(
  generator_value : Value,
) -> Result[Ref[GeneratorState], RuntimeError] {
  match generator_value {
    Value::Instance(inst) =>
      if inst.class.name != "async_generator" {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not an async generator",
          ),
        )
      } else {
        let id_opt = match async_generator_id_from_instance(inst) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let id = match id_opt {
          Some(id) => id
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: invalid async generator".to_string(),
              ),
            )
        }
        if id < 0 || id >= generator_registry.val.length() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "RuntimeError: invalid async generator id".to_string(),
            ),
          )
        }
        Ok(generator_registry.val[id])
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object is not an async generator".to_string(),
        ),
      )
  }
}

///|
fn generator_unwind_to_loop(
  frames : Array[GenFrame],
  is_break : Bool,
) -> Result[Unit, RuntimeError] {
  let mut i = frames.length()
  while i > 0 {
    i = i - 1
    match frames[i] {
      GenFrame::For(
        target~,
        iterator~,
        body~,
        else_body~,
        broke~,
        done~,
        loop_depth~
      ) => {
        let _ = broke
        let _ = done
        // Drop everything above the loop frame.
        while frames.length() > i + 1 {
          let _ = frames.pop()

        }
        if is_break {
          frames[i] = GenFrame::For(
            target~,
            iterator~,
            body~,
            else_body~,
            broke=true,
            done=true,
            loop_depth~,
          )
        }
        // For `continue`, no special state: execution resumes at loop header.
        return Ok(())
      }
      GenFrame::While(condition~, body~, else_body~, broke~, done~, loop_depth~) => {
        let _ = broke
        let _ = done
        while frames.length() > i + 1 {
          let _ = frames.pop()

        }
        if is_break {
          frames[i] = GenFrame::While(
            condition~,
            body~,
            else_body~,
            broke=true,
            done=true,
            loop_depth~,
          )
        }
        return Ok(())
      }
      _ => ()
    }
  }
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      if is_break {
        "SyntaxError: 'break' outside loop".to_string()
      } else {
        "SyntaxError: 'continue' not properly in loop".to_string()
      },
    ),
  )
}

///|
fn generator_step_statement(
  stmt : Stmt,
  state : Ref[GeneratorState],
  loop_depth : Int,
) -> Result[Value?, RuntimeError] {
  match stmt {
    Stmt::WithSpan(span~, stmt~) => {
      push_active_span(span)
      let result = generator_step_statement(stmt, state, loop_depth)
      pop_active_span()
      result
    }
    Stmt::ExprStmt(expr) => {
      match expr {
        Expr::YieldFrom(inner) => {
          let iter_value = match
            eval_expr_with_env(
              inner,
              state.val.locals,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let iterator = match
            iter_value_to_iterator(
              iter_value,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          state.val.frames.push(GenFrame::YieldFrom(iterator~))
          return Ok(None)
        }
        Expr::Yield(expr_opt) => {
          let value = match expr_opt {
            Some(inner) =>
              match
                eval_expr_with_env(
                  inner,
                  state.val.locals,
                  state.val.globals,
                  state.val.builtins,
                  state.val.io,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          return Ok(Some(value))
        }
        _ => ()
      }
      let _ = match
        eval_expr_with_env(
          expr,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(None)
    }
    Stmt::Assign(target~, value~) => {
      match value {
        Expr::YieldFrom(inner) => {
          let iter_value = match
            eval_expr_with_env(
              inner,
              state.val.locals,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let iterator = match
            iter_value_to_iterator(
              iter_value,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          state.val.frames.push(
            GenFrame::AfterAssign(target~, value=Value::None),
          )
          state.val.frames.push(GenFrame::YieldFrom(iterator~))
          return Ok(None)
        }
        Expr::Yield(expr_opt) => {
          let yield_value = match expr_opt {
            Some(inner) =>
              match
                eval_expr_with_env(
                  inner,
                  state.val.locals,
                  state.val.globals,
                  state.val.builtins,
                  state.val.io,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          state.val.frames.push(
            GenFrame::AfterAssign(target~, value=Value::None),
          )
          return Ok(Some(yield_value))
        }
        _ => ()
      }
      let eval_value = match
        eval_expr_with_env(
          value,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let _ = match
        assign_target_with_env(
          target,
          eval_value,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(None)
    }
    Stmt::AugAssign(target~, op~, value~) => {
      let right_val = match
        eval_expr_with_env(
          value,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match target {
        Target::Name(name) => {
          let current = match
            lookup_name_value(
              name,
              state.val.locals,
              state.val.globals,
              state.val.builtins,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let next = match
            eval_binary_op_values(
              op,
              current,
              right_val,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          set_scoped_value(state.val.locals, state.val.globals, name, next)
          Ok(None)
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "augmented assignment target not supported in generator".to_string(),
            ),
          )
      }
    }
    Stmt::Return(expr_opt) => {
      let value = match expr_opt {
        Some(expr) =>
          match
            eval_expr_with_env(
              expr,
              state.val.locals,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        None => Value::None
      }
      Err(generator_stop_iteration_with_value(value))
    }
    Stmt::Yield(expr_opt) => {
      let value = match expr_opt {
        Some(expr) =>
          match
            eval_expr_with_env(
              expr,
              state.val.locals,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        None => Value::None
      }
      Ok(Some(value))
    }
    Stmt::YieldFrom(expr) => {
      let iter_value = match
        eval_expr_with_env(
          expr,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iterator = match
        iter_value_to_iterator(
          iter_value,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.val.frames.push(GenFrame::YieldFrom(iterator~))
      Ok(None)
    }
    Stmt::If(condition~, body~, else_body~) => {
      let cond_value = match
        eval_expr_with_env(
          condition,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if bool_from_value(cond_value) {
        state.val.frames.push(GenFrame::Block(body~, index=0, loop_depth~))
      } else if else_body.length() > 0 {
        state.val.frames.push(
          GenFrame::Block(body=else_body, index=0, loop_depth~),
        )
      }
      Ok(None)
    }
    Stmt::While(condition~, body~, else_body~) => {
      state.val.frames.push(
        GenFrame::While(
          condition~,
          body~,
          else_body~,
          broke=false,
          done=false,
          loop_depth~,
        ),
      )
      Ok(None)
    }
    Stmt::For(target~, iter~, body~, else_body~) => {
      let iter_value = match
        eval_expr_with_env(
          iter,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iterator = match
        iter_value_to_iterator(
          iter_value,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.val.frames.push(
        GenFrame::For(
          target~,
          iterator~,
          body~,
          else_body~,
          broke=false,
          done=false,
          loop_depth~,
        ),
      )
      Ok(None)
    }
    Stmt::Break =>
      if loop_depth > 0 {
        let _ = match generator_unwind_to_loop(state.val.frames, true) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(None)
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'break' outside loop".to_string(),
          ),
        )
      }
    Stmt::Continue =>
      if loop_depth > 0 {
        let _ = match generator_unwind_to_loop(state.val.frames, false) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(None)
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'continue' not properly in loop".to_string(),
          ),
        )
      }
    Stmt::Pass | Stmt::Global(_) | Stmt::Nonlocal(_) => Ok(None)
    Stmt::Assert(condition~, message~) => {
      let value = match
        eval_expr_with_env(
          condition,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if !bool_from_value(value) {
        let text = match message {
          Some(expr) => {
            let msg_value = match
              eval_expr_with_env(
                expr,
                state.val.locals,
                state.val.globals,
                state.val.builtins,
                state.val.io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            "AssertionError: " + value_to_string(msg_value)
          }
          None => "AssertionError: ".to_string()
        }
        return Err(make_runtime_error(RuntimeErrorKind::Runtime, text))
      }
      Ok(None)
    }
    Stmt::Raise(exc~, cause~) =>
      match exc {
        None =>
          match active_exception() {
            Some(err) => Err(err)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "RuntimeError: No active exception to reraise".to_string(),
                ),
              )
          }
        Some(expr) => {
          let context_err_opt = active_exception()
          let raised_value = match
            eval_expr_with_env(
              expr,
              state.val.locals,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let inst_value = match
            ensure_exception_instance_from_value(
              raised_value,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let err0 = match inst_value {
            Value::Instance(inst) => runtime_error_from_exception_instance(inst)
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
                ctx_err,
                state.val.globals,
                state.val.builtins,
                state.val.io,
              )
              RuntimeError::{
                kind: err0.kind,
                message: err0.message,
                span: err0.span,
                traceback: err0.traceback,
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
                eval_expr_with_env(
                  cause_expr,
                  state.val.locals,
                  state.val.globals,
                  state.val.builtins,
                  state.val.io,
                ) {
                Ok(value) => value
                Err(e) => return Err(e)
              }
              let cause_inst = match cause_value {
                Value::None => Value::None
                _ =>
                  match
                    ensure_exception_instance_from_value(
                      cause_value,
                      state.val.globals,
                      state.val.builtins,
                      state.val.io,
                    ) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
              }
              RuntimeError::{
                kind: err1.kind,
                message: err1.message,
                span: err1.span,
                traceback: err1.traceback,
                exc_type: err1.exc_type,
                exc_args: err1.exc_args,
                exc_value: err1.exc_value,
                exc_cause: Some(cause_inst),
                exc_context: err1.exc_context,
                exc_suppress_context: true,
              }
            }
          }
          Err(err2)
        }
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "statement not implemented in generator".to_string(),
        ),
      )
  }
}

///|
fn generator_resume_inner(
  state : Ref[GeneratorState],
  sent_value_in : Value,
) -> Result[Value, RuntimeError] {
  if state.val.done {
    return Err(generator_stop_iteration())
  }
  if !state.val.started {
    match sent_value_in {
      Value::None => ()
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "can't send non-None value to a just-started generator".to_string(),
          ),
        )
    }
    state.val.started = true
  }
  let mut sent_value = sent_value_in
  // Resume points only care about the sent value when the previous suspension
  // left a marker on the frame stack (yield in assignment, or yield from).
  // For plain `yield` statements, the sent value is ignored.
  if state.val.frames.length() == 0 {
    sent_value = Value::None
  } else {
    let top = state.val.frames[state.val.frames.length() - 1]
    match top {
      GenFrame::AfterAssign(..) | GenFrame::YieldFrom(..) => ()
      _ => sent_value = Value::None
    }
  }
  while true {
    if state.val.frames.length() == 0 {
      state.val.done = true
      return Err(generator_stop_iteration_with_value(Value::None))
    }
    let top_index = state.val.frames.length() - 1
    match state.val.frames[top_index] {
      GenFrame::AfterAssign(target~, value~) => {
        let _ = value
        let value_to_assign = sent_value
        sent_value = Value::None
        let _ = match
          assign_target_with_env(
            target,
            value_to_assign,
            state.val.locals,
            state.val.globals,
            state.val.builtins,
            state.val.io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let _ = state.val.frames.pop()
        continue
      }
      GenFrame::YieldFrom(iterator~) =>
        match
          iterator_send(
            iterator,
            sent_value,
            state.val.globals,
            state.val.builtins,
            state.val.io,
          ) {
          Ok(value) => return Ok(value)
          Err(err) =>
            if is_stop_iteration(err) {
              let _ = state.val.frames.pop()
              let stop_value = match err.exc_value {
                Some(value) => value
                None => Value::None
              }
              if state.val.frames.length() > 0 {
                let next_top = state.val.frames[state.val.frames.length() - 1]
                match next_top {
                  GenFrame::AfterAssign(..) => sent_value = stop_value
                  _ => sent_value = Value::None
                }
              } else {
                sent_value = Value::None
              }
              continue
            } else {
              state.val.done = true
              return Err(err)
            }
        }
      GenFrame::Block(body~, index~, loop_depth~) => {
        if index >= body.length() {
          let _ = state.val.frames.pop()
          continue
        }
        state.val.frames[top_index] = GenFrame::Block(
          body~,
          index=index + 1,
          loop_depth~,
        )
        let stmt = body[index]
        match generator_step_statement(stmt, state, loop_depth) {
          Ok(Some(yielded)) => return Ok(yielded)
          Ok(None) => continue
          Err(err) => {
            if is_stop_iteration(err) {
              state.val.done = true
              state.val.frames = []
            }
            return Err(err)
          }
        }
      }
      GenFrame::For(
        target~,
        iterator~,
        body~,
        else_body~,
        broke~,
        done~,
        loop_depth~
      ) => {
        if done {
          let _ = state.val.frames.pop()
          continue
        }
        match
          iterator_next(
            iterator,
            None,
            state.val.globals,
            state.val.builtins,
            state.val.io,
          ) {
          Ok(item) => {
            let _ = match
              assign_target_with_env(
                target,
                item,
                state.val.locals,
                state.val.globals,
                state.val.builtins,
                state.val.io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            state.val.frames.push(
              GenFrame::Block(body~, index=0, loop_depth=loop_depth + 1),
            )
            continue
          }
          Err(err) =>
            if is_stop_iteration(err) {
              state.val.frames[top_index] = GenFrame::For(
                target~,
                iterator~,
                body~,
                else_body~,
                broke~,
                done=true,
                loop_depth~,
              )
              if !broke && else_body.length() > 0 {
                state.val.frames.push(
                  GenFrame::Block(body=else_body, index=0, loop_depth~),
                )
              }
              continue
            } else {
              state.val.done = true
              return Err(err)
            }
        }
      }
      GenFrame::While(condition~, body~, else_body~, broke~, done~, loop_depth~) => {
        if done {
          let _ = state.val.frames.pop()
          continue
        }
        let cond_value = match
          eval_expr_with_env(
            condition,
            state.val.locals,
            state.val.globals,
            state.val.builtins,
            state.val.io,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if bool_from_value(cond_value) {
          state.val.frames.push(
            GenFrame::Block(body~, index=0, loop_depth=loop_depth + 1),
          )
          continue
        }
        state.val.frames[top_index] = GenFrame::While(
          condition~,
          body~,
          else_body~,
          broke~,
          done=true,
          loop_depth~,
        )
        if !broke && else_body.length() > 0 {
          state.val.frames.push(
            GenFrame::Block(body=else_body, index=0, loop_depth~),
          )
        }
        continue
      }
    }
  }
  Err(generator_stop_iteration())
}

///|
fn generator_resume(
  state : Ref[GeneratorState],
  sent_value_in : Value,
) -> Result[Value, RuntimeError] {
  push_traceback_frame(state.val.name, state.val.filename)
  push_closure_env(state.val.closure)
  push_scope_decls_with_nonlocals(
    state.val.global_names,
    state.val.nonlocal_names,
  )
  if state.val.is_async {
    coroutine_enter_context()
  }
  let result = generator_resume_inner(state, sent_value_in)
  if state.val.is_async {
    coroutine_leave_context()
  }
  pop_scope_decls()
  pop_closure_env()
  pop_traceback_frame()
  result
}

///|
fn generator_next(
  generator_value : Value,
  default_value : Value?,
) -> Result[Value, RuntimeError] {
  let state = match generator_state_from_value(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match generator_resume(state, Value::None) {
    Ok(value) => Ok(value)
    Err(err) =>
      if is_stop_iteration(err) {
        match default_value {
          Some(v) => Ok(v)
          None => Err(err)
        }
      } else {
        Err(err)
      }
  }
}

///|
fn generator_send(
  generator_value : Value,
  value : Value,
) -> Result[Value, RuntimeError] {
  let state = match generator_state_from_value(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  generator_resume(state, value)
}

///|
fn generator_close(generator_value : Value) -> Result[Value, RuntimeError] {
  let state = match generator_state_from_value(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  state.val.done = true
  state.val.frames = []
  Ok(Value::None)
}

///|
fn generator_throw(
  generator_value : Value,
  exc : Value,
) -> Result[Value, RuntimeError] {
  let _ = match generator_close(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let err = match exc {
    Value::Instance(inst) => runtime_error_from_exception_instance(inst)
    Value::Class(klass) =>
      make_runtime_error(RuntimeErrorKind::Runtime, klass.name)
    Value::Str(text) => make_runtime_error(RuntimeErrorKind::Runtime, text)
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "exceptions must derive from BaseException".to_string(),
        ),
      )
  }
  Err(err)
}

///|
fn async_generator_stop_iteration() -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Runtime,
    "StopAsyncIteration".to_string(),
  )
}

///|
fn async_generator_next(generator_value : Value) -> Result[Value, RuntimeError] {
  let state = match async_generator_state_from_value(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match generator_resume(state, Value::None) {
    Ok(value) => Ok(value)
    Err(err) =>
      if is_stop_iteration(err) {
        Err(async_generator_stop_iteration())
      } else {
        Err(err)
      }
  }
}

///|
fn async_generator_send(
  generator_value : Value,
  value : Value,
) -> Result[Value, RuntimeError] {
  let state = match async_generator_state_from_value(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match generator_resume(state, value) {
    Ok(value) => Ok(value)
    Err(err) =>
      if is_stop_iteration(err) {
        Err(async_generator_stop_iteration())
      } else {
        Err(err)
      }
  }
}

///|
fn async_generator_close(
  generator_value : Value,
) -> Result[Value, RuntimeError] {
  let state = match async_generator_state_from_value(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  state.val.done = true
  state.val.frames = []
  Ok(Value::None)
}

///|
fn async_generator_throw(
  generator_value : Value,
  exc : Value,
) -> Result[Value, RuntimeError] {
  let _ = match async_generator_close(generator_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let err = match exc {
    Value::Instance(inst) => runtime_error_from_exception_instance(inst)
    Value::Class(klass) =>
      make_runtime_error(RuntimeErrorKind::Runtime, klass.name)
    Value::Str(text) => make_runtime_error(RuntimeErrorKind::Runtime, text)
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "exceptions must derive from BaseException".to_string(),
        ),
      )
  }
  Err(err)
}

///|
fn async_generator_make_anext_coroutine(
  generator_value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let body : Array[Stmt] = [
    Stmt::Return(
      Some(
        Expr::Call(callee=Expr::Name("__mpython_asyncgen_next"), args=[
          Expr::Name("self"),
        ]),
      ),
    ),
  ]
  let locals : Array[(String, Value)] = [("self", generator_value)]
  let filename = current_traceback_filename()
  coroutine_new(
    body,
    locals,
    globals,
    builtins,
    io,
    [],
    [],
    [],
    "<asyncgen_anext>".to_string(),
    filename,
    Config::default(),
  )
}

///|
fn async_generator_make_asend_coroutine(
  generator_value : Value,
  send_value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let body : Array[Stmt] = [
    Stmt::Return(
      Some(
        Expr::Call(callee=Expr::Name("__mpython_asyncgen_send"), args=[
          Expr::Name("self"),
          Expr::Name("value"),
        ]),
      ),
    ),
  ]
  let locals : Array[(String, Value)] = [
    ("self", generator_value),
    ("value", send_value),
  ]
  let filename = current_traceback_filename()
  coroutine_new(
    body,
    locals,
    globals,
    builtins,
    io,
    [],
    [],
    [],
    "<asyncgen_asend>".to_string(),
    filename,
    Config::default(),
  )
}

///|
fn async_generator_make_athrow_coroutine(
  generator_value : Value,
  exc : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let body : Array[Stmt] = [
    Stmt::Return(
      Some(
        Expr::Call(callee=Expr::Name("__mpython_asyncgen_throw"), args=[
          Expr::Name("self"),
          Expr::Name("exc"),
        ]),
      ),
    ),
  ]
  let locals : Array[(String, Value)] = [
    ("self", generator_value),
    ("exc", exc),
  ]
  let filename = current_traceback_filename()
  coroutine_new(
    body,
    locals,
    globals,
    builtins,
    io,
    [],
    [],
    [],
    "<asyncgen_athrow>".to_string(),
    filename,
    Config::default(),
  )
}

///|
fn async_generator_make_aclose_coroutine(
  generator_value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let body : Array[Stmt] = [
    Stmt::Return(
      Some(
        Expr::Call(callee=Expr::Name("__mpython_asyncgen_close"), args=[
          Expr::Name("self"),
        ]),
      ),
    ),
  ]
  let locals : Array[(String, Value)] = [("self", generator_value)]
  let filename = current_traceback_filename()
  coroutine_new(
    body,
    locals,
    globals,
    builtins,
    io,
    [],
    [],
    [],
    "<asyncgen_aclose>".to_string(),
    filename,
    Config::default(),
  )
}
