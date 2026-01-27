///|
/// Builtin function helpers and dispatch for the moonpython runtime.
///
/// Builtin implementations are split across runtime_builtins_*.mbt.
/// This file centralizes builtin dispatch so `moonpython.mbt` can focus on
/// expression evaluation and general call semantics.

///|
fn unexpected_keywords_error(name : String) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() got unexpected keyword arguments".to_string(),
  )
}

///|
fn ensure_no_keywords(
  name : String,
  keywords : Array[(String, Value)],
) -> Result[Unit, RuntimeError] {
  if keywords.length() > 0 {
    Err(unexpected_keywords_error(name))
  } else {
    Ok(())
  }
}

///|
fn touch_env(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Unit {
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io

}

///|
fn unexpected_keyword_argument_error(
  name : String,
  key : String,
) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() got an unexpected keyword argument '" + key + "'",
  )
}

///|
fn multiple_values_error(name : String, key : String) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() got multiple values for argument '" + key + "'",
  )
}

///|
fn missing_required_argument_error(
  name : String,
  arg_name : String,
) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() missing required argument '" + arg_name + "'",
  )
}

///|
fn too_many_arguments_error(name : String, given : Int) -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    name + "() takes at most 3 arguments (" + given.to_string() + " given)",
  )
}

///|
fn dict_env_from_value(
  name : String,
  kind : String,
  value : Value,
) -> Result[(Array[(String, Value)], Array[(Value, Value)]), RuntimeError] {
  match value {
    Value::Dict(pairs) => {
      let env : Array[(String, Value)] = []
      for pair in pairs {
        match pair.0 {
          Value::Str(key) => set_global_value(env, key, pair.1)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                name + "() " + kind + " keys must be str".to_string(),
              ),
            )
        }
      }
      Ok((env, pairs))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() " + kind + " must be a dict".to_string(),
        ),
      )
  }
}

///|
fn dict_pairs_from_value(
  name : String,
  value : Value,
) -> Result[Array[(Value, Value)], RuntimeError] {
  match value {
    Value::Dict(pairs) => Ok(pairs)
    Value::Instance(inst) =>
      if class_includes_dict(inst.class) {
        match get_named_value(inst.dict, dict_storage_name) {
          Some(Value::Dict(pairs)) => Ok(pairs)
          Some(_) =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                name + "() expects a dict".to_string(),
              ),
            )
          None => {
            let pairs : Array[(Value, Value)] = []
            set_named_value(inst.dict, dict_storage_name, Value::Dict(pairs))
            Ok(pairs)
          }
        }
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            name + "() expects a dict".to_string(),
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() expects a dict".to_string(),
        ),
      )
  }
}

///|
fn sync_env_to_dict(
  env : Array[(String, Value)],
  pairs : Array[(Value, Value)],
) -> Unit {
  while pairs.length() > 0 {
    let _ = pairs.pop()

  }
  for pair in env {
    pairs.push((Value::Str(pair.0), pair.1))
  }
}

///|
fn normalize_exec_eval_arg(value_opt : Value?) -> Value? {
  match value_opt {
    Some(Value::None) => None
    _ => value_opt
  }
}

///|
fn resolve_exec_eval_env(
  name : String,
  globals_arg : Value?,
  locals_arg : Value?,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
) -> Result[
  (
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(Value, Value)]?,
    Array[(Value, Value)]?,
  ),
  RuntimeError,
] {
  let globals_value = normalize_exec_eval_arg(globals_arg)
  let locals_value = normalize_exec_eval_arg(locals_arg)
  let mut globals_env = globals
  let mut locals_env = locals
  let mut globals_pairs : Array[(Value, Value)]? = None
  let mut locals_pairs : Array[(Value, Value)]? = None
  match globals_value {
    Some(value) => {
      let (env, pairs) = match dict_env_from_value(name, "globals", value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      globals_env = env
      globals_pairs = Some(pairs)
    }
    None => ()
  }
  match locals_value {
    Some(value) => {
      let (env, pairs) = match dict_env_from_value(name, "locals", value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      locals_env = env
      locals_pairs = Some(pairs)
    }
    None => ()
  }
  if globals_value is Some(_) && locals_value is None {
    locals_env = globals_env
    locals_pairs = globals_pairs
  }
  Ok((locals_env, globals_env, locals_pairs, globals_pairs))
}

///|
fn parse_exec_eval_args(
  name : String,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  required_label : String,
) -> Result[(Value, Value?, Value?), RuntimeError] {
  if positional.length() == 0 {
    return Err(missing_required_argument_error(name, required_label))
  }
  if positional.length() > 3 {
    return Err(too_many_arguments_error(name, positional.length()))
  }
  let mut globals_arg : Value? = None
  let mut locals_arg : Value? = None
  if positional.length() > 1 {
    globals_arg = Some(positional[1])
  }
  if positional.length() > 2 {
    locals_arg = Some(positional[2])
  }
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "globals" =>
        if globals_arg is Some(_) {
          return Err(multiple_values_error(name, "globals"))
        } else {
          globals_arg = Some(value)
        }
      "locals" =>
        if locals_arg is Some(_) {
          return Err(multiple_values_error(name, "locals"))
        } else {
          locals_arg = Some(value)
        }
      _ => return Err(unexpected_keyword_argument_error(name, key))
    }
  }
  Ok((positional[0], globals_arg, locals_arg))
}

///|
fn reverse_values(items : Array[Value]) -> Array[Value] {
  let out : Array[Value] = []
  let mut i = items.length()
  while i > 0 {
    i = i - 1
    out.push(items[i])
  }
  out
}

///|
fn collect_items_from_iterable(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Array[Value], RuntimeError] {
  let iterator = match iter_value_to_iterator(value, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => out.push(item)
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(out)
}

///|
priv enum SortKind {
  Number
  String
  Tuple
  List
} derive(Eq)

///|
fn sort_kind_for_sorted(value : Value) -> SortKind? {
  match value {
    Value::Int(_) | Value::Float(_) | Value::Bool(_) => Some(SortKind::Number)
    Value::Str(_) => Some(SortKind::String)
    Value::Tuple(_) => Some(SortKind::Tuple)
    Value::List(_) => Some(SortKind::List)
    _ => None
  }
}

///|
fn cmp_string_for_sorted(a : String, b : String) -> Int {
  let aa = a.to_array()
  let bb = b.to_array()
  let mut i = 0
  while i < aa.length() && i < bb.length() {
    let ca = aa[i]
    let cb = bb[i]
    if ca < cb {
      return -1
    }
    if ca > cb {
      return 1
    }
    i = i + 1
  }
  if aa.length() < bb.length() {
    -1
  } else if aa.length() > bb.length() {
    1
  } else {
    0
  }
}

///|
fn cmp_value_for_sorted_dynamic(
  a : Value,
  b : Value,
) -> Result[Int, RuntimeError] {
  match (sort_kind_for_sorted(a), sort_kind_for_sorted(b)) {
    (Some(kind_a), Some(kind_b)) =>
      if kind_a == kind_b {
        cmp_value_for_sorted(kind_a, a, b)
      } else {
        Ok(cmp_string_for_sorted(value_to_string(a), value_to_string(b)))
      }
    _ => Ok(cmp_string_for_sorted(value_to_string(a), value_to_string(b)))
  }
}

///|
fn cmp_value_for_sorted(
  kind : SortKind,
  a : Value,
  b : Value,
) -> Result[Int, RuntimeError] {
  match kind {
    SortKind::Number => {
      let (_, an) = match number_value(a) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let (_, bn) = match number_value(b) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if an < bn {
        Ok(-1)
      } else if an > bn {
        Ok(1)
      } else {
        Ok(0)
      }
    }
    SortKind::String =>
      match (a, b) {
        (Value::Str(aa), Value::Str(bb)) => Ok(cmp_string_for_sorted(aa, bb))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "sorted() cannot compare values".to_string(),
            ),
          )
      }
    SortKind::Tuple => {
      let values_a = match a {
        Value::Tuple(values) => values
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "sorted() cannot compare values".to_string(),
            ),
          )
      }
      let values_b = match b {
        Value::Tuple(values) => values
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "sorted() cannot compare values".to_string(),
            ),
          )
      }
      let mut i = 0
      while i < values_a.length() && i < values_b.length() {
        let cmp = match cmp_value_for_sorted_dynamic(values_a[i], values_b[i]) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp != 0 {
          return Ok(cmp)
        }
        i += 1
      }
      if values_a.length() < values_b.length() {
        Ok(-1)
      } else if values_a.length() > values_b.length() {
        Ok(1)
      } else {
        Ok(0)
      }
    }
    SortKind::List => {
      let values_a = match a {
        Value::List(values) => values
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "sorted() cannot compare values".to_string(),
            ),
          )
      }
      let values_b = match b {
        Value::List(values) => values
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "sorted() cannot compare values".to_string(),
            ),
          )
      }
      let mut i = 0
      while i < values_a.length() && i < values_b.length() {
        let cmp = match cmp_value_for_sorted_dynamic(values_a[i], values_b[i]) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp != 0 {
          return Ok(cmp)
        }
        i += 1
      }
      if values_a.length() < values_b.length() {
        Ok(-1)
      } else if values_a.length() > values_b.length() {
        Ok(1)
      } else {
        Ok(0)
      }
    }
  }
}

///|
fn stable_sort_for_sorted(
  items : Array[Value],
  kind : SortKind,
) -> Result[Array[Value], RuntimeError] {
  let mut out : Array[Value] = []
  for item in items {
    let mut inserted = false
    let next : Array[Value] = []
    for existing in out {
      if !inserted {
        let cmp = match cmp_value_for_sorted(kind, item, existing) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp < 0 {
          next.push(item)
          inserted = true
        }
      }
      next.push(existing)
    }
    if !inserted {
      next.push(item)
    }
    out = next
  }
  Ok(out)
}

///|
fn stable_sort_pairs_by_key(
  pairs : Array[(Value, Value)],
  kind : SortKind,
) -> Result[Array[(Value, Value)], RuntimeError] {
  let mut out : Array[(Value, Value)] = []
  for pair in pairs {
    let mut inserted = false
    let next : Array[(Value, Value)] = []
    for existing in out {
      if !inserted {
        let cmp = match cmp_value_for_sorted(kind, pair.0, existing.0) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if cmp < 0 {
          next.push(pair)
          inserted = true
        }
      }
      next.push(existing)
    }
    if !inserted {
      next.push(pair)
    }
    out = next
  }
  Ok(out)
}

///|
priv struct BuiltinDef {
  name : String
  run : (
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError]
}

///|
let builtin_defs_ref : Ref[Array[BuiltinDef]] = { val: [] }

///|
let builtin_defs_ready : Ref[Bool] = { val: false }

///|
fn ensure_builtin_defs_ready() -> Unit {
  if builtin_defs_ready.val {
    return
  }
  builtin_defs_ref.val = [
    BuiltinDef::{ name: "__mpython_run", run: builtin_mpython_run },
    BuiltinDef::{
      name: "__mpython_asyncgenexp_next",
      run: builtin_mpython_asyncgenexp_next,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_next",
      run: builtin_mpython_asyncgen_next,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_send",
      run: builtin_mpython_asyncgen_send,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_throw",
      run: builtin_mpython_asyncgen_throw,
    },
    BuiltinDef::{
      name: "__mpython_asyncgen_close",
      run: builtin_mpython_asyncgen_close,
    },
    BuiltinDef::{
      name: "__mpython_posix_open",
      run: builtin_mpython_posix_open,
    },
    BuiltinDef::{
      name: "__mpython_posix_read",
      run: builtin_mpython_posix_read,
    },
    BuiltinDef::{
      name: "__mpython_posix_lseek",
      run: builtin_mpython_posix_lseek,
    },
    BuiltinDef::{
      name: "__mpython_posix_write",
      run: builtin_mpython_posix_write,
    },
    BuiltinDef::{
      name: "__mpython_posix_close",
      run: builtin_mpython_posix_close,
    },
    BuiltinDef::{
      name: "__mpython_posix_fstat",
      run: builtin_mpython_posix_fstat,
    },
    BuiltinDef::{
      name: "__mpython_posix_unlink",
      run: builtin_mpython_posix_unlink,
    },
    BuiltinDef::{
      name: "__mpython_posix_mkdir",
      run: builtin_mpython_posix_mkdir,
    },
    BuiltinDef::{
      name: "__mpython_posix_rmdir",
      run: builtin_mpython_posix_rmdir,
    },
    BuiltinDef::{
      name: "__mpython_posix_stat",
      run: builtin_mpython_posix_stat,
    },
    BuiltinDef::{
      name: "__mpython_posix_getcwd",
      run: builtin_mpython_posix_getcwd,
    },
    BuiltinDef::{
      name: "__mpython_posix_chdir",
      run: builtin_mpython_posix_chdir,
    },
    BuiltinDef::{
      name: "__mpython_posix_listdir",
      run: builtin_mpython_posix_listdir,
    },
    BuiltinDef::{ name: "__mpython.internal_iter", run: builtin_internal_iter },
    BuiltinDef::{ name: "__mpython.internal_next", run: builtin_internal_next },
    BuiltinDef::{
      name: "rangeiter.__setstate__",
      run: builtin_rangeiter_setstate,
    },
    BuiltinDef::{ name: "asyncio.run", run: builtin_asyncio_run },
    BuiltinDef::{ name: "asyncio.gather", run: builtin_asyncio_gather },
    BuiltinDef::{
      name: "asyncio.iscoroutinefunction",
      run: builtin_asyncio_iscoroutinefunction,
    },
    BuiltinDef::{ name: "platform.system", run: builtin_platform_system },
    BuiltinDef::{ name: "enum.global_enum", run: builtin_enum_global_enum },
    BuiltinDef::{ name: "platform.machine", run: builtin_platform_machine },
    BuiltinDef::{ name: "time.time", run: builtin_time_time },
    BuiltinDef::{ name: "time.monotonic", run: builtin_time_monotonic },
    BuiltinDef::{ name: "time.perf_counter", run: builtin_time_perf_counter },
    BuiltinDef::{
      name: "time.perf_counter_ns",
      run: builtin_time_perf_counter_ns,
    },
    BuiltinDef::{ name: "time.process_time", run: builtin_time_process_time },
    BuiltinDef::{
      name: "time.process_time_ns",
      run: builtin_time_process_time_ns,
    },
    BuiltinDef::{ name: "time.localtime", run: builtin_time_localtime },
    BuiltinDef::{ name: "time.gmtime", run: builtin_time_gmtime },
    BuiltinDef::{ name: "time.sleep", run: builtin_time_sleep },
    BuiltinDef::{ name: "time.strftime", run: builtin_time_strftime },
    BuiltinDef::{
      name: "time.get_clock_info",
      run: builtin_time_get_clock_info,
    },
    BuiltinDef::{ name: "enum.auto", run: builtin_enum_auto },
    BuiltinDef::{ name: "enum._simple_enum", run: builtin_enum_simple_enum },
    BuiltinDef::{
      name: "enum._simple_enum_decorator",
      run: builtin_enum_simple_enum_decorator,
    },
    BuiltinDef::{
      name: "enum._simple_enum_decorator_call",
      run: builtin_enum_simple_enum_decorator_call,
    },
    BuiltinDef::{ name: "atexit.register", run: builtin_atexit_register },
    BuiltinDef::{
      name: "socket.socket.__init__",
      run: builtin_socket_socket_init,
    },
    BuiltinDef::{
      name: "socket.socket.connect",
      run: builtin_socket_socket_connect,
    },
    BuiltinDef::{
      name: "socket.socket.close",
      run: builtin_socket_socket_close,
    },
    BuiltinDef::{ name: "socket.socket.send", run: builtin_socket_socket_send },
    BuiltinDef::{
      name: "socket.socket.sendall",
      run: builtin_socket_socket_sendall,
    },
    BuiltinDef::{
      name: "socket.socket.sendto",
      run: builtin_socket_socket_sendto,
    },
    BuiltinDef::{ name: "socket.socket.recv", run: builtin_socket_socket_recv },
    BuiltinDef::{
      name: "socket.socket.settimeout",
      run: builtin_socket_socket_settimeout,
    },
    BuiltinDef::{
      name: "socket.create_connection",
      run: builtin_socket_create_connection,
    },
    BuiltinDef::{ name: "socket.getaddrinfo", run: builtin_socket_getaddrinfo },
    BuiltinDef::{ name: "faulthandler.enable", run: builtin_faulthandler_noop },
    BuiltinDef::{ name: "faulthandler.disable", run: builtin_faulthandler_noop },
    BuiltinDef::{
      name: "faulthandler.register",
      run: builtin_faulthandler_noop,
    },
    BuiltinDef::{
      name: "faulthandler.unregister",
      run: builtin_faulthandler_noop,
    },
    BuiltinDef::{
      name: "faulthandler.dump_traceback",
      run: builtin_faulthandler_noop,
    },
    BuiltinDef::{
      name: "faulthandler.dump_traceback_later",
      run: builtin_faulthandler_noop,
    },
    BuiltinDef::{
      name: "faulthandler.cancel_dump_traceback_later",
      run: builtin_faulthandler_noop,
    },
    BuiltinDef::{
      name: "faulthandler.is_enabled",
      run: builtin_faulthandler_is_enabled,
    },
    BuiltinDef::{ name: "select.select", run: builtin_select_select },
    BuiltinDef::{ name: "_struct.calcsize", run: builtin_struct_calcsize },
    BuiltinDef::{ name: "_struct.pack", run: builtin_struct_pack },
    BuiltinDef::{ name: "_struct.pack_into", run: builtin_struct_pack_into },
    BuiltinDef::{ name: "_struct.unpack", run: builtin_struct_unpack },
    BuiltinDef::{ name: "_struct.unpack_from", run: builtin_struct_unpack_from },
    BuiltinDef::{ name: "_struct.iter_unpack", run: builtin_struct_iter_unpack },
    BuiltinDef::{ name: "_struct._clearcache", run: builtin_struct_clearcache },
    BuiltinDef::{
      name: "_struct.Struct.__init__",
      run: builtin_struct_struct_init,
    },
    BuiltinDef::{ name: "_struct.Struct.pack", run: builtin_struct_struct_pack },
    BuiltinDef::{
      name: "_struct.Struct.unpack",
      run: builtin_struct_struct_unpack,
    },
    BuiltinDef::{
      name: "_struct.Struct.calcsize",
      run: builtin_struct_struct_calcsize,
    },
    BuiltinDef::{ name: "gc.enable", run: builtin_gc_enable },
    BuiltinDef::{ name: "gc.disable", run: builtin_gc_disable },
    BuiltinDef::{ name: "gc.isenabled", run: builtin_gc_isenabled },
    BuiltinDef::{ name: "gc.collect", run: builtin_gc_collect },
    BuiltinDef::{ name: "gc.get_threshold", run: builtin_gc_get_threshold },
    BuiltinDef::{ name: "gc.set_threshold", run: builtin_gc_set_threshold },
    BuiltinDef::{ name: "gc.get_count", run: builtin_gc_get_count },
    BuiltinDef::{ name: "binascii.crc32", run: builtin_binascii_crc32 },
    BuiltinDef::{
      name: "binascii.b2a_base64",
      run: builtin_binascii_b2a_base64,
    },
    BuiltinDef::{
      name: "binascii.a2b_base64",
      run: builtin_binascii_a2b_base64,
    },
    BuiltinDef::{ name: "binascii.hexlify", run: builtin_binascii_hexlify },
    BuiltinDef::{ name: "binascii.unhexlify", run: builtin_binascii_unhexlify },
    BuiltinDef::{ name: "binascii.b2a_hex", run: builtin_binascii_b2a_hex },
    BuiltinDef::{ name: "binascii.a2b_hex", run: builtin_binascii_a2b_hex },
    BuiltinDef::{ name: "binascii.a2b_qp", run: builtin_binascii_a2b_qp },
    BuiltinDef::{ name: "binascii.b2a_qp", run: builtin_binascii_b2a_qp },
    BuiltinDef::{ name: "binascii.a2b_uu", run: builtin_binascii_a2b_uu },
    BuiltinDef::{ name: "binascii.b2a_uu", run: builtin_binascii_b2a_uu },
    BuiltinDef::{ name: "binascii.crc_hqx", run: builtin_binascii_crc_hqx },
    BuiltinDef::{
      name: "_string.formatter_parser",
      run: builtin_string_formatter_parser,
    },
    BuiltinDef::{
      name: "_string.formatter_field_name_split",
      run: builtin_string_formatter_field_name_split,
    },
    BuiltinDef::{
      name: "_warnings._filters_mutated",
      run: builtin_warnings_filters_mutated,
    },
    BuiltinDef::{ name: "_warnings.warn", run: builtin_warnings_warn },
    BuiltinDef::{
      name: "_warnings.warn_explicit",
      run: builtin_warnings_warn_explicit,
    },
    BuiltinDef::{ name: "_thread.get_ident", run: builtin_thread_get_ident },
    BuiltinDef::{
      name: "_thread.allocate_lock",
      run: builtin_thread_allocate_lock,
    },
    BuiltinDef::{
      name: "_thread.start_new_thread",
      run: builtin_thread_start_new_thread,
    },
    BuiltinDef::{
      name: "_thread._set_sentinel",
      run: builtin_thread_set_sentinel,
    },
    BuiltinDef::{ name: "_thread._count", run: builtin_thread_count },
    BuiltinDef::{ name: "_thread.stack_size", run: builtin_thread_stack_size },
    BuiltinDef::{
      name: "_thread.RLock.__enter__",
      run: builtin_thread_rlock_enter,
    },
    BuiltinDef::{
      name: "_thread.RLock.__exit__",
      run: builtin_thread_rlock_exit,
    },
    BuiltinDef::{
      name: "_thread.RLock.acquire",
      run: builtin_thread_rlock_acquire,
    },
    BuiltinDef::{
      name: "_thread.RLock.release",
      run: builtin_thread_rlock_release,
    },
    BuiltinDef::{
      name: "_thread.RLock.locked",
      run: builtin_thread_rlock_locked,
    },
    BuiltinDef::{
      name: "_thread.RLock._at_fork_reinit",
      run: builtin_thread_rlock_at_fork_reinit,
    },
    BuiltinDef::{ name: "_weakref.ref", run: builtin_weakref_ref },
    BuiltinDef::{ name: "_weakref.proxy", run: builtin_weakref_proxy },
    BuiltinDef::{
      name: "_weakref.getweakrefcount",
      run: builtin_weakref_getweakrefcount,
    },
    BuiltinDef::{
      name: "_weakref.getweakrefs",
      run: builtin_weakref_getweakrefs,
    },
    BuiltinDef::{
      name: "_weakref._remove_dead_weakref",
      run: builtin_weakref_remove_dead_weakref,
    },
    BuiltinDef::{ name: "weakref.__hash__", run: builtin_weakref_hash },
    BuiltinDef::{ name: "code.replace", run: builtin_code_replace },
    BuiltinDef::{ name: "coroutine.close", run: builtin_coroutine_close },
    BuiltinDef::{ name: "itertools.chain", run: builtin_itertools_chain },
    BuiltinDef::{
      name: "itertools.chain.from_iterable",
      run: builtin_itertools_chain_from_iterable,
    },
    BuiltinDef::{
      name: "itertools.filterfalse",
      run: builtin_itertools_filterfalse,
    },
    BuiltinDef::{
      name: "itertools.accumulate",
      run: builtin_itertools_accumulate,
    },
    BuiltinDef::{ name: "itertools.groupby", run: builtin_itertools_groupby },
    BuiltinDef::{ name: "itertools.count", run: builtin_itertools_count },
    BuiltinDef::{ name: "itertools.cycle", run: builtin_itertools_cycle },
    BuiltinDef::{ name: "itertools.repeat", run: builtin_itertools_repeat },
    BuiltinDef::{ name: "itertools.starmap", run: builtin_itertools_starmap },
    BuiltinDef::{ name: "itertools.islice", run: builtin_itertools_islice },
    BuiltinDef::{
      name: "itertools.permutations",
      run: builtin_itertools_permutations,
    },
    BuiltinDef::{ name: "itertools.product", run: builtin_itertools_product },
    BuiltinDef::{ name: "print", run: builtin_print },
    BuiltinDef::{ name: "len", run: builtin_len },
    BuiltinDef::{ name: "range", run: builtin_range },
    BuiltinDef::{ name: "range.__iter__", run: builtin_range_iter },
    BuiltinDef::{ name: "range.__len__", run: builtin_range_len },
    BuiltinDef::{ name: "range.__bool__", run: builtin_range_bool },
    BuiltinDef::{ name: "range.__contains__", run: builtin_range_contains },
    BuiltinDef::{ name: "range.__getitem__", run: builtin_range_getitem },
    BuiltinDef::{ name: "range.count", run: builtin_range_count },
    BuiltinDef::{ name: "range.index", run: builtin_range_index },
    BuiltinDef::{ name: "sum", run: builtin_sum },
    BuiltinDef::{ name: "max", run: builtin_max },
    BuiltinDef::{ name: "min", run: builtin_min },
    BuiltinDef::{ name: "any", run: builtin_any },
    BuiltinDef::{ name: "all", run: builtin_all },
    BuiltinDef::{ name: "enumerate", run: builtin_enumerate },
    BuiltinDef::{ name: "zip", run: builtin_zip },
    BuiltinDef::{ name: "map", run: builtin_map },
    BuiltinDef::{ name: "filter", run: builtin_filter },
    BuiltinDef::{ name: "reversed", run: builtin_reversed },
    BuiltinDef::{ name: "sorted", run: builtin_sorted },
    BuiltinDef::{ name: "input", run: builtin_input },
    BuiltinDef::{ name: "breakpoint", run: builtin_breakpoint },
    BuiltinDef::{ name: "open", run: builtin_open },
    BuiltinDef::{ name: "str", run: builtin_str },
    BuiltinDef::{ name: "str.maketrans", run: builtin_str_maketrans },
    BuiltinDef::{ name: "str.casefold", run: builtin_str_casefold },
    BuiltinDef::{ name: "bytes", run: builtin_bytes },
    BuiltinDef::{ name: "bytes.fromhex", run: builtin_bytes_fromhex },
    BuiltinDef::{ name: "bytes.maketrans", run: builtin_bytes_maketrans },
    BuiltinDef::{ name: "bytes.translate", run: builtin_bytes_translate },
    BuiltinDef::{ name: "bytes.upper", run: builtin_bytes_upper },
    BuiltinDef::{ name: "bytes.rstrip", run: builtin_bytes_rstrip },
    BuiltinDef::{ name: "bytes.join", run: builtin_bytes_join },
    BuiltinDef::{ name: "bytearray", run: builtin_bytearray },
    BuiltinDef::{ name: "bytearray.fromhex", run: builtin_bytearray_fromhex },
    BuiltinDef::{ name: "bytearray.copy", run: builtin_bytearray_copy },
    BuiltinDef::{ name: "bytearray.upper", run: builtin_bytearray_upper },
    BuiltinDef::{ name: "bytearray.rstrip", run: builtin_bytearray_rstrip },
    BuiltinDef::{
      name: "bytearray.translate",
      run: builtin_bytearray_translate,
    },
    BuiltinDef::{
      name: "bytearray.__setitem__",
      run: builtin_bytearray_setitem,
    },
    BuiltinDef::{
      name: "bytearray.__delitem__",
      run: builtin_bytearray_delitem,
    },
    BuiltinDef::{ name: "memoryview", run: builtin_memoryview },
    BuiltinDef::{ name: "memoryview.tobytes", run: builtin_memoryview_tobytes },
    BuiltinDef::{ name: "memoryview.cast", run: builtin_memoryview_cast },
    BuiltinDef::{ name: "int", run: builtin_int },
    BuiltinDef::{ name: "int.__new__", run: builtin_int_new },
    BuiltinDef::{ name: "int.__bool__", run: builtin_int_bool },
    BuiltinDef::{ name: "int.__index__", run: builtin_int_index },
    BuiltinDef::{ name: "int.__repr__", run: builtin_int_repr },
    BuiltinDef::{ name: "int.from_bytes", run: builtin_int_from_bytes },
    BuiltinDef::{ name: "int.to_bytes", run: builtin_int_to_bytes },
    BuiltinDef::{ name: "int.bit_length", run: builtin_int_bit_length },
    BuiltinDef::{ name: "int.conjugate", run: builtin_int_conjugate },
    BuiltinDef::{ name: "float", run: builtin_float },
    BuiltinDef::{ name: "float.__repr__", run: builtin_float_repr },
    BuiltinDef::{ name: "float.__getformat__", run: builtin_float_getformat },
    BuiltinDef::{ name: "float.conjugate", run: builtin_float_conjugate },
    BuiltinDef::{ name: "complex", run: builtin_complex },
    BuiltinDef::{ name: "complex.conjugate", run: builtin_complex_conjugate },
    BuiltinDef::{ name: "list", run: builtin_list },
    BuiltinDef::{ name: "list.copy", run: builtin_list_copy },
    BuiltinDef::{ name: "tuple", run: builtin_tuple },
    BuiltinDef::{ name: "tuple.__new__", run: builtin_tuple_new },
    BuiltinDef::{ name: "slice", run: builtin_slice },
    BuiltinDef::{ name: "set", run: builtin_set },
    BuiltinDef::{ name: "set.copy", run: builtin_set_copy },
    BuiltinDef::{ name: "frozenset", run: builtin_frozenset },
    BuiltinDef::{ name: "dict", run: builtin_dict },
    BuiltinDef::{ name: "dict.copy", run: builtin_dict_copy },
    BuiltinDef::{ name: "dict.fromkeys", run: builtin_dict_fromkeys },
    BuiltinDef::{ name: "dict.get", run: builtin_dict_get },
    BuiltinDef::{ name: "dict.pop", run: builtin_dict_pop },
    BuiltinDef::{ name: "dict.popitem", run: builtin_dict_popitem },
    BuiltinDef::{ name: "dict.setdefault", run: builtin_dict_setdefault },
    BuiltinDef::{ name: "dict.keys", run: builtin_dict_keys },
    BuiltinDef::{ name: "dict.values", run: builtin_dict_values },
    BuiltinDef::{ name: "dict.items", run: builtin_dict_items },
    BuiltinDef::{ name: "dict.update", run: builtin_dict_update },
    BuiltinDef::{ name: "dict.clear", run: builtin_dict_clear },
    BuiltinDef::{ name: "dict.__contains__", run: builtin_dict_contains },
    BuiltinDef::{ name: "dict.__getitem__", run: builtin_dict_getitem },
    BuiltinDef::{ name: "dict.__setitem__", run: builtin_dict_setitem },
    BuiltinDef::{ name: "dict.__delitem__", run: builtin_dict_delitem },
    BuiltinDef::{ name: "dict.__iter__", run: builtin_dict_iter },
    BuiltinDef::{ name: "dict.__len__", run: builtin_dict_len },
    BuiltinDef::{ name: "file.read", run: builtin_file_read },
    BuiltinDef::{ name: "file.readline", run: builtin_file_readline },
    BuiltinDef::{ name: "file.readlines", run: builtin_file_readlines },
    BuiltinDef::{ name: "file.close", run: builtin_file_close },
    BuiltinDef::{ name: "file.write", run: builtin_file_write },
    BuiltinDef::{ name: "file.flush", run: builtin_file_flush },
    BuiltinDef::{ name: "file.seek", run: builtin_file_seek },
    BuiltinDef::{ name: "file.tell", run: builtin_file_tell },
    BuiltinDef::{ name: "file.__iter__", run: builtin_file_iter },
    BuiltinDef::{ name: "file.__next__", run: builtin_file_next },
    BuiltinDef::{ name: "file.__enter__", run: builtin_file_enter },
    BuiltinDef::{ name: "file.__exit__", run: builtin_file_exit },
    BuiltinDef::{ name: "iter", run: builtin_iter },
    BuiltinDef::{ name: "next", run: builtin_next },
    BuiltinDef::{ name: "bool", run: builtin_bool },
    BuiltinDef::{ name: "bool.from_bytes", run: builtin_bool_from_bytes },
    BuiltinDef::{ name: "bool.__new__", run: builtin_bool_new },
    BuiltinDef::{ name: "property", run: builtin_property },
    BuiltinDef::{ name: "property.__init__", run: builtin_property_init },
    BuiltinDef::{ name: "property.__get__", run: builtin_property_dunder_get },
    BuiltinDef::{ name: "property.getter", run: builtin_property_getter },
    BuiltinDef::{ name: "property.setter", run: builtin_property_setter },
    BuiltinDef::{ name: "property.deleter", run: builtin_property_deleter },
    BuiltinDef::{ name: "staticmethod", run: builtin_staticmethod },
    BuiltinDef::{
      name: "staticmethod.__init__",
      run: builtin_staticmethod_init,
    },
    BuiltinDef::{ name: "classmethod", run: builtin_classmethod },
    BuiltinDef::{ name: "classmethod.__init__", run: builtin_classmethod_init },
    BuiltinDef::{ name: "register", run: builtin_register },
    BuiltinDef::{
      name: "__mpython_abc_cache_token",
      run: builtin_mpython_abc_cache_token,
    },
    BuiltinDef::{
      name: "__mpython_abc_cache_token_bump",
      run: builtin_mpython_abc_cache_token_bump,
    },
    BuiltinDef::{ name: "repr", run: builtin_repr },
    BuiltinDef::{ name: "ascii", run: builtin_ascii },
    BuiltinDef::{ name: "abs", run: builtin_abs },
    BuiltinDef::{ name: "round", run: builtin_round },
    BuiltinDef::{ name: "pow", run: builtin_pow },
    BuiltinDef::{ name: "math.sqrt", run: builtin_math_sqrt },
    BuiltinDef::{ name: "math.copysign", run: builtin_math_copysign },
    BuiltinDef::{ name: "math.pow", run: builtin_math_pow },
    BuiltinDef::{ name: "math.log", run: builtin_math_log },
    BuiltinDef::{ name: "math.log2", run: builtin_math_log2 },
    BuiltinDef::{ name: "math.exp", run: builtin_math_exp },
    BuiltinDef::{ name: "math.floor", run: builtin_math_floor },
    BuiltinDef::{ name: "math.ceil", run: builtin_math_ceil },
    BuiltinDef::{ name: "math.trunc", run: builtin_math_trunc },
    BuiltinDef::{ name: "math.frexp", run: builtin_math_frexp },
    BuiltinDef::{ name: "math.ldexp", run: builtin_math_ldexp },
    BuiltinDef::{ name: "math.acos", run: builtin_math_acos },
    BuiltinDef::{ name: "math.cos", run: builtin_math_cos },
    BuiltinDef::{ name: "math.sin", run: builtin_math_sin },
    BuiltinDef::{ name: "math.hypot", run: builtin_math_hypot },
    BuiltinDef::{ name: "math.fabs", run: builtin_math_fabs },
    BuiltinDef::{ name: "math.erf", run: builtin_math_erf },
    BuiltinDef::{ name: "math.lgamma", run: builtin_math_lgamma },
    BuiltinDef::{ name: "math.fsum", run: builtin_math_fsum },
    BuiltinDef::{ name: "math.sumprod", run: builtin_math_sumprod },
    BuiltinDef::{ name: "math.isfinite", run: builtin_math_isfinite },
    BuiltinDef::{ name: "math.isnan", run: builtin_math_isnan },
    BuiltinDef::{ name: "math.isqrt", run: builtin_math_isqrt },
    BuiltinDef::{ name: "divmod", run: builtin_divmod },
    BuiltinDef::{ name: "chr", run: builtin_chr },
    BuiltinDef::{ name: "ord", run: builtin_ord },
    BuiltinDef::{ name: "bin", run: builtin_bin },
    BuiltinDef::{ name: "oct", run: builtin_oct },
    BuiltinDef::{ name: "hex", run: builtin_hex },
    BuiltinDef::{ name: "callable", run: builtin_callable },
    BuiltinDef::{ name: "isinstance", run: builtin_isinstance },
    BuiltinDef::{ name: "issubclass", run: builtin_issubclass },
    BuiltinDef::{ name: "type", run: builtin_type },
    BuiltinDef::{ name: "type.__new__", run: builtin_type_new },
    BuiltinDef::{ name: "id", run: builtin_id },
    BuiltinDef::{ name: "hash", run: builtin_hash },
    BuiltinDef::{ name: "globals", run: builtin_globals },
    BuiltinDef::{
      name: "module_globals.__getitem__",
      run: builtin_module_globals_getitem,
    },
    BuiltinDef::{
      name: "module_globals.__setitem__",
      run: builtin_module_globals_setitem,
    },
    BuiltinDef::{
      name: "module_globals.__delitem__",
      run: builtin_module_globals_delitem,
    },
    BuiltinDef::{
      name: "module_globals.__iter__",
      run: builtin_module_globals_iter,
    },
    BuiltinDef::{
      name: "module_globals.__len__",
      run: builtin_module_globals_len,
    },
    BuiltinDef::{
      name: "module_globals.__contains__",
      run: builtin_module_globals_contains,
    },
    BuiltinDef::{ name: "module_globals.get", run: builtin_module_globals_get },
    BuiltinDef::{
      name: "module_globals.keys",
      run: builtin_module_globals_keys,
    },
    BuiltinDef::{
      name: "module_globals.values",
      run: builtin_module_globals_values,
    },
    BuiltinDef::{
      name: "module_globals.items",
      run: builtin_module_globals_items,
    },
    BuiltinDef::{ name: "module_globals.pop", run: builtin_module_globals_pop },
    BuiltinDef::{
      name: "module_globals.update",
      run: builtin_module_globals_update,
    },
    BuiltinDef::{
      name: "module_globals.copy",
      run: builtin_module_globals_copy,
    },
    BuiltinDef::{ name: "vars", run: builtin_vars },
    BuiltinDef::{ name: "locals", run: builtin_locals },
    BuiltinDef::{ name: "compile", run: builtin_compile },
    BuiltinDef::{ name: "eval", run: builtin_eval },
    BuiltinDef::{ name: "exec", run: builtin_exec },
    BuiltinDef::{ name: "__import__", run: builtin_import },
    BuiltinDef::{ name: "sys.intern", run: builtin_sys_intern },
    BuiltinDef::{ name: "sys.exc_info", run: builtin_sys_exc_info },
    BuiltinDef::{ name: "sys.exception", run: builtin_sys_exception },
    BuiltinDef::{ name: "sys._getframe", run: builtin_sys_getframe },
    BuiltinDef::{ name: "sys.excepthook", run: builtin_sys_excepthook },
    BuiltinDef::{
      name: "sys.__breakpointhook__",
      run: builtin_sys_breakpointhook,
    },
    BuiltinDef::{ name: "pdb.set_trace", run: builtin_pdb_set_trace },
    BuiltinDef::{
      name: "sys.getdefaultencoding",
      run: builtin_sys_getdefaultencoding,
    },
    BuiltinDef::{
      name: "sys.getfilesystemencoding",
      run: builtin_sys_getfilesystemencoding,
    },
    BuiltinDef::{
      name: "sys.getfilesystemencodeerrors",
      run: builtin_sys_getfilesystemencodeerrors,
    },
    BuiltinDef::{
      name: "sys.getrecursionlimit",
      run: builtin_sys_getrecursionlimit,
    },
    BuiltinDef::{
      name: "sys.setrecursionlimit",
      run: builtin_sys_setrecursionlimit,
    },
    BuiltinDef::{ name: "sys.exit", run: builtin_sys_exit },
    BuiltinDef::{ name: "sys.stdin.readline", run: builtin_sys_stdin_readline },
    BuiltinDef::{ name: "sys.stdin.isatty", run: builtin_sys_stdin_isatty },
    BuiltinDef::{ name: "sys.stdout.write", run: builtin_sys_stdout_write },
    BuiltinDef::{ name: "sys.stdout.flush", run: builtin_sys_stdout_flush },
    BuiltinDef::{
      name: "sys.stdout.reconfigure",
      run: builtin_sys_stdout_reconfigure,
    },
    BuiltinDef::{ name: "sys.stdout.isatty", run: builtin_sys_stdout_isatty },
    BuiltinDef::{ name: "sys.stderr.write", run: builtin_sys_stderr_write },
    BuiltinDef::{ name: "sys.stderr.flush", run: builtin_sys_stderr_flush },
    BuiltinDef::{
      name: "sys.stderr.reconfigure",
      run: builtin_sys_stderr_reconfigure,
    },
    BuiltinDef::{ name: "sys.stderr.isatty", run: builtin_sys_stderr_isatty },
    BuiltinDef::{ name: "dir", run: builtin_dir },
    BuiltinDef::{ name: "getattr", run: builtin_getattr },
    BuiltinDef::{ name: "hasattr", run: builtin_hasattr },
    BuiltinDef::{ name: "setattr", run: builtin_setattr },
    BuiltinDef::{ name: "delattr", run: builtin_delattr },
    BuiltinDef::{ name: "super", run: builtin_super },
    BuiltinDef::{ name: "staticmethod.__get__", run: builtin_staticmethod_get },
  ]
  builtin_defs_ready.val = true
}

///|
/// Evaluate a builtin call `name(args...)` with pre-evaluated arguments.
///
/// Returns `Ok(Some(value))` if handled as a builtin, `Ok(None)` if not a builtin.
fn eval_builtin_call(
  name : String,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value?, RuntimeError] {
  ensure_builtin_defs_ready()
  for def in builtin_defs_ref.val {
    if def.name == name {
      let value = match
        (def.run)(positional, keywords, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      return Ok(Some(value))
    }
  }
  Ok(None)
}
