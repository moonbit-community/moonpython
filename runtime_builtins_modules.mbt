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
  // Minimal stub: return the format string unchanged.
  Ok(Value::Str(format))
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
  while i < chars.length() {
    let c = chars[i]
    if is_digit(c) {
      repeat = repeat * 10 + (c.to_int() - '0'.to_int())
      i += 1
      continue
    }
    let n = if repeat == 0 { 1 } else { repeat }
    repeat = 0
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
  let tokens : Array[(Char, Int)] = []
  while i < chars.length() {
    let c = chars[i]
    if is_digit(c) {
      repeat = repeat * 10 + (c.to_int() - '0'.to_int())
      i += 1
      continue
    }
    let n = if repeat == 0 { 1 } else { repeat }
    repeat = 0
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
              match bytes_from_iterable("_struct.pack", other) {
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
              match bytes_from_iterable("_struct.pack", other) {
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
  let bytes = match positional[0] {
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "binascii.crc32() argument must be bytes-like".to_string(),
        ),
      )
  }
  let init = if positional.length() == 2 {
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
            "binascii.crc32() value must be int".to_string(),
          ),
        )
    }
  } else {
    0
  }
  let mask = 0xFFFFFFFF
  let poly = 0xEDB88320
  let mut crc = (init ^ mask) & mask
  for b in bytes {
    crc = (crc ^ (b & 0xFF)) & mask
    for _i = 0; _i < 8; _i = _i + 1 {
      if (crc & 1) != 0 {
        crc = ((crc >> 1) ^ poly) & mask
      } else {
        crc = (crc >> 1) & mask
      }
    }
  }
  let out = (crc ^ mask) & mask
  Ok(Value::Int(@bigint.BigInt::from_int(out)))
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
