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
fn exception_value_matches_handler(
  exc_value : Value,
  handler_class : ClassValue,
  builtins : Array[(String, Value)],
) -> Result[Bool, RuntimeError] {
  let _ = builtins
  if handler_class.name == "Exception" || handler_class.name == "BaseException" {
    return Ok(true)
  }
  let exc_class = match exc_value {
    Value::Instance(inst) => Some(inst.class)
    Value::Class(klass) => Some(klass)
    _ => None
  }
  match exc_class {
    Some(err_class) => {
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
    None => Ok(false)
  }
}

///|
fn handler_classes_from_value(value : Value) -> Array[ClassValue] {
  let classes : Array[ClassValue] = []
  match value {
    Value::Class(klass) => classes.push(klass)
    Value::Tuple(items) =>
      for item in items {
        match item {
          Value::Class(klass) => classes.push(klass)
          _ => ()
        }
      }
    _ => ()
  }
  classes
}

///|
fn exception_group_message_value(inst : InstanceValue) -> Value {
  match get_named_value(inst.dict, "message") {
    Some(v) => v
    None => Value::Str("")
  }
}

///|
fn exception_group_exceptions(
  inst : InstanceValue,
) -> Result[Array[Value], RuntimeError] {
  match get_named_value(inst.dict, "exceptions") {
    Some(Value::List(values)) => Ok(values)
    Some(Value::Tuple(values)) => Ok(values)
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "ExceptionGroup exceptions must be a list".to_string(),
        ),
      )
  }
}

///|
fn exception_group_make(
  klass : ClassValue,
  message : Value,
  exceptions : Array[Value],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  call_callable_with_env(
    Value::Class(klass),
    [message, Value::List(exceptions)],
    [],
    globals,
    builtins,
    io,
  )
}

///|
fn exception_group_split_by_classes(
  group_value : Value,
  handler_classes : Array[ClassValue],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[(Value?, Value?), RuntimeError] {
  if handler_classes.length() == 0 {
    return Ok((None, Some(group_value)))
  }
  let inst = match group_value {
    Value::Instance(inst) => inst
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "except* requires an ExceptionGroup".to_string(),
        ),
      )
  }
  if inst.class.name != "ExceptionGroup" &&
    inst.class.name != "BaseExceptionGroup" {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "except* requires an ExceptionGroup".to_string(),
      ),
    )
  }
  let exceptions = match exception_group_exceptions(inst) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let matched : Array[Value] = []
  let remaining : Array[Value] = []
  for exc in exceptions {
    let mut is_match = false
    for klass in handler_classes {
      match exception_value_matches_handler(exc, klass, builtins) {
        Ok(true) => {
          is_match = true
          break
        }
        Ok(false) => ()
        Err(err) => return Err(err)
      }
    }
    if is_match {
      matched.push(exc)
    } else {
      remaining.push(exc)
    }
  }
  if matched.length() == 0 {
    return Ok((None, Some(group_value)))
  }
  let message = exception_group_message_value(inst)
  let matched_group = match
    exception_group_make(inst.class, message, matched, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let remaining_group = if remaining.length() > 0 {
    match
      exception_group_make(
        inst.class,
        message,
        remaining,
        globals,
        builtins,
        io,
      ) {
      Ok(v) => Some(v)
      Err(err) => return Err(err)
    }
  } else {
    None
  }
  Ok((Some(matched_group), remaining_group))
}

///|
fn exception_group_from_runtime_error(
  err : RuntimeError,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let err_value = exception_value_from_runtime_error(err, globals, builtins, io)
  if err.exc_type == "ExceptionGroup" || err.exc_type == "BaseExceptionGroup" {
    match err_value {
      Value::Instance(inst) => return Ok(Value::Instance(inst))
      _ => ()
    }
  }
  let exc_value = match
    ensure_exception_instance_from_value(err_value, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match get_named_value(builtins, "ExceptionGroup") {
    Some(Value::Class(klass)) =>
      exception_group_make(
        klass,
        Value::Str(""),
        [exc_value],
        globals,
        builtins,
        io,
      )
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: ExceptionGroup is not available".to_string(),
        ),
      )
  }
}

///|
fn runtime_error_from_exception_instance(inst : InstanceValue) -> RuntimeError {
  fn kind_from_exception_name(name : String) -> RuntimeErrorKind {
    match name {
      "ZeroDivisionError" => RuntimeErrorKind::ZeroDivision
      "NameError" | "UnboundLocalError" => RuntimeErrorKind::Name
      "TypeError" => RuntimeErrorKind::Type
      "AttributeError" => RuntimeErrorKind::Attribute
      "IndexError" => RuntimeErrorKind::Index
      "KeyError" => RuntimeErrorKind::Key
      "NotImplementedError" => RuntimeErrorKind::NotImplemented
      _ => RuntimeErrorKind::Runtime
    }
  }

  let mut message = "".to_string()
  match get_named_value(inst.dict, "message") {
    Some(Value::Str(text)) => message = text
    Some(value) => message = value_to_string(value)
    None => ()
  }
  let kind = kind_from_exception_name(inst.class.name)
  // `RuntimeErrorKind` controls how we format errors. For "structured" kinds
  // (TypeError/AttributeError/...), keep `message` as the payload only; for
  // generic runtime errors, keep the fully-qualified "ExcType: msg" form.
  let printed = match kind {
    RuntimeErrorKind::Runtime =>
      if message.length() > 0 {
        inst.class.name + ": " + message
      } else {
        inst.class.name
      }
    _ => message
  }
  let args : Array[String] = if message.length() > 0 { [message] } else { [] }
  let exc_value : Value? = Some(Value::Instance(inst))
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
    kind,
    message: printed,
    span: current_span(),
    traceback: snapshot_traceback(),
    exc_type: inst.class.name,
    exc_args: args,
    exc_value,
    exc_cause,
    exc_context,
    exc_suppress_context,
  }
}

///|
fn make_frame_value(frame : TracebackFrame) -> Value {
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
      // Used by parts of the CPython stdlib (e.g. unittest) when cleaning tracebacks.
      // We don't currently model real frame globals/locals; keep them as empty dicts.
      ("f_globals", Value::Dict([])),
      ("f_locals", Value::Dict([])),
    ],
  })
}

///|
fn make_traceback_value(frames : Array[TracebackFrame]) -> Value {
  if frames.length() == 0 {
    // Some stdlib helpers expect `tb_frame.f_code` etc to exist even when the
    // interpreter doesn't have a real stack. Provide a minimal placeholder.
    let frame_value = make_frame_value(TracebackFrame::{
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
    let frame_value = make_frame_value(frame)
    let dict : Array[(String, Value)] = []
    dict.push(("tb_frame", frame_value))
    dict.push(("tb_lineno", Value::Int(@bigint.BigInt::from_int(frame.line))))
    dict.push(("tb_colno", Value::Int(@bigint.BigInt::from_int(frame.column))))
    dict.push(("tb_lasti", Value::Int(-1N)))
    dict.push(("tb_next", next_value))
    next_value = Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "traceback", bases: [], dict: [] },
      dict,
    })
  }
  next_value
}

///|
fn exception_value_from_runtime_error(
  err : RuntimeError,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  fn maybe_populate_syntax_error(
    dict : Array[(String, Value)],
    err : RuntimeError,
    globals : Array[(String, Value)],
  ) -> Unit {
    if err.exc_type != "SyntaxError" {
      return
    }
    // CPython's traceback helpers expect these fields on SyntaxError instances.
    let filename = match get_named_value(globals, "__file__") {
      Some(Value::Str(name)) => name
      _ => "<module>".to_string()
    }
    set_named_value(dict, "filename", Value::Str(filename))
    set_named_value(dict, "msg", Value::Str(err.message))
    // `traceback` and `unittest` expect this to exist even when we don't have
    // access to the full source line.
    if get_named_value(dict, "text") is None {
      set_named_value(dict, "text", Value::None)
    }
    match err.span {
      Some(span) => {
        set_named_value(
          dict,
          "lineno",
          Value::Int(@bigint.BigInt::from_int(span.line)),
        )
        set_named_value(
          dict,
          "offset",
          Value::Int(@bigint.BigInt::from_int(span.column)),
        )
        set_named_value(
          dict,
          "end_lineno",
          Value::Int(@bigint.BigInt::from_int(span.line)),
        )
        set_named_value(
          dict,
          "end_offset",
          Value::Int(@bigint.BigInt::from_int(span.column)),
        )
      }
      None => ()
    }
  }

  match err.exc_value {
    Some(Value::Instance(inst)) => {
      // Keep the existing exception object, but sync core metadata so
      // context managers (assertRaises, etc.) see a proper exc_type/value/tb.
      set_named_value(
        inst.dict,
        "__traceback__",
        make_traceback_value(err.traceback),
      )
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
      maybe_populate_syntax_error(inst.dict, err, globals)
      return Value::Instance(inst)
    }
    _ => ()
  }
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
          set_named_value(
            inst.dict,
            "__traceback__",
            make_traceback_value(err.traceback),
          )
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
          maybe_populate_syntax_error(inst.dict, err, globals)
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
  config : Config,
  loop_depth : Int,
) -> Result[BlockFlow, RuntimeError] {
  let mut last = Value::None
  for stmt in body {
    match stmt {
      Stmt::WithSpan(span~, stmt~) => {
        push_active_span(span)
        let result = eval_block_flow(
          [stmt],
          locals,
          globals,
          builtins,
          io,
          config,
          loop_depth,
        )
        pop_active_span()
        match result {
          Ok(BlockFlow::Normal(value)) => last = value
          Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
          Ok(BlockFlow::Break) => return Ok(BlockFlow::Break)
          Ok(BlockFlow::Continue) => return Ok(BlockFlow::Continue)
          Err(err) => return Err(err)
        }
      }
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
      Stmt::AnnAssign(target~, annotation~, value~) => {
        match target {
          Target::Name(name) => {
            // Only simple-name annotations contribute to __annotations__.
            // For attribute/subscript targets (e.g. `self.x: T = ...`), CPython
            // does not evaluate/store the annotation at runtime.
            let ann_value = match
              eval_expr_with_env(annotation, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let pairs = match
              get_scoped_value(locals, globals, "__annotations__") {
              Some(Value::Dict(pairs)) => pairs
              Some(_) =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "__annotations__ must be a dict".to_string(),
                  ),
                )
              None => {
                let pairs : Array[(Value, Value)] = []
                set_scoped_value(
                  locals,
                  globals,
                  "__annotations__",
                  Value::Dict(pairs),
                )
                pairs
              }
            }
            let _ = match dict_set_item(pairs, Value::Str(name), ann_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          _ => ()
        }
        match value {
          Some(expr) => {
            let eval_value = match
              eval_expr_with_env(expr, locals, globals, builtins, io) {
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

          }
          None => ()
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
            let current = match
              lookup_name_value(name, locals, globals, builtins) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let next = match
              eval_augassign_op_values(
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
            let current = match
              get_attr_from_value(base, attr, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let next = match
              eval_augassign_op_values(
                op, current, right_val, globals, builtins, io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = match
              set_attr_on_value(base, attr, next, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          Target::Subscript(value~, index~) => {
            let container = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match container {
              Value::List(values) => {
                match index {
                  Expr::Slice(start~, end~, step~) => {
                    let start_value = match start {
                      Some(expr) =>
                        match eval_expr_with_env(expr, locals, globals, builtins, io) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      None => Value::None
                    }
                    let end_value = match end {
                      Some(expr) =>
                        match eval_expr_with_env(expr, locals, globals, builtins, io) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      None => Value::None
                    }
                    let step_value = match step {
                      Some(expr) =>
                        match eval_expr_with_env(expr, locals, globals, builtins, io) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      None => Value::None
                    }
                    let indices = match
                      slice_indices_from_values(
                        values.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    let current = Value::List(slice_values_by_indices(values, indices))
                    let next = match
                      eval_augassign_op_values(
                        op, current, right_val, globals, builtins, io,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    let new_items = match iterable_values(next) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    let (start_i, end_i, step_i) = match
                      slice_params_from_values(
                        values.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    if step_i == 1 {
                      let merged : Array[Value] = []
                      for i = 0; i < start_i; i = i + 1 {
                        merged.push(values[i])
                      }
                      for item in new_items {
                        merged.push(item)
                      }
                      for i = end_i; i < values.length(); i = i + 1 {
                        merged.push(values[i])
                      }
                      replace_array_values(values, merged)
                    } else {
                      if new_items.length() != indices.length() {
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "ValueError: attempt to assign sequence of size " +
                            new_items.length().to_string() +
                            " to extended slice of size " +
                            indices.length().to_string(),
                          ),
                        )
                      }
                      for i = 0; i < indices.length(); i = i + 1 {
                        values[indices[i]] = new_items[i]
                      }
                    }
                  }
                  _ => {
                    let index_value = match
                      eval_expr_with_env(index, locals, globals, builtins, io) {
                      Ok(value) => value
                      Err(err) => return Err(err)
                    }
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
                      eval_augassign_op_values(
                        op, current, right_val, globals, builtins, io,
                      ) {
                      Ok(value) => value
                      Err(err) => return Err(err)
                    }
                    values[norm] = next
                  }
                }
              }
              Value::Dict(pairs) => {
                let index_value = match
                  eval_expr_with_env(index, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
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
                  eval_augassign_op_values(
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
      Stmt::TypeAlias(name~, type_params~, value~) => {
        let _ = type_params
        let _ = value
        set_scoped_value(locals, globals, name, Value::None)
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
        type_params~,
        params~,
        defaults~,
        body~,
        is_generator~,
        is_async~
      ) => {
        let _ = type_params
        let default_values : Array[Value] = []
        for expr in defaults {
          let value = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          default_values.push(value)
        }
        let (global_names, nonlocal_names) = collect_scope_decl_names(body)
        let _ = match
          check_scope_decl_conflicts(params, global_names, nonlocal_names) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let extra_cells : Array[(String, Value)] = []
        for nonlocal_name in nonlocal_names {
          match get_local_value(locals, nonlocal_name) {
            Some(v) =>
              ensure_local_cell(locals, nonlocal_name, deref_cell_value(v))
            None =>
              match lookup_closure_cell(nonlocal_name) {
                Some(cell) => extra_cells.push((nonlocal_name, cell))
                None =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "SyntaxError: no binding for nonlocal '" +
                      nonlocal_name +
                      "' found",
                    ),
                  )
              }
          }
        }
        let inherited = merge_cell_closures(current_closure_env(), extra_cells)
        let closure = merge_cell_closures(locals, inherited)
        let globals_marker = Value::Instance(InstanceValue::{
          class: ClassValue::{
            name: "__mpython_globals__",
            bases: [],
            dict: [],
          },
          dict: globals,
        })
        closure.push(("$__mpython_globals__", globals_marker))
        let func = FunctionValue::{
          name,
          params,
          defaults: default_values,
          body,
          is_generator,
          is_async,
          closure,
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
          let decorator_value = decorator_values[i - 1]
          defined = match decorator_value {
            Value::Function(dec_func) =>
              if dec_func.body.length() == 0 {
                match
                  eval_builtin_call(
                    dec_func.name,
                    [defined],
                    [],
                    locals,
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(Some(value)) => value
                  Ok(None) =>
                    match
                      call_callable_with_env(
                        decorator_value,
                        [defined],
                        [],
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(value) => value
                      Err(err) => return Err(err)
                    }
                  Err(err) => return Err(err)
                }
              } else {
                match
                  call_callable_with_env(
                    decorator_value,
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
            _ =>
              match
                call_callable_with_env(
                  decorator_value,
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
        }
        set_scoped_value(locals, globals, name, defined)
        last = Value::None
      }
      Stmt::Pass => last = Value::None
      Stmt::Global(_) => last = Value::None
      Stmt::Nonlocal(_) =>
        if !in_function_scope() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: nonlocal declaration not allowed at module level".to_string(),
            ),
          )
        } else {
          last = Value::None
        }
      Stmt::Assert(condition~, message~) => {
        let value = match
          eval_expr_with_env(condition, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let ok = match
          truthy_from_value_with_env(value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if !ok {
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
      Stmt::Import(module_name~, alias_name~) => {
        let module_value = match
          import_module(module_name, globals, builtins, io, config) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let binding = match alias_name {
          Some(name) => name
          None => module_top_name(module_name)
        }
        let binding_value = match alias_name {
          Some(_) => module_value
          None =>
            if module_name.contains(".") {
              match module_cache_get(binding) {
                Some(value) => value
                None => module_value
              }
            } else {
              module_value
            }
        }
        set_scoped_value(locals, globals, binding, binding_value)
        last = Value::None
      }
      Stmt::FromImport(module_name~, names~) => {
        let resolved_name = match
          resolve_relative_module_name(module_name, globals) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let module_value = match
          import_module(resolved_name, globals, builtins, io, config) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        for item in names {
          let name = item.0
          let alias_opt = item.1
          if name == "*" {
            match module_value {
              Value::Instance(inst) => {
                // Honor `module.__all__` when present (CPython behavior), to avoid
                // importing unrelated public globals and clobbering package module
                // references (e.g. asyncio/__init__.py relies on `base_events`,
                // `coroutines`, ... referring to submodules).
                let mut imported_any = false
                match get_named_value(inst.dict, "__all__") {
                  Some(Value::List(items)) | Some(Value::Tuple(items)) =>
                    for item in items {
                      match item {
                        Value::Str(sym) => {
                          let value = match
                            get_attr_from_value(
                              module_value, sym, globals, builtins, io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          set_scoped_value(locals, globals, sym, value)
                          imported_any = true
                        }
                        _ => ()
                      }
                    }
                  _ => ()
                }
                if !imported_any {
                  for pair in inst.dict {
                    if pair.0 != "__name__" && !pair.0.has_prefix("_") {
                      set_scoped_value(locals, globals, pair.0, pair.1)
                    }
                  }
                }
              }
              _ => ()
            }
            continue
          }
          let imported = match
            get_attr_from_value(module_value, name, globals, builtins, io) {
            Ok(value) => value
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute => {
                  let submodule = resolved_name + "." + name
                  match
                    import_module(submodule, globals, builtins, io, config) {
                    Ok(value) => value
                    Err(err) => {
                      // CPython shows the *original* import failure (not a generic
                      // "cannot import name") when the submodule exists but raises
                      // during import (common with circular imports).
                      let missing_submodule_message = "ModuleNotFoundError: No module named '" +
                        submodule +
                        "'"
                      if err.exc_type == "ModuleNotFoundError" &&
                        err.message == missing_submodule_message {
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "ImportError: cannot import name '" +
                            name +
                            "' from '" +
                            resolved_name +
                            "'",
                          ),
                        )
                      }
                      return Err(err)
                    }
                  }
                }
                _ => return Err(err)
              }
          }
          let binding = match alias_opt {
            Some(alias_name) => alias_name
            None => name
          }
          set_scoped_value(locals, globals, binding, imported)
        }
        last = Value::None
      }
      Stmt::With(context~, target~, body~) => {
        let ctx_value = match
          eval_expr_with_env(context, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let enter_value = match
          get_attr_from_value(ctx_value, "__enter__", globals, builtins, io) {
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
        let exit_value = match
          get_attr_from_value(ctx_value, "__exit__", globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let body_result = eval_block_flow(
          body, locals, globals, builtins, io, config, loop_depth,
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
            let exc_value = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            let exc_type_value = match exc_value {
              Value::Instance(inst) => Value::Class(inst.class)
              _ => Value::Str(err.exc_type)
            }
            let tb_value = make_traceback_value(err.traceback)
            let exit_result = match
              call_callable_with_env(
                exit_value,
                [exc_type_value, exc_value, tb_value],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(value) => value
              Err(e) => return Err(e)
            }
            let suppress = match
              truthy_from_value_with_env(exit_result, globals, builtins, io) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            if suppress {
              last = Value::None
              ()
            } else {
              return Err(err)
            }
          }
        }
      }
      Stmt::AsyncWith(context~, target~, body~) => {
        // Roughly mirrors CPython:
        // mgr = (EXPR); aenter = type(mgr).__aenter__; aexit = type(mgr).__aexit__
        // value = await aenter(mgr); [TARGET = value];
        // try: SUITE; except: if not await aexit(mgr, *exc): raise; finally: await aexit(mgr, None, None, None)
        let mgr = match
          eval_expr_with_env(context, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let aenter = match
          get_attr_from_value(mgr, "__aenter__", globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let aexit = match
          get_attr_from_value(mgr, "__aexit__", globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let entered = match
          call_callable_with_env(aenter, [], [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let value = match coroutine_await(entered) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match target {
          Some(name) => set_scoped_value(locals, globals, name, value)
          None => ()
        }
        let body_result = eval_block_flow(
          body, locals, globals, builtins, io, config, loop_depth,
        )
        match body_result {
          Ok(flow) => {
            // normal exit: await aexit(mgr, None, None, None)
            let exit_res = match
              call_callable_with_env(
                aexit,
                [Value::None, Value::None, Value::None],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let _ = match coroutine_await(exit_res) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            match flow {
              BlockFlow::Normal(_) => {
                last = Value::None
                ()
              }
              BlockFlow::Return(v) => return Ok(BlockFlow::Return(v))
              BlockFlow::Break => return Ok(BlockFlow::Break)
              BlockFlow::Continue => return Ok(BlockFlow::Continue)
            }
          }
          Err(err) => {
            let exc_value = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            // For `__aexit__`, we currently pass the exception *type name* (string),
            // matching the expectations in `async_test.mbt`.
            let exc_type_value = Value::Str(err.exc_type)
            let tb_value = make_traceback_value(err.traceback)
            // exception exit: suppress if await aexit(...) is truthy
            let exit_call = match
              call_callable_with_env(
                aexit,
                [exc_type_value, exc_value, tb_value],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let exit_value = match coroutine_await(exit_call) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let suppress = match
              truthy_from_value_with_env(exit_value, globals, builtins, io) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            if suppress {
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
          eval_block_flow(
            body, locals, globals, builtins, io, config, loop_depth,
          ) {
          Ok(flow) =>
            if flow is BlockFlow::Normal(_) && else_body.length() > 0 {
              eval_block_flow(
                else_body, locals, globals, builtins, io, config, loop_depth,
              )
            } else {
              Ok(flow)
            }
          Err(err) => {
            let mut has_star = false
            for handler in handlers {
              if handler.is_star {
                has_star = true
                break
              }
            }
            if !has_star {
              let mut handled = false
              let mut handled_result : Result[BlockFlow, RuntimeError] = Err(
                err,
              )
              for handler in handlers {
                let exc_expr_opt = handler.exc
                let name_opt = handler.name
                let handler_body = handler.body
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
                  handler_body, locals, globals, builtins, io, config, loop_depth,
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
            } else {
              let mut remaining_group : Value? = None
              let mut handled = false
              let mut last_flow : BlockFlow = BlockFlow::Normal(Value::None)
              let mut handler_error : RuntimeError? = None
              for handler in handlers {
                let handler_classes = match handler.exc {
                  Some(expr) => {
                    let exc_value = match
                      eval_expr_with_env(expr, locals, globals, builtins, io) {
                      Ok(value) => value
                      Err(e) => {
                        handler_error = Some(e)
                        break
                      }
                    }
                    handler_classes_from_value(exc_value)
                  }
                  None => []
                }
                let group_value = match remaining_group {
                  Some(v) => v
                  None => {
                    let base_group = match
                      exception_group_from_runtime_error(
                        err, globals, builtins, io,
                      ) {
                      Ok(v) => v
                      Err(e) => {
                        handler_error = Some(e)
                        break
                      }
                    }
                    remaining_group = Some(base_group)
                    base_group
                  }
                }
                let (matched_opt, remaining_opt) = match
                  exception_group_split_by_classes(
                    group_value, handler_classes, globals, builtins, io,
                  ) {
                  Ok(v) => v
                  Err(e) => {
                    handler_error = Some(e)
                    break
                  }
                }
                let matched_group = match matched_opt {
                  Some(v) => v
                  None => continue
                }
                handled = true
                match handler.name {
                  Some(name) =>
                    set_scoped_value(locals, globals, name, matched_group)
                  None => ()
                }
                let match_err = match matched_group {
                  Value::Instance(inst) =>
                    runtime_error_from_exception_instance(inst)
                  _ => err
                }
                active_exception_stack.val.push(match_err)
                let next_result = eval_block_flow(
                  handler.body,
                  locals,
                  globals,
                  builtins,
                  io,
                  config,
                  loop_depth,
                )
                let _ = active_exception_stack.val.pop()
                match next_result {
                  Ok(flow) => last_flow = flow
                  Err(e) => {
                    handler_error = Some(e)
                    break
                  }
                }
                remaining_group = remaining_opt
                if remaining_group is None {
                  break
                }
                match last_flow {
                  BlockFlow::Normal(_) => ()
                  _ => break
                }
              }
              if handler_error is Some(e) {
                Err(e)
              } else if remaining_group is Some(rem) {
                match rem {
                  Value::Instance(inst) =>
                    Err(runtime_error_from_exception_instance(inst))
                  _ => Err(err)
                }
              } else if handled {
                Ok(last_flow)
              } else {
                Err(err)
              }
            }
          }
        }

        // Always run finally when leaving the try statement.
        if finally_body.length() > 0 {
          match
            eval_block_flow(
              finally_body, locals, globals, builtins, io, config, loop_depth,
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
      Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~) => {
        let _ = type_params
        let decorator_values : Array[Value] = []
        for dec_expr in decorators {
          let dec_value = match
            eval_expr_with_env(dec_expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          decorator_values.push(dec_value)
        }
        let raw_base_values : Array[Value] = []
        for base in bases {
          match base {
            Expr::Starred(value~) => {
              let iter_value = match
                eval_expr_with_env(value, locals, globals, builtins, io) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              let items = match iterable_values(iter_value) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              for item in items {
                raw_base_values.push(item)
              }
            }
            _ => {
              let value = match
                eval_expr_with_env(base, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              raw_base_values.push(value)
            }
          }
        }
        let base_values : Array[Value] = []
        for base_value in raw_base_values {
          let expanded = match base_value {
            Value::Instance(_) =>
              match
                get_attr_from_value(
                  base_value, "__mro_entries__", globals, builtins, io,
                ) {
                Ok(mro_entries) => {
                  let bases_tuple : Array[Value] = []
                  for item in raw_base_values {
                    bases_tuple.push(item)
                  }
                  let entries = match
                    call_callable_with_env(
                      mro_entries,
                      [Value::Tuple(bases_tuple)],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                  match entries {
                    Value::Tuple(values) => values
                    Value::List(values) => values
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "base class must be a class".to_string(),
                        ),
                      )
                  }
                }
                Err(_) =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "base class must be a class".to_string(),
                    ),
                  )
              }
            _ => [base_value]
          }
          for value in expanded {
            match value {
              Value::Class(_) => base_values.push(value)
              Value::Function(func) =>
                if func.body.length() == 0 && is_builtin_class_name(func.name) {
                  base_values.push(
                    Value::Class(builtin_class_from_name(func.name, builtins)),
                  )
                } else {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "base class must be a class".to_string(),
                    ),
                  )
                }
              other => base_values.push(other)
            }
          }
        }
        let class_kwargs : Array[(String, Value)] = []
        let mut metaclass_value : Value? = None
        for keyword in keywords {
          if keyword.0 == "**" {
            let mapping = match
              eval_expr_with_env(keyword.1, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let pairs = match dict_pairs_from_value("class", mapping) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for pair in pairs {
              match pair.0 {
                Value::Str(key) =>
                  if key == "metaclass" {
                    metaclass_value = Some(pair.1)
                  } else {
                    set_global_value(class_kwargs, key, pair.1)
                  }
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "keywords must be strings".to_string(),
                    ),
                  )
              }
            }
            continue
          }
          if keyword.0 == "metaclass" {
            let value = match
              eval_expr_with_env(keyword.1, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            metaclass_value = Some(value)
            continue
          }
          let value = match
            eval_expr_with_env(keyword.1, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          set_global_value(class_kwargs, keyword.0, value)
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
        for base_value in base_values {
          match base_value {
            Value::Class(base_class) =>
              match get_named_value(base_class.dict, "__module__") {
                Some(Value::Str(module_name)) =>
                  if module_name == "builtins" && base_class.name == "bool" {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "type 'bool' is not an acceptable base type".to_string(),
                      ),
                    )
                  }
                _ => ()
              }
            _ => ()
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
        let mut qualname = name
        match get_global_value(locals, "__qualname__") {
          Some(Value::Str(parent)) => qualname = parent + "." + name
          _ => ()
        }
        class_dict.push(("__module__", Value::Str(module_name)))
        class_dict.push(("__qualname__", Value::Str(qualname)))

        // Best-effort support for zero-arg super(): functions created in this
        // class body can close over a __class__ cell.
        ensure_local_cell(class_dict, "__class__", Value::None)
        let mut pushed_closure = false
        if has_active_closure_env() {
          for i = 0; i < locals.length(); i = i + 1 {
            let name = locals[i].0
            let value = locals[i].1
            if !is_cell_value(value) {
              ensure_local_cell(locals, name, value)
            }
          }
          let class_closure = merge_cell_closures(locals, current_closure_env())
          push_closure_env(class_closure)
          pushed_closure = true
        }
        let flow = match
          eval_block_flow(
            body, class_dict, globals, builtins, io, config, loop_depth,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if pushed_closure {
          pop_closure_env()
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
        // Best-effort metaclass support: select a metaclass and call it
        // (via `type.__new__` or a custom `__new__`) to produce the class.
        let mut selected_meta = Value::Class(
          builtin_class_from_name("type", builtins),
        )
        match metaclass_value {
          Some(v) => selected_meta = v
          None =>
            for base_value in base_values {
              match base_value {
                Value::Class(base_class) =>
                  match
                    get_named_value(base_class.dict, "__mpython_metaclass__") {
                    Some(Value::Class(meta)) => {
                      selected_meta = Value::Class(meta)
                      break
                    }
                    _ => ()
                  }
                _ => ()
              }
            }
        }
        let namespace_pairs : Array[(Value, Value)] = []
        for pair in class_dict {
          namespace_pairs.push((Value::Str(pair.0), pair.1))
        }
        let metaclass_args : Array[Value] = [
          Value::Str(name),
          Value::Tuple(base_values),
          Value::Dict(namespace_pairs),
        ]
        let created_value = match
          call_callable_with_env(
            selected_meta, metaclass_args, class_kwargs, globals, builtins, io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        // CPython allows metaclasses to return non-type objects; in that case
        // the class statement binds the returned value.
        match created_value {
          Value::Class(klass) => {
            // Fill the __class__ cell so closures can resolve it (for super()).
            match get_named_value(class_dict, "__class__") {
              Some(cell) => cell_set_value(cell, Value::Class(klass))
              None => ()
            }
            // Track the metaclass if the metaclass protocol didn't already.
            if get_named_value(klass.dict, "__mpython_metaclass__") is None {
              match selected_meta {
                Value::Class(meta) =>
                  set_named_value(
                    klass.dict,
                    "__mpython_metaclass__",
                    Value::Class(meta),
                  )
                _ => ()
              }
            }
            let _ = match class_mro(klass) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            // Descriptor hook: record the attribute name on built-in property
            // instances so AttributeError messages can include it.
            for pair in klass.dict {
              match pair.1 {
                Value::Instance(desc_inst) =>
                  if class_has_base_name(desc_inst.class, "property") {
                    if get_named_value(desc_inst.dict, "__name__") is None {
                      set_named_value(
                        desc_inst.dict,
                        "__name__",
                        Value::Str(pair.0),
                      )
                    }
                  }
                _ => ()
              }
            }
            fn value_is_abstract(
              value : Value,
              globals : Array[(String, Value)],
              builtins : Array[(String, Value)],
              io : MockIO,
            ) -> Result[Bool, RuntimeError] {
              match
                get_attr_from_value(
                  value, "__isabstractmethod__", globals, builtins, io,
                ) {
                Ok(flag) =>
                  truthy_from_value_with_env(flag, globals, builtins, io)
                Err(err) =>
                  match err.kind {
                    RuntimeErrorKind::Attribute => Ok(false)
                    _ =>
                      if err.exc_type == "AttributeError" {
                        Ok(false)
                      } else {
                        Err(err)
                      }
                  }
              }
            }

            let abstract_names : Array[Value] = []
            for pair in class_dict {
              let is_abstract = match
                value_is_abstract(pair.1, globals, builtins, io) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              if is_abstract {
                match set_add_unique(abstract_names, Value::Str(pair.0)) {
                  Ok(_) => ()
                  Err(_) => ()
                }
              }
            }
            let mut has_abstractmethods_attr = false
            for base_value in base_values {
              match base_value {
                Value::Class(base_class) => {
                  let base_abs = get_named_value(
                    base_class.dict,
                    "__abstractmethods__",
                  )
                  if base_abs is Some(_) {
                    has_abstractmethods_attr = true
                  }
                  match base_abs {
                    Some(Value::Set(items)) | Some(Value::Tuple(items)) =>
                      for item in items {
                        match item {
                          Value::Str(name) =>
                            match lookup_class_attr(klass, name) {
                              Ok(Some(value)) => {
                                let is_abstract = match
                                  value_is_abstract(
                                    value, globals, builtins, io,
                                  ) {
                                  Ok(v) => v
                                  Err(err) => return Err(err)
                                }
                                if is_abstract {
                                  match
                                    set_add_unique(
                                      abstract_names,
                                      Value::Str(name),
                                    ) {
                                    Ok(_) => ()
                                    Err(_) => ()
                                  }
                                }
                              }
                              _ => ()
                            }
                          _ => ()
                        }
                      }
                    _ => ()
                  }
                }
                _ => ()
              }
            }
            if abstract_names.length() > 0 || has_abstractmethods_attr {
              // Override inherited __abstractmethods__ (even when empty) so concrete
              // subclasses of ABCs don't appear abstract.
              set_named_value(
                klass.dict,
                "__abstractmethods__",
                Value::Set(abstract_names),
              )
            }
            // Call `__init_subclass__` on the *base* (PEP 487). When defining a class
            // that itself defines `__init_subclass__`, CPython does not call the new
            // class' own hook for its creation; it calls the inherited hook via `super()`.
            let inherited_init_subclass : Value? = match class_mro(klass) {
              Ok(mro) => {
                let mut found : Value? = None
                for i = 1; i < mro.length(); i = i + 1 {
                  match get_named_value(mro[i].dict, "__init_subclass__") {
                    Some(Value::Function(func)) => {
                      found = Some(
                        Value::BoundMethod(BoundMethodValue::{
                          function: func,
                          self: Value::Class(klass),
                        }),
                      )
                      break
                    }
                    _ => ()
                  }
                }
                found
              }
              Err(_) => None
            }
            match inherited_init_subclass {
              Some(hook) => {
                let _ = match
                  call_callable_with_env(
                    hook,
                    [],
                    class_kwargs,
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }

              }
              None => ()
            }
            let mut defined : Value = Value::Class(klass)
            for i = decorator_values.length(); i > 0; i = i - 1 {
              let decorator_value = decorator_values[i - 1]
              defined = match decorator_value {
                Value::Function(dec_func) =>
                  if dec_func.body.length() == 0 {
                    match
                      eval_builtin_call(
                        dec_func.name,
                        [defined],
                        [],
                        locals,
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(Some(value)) => value
                      Ok(None) =>
                        match
                          call_callable_with_env(
                            decorator_value,
                            [defined],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      Err(err) => return Err(err)
                    }
                  } else {
                    match
                      call_callable_with_env(
                        decorator_value,
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
                _ =>
                  match
                    call_callable_with_env(
                      decorator_value,
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
            }
            set_scoped_value(locals, globals, name, defined)
            last = Value::None
          }
          other => {
            let mut defined : Value = other
            for i = decorator_values.length(); i > 0; i = i - 1 {
              let decorator_value = decorator_values[i - 1]
              defined = match decorator_value {
                Value::Function(dec_func) =>
                  if dec_func.body.length() == 0 {
                    match
                      eval_builtin_call(
                        dec_func.name,
                        [defined],
                        [],
                        locals,
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(Some(value)) => value
                      Ok(None) =>
                        match
                          call_callable_with_env(
                            decorator_value,
                            [defined],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      Err(err) => return Err(err)
                    }
                  } else {
                    match
                      call_callable_with_env(
                        decorator_value,
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
                _ =>
                  match
                    call_callable_with_env(
                      decorator_value,
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
            }
            set_scoped_value(locals, globals, name, defined)
            last = Value::None
          }
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        let mut broke = false
        while true {
          let cond_value = match
            eval_expr_with_env(condition, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let ok = match
            truthy_from_value_with_env(cond_value, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if !ok {
            break
          }
          match
            eval_block_flow(
              body,
              locals,
              globals,
              builtins,
              io,
              config,
              loop_depth + 1,
            ) {
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
              else_body, locals, globals, builtins, io, config, loop_depth,
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
        let iterator = match
          iter_value_to_iterator(iter_value, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        while true {
          let item = match
            iterator_next(iterator, None, globals, builtins, io) {
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
            eval_block_flow(
              body,
              locals,
              globals,
              builtins,
              io,
              config,
              loop_depth + 1,
            ) {
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
              else_body, locals, globals, builtins, io, config, loop_depth,
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
      Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        // Minimal async-for semantics:
        // it = (ITER); it = type(it).__aiter__(it)
        // loop: value = await type(it).__anext__(it); assign target; exec body
        // StopAsyncIteration => break; optional else_body if not broken
        let iter_value = match
          eval_expr_with_env(iter, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let aiter_value = match
          get_attr_from_value(iter_value, "__aiter__", globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let iterator0 = match
          call_callable_with_env(aiter_value, [], [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let iterator = iterator0
        let mut broke = false
        while true {
          let anext_value = match
            get_attr_from_value(iterator, "__anext__", globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let next_awaitable = match
            call_callable_with_env(anext_value, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let item = match coroutine_await(next_awaitable) {
            Ok(v) => v
            Err(err) => {
              if err.exc_type == "StopAsyncIteration" {
                break
              }
              return Err(err)
            }
          }
          let _ = match
            assign_target_with_env(target, item, locals, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match
            eval_block_flow(
              body,
              locals,
              globals,
              builtins,
              io,
              config,
              loop_depth + 1,
            ) {
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
              else_body, locals, globals, builtins, io, config, loop_depth,
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
                guard_ok = match
                  truthy_from_value_with_env(guard_value, globals, builtins, io) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
              }
              if guard_ok {
                match
                  eval_block_flow(
                    case_body, locals, globals, builtins, io, config, loop_depth,
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
        let ok = match
          truthy_from_value_with_env(cond_value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if ok {
          match
            eval_block_flow(
              body, locals, globals, builtins, io, config, loop_depth,
            ) {
            Ok(BlockFlow::Normal(_)) => ()
            Ok(BlockFlow::Return(value)) => return Ok(BlockFlow::Return(value))
            Ok(BlockFlow::Break) => return Ok(BlockFlow::Break)
            Ok(BlockFlow::Continue) => return Ok(BlockFlow::Continue)
            Err(err) => return Err(err)
          }
        } else {
          match
            eval_block_flow(
              else_body, locals, globals, builtins, io, config, loop_depth,
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
  config : Config,
) -> Result[Value, RuntimeError] {
  push_active_config(config)
  let result = eval_block_flow(body, locals, globals, builtins, io, config, 0)
  pop_active_config()
  match result {
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
