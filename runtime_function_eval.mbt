///|
/// Function and generator invocation helpers.

///|
fn prepare_function_locals(
  locals : Array[(String, Value)],
  body : Array[Stmt],
  params : Array[String],
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Unit {
  let local_names = collect_function_local_names(
    body, params, global_names, nonlocal_names,
  )
  for name in local_names {
    ensure_local_cell_unbound(locals, name)
  }
}

///|
fn eval_function_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals = match
    bind_function_args_with_kwargs(func, positional, keywords) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let active_globals = resolve_function_globals(func, globals)
  let (global_names, nonlocal_names) = collect_scope_decl_names(func.body)
  let _ = match
    check_scope_decl_conflicts(func.params, global_names, nonlocal_names) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  prepare_function_locals(
    locals,
    func.body,
    func.params,
    global_names,
    nonlocal_names,
  )
  let filename = current_traceback_filename()
  if func.is_async {
    if func.is_generator {
      return Ok(
        async_generator_new(
          func.body,
          locals,
          active_globals,
          builtins,
          io,
          global_names,
          nonlocal_names,
          func.closure,
          func.name,
          filename,
        ),
      )
    }
    return Ok(
      coroutine_new(
        func.body,
        locals,
        active_globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        func.name,
        filename,
        current_config(),
      ),
    )
  }
  push_traceback_frame(func.name, filename)
  push_closure_env(func.closure)
  push_scope_decls_with_nonlocals(global_names, nonlocal_names)
  // Prefer bytecode execution for function bodies; fall back to the legacy AST
  // evaluator when the compiler doesn't cover a construct yet.
  let result = match compile_stmts_to_bc(func.body, func.name, filename) {
    Ok(code) => {
      push_active_config(current_config())
      let out = bc_exec(code, locals, active_globals, builtins, io)
      pop_active_config()
      out
    }
    Err(err) =>
      match err.kind {
        RuntimeErrorKind::NotImplemented =>
          if current_config().bytecode_strict {
            Err(err)
          } else {
            eval_block(
              func.body,
              locals,
              active_globals,
              builtins,
              io,
              current_config(),
            )
          }
        _ => Err(err)
      }
  }
  pop_scope_decls()
  pop_closure_env()
  pop_traceback_frame()
  result
}

///|
fn bind_function_args_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
) -> Result[Array[(String, Value)], RuntimeError] {
  let posonly_params : Array[String] = []
  let pending_pos_params : Array[String] = []
  let pos_params : Array[String] = []
  let kw_only_params : Array[String] = []
  let mut vararg_name : String? = None
  let mut kwarg_name : String? = None
  let defaults_by_name : Array[(String, Value)] = []
  let mut default_idx = 0
  let mut kw_only = false
  let mut saw_posonly_marker = false
  for param in func.params {
    if param_is_posonly_marker(param) {
      if !saw_posonly_marker {
        for name in pending_pos_params {
          posonly_params.push(name)
        }
        pending_pos_params.clear()
      }
      saw_posonly_marker = true
      continue
    }
    if param_is_kw_only_marker(param) {
      kw_only = true
      continue
    }
    if param_is_kwarg(param) {
      kwarg_name = normalize_param_name(param)
      kw_only = true
      continue
    }
    if param_is_vararg(param) {
      vararg_name = normalize_param_name(param)
      kw_only = true
      continue
    }
    match normalize_param_name(param) {
      Some(name) => {
        if kw_only {
          kw_only_params.push(name)
        } else if saw_posonly_marker {
          pos_params.push(name)
        } else {
          pending_pos_params.push(name)
        }
        if param_has_default_marker(param) {
          if default_idx >= func.defaults.length() {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: bad function defaults in " + func.name,
              ),
            )
          }
          defaults_by_name.push((name, func.defaults[default_idx]))
          default_idx += 1
        }
      }
      None => ()
    }
  }
  if !saw_posonly_marker {
    for name in pending_pos_params {
      pos_params.push(name)
    }
  }
  if default_idx != func.defaults.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "RuntimeError: bad function defaults in " + func.name,
      ),
    )
  }
  let positional_param_count = posonly_params.length() + pos_params.length()
  if vararg_name is None && positional.length() > positional_param_count {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        func.name +
        "() takes " +
        positional_param_count.to_string() +
        " positional arguments but " +
        positional.length().to_string() +
        " were given",
      ),
    )
  }
  fn find_default(
    defaults_by_name : Array[(String, Value)],
    name : String,
  ) -> Value? {
    for entry in defaults_by_name {
      if entry.0 == name {
        return Some(entry.1)
      }
    }
    None
  }

  let all_pos_params : Array[String] = []
  for name in posonly_params {
    all_pos_params.push(name)
  }
  for name in pos_params {
    all_pos_params.push(name)
  }
  let pos_values : Array[(String, Value)] = []
  let pos_assigned : Array[Bool] = []
  for name in all_pos_params {
    pos_values.push((name, Value::None))
    pos_assigned.push(false)
  }
  let kw_values : Array[(String, Value)] = []
  let kw_assigned : Array[Bool] = []
  for name in kw_only_params {
    kw_values.push((name, Value::None))
    kw_assigned.push(false)
  }
  let vararg_values : Array[Value] = []
  let kwarg_values : Array[(Value, Value)] = []
  for i = 0; i < positional.length(); i = i + 1 {
    if i < all_pos_params.length() {
      pos_values[i] = (all_pos_params[i], positional[i])
      pos_assigned[i] = true
    } else {
      vararg_values.push(positional[i])
    }
  }
  for pair in keywords {
    let name = pair.0
    let value = pair.1
    // Positional-only parameters (before "/") can't be filled by keywords.
    // When **kwargs exists, CPython keeps the keyword and still expects the
    // positional-only argument to be provided positionally.
    let mut is_posonly = false
    for p in posonly_params {
      if p == name {
        is_posonly = true
        break
      }
    }
    if is_posonly && kwarg_name is None {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          func.name +
          "() got some positional-only arguments passed as keyword arguments: '" +
          name +
          "'",
        ),
      )
    }
    let mut handled = false
    for i = 0; i < pos_params.length(); i = i + 1 {
      if pos_params[i] == name {
        handled = true
        // `pos_assigned` indexes cover both posonly and pos-or-kw params; the
        // pos-or-kw section starts after the posonly prefix.
        let slot = posonly_params.length() + i
        if pos_assigned[slot] {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        pos_values[slot] = (name, value)
        pos_assigned[slot] = true
        break
      }
    }
    if handled {
      continue
    }
    for i = 0; i < kw_only_params.length(); i = i + 1 {
      if kw_only_params[i] == name {
        handled = true
        if kw_assigned[i] {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        kw_values[i] = (name, value)
        kw_assigned[i] = true
        break
      }
    }
    if handled {
      continue
    }
    match kwarg_name {
      Some(_) => {
        let mut exists = false
        for entry in kwarg_values {
          match entry.0 {
            Value::Str(key) => if key == name { exists = true }
            _ => ()
          }
        }
        if exists {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        kwarg_values.push((Value::Str(name), value))
      }
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            func.name + "() got an unexpected keyword argument '" + name + "'",
          ),
        )
    }
  }
  let missing_pos : Array[String] = []
  for i = 0; i < all_pos_params.length(); i = i + 1 {
    if !pos_assigned[i] {
      match find_default(defaults_by_name, all_pos_params[i]) {
        Some(value) => {
          pos_values[i] = (all_pos_params[i], value)
          pos_assigned[i] = true
        }
        None => missing_pos.push(all_pos_params[i])
      }
    }
  }
  if missing_pos.length() > 0 {
    let buf = StringBuilder::new()
    buf.write_string(func.name)
    buf.write_string("() missing ")
    buf.write_string(missing_pos.length().to_string())
    buf.write_string(" required positional argument")
    if missing_pos.length() != 1 {
      buf.write_string("s")
    }
    buf.write_string(": ")
    for i = 0; i < missing_pos.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("'")
      buf.write_string(missing_pos[i])
      buf.write_string("'")
    }
    return Err(make_runtime_error(RuntimeErrorKind::Type, buf.to_string()))
  }
  let missing_kw : Array[String] = []
  for i = 0; i < kw_only_params.length(); i = i + 1 {
    if !kw_assigned[i] {
      match find_default(defaults_by_name, kw_only_params[i]) {
        Some(value) => {
          kw_values[i] = (kw_only_params[i], value)
          kw_assigned[i] = true
        }
        None => missing_kw.push(kw_only_params[i])
      }
    }
  }
  if missing_kw.length() > 0 {
    let buf = StringBuilder::new()
    buf.write_string(func.name)
    buf.write_string("() missing ")
    buf.write_string(missing_kw.length().to_string())
    buf.write_string(" required keyword-only argument")
    if missing_kw.length() != 1 {
      buf.write_string("s")
    }
    buf.write_string(": ")
    for i = 0; i < missing_kw.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("'")
      buf.write_string(missing_kw[i])
      buf.write_string("'")
    }
    return Err(make_runtime_error(RuntimeErrorKind::Type, buf.to_string()))
  }
  let locals : Array[(String, Value)] = []
  for item in pos_values {
    locals.push(item)
  }
  match vararg_name {
    Some(name) => locals.push((name, Value::Tuple(vararg_values)))
    None => ()
  }
  for item in kw_values {
    locals.push(item)
  }
  match kwarg_name {
    Some(name) => locals.push((name, Value::Dict(kwarg_values)))
    None => ()
  }
  Ok(locals)
}

///|
fn eval_generator_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals = match
    bind_function_args_with_kwargs(func, positional, keywords) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let active_globals = resolve_function_globals(func, globals)
  let (global_names, nonlocal_names) = collect_scope_decl_names(func.body)
  let _ = match
    check_scope_decl_conflicts(func.params, global_names, nonlocal_names) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  prepare_function_locals(
    locals,
    func.body,
    func.params,
    global_names,
    nonlocal_names,
  )
  let filename = current_traceback_filename()
  if func.is_async {
    Ok(
      async_generator_new(
        func.body,
        locals,
        active_globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        func.name,
        filename,
      ),
    )
  } else {
    Ok(
      generator_new(
        func.body,
        locals,
        active_globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        func.name,
        filename,
      ),
    )
  }
}

///|
let runtime_callbacks_ready : Ref[Bool] = { val: false }

///|
fn ensure_runtime_callbacks_ready() -> Unit {
  if runtime_callbacks_ready.val {
    return
  }
  set_eval_function_with_kwargs_callback(eval_function_with_kwargs)
  set_eval_generator_with_kwargs_callback(eval_generator_with_kwargs)
  runtime_callbacks_ready.val = true
}

///|
