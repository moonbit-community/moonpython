///|
/// Module-backed helpers (asyncio/_thread/_weakref/itertools/coroutine/code).

///|
fn builtin_mpython_run(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_run", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_run() takes exactly one argument".to_string(),
      ),
    )
  }
  coroutine_await(positional[0])
}

///|
fn builtin_asyncio_iscoroutinefunction(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("asyncio.iscoroutinefunction", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "iscoroutinefunction() takes exactly one argument".to_string(),
      ),
    )
  }
  let target = positional[0]
  let mut ok = false
  match target {
    Value::Function(func) => ok = func.is_async && !func.is_generator
    Value::BoundMethod(bm) =>
      ok = bm.function.is_async && !bm.function.is_generator
    _ => ()
  }
  Ok(Value::Bool(ok))
}

///|
fn builtin_platform_system(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("platform.system", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "system() takes no arguments".to_string(),
      ),
    )
  }
  // Minimal platform tag. Keep it aligned with `sys.platform` ("wasi") so the
  // stdlib can take appropriate feature-gating branches.
  Ok(Value::Str("wasi"))
}

///|
fn builtin_platform_machine(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("platform.machine", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "machine() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Str("wasm32"))
}

///|
let enum_auto_counter : Ref[Int] = { val: 0 }

///|
fn builtin_enum_auto(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("enum.auto", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "auto() takes no arguments".to_string(),
      ),
    )
  }
  enum_auto_counter.val = enum_auto_counter.val + 1
  let dict : Array[(String, Value)] = [
    ("value", Value::Int(@bigint.BigInt::from_int(enum_auto_counter.val))),
  ]
  Ok(
    Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "auto", bases: [], dict: [] },
      dict,
    }),
  )
}

///|
fn builtin_enum_simple_enum(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  // Accept any signature; return a decorator that is currently a no-op.
  let _ = positional
  let _ = keywords
  Ok(
    Value::Function(FunctionValue::{
      name: "enum._simple_enum_decorator",
      params: ["cls"],
      defaults: [],
      body: [],
      is_generator: false,
      is_async: false,
      closure: [],
    }),
  )
}

///|
fn builtin_enum_simple_enum_decorator(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("enum._simple_enum_decorator", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "enum decorator takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_enum_simple_enum_decorator_call(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match
    ensure_no_keywords("enum._simple_enum_decorator_call", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__call__() takes exactly two arguments".to_string(),
      ),
    )
  }
  Ok(positional[1])
}

///|
fn builtin_atexit_register(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "atexit.register() missing callable".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn ensure_socket_buffer(dict : Array[(String, Value)]) -> Array[Int] {
  match lookup_iterable_field(dict, "buffer") {
    Some(Value::ByteArray(buf)) => buf
    Some(Value::Bytes(buf)) => buf
    Some(Value::MemoryView(buf)) => buf
    _ => {
      let buf : Array[Int] = []
      set_iterable_field(dict, "buffer", Value::ByteArray(buf))
      buf
    }
  }
}

///|
fn socket_bytes_from_value(value : Value) -> Result[Array[Int], RuntimeError] {
  match value {
    Value::Bytes(bytes) | Value::ByteArray(bytes) | Value::MemoryView(bytes) =>
      Ok(bytes)
    Value::Str(text) => Ok(encode_string_utf8(text))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "socket expects a bytes-like object".to_string(),
        ),
      )
  }
}

///|
fn builtin_socket_socket_init(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "socket.__init__ missing self".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      let _ = ensure_socket_buffer(inst.dict)
      set_iterable_field(inst.dict, "closed", Value::Bool(false))
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "socket.__init__ invalid self".to_string(),
        ),
      )
  }
}

///|
fn builtin_socket_socket_connect(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "connect() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      set_iterable_field(inst.dict, "address", positional[1])
      set_iterable_field(inst.dict, "connected", Value::Bool(true))
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "connect() invalid self".to_string(),
        ),
      )
  }
}

///|
fn builtin_socket_socket_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "close() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      set_iterable_field(inst.dict, "closed", Value::Bool(true))
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "close() invalid self".to_string(),
        ),
      )
  }
}

///|
fn builtin_socket_socket_send(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "send() takes exactly one argument".to_string(),
      ),
    )
  }
  let payload = match socket_bytes_from_value(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[0] {
    Value::Instance(inst) => {
      let buf = ensure_socket_buffer(inst.dict)
      for byte in payload {
        buf.push(byte)
      }
      Ok(Value::Int(@bigint.BigInt::from_int(payload.length())))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "send() invalid self".to_string(),
        ),
      )
  }
}

///|
fn builtin_socket_socket_sendall(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  let _ = match
    builtin_socket_socket_send(positional, [], locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_enum_global_enum(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut update_str = false
  for pair in keywords {
    if pair.0 == "update_str" {
      match pair.1 {
        Value::Bool(v) => update_str = v
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "global_enum() update_str must be bool".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "global_enum() got unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  let _ = update_str
  if positional.length() < 1 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "global_enum() expects a class".to_string(),
      ),
    )
  }
  let cls = positional[0]
  let module_name = match cls {
    Value::Class(klass) =>
      match get_named_value(klass.dict, "__module__") {
        Some(Value::Str(name)) => name
        _ => "<unknown>".to_string()
      }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "global_enum() expects a class".to_string(),
        ),
      )
  }
  let module_value = match module_cache_get(module_name) {
    Some(v) => v
    None => return Ok(cls)
  }
  fn is_global_member_name(name : String) -> Bool {
    if name.length() == 0 {
      return false
    }
    for ch in name {
      let code = ch.to_int()
      let ok = (code >= 0x41 && code <= 0x5A) || // A-Z
        (code >= 0x30 && code <= 0x39) || // 0-9
        code == 0x5F // _
      if !ok {
        return false
      }
    }
    true
  }

  match (cls, module_value) {
    (Value::Class(klass), Value::Instance(mod_inst)) =>
      for pair in klass.dict {
        if is_global_member_name(pair.0) {
          set_named_value(mod_inst.dict, pair.0, pair.1)
        }
      }
    _ => ()
  }
  Ok(cls)
}

///|
fn builtin_socket_socket_sendto(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "sendto() takes exactly two arguments".to_string(),
      ),
    )
  }
  // ignore address; treat as send
  builtin_socket_socket_send(
    [positional[0], positional[1]],
    [],
    locals,
    globals,
    builtins,
    io,
  )
}

///|
fn builtin_socket_socket_recv(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "recv() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::Bytes([]))
}

///|
fn builtin_socket_socket_settimeout(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "settimeout() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      set_iterable_field(inst.dict, "timeout", positional[1])
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "settimeout() invalid self".to_string(),
        ),
      )
  }
}

///|
fn builtin_socket_create_connection(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "create_connection() missing address".to_string(),
      ),
    )
  }
  let klass = socket_socket_class(builtins)
  let dict : Array[(String, Value)] = [
    ("buffer", Value::ByteArray([])),
    ("closed", Value::Bool(false)),
    ("connected", Value::Bool(true)),
    ("address", positional[0]),
  ]
  Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
}

///|
fn builtin_socket_getaddrinfo(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = builtins
  let _ = io
  let _ = globals
  let _ = locals
  let _ = positional
  let _ = keywords
  // Minimal stub: no real DNS/networking.
  Ok(Value::List([]))
}

///|
fn builtin_mpython_asyncgenexp_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgenexp_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgenexp_next() takes exactly one argument".to_string(),
      ),
    )
  }
  async_genexp_next(positional[0])
}

///|
fn builtin_mpython_asyncgen_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_next() takes exactly one argument".to_string(),
      ),
    )
  }
  async_generator_next(positional[0])
}

///|
fn builtin_mpython_asyncgen_send(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_send", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_send() takes exactly two arguments".to_string(),
      ),
    )
  }
  async_generator_send(positional[0], positional[1])
}

///|
fn builtin_mpython_asyncgen_throw(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_throw", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_throw() takes exactly two arguments".to_string(),
      ),
    )
  }
  async_generator_throw(positional[0], positional[1])
}

///|
fn builtin_mpython_asyncgen_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_close", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_close() takes exactly one argument".to_string(),
      ),
    )
  }
  async_generator_close(positional[0])
}

///|
fn builtin_asyncio_run(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("asyncio.run", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "asyncio.run() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "coroutine" {
        coroutine_await(positional[0])
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" +
            type_name_from_value(positional[0]) +
            "' object can't be used in 'await' expression",
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" +
          type_name_from_value(positional[0]) +
          "' object can't be used in 'await' expression",
        ),
      )
  }
}

///|
fn builtin_asyncio_gather(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("asyncio.gather", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  for coro in positional {
    let value = match coro {
      Value::Instance(inst) =>
        if inst.class.name == "coroutine" {
          match coroutine_await(coro) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "'" +
              type_name_from_value(coro) +
              "' object can't be used in 'await' expression",
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" +
            type_name_from_value(coro) +
            "' object can't be used in 'await' expression",
          ),
        )
    }
    results.push(value)
  }
  Ok(Value::List(results))
}

///|
fn builtin_time_time(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.time", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.time() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Float(0.0))
}

///|
fn builtin_time_monotonic(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.monotonic", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.monotonic() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Float(0.0))
}

///|
fn builtin_time_perf_counter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.perf_counter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.perf_counter() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Float(0.0))
}

///|
fn builtin_time_perf_counter_ns(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.perf_counter_ns", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.perf_counter_ns() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(0N))
}

///|
fn builtin_time_process_time(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.process_time", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.process_time() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Float(0.0))
}

///|
fn builtin_time_process_time_ns(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.process_time_ns", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.process_time_ns() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(0N))
}

///|
fn builtin_time_sleep(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.sleep", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.sleep() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_time_localtime(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.localtime", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 && positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.localtime() takes 0 or 1 argument".to_string(),
      ),
    )
  }
  // Minimal stub: return a 9-tuple shaped like time.struct_time.
  // logging only needs this to be accepted by time.strftime() (also stubbed).
  Ok(
    Value::Tuple([
      Value::Int(1970N),
      Value::Int(1N),
      Value::Int(1N),
      Value::Int(0N),
      Value::Int(0N),
      Value::Int(0N),
      Value::Int(0N),
      Value::Int(1N),
      Value::Int(0N),
    ]),
  )
}

///|
fn builtin_time_gmtime(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.gmtime", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 && positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.gmtime() takes 0 or 1 argument".to_string(),
      ),
    )
  }
  let seconds = if positional.length() == 1 {
    match positional[0] {
      Value::Int(v) => v
      Value::Bool(v) => if v { 1N } else { 0N }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "time.gmtime() argument must be int".to_string(),
          ),
        )
    }
  } else {
    0N
  }
  // Convert seconds since the Unix epoch to a UTC struct_time tuple.
  let day_seconds = 86400N
  let mut days = seconds / day_seconds
  let mut rem = seconds % day_seconds
  if rem < 0N {
    rem = rem + day_seconds
    days = days - 1N
  }
  let rem_i = match bigint_to_int_checked(rem) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let days_i = match bigint_to_int_checked(days) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let hour = rem_i / 3600
  let minute = rem_i % 3600 / 60
  let second = rem_i % 60
  fn is_leap_year(year : Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }
  // Howard Hinnant's civil_from_days algorithm (proleptic Gregorian).
  let z = days_i + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097 // [0, 146096]
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 // [0, 399]
  let mut year = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100) // [0, 365]
  let mp = (5 * doy + 2) / 153 // [0, 11]
  let day = doy - (153 * mp + 2) / 5 + 1 // [1, 31]
  let month = mp + (if mp < 10 { 3 } else { -9 }) // [1, 12]
  year = year + (if month <= 2 { 1 } else { 0 })
  let mut yday = day
  let month_lengths : Array[Int] = if is_leap_year(year) {
    [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  } else {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  }
  for i = 0; i < month - 1; i = i + 1 {
    yday = yday + month_lengths[i]
  }
  let wday = (days_i + 3) % 7
  Ok(
    Value::Tuple([
      Value::Int(@bigint.BigInt::from_int(year)),
      Value::Int(@bigint.BigInt::from_int(month)),
      Value::Int(@bigint.BigInt::from_int(day)),
      Value::Int(@bigint.BigInt::from_int(hour)),
      Value::Int(@bigint.BigInt::from_int(minute)),
      Value::Int(@bigint.BigInt::from_int(second)),
      Value::Int(@bigint.BigInt::from_int(wday)),
      Value::Int(@bigint.BigInt::from_int(yday)),
      Value::Int(0N),
    ]),
  )
}

///|
fn builtin_time_strftime(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.strftime", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 && positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "time.strftime() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let format = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "strftime() argument 1 must be str".to_string(),
        ),
      )
  }
  let time_tuple : Array[Value] = if positional.length() == 2 {
    match positional[1] {
      Value::Tuple(values) | Value::List(values) => values
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "strftime() argument 2 must be a tuple".to_string(),
          ),
        )
    }
  } else {
    []
  }
  let tm_year = if time_tuple.length() >= 1 {
    match index_from_value(time_tuple[0], 0) {
      Ok(v) => v
      Err(_) => 1970
    }
  } else {
    1970
  }
  let tm_mon = if time_tuple.length() >= 2 {
    match index_from_value(time_tuple[1], 0) {
      Ok(v) => v
      Err(_) => 1
    }
  } else {
    1
  }
  let tm_mday = if time_tuple.length() >= 3 {
    match index_from_value(time_tuple[2], 0) {
      Ok(v) => v
      Err(_) => 1
    }
  } else {
    1
  }
  let tm_wday = if time_tuple.length() >= 7 {
    match index_from_value(time_tuple[6], 0) {
      Ok(v) => v
      Err(_) => 0
    }
  } else {
    0
  }
  let weekday_abbr : Array[String] = [
    "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
  ]
  let weekday_full : Array[String] = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
  ]
  let month_abbr : Array[String] = [
    "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let month_full : Array[String] = [
    "", "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December",
  ]
  fn two_digits(n : Int) -> String {
    if n < 0 {
      n.to_string()
    } else if n < 10 {
      "0" + n.to_string()
    } else {
      n.to_string()
    }
  }

  let chars = format.to_array()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '%' && i + 1 < chars.length() {
      let code = chars[i + 1]
      match code {
        '%' => buf.write_char('%')
        'a' =>
          if tm_wday >= 0 && tm_wday < weekday_abbr.length() {
            buf.write_string(weekday_abbr[tm_wday])
          } else {
            buf.write_string("%a")
          }
        'A' =>
          if tm_wday >= 0 && tm_wday < weekday_full.length() {
            buf.write_string(weekday_full[tm_wday])
          } else {
            buf.write_string("%A")
          }
        'b' =>
          if tm_mon >= 0 && tm_mon < month_abbr.length() {
            buf.write_string(month_abbr[tm_mon])
          } else {
            buf.write_string("%b")
          }
        'B' =>
          if tm_mon >= 0 && tm_mon < month_full.length() {
            buf.write_string(month_full[tm_mon])
          } else {
            buf.write_string("%B")
          }
        'd' => buf.write_string(two_digits(tm_mday))
        'm' => buf.write_string(two_digits(tm_mon))
        'Y' => buf.write_string(tm_year.to_string())
        'y' =>
          if tm_year >= 0 {
            buf.write_string(two_digits(tm_year % 100))
          } else {
            buf.write_string(two_digits(tm_year))
          }
        _ => {
          buf.write_char('%')
          buf.write_char(code)
        }
      }
      i += 2
      continue
    }
    buf.write_char(c)
    i += 1
  }
  Ok(Value::Str(buf.to_string()))
}

///|
fn builtin_time_get_clock_info(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("time.get_clock_info", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "get_clock_info() takes exactly one argument".to_string(),
      ),
    )
  }
  let name = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "get_clock_info() argument must be str".to_string(),
        ),
      )
  }
  let (monotonic, resolution) : (Bool, Double) = match name {
    "time" => (false, 0.000001)
    "monotonic" => (true, 0.000001)
    "perf_counter" => (true, 0.000000001)
    "process_time" => (true, 0.000001)
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: unknown clock".to_string(),
        ),
      )
  }
  let info_class = ClassValue::{ name: "clock_info", bases: [], dict: [] }
  Ok(
    Value::Instance(InstanceValue::{
      class: info_class,
      dict: [
        ("implementation", Value::Str("moonpython")),
        ("monotonic", Value::Bool(monotonic)),
        ("adjustable", Value::Bool(false)),
        ("resolution", Value::Float(resolution)),
      ],
    }),
  )
}

///|
fn builtin_string_formatter_parser(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_string.formatter_parser", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_string.formatter_parser() takes exactly one argument".to_string(),
      ),
    )
  }
  let text = match positional[0] {
    Value::Str(s) => s
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_string.formatter_parser() expects a str".to_string(),
        ),
      )
  }
  let out : Array[Value] = []
  let chars = text.to_array()
  let mut i = 0
  let mut lit = StringBuilder::new()
  while i < chars.length() {
    let c = chars[i]
    if c == '{' {
      if i + 1 < chars.length() && chars[i + 1] == '{' {
        lit.write_char('{')
        i += 2
        continue
      }
      // Flush literal then parse field.
      let literal_text = lit.to_string()
      lit = StringBuilder::new()
      let mut j = i + 1
      while j < chars.length() && chars[j] != '}' {
        j += 1
      }
      if j >= chars.length() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: expected '}' before end of string".to_string(),
          ),
        )
      }
      let inner = substring(text, i + 1, j).to_string()
      // Very small subset: field_name[!conv][:spec]
      let mut field_name = inner
      let mut conversion : Value = Value::None
      let mut format_spec : Value = Value::None
      match find_char(field_name, '!') {
        Some(pos) => {
          if pos + 1 < field_name.length() {
            conversion = Value::Str(substring(field_name, pos + 1, pos + 2))
          }
          field_name = substring(field_name, 0, pos).to_string()
        }
        None => ()
      }
      match find_char(field_name, ':') {
        Some(pos) => {
          format_spec = Value::Str(
            substring(field_name, pos + 1, field_name.length()),
          )
          field_name = substring(field_name, 0, pos).to_string()
        }
        None => ()
      }
      let field_value : Value = if field_name.length() == 0 {
        Value::Str("")
      } else {
        Value::Str(field_name.trim(chars=" \t").to_string())
      }
      out.push(
        Value::Tuple([
          Value::Str(literal_text),
          field_value,
          format_spec,
          conversion,
        ]),
      )
      i = j + 1
      continue
    }
    if c == '}' {
      if i + 1 < chars.length() && chars[i + 1] == '}' {
        lit.write_char('}')
        i += 2
        continue
      }
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: single '}' encountered in format string".to_string(),
        ),
      )
    }
    lit.write_char(c)
    i += 1
  }
  // Trailing literal-only part.
  out.push(
    Value::Tuple([
      Value::Str(lit.to_string()),
      Value::None,
      Value::None,
      Value::None,
    ]),
  )
  Ok(make_iterator(out))
}

///|
fn builtin_string_formatter_field_name_split(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match
    ensure_no_keywords("_string.formatter_field_name_split", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_string.formatter_field_name_split() takes exactly one argument".to_string(),
      ),
    )
  }
  let field_name = match positional[0] {
    Value::Str(s) => s
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_string.formatter_field_name_split() expects a str".to_string(),
        ),
      )
  }
  // Minimal: no attribute/index traversal. Return `(first, empty_iter)`.
  Ok(Value::Tuple([Value::Str(field_name), make_iterator([])]))
}

///|
fn builtin_thread_get_ident(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.get_ident", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.get_ident() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(1N))
}

///|
fn builtin_thread_allocate_lock(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.allocate_lock", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.allocate_lock() takes no arguments".to_string(),
      ),
    )
  }
  let klass = thread_rlock_class(builtins)
  Ok(
    Value::Instance(InstanceValue::{
      class: klass,
      dict: [
        ("hashvalue", Value::Int(fresh_object_hashvalue())),
        ("_locked", Value::Bool(false)),
      ],
    }),
  )
}

///|
fn builtin_thread_start_new_thread(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.start_new_thread", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 && positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.start_new_thread() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let func = positional[0]
  let args_list : Array[Value] = match positional[1] {
    Value::Tuple(items) => items
    Value::List(items) => items
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.start_new_thread() args must be a tuple".to_string(),
        ),
      )
  }
  let kwargs : Array[(String, Value)] = []
  if positional.length() == 3 {
    match positional[2] {
      Value::Dict(pairs) =>
        for pair in pairs {
          match pair.0 {
            Value::Str(key) => kwargs.push((key, pair.1))
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "_thread.start_new_thread() kwargs must have str keys".to_string(),
                ),
              )
          }
        }
      Value::None => ()
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "_thread.start_new_thread() kwargs must be a dict".to_string(),
          ),
        )
    }
  }

  // Synchronous fallback: run inline so pure-Python code that *expects* the
  // _thread API can at least execute. This is not real threading.
  let _ = match
    call_callable_with_env(func, args_list, kwargs, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Int(1N))
}

///|
fn builtin_thread_set_sentinel(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread._set_sentinel", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread._set_sentinel() takes no arguments".to_string(),
      ),
    )
  }
  let klass = thread_rlock_class(builtins)
  Ok(
    Value::Instance(InstanceValue::{
      class: klass,
      dict: [
        ("hashvalue", Value::Int(fresh_object_hashvalue())),
        ("_locked", Value::Bool(false)),
      ],
    }),
  )
}

///|
fn builtin_thread_count(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread._count", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread._count() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(0N))
}

///|
fn builtin_thread_stack_size(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.stack_size", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.stack_size() takes at most one argument".to_string(),
      ),
    )
  }
  // Ignore requested size for now; report "old" size as 0.
  Ok(Value::Int(0N))
}

///|
fn thread_lock_get_locked(dict : Array[(String, Value)]) -> Bool {
  match get_named_value(dict, "_locked") {
    Some(Value::Bool(v)) => v
    _ => false
  }
}

///|
fn thread_lock_set_locked(dict : Array[(String, Value)], locked : Bool) -> Unit {
  set_named_value(dict, "_locked", Value::Bool(locked))
}

///|
fn builtin_thread_rlock_enter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.RLock.__enter__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.RLock.__enter__() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      thread_lock_set_locked(inst.dict, true)
      Ok(positional[0])
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.RLock.__enter__() expects a lock".to_string(),
        ),
      )
  }
}

///|
fn builtin_thread_rlock_exit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.RLock.__exit__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.RLock.__exit__() takes exactly four arguments".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      thread_lock_set_locked(inst.dict, false)
      Ok(Value::Bool(false))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.RLock.__exit__() expects a lock".to_string(),
        ),
      )
  }
}

///|
fn builtin_thread_rlock_acquire(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  // Accept `blocking=` / `timeout=` like CPython.
  let mut blocking = true
  let mut has_timeout = false
  for kw in keywords {
    if kw.0 == "blocking" {
      blocking = bool_from_value(kw.1)
    } else if kw.0 == "timeout" {
      has_timeout = true
      let _ = kw

    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "acquire() got an unexpected keyword argument '" + kw.0 + "'",
        ),
      )
    }
  }
  let _ = has_timeout
  if positional.length() < 1 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.RLock.acquire() takes 1 to 3 arguments".to_string(),
      ),
    )
  }
  if positional.length() >= 2 {
    blocking = bool_from_value(positional[1])
  }
  match positional[0] {
    Value::Instance(inst) => {
      let locked = thread_lock_get_locked(inst.dict)
      if locked && !blocking {
        return Ok(Value::Bool(false))
      }
      thread_lock_set_locked(inst.dict, true)
      Ok(Value::Bool(true))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.RLock.acquire() expects a lock".to_string(),
        ),
      )
  }
}

///|
fn builtin_thread_rlock_release(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.RLock.release", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.RLock.release() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      thread_lock_set_locked(inst.dict, false)
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.RLock.release() expects a lock".to_string(),
        ),
      )
  }
}

///|
fn builtin_thread_rlock_locked(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.RLock.locked", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.RLock.locked() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => Ok(Value::Bool(thread_lock_get_locked(inst.dict)))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.RLock.locked() expects a lock".to_string(),
        ),
      )
  }
}

///|
fn builtin_thread_rlock_at_fork_reinit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.RLock._at_fork_reinit", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.RLock._at_fork_reinit() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => {
      thread_lock_set_locked(inst.dict, false)
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_thread.RLock._at_fork_reinit() expects a lock".to_string(),
        ),
      )
  }
}

///|
fn make_weakref_instance(value : Value, klass_opt : ClassValue?) -> Value {
  let hash = @bigint.BigInt::from_int64(hash_string(value_to_string(value)))
  let dict : Array[(String, Value)] = [
    ("value", value),
    ("hashvalue", Value::Int(hash)),
  ]
  let klass = match klass_opt {
    Some(value) => value
    None => ClassValue::{ name: "weakref", bases: [], dict: [] }
  }
  Value::Instance(InstanceValue::{ class: klass, dict })
}

///|
fn builtin_weakref_ref(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.ref", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut cls_opt : ClassValue? = None
  let mut start = 0
  if positional.length() > 0 {
    match positional[0] {
      Value::Class(klass) => {
        cls_opt = Some(klass)
        start = 1
      }
      _ => ()
    }
  }
  let remaining = positional.length() - start
  if remaining != 1 && remaining != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "ref() takes one or two arguments".to_string(),
      ),
    )
  }
  Ok(make_weakref_instance(positional[start], cls_opt))
}

///|
fn builtin_weakref_proxy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.proxy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "proxy() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_weakref_getweakrefcount(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.getweakrefcount", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getweakrefcount() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::Int(0N))
}

///|
fn builtin_weakref_getweakrefs(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.getweakrefs", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getweakrefs() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::List([]))
}

///|
fn builtin_weakref_remove_dead_weakref(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref._remove_dead_weakref", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_remove_dead_weakref() takes exactly two arguments".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Dict(pairs) => {
      let _ = match dict_delete_key(pairs, positional[1]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_remove_dead_weakref() argument must be dict".to_string(),
        ),
      )
  }
}

///|
fn builtin_weakref_hash(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("weakref.__hash__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__hash__() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      match get_named_value(inst.dict, "hashvalue") {
        Some(Value::Int(value)) => Ok(Value::Int(value))
        Some(_) | None => Ok(Value::Int(0N))
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "__hash__() expects a weakref instance".to_string(),
        ),
      )
  }
}

///|
fn builtin_code_replace(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "code.replace() missing code object".to_string(),
      ),
    )
  }
  let mut flags = 0N
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "code" {
        match get_named_value(inst.dict, "co_flags") {
          Some(Value::Int(v)) => flags = v
          Some(Value::Bool(v)) => flags = if v { 1N } else { 0N }
          _ => ()
        }
      }
    _ => ()
  }
  for kw in keywords {
    if kw.0 == "co_flags" {
      let value = match index_from_value(kw.1, 0) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      flags = @bigint.BigInt::from_int(value)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "code.replace() got an unexpected keyword '" + kw.0 + "'",
        ),
      )
    }
  }
  Ok(make_code_instance(flags))
}

///|
fn builtin_coroutine_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("coroutine.close", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "coroutine.close() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_faulthandler_noop(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = positional
  let _ = keywords
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  Ok(Value::None)
}

///|
fn builtin_faulthandler_is_enabled(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = positional
  let _ = keywords
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  Ok(Value::Bool(false))
}

///|
fn builtin_select_select(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  // Minimal stub: always report nothing ready.
  // CPython signature: select(rlist, wlist, xlist[, timeout])
  if positional.length() < 3 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "select.select() takes 3 or 4 arguments".to_string(),
      ),
    )
  }
  Ok(Value::Tuple([Value::List([]), Value::List([]), Value::List([])]))
}

///|
fn struct_field_size(code : Char, repeat : Int) -> (Int, Int)? {
  let unit = match code {
    'x' => 1
    'c' => 1
    'b' => 1
    'B' => 1
    '?' => 1
    'h' => 2
    'H' => 2
    'i' => 4
    'I' => 4
    'l' => 4
    'L' => 4
    'q' => 8
    'Q' => 8
    'P' => 8
    's' => 1
    'p' => 1
    _ => -1
  }
  if unit < 0 {
    return None
  }
  if code == 'x' {
    Some((unit * repeat, 0))
  } else if code == 's' || code == 'p' {
    Some((unit * repeat, 1))
  } else {
    Some((unit * repeat, repeat))
  }
}

///|
fn struct_parse_format(fmt : String) -> Result[(Int, Int), RuntimeError] {
  let chars = fmt.to_array()
  let mut i = 0
  if chars.length() > 0 {
    let c0 = chars[0]
    if c0 == '@' || c0 == '=' || c0 == '<' || c0 == '>' || c0 == '!' {
      i = 1
    }
  }
  let mut size = 0
  let mut fields = 0
  let mut repeat = 0
  let mut has_repeat = false
  while i < chars.length() {
    let c = chars[i]
    if is_digit(c) {
      repeat = repeat * 10 + (c.to_int() - '0'.to_int())
      has_repeat = true
      i += 1
      continue
    }
    let n = if has_repeat { repeat } else { 1 }
    repeat = 0
    has_repeat = false
    match struct_field_size(c, n) {
      Some(pair) => {
        size += pair.0
        fields += pair.1
      }
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "struct.error: bad char in struct format".to_string(),
          ),
        )
    }
    i += 1
  }
  Ok((size, fields))
}

///|
priv enum StructEndian {
  Little
  Big
} derive(Eq)

///|
fn struct_parse_format_detail(
  fmt : String,
) -> Result[(StructEndian, Int, Int, Array[(Char, Int)]), RuntimeError] {
  let chars = fmt.to_array()
  let mut i = 0
  let mut endian = StructEndian::Little
  if chars.length() > 0 {
    let c0 = chars[0]
    if c0 == '>' || c0 == '!' {
      endian = StructEndian::Big
      i = 1
    } else if c0 == '<' {
      endian = StructEndian::Little
      i = 1
    } else if c0 == '@' || c0 == '=' {
      endian = StructEndian::Little
      i = 1
    }
  }
  let mut size = 0
  let mut fields = 0
  let mut repeat = 0
  let mut has_repeat = false
  let tokens : Array[(Char, Int)] = []
  while i < chars.length() {
    let c = chars[i]
    if is_digit(c) {
      repeat = repeat * 10 + (c.to_int() - '0'.to_int())
      has_repeat = true
      i += 1
      continue
    }
    let n = if has_repeat { repeat } else { 1 }
    repeat = 0
    has_repeat = false
    match struct_field_size(c, n) {
      Some(pair) => {
        size += pair.0
        fields += pair.1
      }
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "struct.error: bad char in struct format".to_string(),
          ),
        )
    }
    tokens.push((c, n))
    i += 1
  }
  Ok((endian, size, fields, tokens))
}

///|
fn struct_pack_int_bytes(
  value : @bigint.BigInt,
  length : Int,
  signed : Bool,
  endian : StructEndian,
) -> Result[Array[Int], RuntimeError] {
  let mut modulus = 1N
  for _i = 0; _i < length; _i = _i + 1 {
    modulus = modulus * 256
  }
  let mut unsigned_value = value
  if signed {
    let limit = modulus / 2
    if value < -limit || value >= limit {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "struct.error: argument out of range".to_string(),
        ),
      )
    }
    if value < 0N {
      unsigned_value = value + modulus
    }
  } else if value < 0N || value >= modulus {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "struct.error: argument out of range".to_string(),
      ),
    )
  }
  let out : Array[Int] = []
  let mut v = unsigned_value
  for _i = 0; _i < length; _i = _i + 1 {
    let byte_val = v % 256N
    let byte_int = match bigint_to_int_checked(byte_val) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    out.push(byte_int)
    v = v / 256N
  }
  if endian == StructEndian::Big {
    let ordered : Array[Int] = []
    let mut j = out.length() - 1
    while j >= 0 {
      ordered.push(out[j])
      j -= 1
    }
    return Ok(ordered)
  }
  Ok(out)
}

///|
fn struct_unpack_int_bytes(
  buf : Array[Int],
  offset : Int,
  length : Int,
  signed : Bool,
  endian : StructEndian,
) -> @bigint.BigInt {
  let mut value = 0N
  if endian == StructEndian::Big {
    for i = 0; i < length; i = i + 1 {
      value = value * 256 + @bigint.BigInt::from_int(buf[offset + i])
    }
  } else {
    let mut factor = 1N
    for i = 0; i < length; i = i + 1 {
      value = value + @bigint.BigInt::from_int(buf[offset + i]) * factor
      factor = factor * 256
    }
  }
  if signed && length > 0 {
    let sign_byte = if endian == StructEndian::Big {
      buf[offset]
    } else {
      buf[offset + length - 1]
    }
    if (sign_byte & 0x80) != 0 {
      let mut modulus = 1N
      for _i = 0; _i < length; _i = _i + 1 {
        modulus = modulus * 256
      }
      value = value - modulus
    }
  }
  value
}

///|
fn builtin_struct_calcsize(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_struct.calcsize", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.calcsize() takes exactly one argument".to_string(),
      ),
    )
  }
  let fmt = match positional[0] {
    Value::Str(s) => s
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => {
      let buf = StringBuilder::new()
      for b in values {
        buf.write_char((b & 0xFF).to_char().unwrap())
      }
      buf.to_string()
    }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_struct.calcsize() format must be str or bytes".to_string(),
        ),
      )
  }
  let (size, _) = match struct_parse_format(fmt) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Int(@bigint.BigInt::from_int(size)))
}

///|
fn builtin_struct_pack(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_struct.pack", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Err(missing_required_argument_error("_struct.pack", "format"))
  }
  let fmt = match positional[0] {
    Value::Str(s) => s
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => {
      let buf = StringBuilder::new()
      for b in values {
        buf.write_char((b & 0xFF).to_char().unwrap())
      }
      buf.to_string()
    }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_struct.pack() format must be str or bytes".to_string(),
        ),
      )
  }
  let (endian, _, fields, tokens) = match struct_parse_format_detail(fmt) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() - 1 != fields {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "struct.error: pack expected " +
        fields.to_string() +
        " items".to_string(),
      ),
    )
  }
  let mut arg_i = 1
  let out : Array[Int] = []
  for token in tokens {
    let code = token.0
    let n = token.1
    match code {
      'x' =>
        for _i = 0; _i < n; _i = _i + 1 {
          out.push(0)
        }
      's' => {
        let bytes = if arg_i >= positional.length() {
          []
        } else {
          let v = positional[arg_i]
          arg_i += 1
          match v {
            Value::Bytes(items)
            | Value::ByteArray(items)
            | Value::MemoryView(items) => items
            other =>
              match
                bytes_from_iterable(
                  "_struct.pack", other, globals, builtins, io,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
          }
        }
        for i = 0; i < n; i = i + 1 {
          if i < bytes.length() {
            out.push(bytes[i])
          } else {
            out.push(0)
          }
        }
      }
      'p' => {
        let bytes = if arg_i >= positional.length() {
          []
        } else {
          let v = positional[arg_i]
          arg_i += 1
          match v {
            Value::Bytes(items)
            | Value::ByteArray(items)
            | Value::MemoryView(items) => items
            other =>
              match
                bytes_from_iterable(
                  "_struct.pack", other, globals, builtins, io,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
          }
        }
        let max_payload = if n > 0 { n - 1 } else { 0 }
        let payload_len = if bytes.length() > max_payload {
          max_payload
        } else {
          bytes.length()
        }
        out.push(payload_len)
        let mut i = 0
        while i < max_payload {
          if i < payload_len {
            out.push(bytes[i])
          } else {
            out.push(0)
          }
          i += 1
        }
      }
      '?' =>
        for _i = 0; _i < n; _i = _i + 1 {
          let v = positional[arg_i]
          arg_i += 1
          out.push(if bool_from_value(v) { 1 } else { 0 })
        }
      'c' =>
        for _i = 0; _i < n; _i = _i + 1 {
          let v = positional[arg_i]
          arg_i += 1
          let b = match v {
            Value::Bytes(items)
            | Value::ByteArray(items)
            | Value::MemoryView(items) =>
              if items.length() == 1 {
                items[0]
              } else {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "struct.error: char format requires a bytes object of length 1".to_string(),
                  ),
                )
              }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "struct.error: char format requires a bytes object of length 1".to_string(),
                ),
              )
          }
          out.push(b)
        }
      _ => {
        let (unit, is_signed) = match code {
          'b' => (1, true)
          'B' => (1, false)
          'h' => (2, true)
          'H' => (2, false)
          'i' | 'l' => (4, true)
          'I' | 'L' => (4, false)
          'q' => (8, true)
          'Q' | 'P' => (8, false)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "struct.error: bad char in struct format".to_string(),
              ),
            )
        }
        for _i = 0; _i < n; _i = _i + 1 {
          let v = positional[arg_i]
          arg_i += 1
          let int_value = match v {
            Value::Int(bi) => bi
            Value::Bool(b) => if b { 1N } else { 0N }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "struct.error: required argument is not an integer".to_string(),
                ),
              )
          }
          let bytes = match
            struct_pack_int_bytes(int_value, unit, is_signed, endian) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for b in bytes {
            out.push(b)
          }
        }
      }
    }
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_struct_unpack(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_struct.unpack", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.unpack() takes exactly 2 arguments".to_string(),
      ),
    )
  }
  let fmt = match positional[0] {
    Value::Str(s) => s
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => {
      let buf = StringBuilder::new()
      for b in values {
        buf.write_char((b & 0xFF).to_char().unwrap())
      }
      buf.to_string()
    }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_struct.unpack() format must be str or bytes".to_string(),
        ),
      )
  }
  let (endian, size, fields, tokens) = match struct_parse_format_detail(fmt) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let buf = match positional[1] {
    Value::Bytes(items) | Value::ByteArray(items) | Value::MemoryView(items) =>
      items
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_struct.unpack() argument 2 must be a bytes-like object".to_string(),
        ),
      )
  }
  if buf.length() < size {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "struct.error: unpack requires a buffer of " +
        size.to_string() +
        " bytes",
      ),
    )
  }
  let items : Array[Value] = []
  let mut offset = 0
  for token in tokens {
    let code = token.0
    let n = token.1
    match code {
      'x' => offset += n
      's' => {
        let part : Array[Int] = []
        for i = 0; i < n; i = i + 1 {
          part.push(buf[offset + i])
        }
        offset += n
        items.push(Value::Bytes(part))
      }
      'p' => {
        let part : Array[Int] = []
        if n == 0 {
          items.push(Value::Bytes(part))
        } else {
          let declared_len = buf[offset]
          let max_payload = n - 1
          let payload_len = if declared_len > max_payload {
            max_payload
          } else {
            declared_len
          }
          for i = 0; i < payload_len; i = i + 1 {
            part.push(buf[offset + 1 + i])
          }
          items.push(Value::Bytes(part))
        }
        offset += n
      }
      '?' =>
        for _i = 0; _i < n; _i = _i + 1 {
          items.push(Value::Bool(buf[offset] != 0))
          offset += 1
        }
      'c' =>
        for _i = 0; _i < n; _i = _i + 1 {
          items.push(Value::Bytes([buf[offset]]))
          offset += 1
        }
      _ => {
        let (unit, is_signed) = match code {
          'b' => (1, true)
          'B' => (1, false)
          'h' => (2, true)
          'H' => (2, false)
          'i' | 'l' => (4, true)
          'I' | 'L' => (4, false)
          'q' => (8, true)
          'Q' | 'P' => (8, false)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "struct.error: bad char in struct format".to_string(),
              ),
            )
        }
        for _i = 0; _i < n; _i = _i + 1 {
          let v = struct_unpack_int_bytes(buf, offset, unit, is_signed, endian)
          items.push(Value::Int(v))
          offset += unit
        }
      }
    }
  }
  if items.length() != fields {
    // Best-effort safety for our parser, should not happen if struct_field_size matches.
    while items.length() < fields {
      items.push(Value::None)
    }
  }
  Ok(Value::Tuple(items))
}

///|
fn builtin_struct_pack_into(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  let _ = positional
  Ok(Value::None)
}

///|
fn builtin_struct_unpack_from(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  // Minimal: delegate to unpack, ignore offset.
  if positional.length() < 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.unpack_from() needs at least 2 arguments".to_string(),
      ),
    )
  }
  let fmt = positional[0]
  let buf = positional[1]
  builtin_struct_unpack([fmt, buf], [], locals, globals, builtins, io)
}

///|
fn builtin_struct_iter_unpack(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  let _ = positional
  Ok(Value::List([]))
}

///|
fn builtin_struct_clearcache(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  let _ = positional
  Ok(Value::None)
}

///|
fn builtin_struct_struct_init(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.Struct() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) => set_named_value(inst.dict, "format", positional[1])
    _ => ()
  }
  Ok(Value::None)
}

///|
fn builtin_struct_struct_pack(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.Struct.pack() missing self".to_string(),
      ),
    )
  }
  let fmt_opt = match positional[0] {
    Value::Instance(inst) => get_named_value(inst.dict, "format")
    _ => None
  }
  let fmt = match fmt_opt {
    Some(Value::Str(s)) => Value::Str(s)
    _ => Value::Str("@".to_string())
  }
  let args : Array[Value] = [fmt]
  for i = 1; i < positional.length(); i = i + 1 {
    args.push(positional[i])
  }
  builtin_struct_pack(args, [], locals, globals, builtins, io)
}

///|
fn builtin_struct_struct_unpack(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.Struct.unpack() takes exactly one argument".to_string(),
      ),
    )
  }
  let fmt_opt = match positional[0] {
    Value::Instance(inst) => get_named_value(inst.dict, "format")
    _ => None
  }
  let fmt = match fmt_opt {
    Some(Value::Str(s)) => Value::Str(s)
    _ => Value::Str("@".to_string())
  }
  builtin_struct_unpack([fmt, positional[1]], [], locals, globals, builtins, io)
}

///|
fn builtin_struct_struct_calcsize(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_struct.Struct.calcsize() takes no arguments".to_string(),
      ),
    )
  }
  let fmt_opt = match positional[0] {
    Value::Instance(inst) => get_named_value(inst.dict, "format")
    _ => None
  }
  let fmt = match fmt_opt {
    Some(Value::Str(s)) => Value::Str(s)
    _ => Value::Str("@".to_string())
  }
  builtin_struct_calcsize([fmt], [], locals, globals, builtins, io)
}

///|
let gc_enabled_ref : Ref[Bool] = { val: true }

///|
let gc_threshold_ref : Ref[(Int, Int, Int)] = { val: (700, 10, 10) }

///|
fn builtin_gc_enable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.enable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.enable() takes no arguments".to_string(),
      ),
    )
  }
  gc_enabled_ref.val = true
  Ok(Value::None)
}

///|
fn builtin_gc_disable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.disable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.disable() takes no arguments".to_string(),
      ),
    )
  }
  gc_enabled_ref.val = false
  Ok(Value::None)
}

///|
fn builtin_gc_isenabled(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.isenabled", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.isenabled() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Bool(gc_enabled_ref.val))
}

///|
fn builtin_gc_collect(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.collect", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  // CPython accepts an optional generation int; we ignore it.
  if positional.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.collect() takes at most 1 argument".to_string(),
      ),
    )
  }
  Ok(Value::Int(0N))
}

///|
fn builtin_gc_get_threshold(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.get_threshold", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.get_threshold() takes no arguments".to_string(),
      ),
    )
  }
  let (t0, t1, t2) = gc_threshold_ref.val
  Ok(
    Value::Tuple([
      Value::Int(@bigint.BigInt::from_int(t0)),
      Value::Int(@bigint.BigInt::from_int(t1)),
      Value::Int(@bigint.BigInt::from_int(t2)),
    ]),
  )
}

///|
fn builtin_gc_set_threshold(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.set_threshold", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 1 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.set_threshold() takes 1 to 3 arguments".to_string(),
      ),
    )
  }
  let t0 = match index_from_value(positional[0], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let t1 = if positional.length() >= 2 {
    match index_from_value(positional[1], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    gc_threshold_ref.val.1
  }
  let t2 = if positional.length() >= 3 {
    match index_from_value(positional[2], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    gc_threshold_ref.val.2
  }
  gc_threshold_ref.val = (t0, t1, t2)
  Ok(Value::None)
}

///|
fn builtin_gc_get_count(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("gc.get_count", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "gc.get_count() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Tuple([Value::Int(0N), Value::Int(0N), Value::Int(0N)]))
}

///|
fn builtin_binascii_crc32(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("binascii.crc32", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.crc32() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let bytes = match
    binascii_bytes_like("binascii.crc32", positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "binascii.crc32() argument must be bytes-like".to_string(),
        ),
      )
  }
  let init = if positional.length() == 2 {
    match positional[1] {
      Value::Int(v) => v
      Value::Bool(v) => if v { 1N } else { 0N }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "binascii.crc32() value must be int".to_string(),
          ),
        )
    }
  } else {
    0N
  }
  let mask_big = 0xFFFFFFFFN
  let init_u32 : Int64 = (init & mask_big).to_int64()
  let mask : Int64 = 0xFFFFFFFFL
  let poly : Int64 = 0xEDB88320L
  let mut crc : Int64 = (init_u32 ^ mask) & mask
  for b in bytes {
    crc = (crc ^ (b & 0xFF).to_int64()) & mask
    for _i = 0; _i < 8; _i = _i + 1 {
      if (crc & 1) != 0 {
        crc = ((crc >> 1) ^ poly) & mask
      } else {
        crc = (crc >> 1) & mask
      }
    }
  }
  let out = (crc ^ mask) & mask
  Ok(Value::Int(@bigint.BigInt::from_int64(out)))
}

///|
fn binascii_bytes_like(
  name : String,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Int], RuntimeError] {
  let _ = globals
  let _ = builtins
  let _ = io
  match value {
    Value::Bytes(values) => Ok(copy_ints(values))
    Value::ByteArray(values) => Ok(copy_ints(values))
    Value::MemoryView(values) => Ok(copy_ints(values))
    Value::Instance(inst) =>
      if inst.class.name == "array" {
        let typecode = match get_named_value(inst.dict, "typecode") {
          Some(Value::Str(v)) => v
          _ => "".to_string()
        }
        if typecode != "b" && typecode != "B" {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "a bytes-like object is required, not '" +
              type_name_from_value(value) +
              "'".to_string(),
            ),
          )
        }
        let data = match get_named_value(inst.dict, "_data") {
          Some(Value::List(values)) => values
          _ => []
        }
        let out : Array[Int] = []
        for v in data {
          let int_val = match v {
            Value::Int(bi) =>
              match bigint_to_int_checked(bi) {
                Ok(iv) => iv
                Err(err) => return Err(err)
              }
            Value::Bool(b) => if b { 1 } else { 0 }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  name + "() an integer is required".to_string(),
                ),
              )
          }
          out.push(int_val & 0xFF)
        }
        Ok(out)
      } else if inst.class.name == "memoryview" {
        match get_named_value(inst.dict, "__mpython_contiguous__") {
          Some(Value::Bool(false)) =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "BufferError: memoryview: underlying buffer is not C-contiguous".to_string(),
              ),
            )
          _ => ()
        }
        match get_named_value(inst.dict, "__mpython_bytes__") {
          Some(Value::MemoryView(values))
          | Some(Value::Bytes(values))
          | Some(Value::ByteArray(values)) => Ok(copy_ints(values))
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "a bytes-like object is required, not '" +
                type_name_from_value(value) +
                "'".to_string(),
              ),
            )
        }
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "a bytes-like object is required, not '" +
            type_name_from_value(value) +
            "'".to_string(),
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "a bytes-like object is required, not '" +
          type_name_from_value(value) +
          "'".to_string(),
        ),
      )
  }
}

///|
fn binascii_a2b_input_bytes(
  name : String,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Int], RuntimeError] {
  match value {
    Value::Str(text) => {
      let out : Array[Int] = []
      for ch in text.to_array() {
        let code = ch.to_int()
        if code > 127 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "ValueError: string argument should contain only ASCII characters".to_string(),
            ),
          )
        }
        out.push(code)
      }
      Ok(out)
    }
    _ => binascii_bytes_like(name, value, globals, builtins, io)
  }
}

///|
fn binascii_error_from_message(
  message : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[RuntimeError, RuntimeError] {
  match module_cache_get("binascii") {
    Some(Value::Instance(inst)) =>
      match get_named_value(inst.dict, "Error") {
        Some(Value::Class(klass)) => {
          let inst_value = match
            call_callable_with_env(
              Value::Class(klass),
              [Value::Str(message)],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(Value::Instance(exc_inst)) => exc_inst
            Ok(_) =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "RuntimeError: binascii.Error constructor returned non-exception".to_string(),
                ),
              )
            Err(err) => return Err(err)
          }
          Ok(runtime_error_from_exception_instance(inst_value))
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "ImportError: binascii.Error is missing".to_string(),
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ImportError: binascii module is not loaded".to_string(),
        ),
      )
  }
}

///|
fn builtin_binascii_b2a_base64(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut newline : Bool = true
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.b2a_base64() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 2 {
    newline = match positional[1] {
      Value::Bool(v) => v
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "binascii.b2a_base64() newline must be bool".to_string(),
          ),
        )
    }
  }
  for pair in keywords {
    if pair.0 == "newline" {
      newline = match pair.1 {
        Value::Bool(v) => v
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "binascii.b2a_base64() newline must be bool".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "b2a_base64() got an unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  let bytes = match
    binascii_bytes_like(
      "binascii.b2a_base64",
      positional[0],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_array()
  fn alpha_at(alpha : Array[Char], idx : Int) -> Int {
    alpha[idx].to_int()
  }

  let out : Array[Int] = []
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i] & 0xFF
    let b1 = if i + 1 < bytes.length() { bytes[i + 1] & 0xFF } else { 0 }
    let b2 = if i + 2 < bytes.length() { bytes[i + 2] & 0xFF } else { 0 }
    let triple = (b0 << 16) | (b1 << 8) | b2
    let idx0 = (triple >> 18) & 0x3F
    let idx1 = (triple >> 12) & 0x3F
    let idx2 = (triple >> 6) & 0x3F
    let idx3 = triple & 0x3F
    out.push(alpha_at(alphabet, idx0))
    out.push(alpha_at(alphabet, idx1))
    if i + 1 < bytes.length() {
      out.push(alpha_at(alphabet, idx2))
    } else {
      out.push('='.to_int())
    }
    if i + 2 < bytes.length() {
      out.push(alpha_at(alphabet, idx3))
    } else {
      out.push('='.to_int())
    }
    i = i + 3
  }
  if newline {
    out.push('\n'.to_int())
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_binascii_a2b_base64(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut strict_mode : Bool = false
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.a2b_base64() takes exactly one argument".to_string(),
      ),
    )
  }
  for pair in keywords {
    if pair.0 == "strict_mode" {
      strict_mode = match pair.1 {
        Value::Bool(v) => v
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "binascii.a2b_base64() strict_mode must be bool".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "a2b_base64() got an unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  let raw = match
    binascii_a2b_input_bytes(
      "binascii.a2b_base64",
      positional[0],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  // Map base64 sextets.
  let table : Array[Int] = []
  for _i = 0; _i < 256; _i = _i + 1 {
    table.push(-1)
  }
  let alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_array()
  for i = 0; i < alpha.length(); i = i + 1 {
    table[alpha[i].to_int()] = i
  }
  let decode_strict_error = fn(
    message : String,
  ) -> Result[Value, RuntimeError] {
    let err = match
      binascii_error_from_message(message, globals, builtins, io) {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    Err(err)
  }
  let decode_error_invalid_length = fn(
    n_data_chars : Int,
  ) -> Result[Value, RuntimeError] {
    let msg = "Invalid base64-encoded string: number of data characters (" +
      n_data_chars.to_string() +
      ") cannot be 1 more than a multiple of 4"
    decode_strict_error(msg)
  }
  if strict_mode {
    if raw.length() == 0 {
      return Ok(Value::Bytes([]))
    }
    let out : Array[Int] = []
    let mut quad : Array[Int] = []
    let mut data_chars = 0
    let mut i = 0
    while i < raw.length() {
      let c = raw[i] & 0xFF
      if c == '='.to_int() && quad.length() == 0 {
        if i == 0 {
          return decode_strict_error("Leading padding".to_string())
        }
        return decode_strict_error("Excess padding".to_string())
      }
      if c != '='.to_int() {
        if table[c] < 0 {
          return decode_strict_error("Only base64 data is allowed".to_string())
        }
        data_chars = data_chars + 1
      }
      quad.push(c)
      if quad.length() == 4 {
        if quad[0] == '='.to_int() || quad[1] == '='.to_int() {
          return decode_strict_error("Discontinuous padding".to_string())
        }
        let pad2 = quad[2] == '='.to_int()
        let pad3 = quad[3] == '='.to_int()
        if pad2 && !pad3 {
          return decode_strict_error("Discontinuous padding".to_string())
        }
        let v0 = table[quad[0]]
        let v1 = table[quad[1]]
        let v2 = if pad2 { 0 } else { table[quad[2]] }
        let v3 = if pad3 { 0 } else { table[quad[3]] }
        let triple = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
        out.push((triple >> 16) & 0xFF)
        if !pad2 {
          out.push((triple >> 8) & 0xFF)
        }
        if !pad3 {
          out.push(triple & 0xFF)
        }
        if pad2 || pad3 {
          if i + 1 != raw.length() {
            return decode_strict_error("Excess data".to_string())
          }
          return Ok(Value::Bytes(out))
        }
        quad = []
      }
      i = i + 1
    }
    if quad.length() != 0 {
      if data_chars % 4 == 1 {
        return decode_error_invalid_length(data_chars)
      }
      return decode_strict_error("Incorrect padding".to_string())
    }
    Ok(Value::Bytes(out))
  } else {
    // Non-strict mode: ignore non-alphabet characters and be permissive about
    // stray '=' padding, matching CPython's legacy decoder behavior.
    let filtered : Array[Int] = []
    let mut n_data_chars = 0
    for b in raw {
      let c = b & 0xFF
      if c == '='.to_int() {
        filtered.push(c)
      } else if table[c] >= 0 {
        filtered.push(c)
        n_data_chars = n_data_chars + 1
      } else {
        ()
      }
    }
    if n_data_chars % 4 == 1 {
      let err = match
        binascii_error_from_message(
          "Invalid base64-encoded string: number of data characters (" +
          n_data_chars.to_string() +
          ") cannot be 1 more than a multiple of 4".to_string(),
          globals,
          builtins,
          io,
        ) {
        Ok(e) => e
        Err(e) => return Err(e)
      }
      return Err(err)
    }
    let out : Array[Int] = []
    let mut quad : Array[Int] = []
    let mut idx = 0
    while idx < filtered.length() {
      let c = filtered[idx]
      if c == '='.to_int() {
        if quad.length() == 0 {
          idx = idx + 1
          continue
        }
        if quad.length() == 1 {
          let err = match
            binascii_error_from_message(
              "Incorrect padding".to_string(),
              globals,
              builtins,
              io,
            ) {
            Ok(e) => e
            Err(e) => return Err(e)
          }
          return Err(err)
        }
        if quad.length() == 2 {
          if idx + 1 < filtered.length() && filtered[idx + 1] != '='.to_int() {
            idx = idx + 1
            continue
          }
        }
        quad.push(c)
      } else {
        quad.push(c)
      }
      if quad.length() == 4 {
        let pad2 = quad[2] == '='.to_int()
        let pad3 = quad[3] == '='.to_int()
        if pad2 && !pad3 {
          let err = match
            binascii_error_from_message(
              "Incorrect padding".to_string(),
              globals,
              builtins,
              io,
            ) {
            Ok(e) => e
            Err(e) => return Err(e)
          }
          return Err(err)
        }
        let v0 = table[quad[0]]
        let v1 = table[quad[1]]
        let v2 = if pad2 { 0 } else { table[quad[2]] }
        let v3 = if pad3 { 0 } else { table[quad[3]] }
        let triple = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
        out.push((triple >> 16) & 0xFF)
        if !pad2 {
          out.push((triple >> 8) & 0xFF)
        }
        if !pad3 {
          out.push(triple & 0xFF)
        }
        if pad2 || pad3 {
          return Ok(Value::Bytes(out))
        }
        quad = []
      }
      idx = idx + 1
    }
    if quad.length() == 0 {
      return Ok(Value::Bytes(out))
    }
    if quad.length() == 2 || quad.length() == 3 {
      let err = match
        binascii_error_from_message(
          "Incorrect padding".to_string(),
          globals,
          builtins,
          io,
        ) {
        Ok(e) => e
        Err(e) => return Err(e)
      }
      return Err(err)
    }
    // quad.length()==1 should have been caught by the invalid-length check.
    let err = match
      binascii_error_from_message(
        "Incorrect padding".to_string(),
        globals,
        builtins,
        io,
      ) {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    Err(err)
  }
}

///|
fn binascii_unhexlify_bytes(
  bytes : Array[Int],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Int], RuntimeError] {
  if bytes.length() % 2 != 0 {
    let err = match
      binascii_error_from_message(
        "Odd-length string".to_string(),
        globals,
        builtins,
        io,
      ) {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    return Err(err)
  }
  fn hex_value(v : Int) -> Int? {
    if v >= '0'.to_int() && v <= '9'.to_int() {
      Some(v - '0'.to_int())
    } else if v >= 'a'.to_int() && v <= 'f'.to_int() {
      Some(10 + (v - 'a'.to_int()))
    } else if v >= 'A'.to_int() && v <= 'F'.to_int() {
      Some(10 + (v - 'A'.to_int()))
    } else {
      None
    }
  }

  let out : Array[Int] = []
  let mut i = 0
  while i < bytes.length() {
    let hi = match hex_value(bytes[i]) {
      Some(v) => v
      None => {
        let err = match
          binascii_error_from_message(
            "Non-hex digit found".to_string(),
            globals,
            builtins,
            io,
          ) {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        return Err(err)
      }
    }
    let lo = match hex_value(bytes[i + 1]) {
      Some(v) => v
      None => {
        let err = match
          binascii_error_from_message(
            "Non-hex digit found".to_string(),
            globals,
            builtins,
            io,
          ) {
          Ok(e) => e
          Err(e) => return Err(e)
        }
        return Err(err)
      }
    }
    out.push((hi << 4) | lo)
    i = i + 2
  }
  Ok(out)
}

///|
fn builtin_binascii_hexlify(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.hexlify() takes from 1 to 3 arguments".to_string(),
      ),
    )
  }
  let mut sep_value : Value? = None
  let mut bytes_per_sep_value : Value? = None
  if positional.length() >= 2 {
    sep_value = Some(positional[1])
  }
  if positional.length() == 3 {
    bytes_per_sep_value = Some(positional[2])
  }
  for pair in keywords {
    match pair.0 {
      "sep" =>
        if sep_value is Some(_) {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "hexlify() got multiple values for argument 'sep'".to_string(),
            ),
          )
        } else {
          sep_value = Some(pair.1)
        }
      "bytes_per_sep" =>
        if bytes_per_sep_value is Some(_) {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "hexlify() got multiple values for argument 'bytes_per_sep'".to_string(),
            ),
          )
        } else {
          bytes_per_sep_value = Some(pair.1)
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "hexlify() got an unexpected keyword argument '" + pair.0 + "'",
          ),
        )
    }
  }
  let bytes = match
    binascii_bytes_like(
      "binascii.hexlify",
      positional[0],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let sep_bytes : Array[Int] = match sep_value {
    None | Some(Value::None) => []
    Some(Value::Str(text)) => {
      let out : Array[Int] = []
      for ch in text.to_array() {
        let code = ch.to_int()
        if code > 127 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "hexlify() sep must be ASCII str".to_string(),
            ),
          )
        }
        out.push(code)
      }
      out
    }
    Some(Value::Bytes(v))
    | Some(Value::ByteArray(v))
    | Some(Value::MemoryView(v)) => copy_ints(v)
    Some(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "hexlify() sep must be str or bytes-like".to_string(),
        ),
      )
  }
  if sep_bytes.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: sep must be at most one byte".to_string(),
      ),
    )
  }
  let bytes_per_sep = match bytes_per_sep_value {
    None => 1
    Some(Value::Int(v)) =>
      match bigint_to_int_checked(v) {
        Ok(iv) => iv
        Err(err) => return Err(err)
      }
    Some(Value::Bool(v)) => if v { 1 } else { 0 }
    Some(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "hexlify() bytes_per_sep must be int".to_string(),
        ),
      )
  }
  if bytes_per_sep == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: bytes_per_sep must not be zero".to_string(),
      ),
    )
  }
  let hex = "0123456789abcdef".to_array()
  let out : Array[Int] = []
  if sep_bytes.length() == 0 {
    for b in bytes {
      let v = b & 0xFF
      out.push(hex[(v >> 4) & 0xF].to_int())
      out.push(hex[v & 0xF].to_int())
    }
    return Ok(Value::Bytes(out))
  }
  let sep_b = sep_bytes[0] & 0xFF
  let bps = bytes_per_sep
  let mut first_group = 0
  let mut group_len = bps
  if bps < 0 {
    group_len = -bps
    let rem = bytes.length() % group_len
    first_group = if rem == 0 { group_len } else { rem }
  }
  for idx = 0; idx < bytes.length(); idx = idx + 1 {
    if idx > 0 {
      if bps > 0 {
        if idx % bps == 0 {
          out.push(sep_b)
        }
      } else if idx == first_group ||
        (idx > first_group && (idx - first_group) % group_len == 0) {
        out.push(sep_b)
      }
    }
    let v = bytes[idx] & 0xFF
    out.push(hex[(v >> 4) & 0xF].to_int())
    out.push(hex[v & 0xF].to_int())
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_binascii_unhexlify(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("binascii.unhexlify", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.unhexlify() takes exactly one argument".to_string(),
      ),
    )
  }
  let bytes = match
    binascii_a2b_input_bytes(
      "binascii.unhexlify",
      positional[0],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let decoded = match binascii_unhexlify_bytes(bytes, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bytes(decoded))
}

///|
fn builtin_binascii_b2a_hex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  builtin_binascii_hexlify(positional, keywords, locals, globals, builtins, io)
}

///|
fn builtin_binascii_a2b_hex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  builtin_binascii_unhexlify(
    positional, keywords, locals, globals, builtins, io,
  )
}

///|
fn builtin_binascii_a2b_qp(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut data_value : Value? = None
  let mut header = false
  if positional.length() >= 1 {
    data_value = Some(positional[0])
  }
  if positional.length() >= 2 {
    header = match positional[1] {
      Value::Bool(v) => v
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "binascii.a2b_qp() header must be bool".to_string(),
          ),
        )
    }
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.a2b_qp() takes at most 2 arguments".to_string(),
      ),
    )
  }
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "data" =>
        if positional.length() >= 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "a2b_qp() got multiple values for argument 'data'".to_string(),
            ),
          )
        } else {
          data_value = Some(value)
        }
      "header" =>
        if positional.length() >= 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "a2b_qp() got multiple values for argument 'header'".to_string(),
            ),
          )
        } else {
          header = match value {
            Value::Bool(v) => v
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "binascii.a2b_qp() header must be bool".to_string(),
                ),
              )
          }
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "a2b_qp() got an unexpected keyword argument '" + key + "'",
          ),
        )
    }
  }
  let data_value = match data_value {
    Some(v) => v
    None => return Err(missing_required_argument_error("a2b_qp", "data"))
  }
  let bytes = match
    binascii_a2b_input_bytes(
      "binascii.a2b_qp", data_value, globals, builtins, io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  fn hex_value(v : Int) -> Int? {
    if v >= '0'.to_int() && v <= '9'.to_int() {
      Some(v - '0'.to_int())
    } else if v >= 'a'.to_int() && v <= 'f'.to_int() {
      Some(10 + (v - 'a'.to_int()))
    } else if v >= 'A'.to_int() && v <= 'F'.to_int() {
      Some(10 + (v - 'A'.to_int()))
    } else {
      None
    }
  }

  let out : Array[Int] = []
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i] & 0xFF
    if header && b == '_'.to_int() {
      out.push(' '.to_int())
      i = i + 1
      continue
    }
    if b != '='.to_int() {
      out.push(b)
      i = i + 1
      continue
    }
    if i + 1 >= bytes.length() {
      // Trailing '=' is ignored.
      break
    }
    let b1 = bytes[i + 1] & 0xFF
    if b1 == '\n'.to_int() {
      // Soft line break: "=\n"
      i = i + 2
      continue
    }
    if b1 == '\r'.to_int() {
      if i + 2 < bytes.length() && (bytes[i + 2] & 0xFF) == '\n'.to_int() {
        // Soft line break: "=\r\n"
        i = i + 3
        continue
      }
      // "=\r" eats everything up to (and including) the next '\n' if present.
      i = i + 2
      while i < bytes.length() && (bytes[i] & 0xFF) != '\n'.to_int() {
        i = i + 1
      }
      if i < bytes.length() && (bytes[i] & 0xFF) == '\n'.to_int() {
        i = i + 1
      }
      continue
    }
    if i + 2 < bytes.length() {
      let b2 = bytes[i + 2] & 0xFF
      match (hex_value(b1), hex_value(b2)) {
        (Some(hi), Some(lo)) => {
          out.push((hi << 4) | lo)
          i = i + 3
          continue
        }
        _ => ()
      }
    }
    // Invalid escape: keep '=' literally.
    out.push('='.to_int())
    i = i + 1
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_binascii_b2a_qp(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut quotetabs = false
  let mut istext = true
  let mut header = false
  if positional.length() == 0 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.b2a_qp() takes from 1 to 4 arguments".to_string(),
      ),
    )
  }
  if positional.length() >= 2 {
    quotetabs = match positional[1] {
      Value::Bool(v) => v
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "binascii.b2a_qp() quotetabs must be bool".to_string(),
          ),
        )
    }
  }
  if positional.length() >= 3 {
    istext = match positional[2] {
      Value::Bool(v) => v
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "binascii.b2a_qp() istext must be bool".to_string(),
          ),
        )
    }
  }
  if positional.length() == 4 {
    header = match positional[3] {
      Value::Bool(v) => v
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "binascii.b2a_qp() header must be bool".to_string(),
          ),
        )
    }
  }
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "quotetabs" =>
        if positional.length() >= 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "b2a_qp() got multiple values for argument 'quotetabs'".to_string(),
            ),
          )
        } else {
          quotetabs = match value {
            Value::Bool(v) => v
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "binascii.b2a_qp() quotetabs must be bool".to_string(),
                ),
              )
          }
        }
      "istext" =>
        if positional.length() >= 3 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "b2a_qp() got multiple values for argument 'istext'".to_string(),
            ),
          )
        } else {
          istext = match value {
            Value::Bool(v) => v
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "binascii.b2a_qp() istext must be bool".to_string(),
                ),
              )
          }
        }
      "header" =>
        if positional.length() >= 4 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "b2a_qp() got multiple values for argument 'header'".to_string(),
            ),
          )
        } else {
          header = match value {
            Value::Bool(v) => v
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "binascii.b2a_qp() header must be bool".to_string(),
                ),
              )
          }
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "b2a_qp() got an unexpected keyword argument '" + key + "'",
          ),
        )
    }
  }
  let bytes = match
    binascii_bytes_like("binascii.b2a_qp", positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  fn hex_upper(n : Int) -> Int {
    if n < 10 {
      '0'.to_int() + n
    } else {
      'A'.to_int() + (n - 10)
    }
  }

  fn emit_hex_escape(out : Array[Int], b : Int) -> Unit {
    let v = b & 0xFF
    out.push('='.to_int())
    out.push(hex_upper((v >> 4) & 0xF))
    out.push(hex_upper(v & 0xF))
  }

  fn uu_newline_bytes(bytes : Array[Int]) -> Array[Int] {
    let mut has_crlf = false
    for i = 0; i + 1 < bytes.length(); i = i + 1 {
      if (bytes[i] & 0xFF) == '\r'.to_int() &&
        (bytes[i + 1] & 0xFF) == '\n'.to_int() {
        has_crlf = true
        break
      }
    }
    if has_crlf {
      ['\r'.to_int(), '\n'.to_int()]
    } else {
      ['\n'.to_int()]
    }
  }

  let newline = uu_newline_bytes(bytes)
  let out : Array[Int] = []
  fn soft_break(
    out : Array[Int],
    newline : Array[Int],
    col_ref : Ref[Int],
  ) -> Unit {
    out.push('='.to_int())
    for b in newline {
      out.push(b)
    }
    col_ref.val = 0
  }

  let col_ref : Ref[Int] = { val: 0 }
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i] & 0xFF
    if istext {
      if b == '\r'.to_int() &&
        i + 1 < bytes.length() &&
        (bytes[i + 1] & 0xFF) == '\n'.to_int() {
        for nb in newline {
          out.push(nb)
        }
        col_ref.val = 0
        i = i + 2
        continue
      }
      if b == '\n'.to_int() {
        for nb in newline {
          out.push(nb)
        }
        col_ref.val = 0
        i = i + 1
        continue
      }
    }
    let chunk : Array[Int] = []

    // Special cases for spaces and tabs.
    if b == ' '.to_int() || b == '\t'.to_int() {
      let at_end = i + 1 >= bytes.length()
      let next_is_break = if istext && !at_end {
        let n1 = bytes[i + 1] & 0xFF
        n1 == '\n'.to_int() ||
        (
          n1 == '\r'.to_int() &&
          i + 2 < bytes.length() &&
          (bytes[i + 2] & 0xFF) == '\n'.to_int()
        )
      } else {
        false
      }
      let trailing = at_end || next_is_break
      if trailing || quotetabs {
        emit_hex_escape(chunk, b)
      } else if header && b == ' '.to_int() {
        chunk.push('_'.to_int())
      } else {
        chunk.push(b)
      }
    } else if header && b == '_'.to_int() {
      emit_hex_escape(chunk, b)
    } else if b == '.'.to_int() && col_ref.val == 0 {
      emit_hex_escape(chunk, b)
    } else if b == '='.to_int() {
      emit_hex_escape(chunk, b)
    } else if istext && b == '\r'.to_int() {
      // Bare CR is treated as literal in text mode.
      chunk.push(b)
    } else if b >= 33 && b <= 126 {
      chunk.push(b)
    } else if istext && b == '\t'.to_int() {
      chunk.push(b)
    } else {
      emit_hex_escape(chunk, b)
    }

    // Line wrapping (RFC 2045: 76 chars max).
    if col_ref.val + chunk.length() > 76 {
      soft_break(out, newline, col_ref)
    }
    for v in chunk {
      out.push(v)
    }
    col_ref.val = col_ref.val + chunk.length()
    i = i + 1
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_binascii_b2a_uu(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut backtick = false
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.b2a_uu() takes exactly one argument".to_string(),
      ),
    )
  }
  for pair in keywords {
    if pair.0 == "backtick" {
      backtick = match pair.1 {
        Value::Bool(v) => v
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "binascii.b2a_uu() backtick must be bool".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "b2a_uu() got an unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  let bytes = match
    binascii_bytes_like("binascii.b2a_uu", positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if bytes.length() > 45 {
    let err = match
      binascii_error_from_message(
        "At most 45 bytes at once".to_string(),
        globals,
        builtins,
        io,
      ) {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    return Err(err)
  }
  fn uu_char(v : Int, backtick : Bool) -> Int {
    let vv = v & 0x3F
    if vv == 0 && backtick {
      '`'.to_int()
    } else {
      vv + 32
    }
  }

  let out : Array[Int] = []
  out.push(uu_char(bytes.length(), backtick))
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i] & 0xFF
    let b1 = if i + 1 < bytes.length() { bytes[i + 1] & 0xFF } else { 0 }
    let b2 = if i + 2 < bytes.length() { bytes[i + 2] & 0xFF } else { 0 }
    let v0 = (b0 >> 2) & 0x3F
    let v1 = ((b0 << 4) | (b1 >> 4)) & 0x3F
    let v2 = ((b1 << 2) | (b2 >> 6)) & 0x3F
    let v3 = b2 & 0x3F
    out.push(uu_char(v0, backtick))
    out.push(uu_char(v1, backtick))
    out.push(uu_char(v2, backtick))
    out.push(uu_char(v3, backtick))
    i = i + 3
  }
  out.push('\n'.to_int())
  Ok(Value::Bytes(out))
}

///|
fn builtin_binascii_a2b_uu(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("binascii.a2b_uu", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.a2b_uu() takes exactly one argument".to_string(),
      ),
    )
  }
  let bytes = match
    binascii_a2b_input_bytes(
      "binascii.a2b_uu",
      positional[0],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if bytes.length() == 0 {
    return Ok(Value::Bytes([]))
  }
  let len_char = bytes[0] & 0xFF
  let n = (len_char - 32) & 0x3F
  fn uu_val(c : Int) -> Int {
    (c - 32) & 0x3F
  }

  let encoded : Array[Int] = []
  for i = 1; i < bytes.length(); i = i + 1 {
    let c = bytes[i] & 0xFF
    if c == '\n'.to_int() || c == '\r'.to_int() {
      break
    }
    encoded.push(c)
  }
  if encoded.length() != 0 && encoded.length() % 4 != 0 {
    let err = match
      binascii_error_from_message(
        "Illegal uuencoded line".to_string(),
        globals,
        builtins,
        io,
      ) {
      Ok(e) => e
      Err(e) => return Err(e)
    }
    return Err(err)
  }
  let groups = (n + 2) / 3
  let out : Array[Int] = []
  let mut idx = 0
  for _g = 0; _g < groups; _g = _g + 1 {
    let c0 = if idx < encoded.length() { uu_val(encoded[idx]) } else { 0 }
    let c1 = if idx + 1 < encoded.length() {
      uu_val(encoded[idx + 1])
    } else {
      0
    }
    let c2 = if idx + 2 < encoded.length() {
      uu_val(encoded[idx + 2])
    } else {
      0
    }
    let c3 = if idx + 3 < encoded.length() {
      uu_val(encoded[idx + 3])
    } else {
      0
    }
    let b0 = ((c0 << 2) | (c1 >> 4)) & 0xFF
    let b1 = (((c1 & 0xF) << 4) | (c2 >> 2)) & 0xFF
    let b2 = (((c2 & 0x3) << 6) | c3) & 0xFF
    out.push(b0)
    out.push(b1)
    out.push(b2)
    idx = idx + 4
  }
  // Truncate to declared length.
  let truncated : Array[Int] = []
  for i2 = 0; i2 < out.length() && i2 < n; i2 = i2 + 1 {
    truncated.push(out[i2])
  }
  Ok(Value::Bytes(truncated))
}

///|
fn builtin_binascii_crc_hqx(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("binascii.crc_hqx", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "binascii.crc_hqx() takes exactly 2 arguments".to_string(),
      ),
    )
  }
  let bytes = match
    binascii_bytes_like(
      "binascii.crc_hqx",
      positional[0],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut crc = match positional[1] {
    Value::Int(v) =>
      match bigint_to_int_checked(v) {
        Ok(iv) => iv
        Err(err) => return Err(err)
      }
    Value::Bool(v) => if v { 1 } else { 0 }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "binascii.crc_hqx() crc must be int".to_string(),
        ),
      )
  }
  crc = crc & 0xFFFF
  fn crc_step(crc : Int, b : Int) -> Int {
    let mut c = (crc ^ ((b & 0xFF) << 8)) & 0xFFFF
    for _i = 0; _i < 8; _i = _i + 1 {
      if (c & 0x8000) != 0 {
        c = ((c << 1) ^ 0x1021) & 0xFFFF
      } else {
        c = (c << 1) & 0xFFFF
      }
    }
    c
  }

  for b in bytes {
    crc = crc_step(crc, b)
  }
  Ok(Value::Int(@bigint.BigInt::from_int(crc)))
}

///|
fn builtin_itertools_chain(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.chain", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  // `itertools.chain` is exposed as a callable factory object in this runtime.
  // Ignore the implicit `self` passed via `__call__`.
  let start_idx = match positional {
    [Value::Instance(inst), ..] =>
      if inst.class.name == "chain_factory" {
        1
      } else {
        0
      }
    _ => 0
  }
  let items : Array[Value] = []
  for i = start_idx; i < positional.length(); i = i + 1 {
    let iter_value = positional[i]
    let values = match iterable_values(iter_value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    for item in values {
      items.push(item)
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_chain_from_iterable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.chain.from_iterable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let iterable_value = if positional.length() == 2 {
    match positional[0] {
      Value::Instance(inst) =>
        if inst.class.name == "chain_factory" {
          positional[1]
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "chain.from_iterable() takes exactly one argument".to_string(),
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "chain.from_iterable() takes exactly one argument".to_string(),
          ),
        )
    }
  } else if positional.length() == 1 {
    positional[0]
  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "chain.from_iterable() takes exactly one argument".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(iterable_value, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        let values = match iterable_values(item) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        for value in values {
          items.push(value)
        }
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_filterfalse(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.filterfalse", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "filterfalse() takes exactly two arguments".to_string(),
      ),
    )
  }
  let predicate = positional[0]
  let values = match iterable_values(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Value] = []
  for item in values {
    let keep = if predicate is Value::None {
      match truthy_from_value_with_env(item, globals, builtins, io) {
        Ok(v) => !v
        Err(err) => return Err(err)
      }
    } else {
      let pred_val = match
        call_callable_with_env(predicate, [item], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match truthy_from_value_with_env(pred_val, globals, builtins, io) {
        Ok(v) => !v
        Err(err) => return Err(err)
      }
    }
    if keep {
      out.push(item)
    }
  }
  Ok(make_iterator(out))
}

///|
fn builtin_itertools_accumulate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut initial_opt : Value? = None
  for pair in keywords {
    if pair.0 == "initial" {
      initial_opt = Some(pair.1)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "accumulate() got unexpected keyword arguments".to_string(),
        ),
      )
    }
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "accumulate() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let func_opt = if positional.length() == 2 {
    Some(positional[1])
  } else {
    None
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  let mut acc_opt : Value? = initial_opt
  if acc_opt is None {
    if items.length() == 0 {
      return Ok(make_iterator(results))
    }
    acc_opt = Some(items[0])
    results.push(items[0])
  } else {
    results.push(acc_opt.unwrap())
  }
  let start = if initial_opt is Some(_) { 0 } else { 1 }
  for i = start; i < items.length(); i = i + 1 {
    let current = acc_opt.unwrap()
    let next = match func_opt {
      Some(func) =>
        match func {
          Value::None => {
            let (a_is_float, a_num) = match number_value(current) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let (b_is_float, b_num) = match number_value(items[i]) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let sum = a_num + b_num
            if a_is_float || b_is_float {
              Value::Float(sum)
            } else {
              Value::Int(@bigint.BigInt::from_int64(sum.to_int64()))
            }
          }
          _ =>
            match
              call_callable_with_env(
                func,
                [current, items[i]],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
        }
      None => {
        let (a_is_float, a_num) = match number_value(current) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let (b_is_float, b_num) = match number_value(items[i]) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let sum = a_num + b_num
        if a_is_float || b_is_float {
          Value::Float(sum)
        } else {
          Value::Int(@bigint.BigInt::from_int64(sum.to_int64()))
        }
      }
    }
    acc_opt = Some(next)
    results.push(next)
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_groupby(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut key_fn_opt : Value? = None
  for pair in keywords {
    if pair.0 == "key" {
      key_fn_opt = Some(pair.1)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "groupby() got unexpected keyword arguments".to_string(),
        ),
      )
    }
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "groupby() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 2 {
    if key_fn_opt is Some(_) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "groupby() got multiple values for argument 'key'".to_string(),
        ),
      )
    }
    key_fn_opt = Some(positional[1])
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  let mut current_key_opt : Value? = None
  let mut current_items : Array[Value] = []
  for item in items {
    let key = match key_fn_opt {
      Some(func) =>
        match func {
          Value::None => item
          _ =>
            match
              call_callable_with_env(func, [item], [], globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
        }
      None => item
    }
    if current_key_opt is None {
      current_key_opt = Some(key)
      current_items.push(item)
    } else if eq_value(current_key_opt.unwrap(), key) {
      current_items.push(item)
    } else {
      results.push(
        Value::Tuple([current_key_opt.unwrap(), make_iterator(current_items)]),
      )
      current_key_opt = Some(key)
      current_items = [item]
    }
  }
  if current_key_opt is Some(_) {
    results.push(
      Value::Tuple([current_key_opt.unwrap(), make_iterator(current_items)]),
    )
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_repeat(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.repeat", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "repeat() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let value = positional[0]
  if positional.length() == 1 || positional[1] is Value::None {
    return Ok(make_repeat_iterator(value, None))
  }
  let times = match index_from_value(positional[1], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = if times < 0 { 0 } else { times }
  Ok(make_repeat_iterator(value, Some(@bigint.BigInt::from_int(count))))
}

///|
fn builtin_itertools_cycle(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.cycle", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "cycle() takes exactly one argument".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(make_cycle_iterator(iterator))
}

///|
fn builtin_itertools_starmap(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.starmap", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "starmap() takes exactly two arguments".to_string(),
      ),
    )
  }
  let func = positional[0]
  let iterator = match
    iter_value_to_iterator(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        let args = match item {
          Value::Tuple(values) => values
          Value::List(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "starmap() argument must yield tuples".to_string(),
              ),
            )
        }
        let value = match
          call_callable_with_env(func, args, [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        results.push(value)
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_count(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.count", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "count() takes at most two arguments".to_string(),
      ),
    )
  }
  let start_value = if positional.length() > 0 {
    match positional[0] {
      Value::Bool(v) =>
        Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
      Value::Int(_) | Value::Float(_) => positional[0]
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "count() start must be a number".to_string(),
          ),
        )
    }
  } else {
    Value::Int(0N)
  }
  let step_value = if positional.length() > 1 {
    match positional[1] {
      Value::Bool(v) =>
        Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
      Value::Int(_) | Value::Float(_) => positional[1]
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "count() step must be a number".to_string(),
          ),
        )
    }
  } else {
    Value::Int(1N)
  }
  Ok(make_count_iterator(start_value, step_value))
}

///|
fn builtin_itertools_islice(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.islice", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "islice() takes 2 to 4 arguments".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let start = if positional.length() >= 3 {
    match index_from_value(positional[1], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    0
  }
  let stop_value = if positional.length() >= 3 {
    positional[2]
  } else {
    positional[1]
  }
  let stop = match index_from_value(stop_value, 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let step = if positional.length() == 4 {
    match index_from_value(positional[3], 1) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    1
  }
  if step <= 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: step must be positive".to_string(),
      ),
    )
  }
  let items : Array[Value] = []
  let mut idx = 0
  while idx < stop {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        if idx >= start && (idx - start) % step == 0 {
          items.push(item)
        }
        idx += 1
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_permutations(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.permutations", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "permutations() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let values = match positional[0] {
    Value::Str(text) => {
      let out : Array[Value] = []
      for ch in text.to_array() {
        let buf = StringBuilder::new()
        buf.write_char(ch)
        out.push(Value::Str(buf.to_string()))
      }
      out
    }
    Value::List(items) => items
    Value::Tuple(items) => items
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "permutations() expects a str or sequence".to_string(),
        ),
      )
  }
  let r = if positional.length() == 2 {
    match positional[1] {
      Value::Int(v) =>
        match bigint_to_int_checked(v) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      Value::Bool(v) => if v { 1 } else { 0 }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "permutations() r must be int".to_string(),
          ),
        )
    }
  } else {
    values.length()
  }
  if r < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: r must be non-negative".to_string(),
      ),
    )
  }
  if r > values.length() {
    return Ok(Value::List([]))
  }
  fn build_permutations(values : Array[Value], r : Int) -> Array[Value] {
    if r == 0 {
      return [Value::Tuple([])]
    }
    let out : Array[Value] = []
    for i = 0; i < values.length(); i = i + 1 {
      let first = values[i]
      let rest : Array[Value] = []
      for j = 0; j < values.length(); j = j + 1 {
        if j != i {
          rest.push(values[j])
        }
      }
      let tails = build_permutations(rest, r - 1)
      for tail in tails {
        match tail {
          Value::Tuple(items) => {
            let combined : Array[Value] = [first]
            for item in items {
              combined.push(item)
            }
            out.push(Value::Tuple(combined))
          }
          _ => ()
        }
      }
    }
    out
  }

  Ok(Value::List(build_permutations(values, r)))
}

///|
fn builtin_itertools_product(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut repeat = 1
  for item in keywords {
    if item.0 == "repeat" {
      match item.1 {
        Value::Int(v) =>
          match bigint_to_int_checked(v) {
            Ok(value) => repeat = value
            Err(err) => return Err(err)
          }
        Value::Bool(v) => repeat = if v { 1 } else { 0 }
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "product() repeat must be int".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "product() got unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  if repeat < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: repeat must be non-negative".to_string(),
      ),
    )
  }
  if repeat == 0 || positional.length() == 0 {
    return Ok(Value::List([Value::Tuple([])]))
  }
  fn to_values(value : Value) -> Result[Array[Value], RuntimeError] {
    match value {
      Value::Str(text) => {
        let out : Array[Value] = []
        for ch in text.to_array() {
          let buf = StringBuilder::new()
          buf.write_char(ch)
          out.push(Value::Str(buf.to_string()))
        }
        Ok(out)
      }
      Value::List(items) => Ok(items)
      Value::Tuple(items) => Ok(items)
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "product() expects a str or sequence".to_string(),
          ),
        )
    }
  }

  let pools : Array[Array[Value]] = []
  for item in positional {
    let values = match to_values(item) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    pools.push(values)
  }
  let expanded : Array[Array[Value]] = []
  for pool in pools {
    for i = 0; i < repeat; i = i + 1 {
      expanded.push(pool)
    }
  }
  let mut results : Array[Value] = [Value::Tuple([])]
  for pool in expanded {
    let next : Array[Value] = []
    for item in results {
      match item {
        Value::Tuple(items) =>
          for value in pool {
            let combo : Array[Value] = []
            for v in items {
              combo.push(v)
            }
            combo.push(value)
            next.push(Value::Tuple(combo))
          }
        _ => ()
      }
    }
    results = next
  }
  Ok(Value::List(results))
}

///|
fn builtin_warnings_filters_mutated(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() > 0 {
    let _ = positional[0]

  }
  if keywords.length() > 0 {
    let _ = keywords[0]

  }
  Ok(Value::None)
}

///|
fn warnings_default_category(builtins : Array[(String, Value)]) -> Value {
  match get_named_value(builtins, "UserWarning") {
    Some(Value::Class(k)) => Value::Class(k)
    _ => Value::None
  }
}

///|
fn builtin_warnings_warn(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_warnings.warn() expects at least 1 argument".to_string(),
      ),
    )
  }
  let message = positional[0]
  let mut category : Value = Value::None
  let mut stacklevel : Int = 1
  if positional.length() > 1 {
    category = positional[1]
  }
  if positional.length() > 2 {
    match index_from_value(positional[2], 0) {
      Ok(v) => stacklevel = v
      Err(err) => return Err(err)
    }
  }
  if positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_warnings.warn() takes at most 4 arguments".to_string(),
      ),
    )
  }
  for item in keywords {
    let key = item.0
    let value = item.1
    if key == "category" {
      category = value
    } else if key == "stacklevel" {
      match index_from_value(value, 0) {
        Ok(v) => stacklevel = v
        Err(err) => return Err(err)
      }
    } else if key == "source" || key == "skip_file_prefixes" {
      // ignored
      let _ = value

    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_warnings.warn() got an unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  if category is Value::None {
    category = warnings_default_category(builtins)
  }
  let message_obj = match message {
    Value::Instance(inst) =>
      if class_has_base_name(inst.class, "Warning") {
        category = Value::Class(inst.class)
        message
      } else {
        message
      }
    _ =>
      match category {
        Value::Class(_) =>
          match
            call_callable_with_env(
              category,
              [message],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        _ => message
      }
  }
  let frames = snapshot_traceback()
  let (filename, lineno) = if frames.length() == 0 {
    ("sys".to_string(), 1)
  } else {
    let mut idx = frames.length() - 1
    if stacklevel > 1 && stacklevel <= frames.length() {
      idx = frames.length() - stacklevel
    }
    (frames[idx].filename, frames[idx].line)
  }
  let import_value = match get_named_value(builtins, "__import__") {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "missing builtins.__import__".to_string(),
        ),
      )
  }
  let warnings_module = match
    call_callable_with_env(
      import_value,
      [Value::Str("warnings")],
      [],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let showwarning = match
    get_attr_from_value(warnings_module, "showwarning", globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = match
    call_callable_with_env(
      showwarning,
      [
        message_obj,
        category,
        Value::Str(filename),
        Value::Int(@bigint.BigInt::from_int(lineno)),
        Value::None,
        Value::None,
      ],
      [],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_warnings_warn_explicit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_warnings.warn_explicit", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_warnings.warn_explicit() expects at least 4 arguments".to_string(),
      ),
    )
  }
  let message = positional[0]
  let mut category = positional[1]
  let filename = match positional[2] {
    Value::Str(s) => s
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_warnings.warn_explicit() filename must be str".to_string(),
        ),
      )
  }
  let lineno = match index_from_value(positional[3], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let message_obj = match message {
    Value::Instance(inst) =>
      if class_has_base_name(inst.class, "Warning") {
        category = Value::Class(inst.class)
        message
      } else {
        message
      }
    _ =>
      match category {
        Value::Class(_) =>
          match
            call_callable_with_env(
              category,
              [message],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        _ => message
      }
  }
  let import_value = match get_named_value(builtins, "__import__") {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "missing builtins.__import__".to_string(),
        ),
      )
  }
  let warnings_module = match
    call_callable_with_env(
      import_value,
      [Value::Str("warnings")],
      [],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let showwarning = match
    get_attr_from_value(warnings_module, "showwarning", globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = match
    call_callable_with_env(
      showwarning,
      [
        message_obj,
        category,
        Value::Str(filename),
        Value::Int(@bigint.BigInt::from_int(lineno)),
        Value::None,
        Value::None,
      ],
      [],
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}
