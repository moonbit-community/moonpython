///|
/// Minimal module objects + module loading for `import`.

///|
let module_cache : Ref[Array[(String, Value)]] = { val: [] }

///|
let sys_modules_ref : Ref[Array[(Value, Value)]] = { val: [] }

///|
fn module_cache_get(name : String) -> Value? {
  for pair in module_cache.val {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in sys_modules_ref.val {
    match pair.0 {
      Value::Str(text) => if text == name { return Some(pair.1) }
      _ => ()
    }
  }
  None
}

///|
fn module_cache_set(name : String, module_value : Value) -> Unit {
  for i = 0; i < module_cache.val.length(); i = i + 1 {
    if module_cache.val[i].0 == name {
      module_cache.val[i] = (name, module_value)
      for j = 0; j < sys_modules_ref.val.length(); j = j + 1 {
        match sys_modules_ref.val[j].0 {
          Value::Str(text) =>
            if text == name {
              sys_modules_ref.val[j] = (Value::Str(name), module_value)
              return
            }
          _ => ()
        }
      }
      sys_modules_ref.val.push((Value::Str(name), module_value))
      return
    }
  }
  module_cache.val.push((name, module_value))
  for j = 0; j < sys_modules_ref.val.length(); j = j + 1 {
    match sys_modules_ref.val[j].0 {
      Value::Str(text) =>
        if text == name {
          sys_modules_ref.val[j] = (Value::Str(name), module_value)
          return
        }
      _ => ()
    }
  }
  sys_modules_ref.val.push((Value::Str(name), module_value))
}

///|
fn module_cache_delete(name : String) -> Unit {
  let mut i = module_cache.val.length()
  while i > 0 {
    i = i - 1
    if module_cache.val[i].0 == name {
      let _ = module_cache.val.remove(i)

    }
  }
  let mut j = sys_modules_ref.val.length()
  while j > 0 {
    j = j - 1
    match sys_modules_ref.val[j].0 {
      Value::Str(text) =>
        if text == name {
          let _ = sys_modules_ref.val.remove(j)

        }
      _ => ()
    }
  }
}

///|
fn module_name_parts(name : String) -> Array[String] {
  let out : Array[String] = []
  for part in name.split(".") {
    let text = part.to_string()
    if text.length() > 0 {
      out.push(text)
    }
  }
  out
}

///|
fn module_top_name(name : String) -> String {
  let parts = module_name_parts(name)
  if parts.length() == 0 {
    name
  } else {
    parts[0]
  }
}

///|
fn module_rel_path(name : String) -> String {
  let parts = module_name_parts(name)
  if parts.length() == 0 {
    name
  } else {
    let mut joined = parts[0]
    for i = 1; i < parts.length(); i = i + 1 {
      joined = joined + "/" + parts[i]
    }
    joined
  }
}

///|
fn module_join_parts(parts : Array[String], count : Int) -> String {
  if count <= 0 || parts.length() == 0 {
    "".to_string()
  } else {
    let mut joined = parts[0]
    let mut i = 1
    while i < count && i < parts.length() {
      joined = joined + "." + parts[i]
      i += 1
    }
    joined
  }
}

///|
fn module_parent_name(name : String) -> String {
  let parts = module_name_parts(name)
  if parts.length() <= 1 {
    "".to_string()
  } else {
    module_join_parts(parts, parts.length() - 1)
  }
}

///|
fn resolve_relative_module_name(
  module_name : String,
  globals : Array[(String, Value)],
) -> Result[String, RuntimeError] {
  if module_name.length() > 0 && !module_name.has_prefix(".") {
    return Ok(module_name)
  }
  let mut level = 1
  let mut rest = "".to_string()
  if module_name.length() > 0 {
    let chars = module_name.to_array()
    level = 0
    while level < chars.length() && chars[level] == '.' {
      level += 1
    }
    rest = substring(module_name, level, module_name.length())
  }
  let package_name = match get_named_value(globals, "__package__") {
    Some(Value::Str(name)) => name
    _ => "".to_string()
  }
  if package_name.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ImportError: attempted relative import with no known parent package",
      ),
    )
  }
  let parts = module_name_parts(package_name)
  let base_len = parts.length() - (level - 1)
  if base_len <= 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ImportError: attempted relative import beyond top-level package",
      ),
    )
  }
  let base = module_join_parts(parts, base_len)
  if rest.length() == 0 {
    Ok(base)
  } else {
    Ok(base + "." + rest)
  }
}

///|
fn set_module_attr(module_value : Value, name : String, value : Value) -> Unit {
  match module_value {
    Value::Instance(inst) => set_named_value(inst.dict, name, value)
    _ => ()
  }
}

///|
fn ensure_module_entry(name : String) -> Value {
  match module_cache_get(name) {
    Some(value) => value
    None => {
      let module_value = make_module_instance(name, [])
      module_cache_set(name, module_value)
      module_value
    }
  }
}

///|
fn register_module_hierarchy(
  module_name : String,
  module_value : Value,
) -> Unit {
  let parts = module_name_parts(module_name)
  if parts.length() == 0 {
    return
  }
  module_cache_set(module_name, module_value)
  if parts.length() == 1 {
    return
  }
  let mut prefix = parts[0]
  let mut parent = ensure_module_entry(prefix)
  for i = 1; i < parts.length(); i = i + 1 {
    let part = parts[i]
    let current_name = prefix + "." + part
    let current = if i == parts.length() - 1 {
      module_value
    } else {
      ensure_module_entry(current_name)
    }
    set_module_attr(parent, part, current)
    parent = current
    prefix = current_name
  }
}

///|
fn module_function_stub(name : String) -> Value {
  Value::Function(FunctionValue::{
    name,
    params: [],
    defaults: [],
    body: [],
    is_generator: false,
    is_async: false,
    closure: [],
  })
}

///|
fn make_importlib_loader() -> Value {
  // Loader used by the stdlib `importlib` machinery. Methods are intrinsics
  // implemented in `call_callable_with_env`.
  let loader_class = ClassValue::{
    name: "_MpythonLoader",
    bases: [],
    dict: [
      (
        "create_module",
        Value::Function(FunctionValue::{
          name: "__mpython_create_module",
          params: ["self", "spec"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "exec_module",
        Value::Function(FunctionValue::{
          name: "__mpython_exec_module",
          params: ["self", "module"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  Value::Instance(InstanceValue::{ class: loader_class, dict: [] })
}

///|
fn make_importlib_finder() -> Value {
  // A minimal `sys.meta_path` finder to make CPython's pure-Python importlib
  // usable. The actual search logic lives in the intrinsic implementation.
  let finder_class = ClassValue::{
    name: "_MpythonPathFinder",
    bases: [],
    dict: [
      (
        "find_spec",
        Value::Function(FunctionValue::{
          name: "__mpython_find_spec",
          params: ["self", "fullname", "path", "target"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  Value::Instance(InstanceValue::{ class: finder_class, dict: [] })
}

///|
fn make_module_instance(name : String, dict : Array[(String, Value)]) -> Value {
  let module_class = ClassValue::{ name: "module", bases: [], dict: [] }
  let spec_class = ClassValue::{ name: "ModuleSpec", bases: [], dict: [] }
  let spec_value = Value::Instance(InstanceValue::{
    class: spec_class,
    dict: [
      ("name", Value::Str(name)),
      ("origin", Value::Str("<builtin>")),
      ("loader", Value::None),
      ("parent", Value::Str("")),
      ("submodule_search_locations", Value::None),
      ("cached", Value::None),
      ("loader_state", Value::None),
      ("_uninitialized_submodules", Value::List([])),
      ("has_location", Value::Bool(false)),
    ],
  })
  Value::Instance(InstanceValue::{
    class: module_class,
    // Keep a minimum set of attributes expected by CPython's importlib and
    // stdlib test harness. These are intentionally shallow shims.
    dict: [
      ("__name__", Value::Str(name)),
      ("__package__", Value::Str("")),
      ("__loader__", Value::None),
      ("__spec__", spec_value),
    ] +
    dict,
  })
}

///|
fn make_math_module() -> Value {
  make_module_instance("math", [
    ("pi", Value::Float(3.141592653589793)),
    ("e", Value::Float(2.718281828459045)),
    ("tau", Value::Float(6.283185307179586)),
    ("sqrt", module_function_stub("math.sqrt")),
    ("pow", module_function_stub("math.pow")),
    ("log", module_function_stub("math.log")),
    ("log2", module_function_stub("math.log2")),
    ("exp", module_function_stub("math.exp")),
    ("ceil", module_function_stub("math.ceil")),
    ("floor", module_function_stub("math.floor")),
    ("trunc", module_function_stub("math.trunc")),
    ("frexp", module_function_stub("math.frexp")),
    ("ldexp", module_function_stub("math.ldexp")),
    ("acos", module_function_stub("math.acos")),
    ("cos", module_function_stub("math.cos")),
    ("sin", module_function_stub("math.sin")),
    ("hypot", module_function_stub("math.hypot")),
    ("fabs", module_function_stub("math.fabs")),
    ("erf", module_function_stub("math.erf")),
    ("lgamma", module_function_stub("math.lgamma")),
    ("fsum", module_function_stub("math.fsum")),
    ("sumprod", module_function_stub("math.sumprod")),
    ("isfinite", module_function_stub("math.isfinite")),
    ("isqrt", module_function_stub("math.isqrt")),
  ])
}

///|
fn make_time_module(builtins : Array[(String, Value)]) -> Value {
  let tuple_class = builtin_class_from_name("tuple", builtins)
  make_module_instance("time", [
    ("time", module_function_stub("time.time")),
    ("monotonic", module_function_stub("time.monotonic")),
    ("perf_counter", module_function_stub("time.perf_counter")),
    ("perf_counter_ns", module_function_stub("time.perf_counter_ns")),
    ("process_time", module_function_stub("time.process_time")),
    ("process_time_ns", module_function_stub("time.process_time_ns")),
    ("get_clock_info", module_function_stub("time.get_clock_info")),
    ("localtime", module_function_stub("time.localtime")),
    ("gmtime", module_function_stub("time.gmtime")),
    ("sleep", module_function_stub("time.sleep")),
    ("strftime", module_function_stub("time.strftime")),
    // Minimal compatibility: our `time.localtime()` returns a plain tuple.
    // Expose `struct_time` as an alias to `tuple` so stdlib code can reference it.
    ("struct_time", Value::Class(tuple_class)),
  ])
}

///|
fn make_platform_module() -> Value {
  // Minimal `platform` shim. The real CPython `platform` module relies on
  // tuple subclassing (namedtuple) which moonpython does not fully support yet.
  make_module_instance("platform", [
    (
      "system",
      Value::Function(FunctionValue::{
        name: "platform.system",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "machine",
      Value::Function(FunctionValue::{
        name: "platform.machine",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ])
}

///|
fn make_enum_module(builtins : Array[(String, Value)]) -> Value {
  // Minimal enum shim: enough for stdlib modules like `calendar` and basic
  // `IntEnum`/`IntFlag` usage. This is *not* a full implementation of
  // CPython's enum module.
  let object_class = builtin_class_from_name("object", builtins)
  let int_class = builtin_class_from_name("int", builtins)
  let str_class = builtin_class_from_name("str", builtins)
  let enum_class = ClassValue::{
    name: "Enum",
    bases: [Value::Class(object_class)],
    dict: [],
  }
  let int_enum_class = ClassValue::{
    name: "IntEnum",
    bases: [Value::Class(int_class), Value::Class(enum_class)],
    dict: [],
  }
  let str_enum_class = ClassValue::{
    name: "StrEnum",
    bases: [Value::Class(str_class), Value::Class(enum_class)],
    dict: [],
  }
  let int_flag_class = ClassValue::{
    name: "IntFlag",
    bases: [Value::Class(int_class), Value::Class(enum_class)],
    dict: [],
  }
  let decorator_class = ClassValue::{
    name: "_SimpleEnumDecorator",
    bases: [],
    dict: [
      (
        "__call__",
        Value::Function(FunctionValue::{
          name: "enum._simple_enum_decorator_call",
          params: ["self", "cls"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  make_module_instance("enum", [
    ("Enum", Value::Class(enum_class)),
    ("IntEnum", Value::Class(int_enum_class)),
    ("StrEnum", Value::Class(str_enum_class)),
    ("IntFlag", Value::Class(int_flag_class)),
    ("auto", module_function_stub("enum.auto")),
    ("global_enum", module_function_stub("enum.global_enum")),
    ("_simple_enum", module_function_stub("enum._simple_enum")),
    ("_SimpleEnumDecorator", Value::Class(decorator_class)),
  ])
}

///|
fn make_faulthandler_module() -> Value {
  // CPython exposes faulthandler as a C extension; for moonpython we provide a
  // minimal no-op shim so the stdlib test harness can import and call it.
  make_module_instance("faulthandler", [
    ("enable", module_function_stub("faulthandler.enable")),
    ("disable", module_function_stub("faulthandler.disable")),
    ("register", module_function_stub("faulthandler.register")),
    ("unregister", module_function_stub("faulthandler.unregister")),
    ("dump_traceback", module_function_stub("faulthandler.dump_traceback")),
    (
      "dump_traceback_later",
      module_function_stub("faulthandler.dump_traceback_later"),
    ),
    (
      "cancel_dump_traceback_later",
      module_function_stub("faulthandler.cancel_dump_traceback_later"),
    ),
    ("is_enabled", module_function_stub("faulthandler.is_enabled")),
  ])
}

///|
fn make_atexit_module() -> Value {
  // Minimal `atexit` shim: used by stdlib modules like `logging` to register
  // shutdown hooks. We don't execute hooks yet, but `register()` must exist.
  make_module_instance("atexit", [
    ("register", module_function_stub("atexit.register")),
  ])
}

///|
let socket_socket_class_ref : Ref[ClassValue?] = { val: None }

///|
fn socket_socket_class(builtins : Array[(String, Value)]) -> ClassValue {
  match socket_socket_class_ref.val {
    Some(klass) => return klass
    None => ()
  }
  let object_class = builtin_class_from_name("object", builtins)
  let dict : Array[(String, Value)] = [
    (
      "__init__",
      Value::Function(FunctionValue::{
        name: "socket.socket.__init__",
        params: ["self", "*args", "**kwargs"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "connect",
      Value::Function(FunctionValue::{
        name: "socket.socket.connect",
        params: ["self", "address"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "close",
      Value::Function(FunctionValue::{
        name: "socket.socket.close",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "send",
      Value::Function(FunctionValue::{
        name: "socket.socket.send",
        params: ["self", "data"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "sendall",
      Value::Function(FunctionValue::{
        name: "socket.socket.sendall",
        params: ["self", "data"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "sendto",
      Value::Function(FunctionValue::{
        name: "socket.socket.sendto",
        params: ["self", "data", "address"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "recv",
      Value::Function(FunctionValue::{
        name: "socket.socket.recv",
        params: ["self", "bufsize"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "settimeout",
      Value::Function(FunctionValue::{
        name: "socket.socket.settimeout",
        params: ["self", "timeout"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ]
  let klass = ClassValue::{
    name: "socket",
    bases: [Value::Class(object_class)],
    dict,
  }
  socket_socket_class_ref.val = Some(klass)
  klass
}

///|
fn make_socket_module(builtins : Array[(String, Value)]) -> Value {
  // Minimal `socket` shim: enough for importing `logging.handlers` and running
  // non-networking stdlib tests. This does not implement real networking.
  make_module_instance("socket", [
    ("AF_UNSPEC", Value::Int(0N)),
    ("AF_UNIX", Value::Int(1N)),
    ("AF_INET", Value::Int(2N)),
    ("AF_INET6", Value::Int(10N)),
    ("AI_PASSIVE", Value::Int(1N)),
    ("SOCK_STREAM", Value::Int(1N)),
    ("SOCK_DGRAM", Value::Int(2N)),
    ("has_ipv6", Value::Bool(false)),
    ("socket", Value::Class(socket_socket_class(builtins))),
    ("create_connection", module_function_stub("socket.create_connection")),
    ("getaddrinfo", module_function_stub("socket.getaddrinfo")),
  ])
}

///|
fn make_select_module() -> Value {
  make_module_instance("select", [
    ("select", module_function_stub("select.select")),
  ])
}

///|
fn make_struct_module(builtins : Array[(String, Value)]) -> Value {
  let exc_base = match get_named_value(builtins, "Exception") {
    Some(Value::Class(c)) => Value::Class(c)
    _ => Value::None
  }
  let struct_error_class = ClassValue::{
    name: "error",
    bases: if exc_base is Value::Class(_) {
      [exc_base]
    } else {
      []
    },
    dict: [],
  }
  let struct_class = ClassValue::{
    name: "Struct",
    bases: [],
    dict: [
      (
        "__init__",
        Value::Function(FunctionValue::{
          name: "_struct.Struct.__init__",
          params: ["self", "format"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "pack",
        Value::Function(FunctionValue::{
          name: "_struct.Struct.pack",
          params: [],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "unpack",
        Value::Function(FunctionValue::{
          name: "_struct.Struct.unpack",
          params: ["self", "buffer"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "calcsize",
        Value::Function(FunctionValue::{
          name: "_struct.Struct.calcsize",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  make_module_instance("_struct", [
    ("calcsize", module_function_stub("_struct.calcsize")),
    ("pack", module_function_stub("_struct.pack")),
    ("pack_into", module_function_stub("_struct.pack_into")),
    ("unpack", module_function_stub("_struct.unpack")),
    ("unpack_from", module_function_stub("_struct.unpack_from")),
    ("iter_unpack", module_function_stub("_struct.iter_unpack")),
    ("Struct", Value::Class(struct_class)),
    ("error", Value::Class(struct_error_class)),
    ("_clearcache", module_function_stub("_struct._clearcache")),
    ("__doc__", Value::Str("Minimal _struct shim for moonpython")),
  ])
}

///|
fn make_gc_module() -> Value {
  // CPython exposes `gc` as a C extension. For moonpython we provide a minimal
  // shim that is sufficient for importing/running parts of the stdlib tests.
  make_module_instance("gc", [
    // Used by regrtest and some tests. We never populate it (no real GC), but
    // it must exist and be mutable.
    ("garbage", Value::List([])),
    ("callbacks", Value::List([])),
    ("enable", module_function_stub("gc.enable")),
    ("disable", module_function_stub("gc.disable")),
    ("isenabled", module_function_stub("gc.isenabled")),
    ("collect", module_function_stub("gc.collect")),
    ("get_threshold", module_function_stub("gc.get_threshold")),
    ("set_threshold", module_function_stub("gc.set_threshold")),
    ("get_count", module_function_stub("gc.get_count")),
  ])
}

///|
fn make_binascii_module(builtins : Array[(String, Value)]) -> Value {
  // CPython exposes `binascii` as a C extension. moonpython doesn't support C
  // extensions, so provide a small pure-runtime subset used by the stdlib.
  let exc_base : Array[Value] = []
  match get_named_value(builtins, "ValueError") {
    Some(Value::Class(exc)) => exc_base.push(Value::Class(exc))
    _ => ()
  }
  if exc_base.length() == 0 {
    match get_named_value(builtins, "Exception") {
      Some(Value::Class(exc)) => exc_base.push(Value::Class(exc))
      _ => ()
    }
  }
  let error_class = ClassValue::{ name: "Error", bases: exc_base, dict: [] }
  let incomplete_class = ClassValue::{
    name: "Incomplete",
    bases: [Value::Class(error_class)],
    dict: [],
  }
  make_module_instance("binascii", [
    ("Error", Value::Class(error_class)),
    ("Incomplete", Value::Class(incomplete_class)),
    ("a2b_base64", module_function_stub("binascii.a2b_base64")),
    ("b2a_base64", module_function_stub("binascii.b2a_base64")),
    ("hexlify", module_function_stub("binascii.hexlify")),
    ("unhexlify", module_function_stub("binascii.unhexlify")),
    ("a2b_hex", module_function_stub("binascii.a2b_hex")),
    ("b2a_hex", module_function_stub("binascii.b2a_hex")),
    ("crc32", module_function_stub("binascii.crc32")),
    ("__doc__", Value::Str("Minimal binascii shim for moonpython")),
  ])
}

///|
fn make_asyncio_module() -> Value {
  make_module_instance("asyncio", [
    ("run", module_function_stub("asyncio.run")),
    ("gather", module_function_stub("asyncio.gather")),
    (
      "iscoroutinefunction",
      Value::Function(FunctionValue::{
        name: "asyncio.iscoroutinefunction",
        params: ["func"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ])
}

///|
let rlock_class_ref : Ref[ClassValue?] = { val: None }

///|
fn thread_rlock_class(builtins : Array[(String, Value)]) -> ClassValue {
  match rlock_class_ref.val {
    Some(value) => return value
    None => ()
  }
  let bases : Array[Value] = []
  match get_named_value(builtins, "object") {
    Some(Value::Class(object_class)) => bases.push(Value::Class(object_class))
    _ => ()
  }
  let dict : Array[(String, Value)] = [
    (
      "__enter__",
      Value::Function(FunctionValue::{
        name: "_thread.RLock.__enter__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__exit__",
      Value::Function(FunctionValue::{
        name: "_thread.RLock.__exit__",
        params: ["self", "exc_type", "exc", "tb"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "acquire",
      Value::Function(FunctionValue::{
        name: "_thread.RLock.acquire",
        params: ["self", "blocking", "timeout"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "release",
      Value::Function(FunctionValue::{
        name: "_thread.RLock.release",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "locked",
      Value::Function(FunctionValue::{
        name: "_thread.RLock.locked",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "_at_fork_reinit",
      Value::Function(FunctionValue::{
        name: "_thread.RLock._at_fork_reinit",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ]
  let klass = ClassValue::{ name: "RLock", bases, dict }
  rlock_class_ref.val = Some(klass)
  klass
}

///|
fn make_thread_module(builtins : Array[(String, Value)]) -> Value {
  let rlock_class = thread_rlock_class(builtins)
  let exc_bases : Array[Value] = []
  match get_named_value(builtins, "Exception") {
    Some(Value::Class(exception_class)) =>
      exc_bases.push(Value::Class(exception_class))
    _ => ()
  }
  let error_class = ClassValue::{ name: "error", bases: exc_bases, dict: [] }
  make_module_instance("_thread", [
    ("get_ident", module_function_stub("_thread.get_ident")),
    ("allocate_lock", module_function_stub("_thread.allocate_lock")),
    ("start_new_thread", module_function_stub("_thread.start_new_thread")),
    ("daemon_threads_allowed", Value::Bool(true)),
    ("_set_sentinel", module_function_stub("_thread._set_sentinel")),
    ("_count", module_function_stub("_thread._count")),
    ("stack_size", module_function_stub("_thread.stack_size")),
    ("TIMEOUT_MAX", Value::Float(9223372036.0)),
    ("error", Value::Class(error_class)),
    ("RLock", Value::Class(rlock_class)),
  ])
}

///|
fn warnings_function_stub(name : String) -> Value {
  Value::Function(FunctionValue::{
    name,
    params: ["*args", "**kwargs"],
    defaults: [],
    body: [],
    is_generator: false,
    is_async: false,
    closure: [],
  })
}

///|
fn make_warnings_module() -> Value {
  make_module_instance("_warnings", [
    ("filters", Value::List([])),
    ("_defaultaction", Value::Str("default")),
    ("_onceregistry", Value::Dict([])),
    ("_filters_mutated", warnings_function_stub("_warnings._filters_mutated")),
    ("warn", warnings_function_stub("_warnings.warn")),
    ("warn_explicit", warnings_function_stub("_warnings.warn_explicit")),
  ])
}

///|
fn make_string_cmodule() -> Value {
  make_module_instance("_string", [
    ("formatter_parser", module_function_stub("_string.formatter_parser")),
    (
      "formatter_field_name_split",
      module_function_stub("_string.formatter_field_name_split"),
    ),
  ])
}

///|
fn make_itertools_chain_factory() -> Value {
  let dict : Array[(String, Value)] = [
    ("__call__", module_function_stub("itertools.chain")),
    ("from_iterable", module_function_stub("itertools.chain.from_iterable")),
  ]
  let klass = ClassValue::{ name: "chain_factory", bases: [], dict }
  Value::Instance(InstanceValue::{ class: klass, dict: [] })
}

///|
fn make_itertools_module() -> Value {
  make_module_instance("itertools", [
    ("chain", make_itertools_chain_factory()),
    ("accumulate", module_function_stub("itertools.accumulate")),
    ("filterfalse", module_function_stub("itertools.filterfalse")),
    ("groupby", module_function_stub("itertools.groupby")),
    ("count", module_function_stub("itertools.count")),
    ("cycle", module_function_stub("itertools.cycle")),
    ("repeat", module_function_stub("itertools.repeat")),
    ("starmap", module_function_stub("itertools.starmap")),
    ("islice", module_function_stub("itertools.islice")),
    ("permutations", module_function_stub("itertools.permutations")),
    ("product", module_function_stub("itertools.product")),
  ])
}

///|
fn make_weakref_module(builtins : Array[(String, Value)]) -> Value {
  let bases : Array[Value] = []
  match get_named_value(builtins, "object") {
    Some(Value::Class(object_class)) => bases.push(Value::Class(object_class))
    _ => ()
  }
  let weakref_dict : Array[(String, Value)] = [
    ("__new__", module_function_stub("_weakref.ref")),
    ("__hash__", module_function_stub("weakref.__hash__")),
  ]
  let reference_type_class = ClassValue::{
    name: "weakref",
    bases,
    dict: weakref_dict,
  }
  let proxy_type_class = ClassValue::{ name: "ProxyType", bases, dict: [] }
  let callable_proxy_type_class = ClassValue::{
    name: "CallableProxyType",
    bases,
    dict: [],
  }
  make_module_instance("_weakref", [
    ("ref", Value::Class(reference_type_class)),
    ("proxy", module_function_stub("_weakref.proxy")),
    ("getweakrefcount", module_function_stub("_weakref.getweakrefcount")),
    ("getweakrefs", module_function_stub("_weakref.getweakrefs")),
    (
      "_remove_dead_weakref",
      module_function_stub("_weakref._remove_dead_weakref"),
    ),
    ("ReferenceType", Value::Class(reference_type_class)),
    ("ProxyType", Value::Class(proxy_type_class)),
    ("CallableProxyType", Value::Class(callable_proxy_type_class)),
  ])
}

///|
fn make_builtins_module(builtins : Array[(String, Value)]) -> Value {
  let dict : Array[(String, Value)] = []
  for pair in builtins {
    dict.push(pair)
  }
  make_module_instance("builtins", dict)
}

///|
fn make_sys_module(builtins : Array[(String, Value)], config : Config) -> Value {
  let _ = builtins
  let builtin_module_names = Value::Tuple([
    Value::Str("builtins"),
    Value::Str("sys"),
    Value::Str("posix"),
    Value::Str("_struct"),
    Value::Str("gc"),
    Value::Str("binascii"),
    Value::Str("faulthandler"),
    Value::Str("select"),
    Value::Str("_thread"),
    Value::Str("_warnings"),
    Value::Str("_weakref"),
    Value::Str("_string"),
    Value::Str("itertools"),
    Value::Str("math"),
    Value::Str("time"),
    Value::Str("asyncio"),
  ])
  let version_info = Value::Tuple([
    Value::Int(3N),
    Value::Int(12N),
    Value::Int(0N),
    Value::Str("final"),
    Value::Int(0N),
  ])
  let impl_class = ClassValue::{ name: "implementation", bases: [], dict: [] }
  let impl_value = Value::Instance(InstanceValue::{
    class: impl_class,
    dict: [("name", Value::Str("moonpython")), ("version", version_info)],
  })
  let float_info_class = ClassValue::{ name: "float_info", bases: [], dict: [] }
  let float_info_value = Value::Instance(InstanceValue::{
    class: float_info_class,
    dict: [
      ("max", Value::Float(1.7976931348623157e308)),
      ("max_exp", Value::Int(1024N)),
      ("max_10_exp", Value::Int(308N)),
      ("min", Value::Float(2.2250738585072014e-308)),
      ("min_exp", Value::Int(-1021N)),
      ("min_10_exp", Value::Int(-307N)),
      ("digits", Value::Int(15N)),
      ("mant_dig", Value::Int(53N)),
      ("epsilon", Value::Float(2.220446049250313e-16)),
      ("radix", Value::Int(2N)),
      ("rounds", Value::Int(1N)),
    ],
  })
  let hash_info_class = ClassValue::{ name: "hash_info", bases: [], dict: [] }
  let hash_info_value = Value::Instance(InstanceValue::{
    class: hash_info_class,
    dict: [
      ("width", Value::Int(64N)),
      ("modulus", Value::Int(2305843009213693951N)),
      ("inf", Value::Int(314159N)),
      ("nan", Value::Int(0N)),
      ("imag", Value::Int(1000003N)),
      ("algorithm", Value::Str("siphash13")),
      ("hash_bits", Value::Int(64N)),
      ("seed_bits", Value::Int(128N)),
      ("cutoff", Value::Int(0N)),
    ],
  })
  let flags_class = ClassValue::{ name: "flags", bases: [], dict: [] }
  let flags_value = Value::Instance(InstanceValue::{
    class: flags_class,
    dict: [
      ("debug", Value::Int(0N)),
      ("inspect", Value::Int(0N)),
      ("interactive", Value::Int(0N)),
      ("optimize", Value::Int(0N)),
      ("dont_write_bytecode", Value::Int(0N)),
      ("no_user_site", Value::Int(0N)),
      ("no_site", Value::Int(0N)),
      ("ignore_environment", Value::Int(0N)),
      ("verbose", Value::Int(0N)),
      ("bytes_warning", Value::Int(0N)),
      ("quiet", Value::Int(0N)),
      ("hash_randomization", Value::Int(0N)),
      ("isolated", Value::Int(0N)),
      ("dev_mode", Value::Int(0N)),
      ("utf8_mode", Value::Int(0N)),
      ("warn_default_encoding", Value::Int(0N)),
    ],
  })
  let stdout_class = ClassValue::{
    name: "stdout",
    bases: [],
    dict: [
      (
        "write",
        Value::Function(FunctionValue::{
          name: "sys.stdout.write",
          params: ["self", "text"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "flush",
        Value::Function(FunctionValue::{
          name: "sys.stdout.flush",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "reconfigure",
        Value::Function(FunctionValue::{
          name: "sys.stdout.reconfigure",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  let stderr_class = ClassValue::{
    name: "stderr",
    bases: [],
    dict: [
      (
        "write",
        Value::Function(FunctionValue::{
          name: "sys.stderr.write",
          params: ["self", "text"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "flush",
        Value::Function(FunctionValue::{
          name: "sys.stderr.flush",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "reconfigure",
        Value::Function(FunctionValue::{
          name: "sys.stderr.reconfigure",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  let stdout_value = Value::Instance(InstanceValue::{
    class: stdout_class,
    dict: [
      ("encoding", Value::Str("utf-8")),
      ("errors", Value::Str("strict")),
      ("newline", Value::None),
    ],
  })
  let stderr_value = Value::Instance(InstanceValue::{
    class: stderr_class,
    dict: [
      ("encoding", Value::Str("utf-8")),
      ("errors", Value::Str("strict")),
      ("newline", Value::None),
    ],
  })
  let prefix_value = Value::Str("")

  // `sys.argv` and `sys.path` are heavily relied upon by the CPython stdlib
  // (e.g. `unittest` assumes `argv[0]` exists).
  let argv_values : Array[Value] = []
  for arg in config.argv {
    argv_values.push(Value::Str(arg))
  }
  let path_values : Array[Value] = []
  let mut script_dir = "".to_string()
  match config.main_path {
    Some(main_path) => {
      let base = @path.Path(main_path).dirname().to_string()
      let base_abs = resolve_path_from_initial_cwd(base)
      if base_abs.length() > 0 && base_abs != "." {
        script_dir = base_abs
      }
    }
    None => ()
  }
  path_values.push(Value::Str(script_dir))
  if script_dir.length() > 0 {
    path_values.push(Value::Str(""))
  }
  for root in config.import_paths {
    path_values.push(Value::Str(resolve_path_from_initial_cwd(root)))
  }
  make_module_instance("sys", [
    ("maxsize", Value::Int(9223372036854775807N)),
    ("version", Value::Str("3.12.0 (#0, Jan 01 1970, 00:00:00) [moonpython]")),
    ("version_info", version_info),
    ("byteorder", Value::Str("little")),
    // Use a CPython-recognized platform tag so the stdlib can take appropriate
    // feature-gating branches (no subprocess/fork on WASI).
    ("platform", Value::Str("wasi")),
    ("platlibdir", Value::Str("lib")),
    ("abiflags", Value::Str("")),
    ("executable", Value::Str("moonpython")),
    ("implementation", impl_value),
    ("float_info", float_info_value),
    ("hash_info", hash_info_value),
    ("flags", flags_value),
    ("prefix", prefix_value),
    ("base_prefix", prefix_value),
    ("exec_prefix", prefix_value),
    ("base_exec_prefix", prefix_value),
    ("builtin_module_names", builtin_module_names),
    ("modules", Value::Dict(sys_modules_ref.val)),
    ("path", Value::List(path_values)),
    ("path_hooks", Value::List([])),
    ("path_importer_cache", Value::Dict([])),
    ("meta_path", Value::List([make_importlib_finder()])),
    ("argv", Value::List(argv_values)),
    ("warnoptions", Value::List([])),
    ("stdout", stdout_value),
    ("stderr", stderr_value),
    ("stdin", Value::None),
    ("__stdout__", stdout_value),
    ("__stderr__", stderr_value),
    ("__stdin__", Value::None),
    (
      "unraisablehook",
      Value::Function(FunctionValue::{
        name: "sys.unraisablehook",
        params: ["unraisable"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__unraisablehook__",
      Value::Function(FunctionValue::{
        name: "sys.unraisablehook",
        params: ["unraisable"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "exit",
      Value::Function(FunctionValue::{
        name: "sys.exit",
        params: ["status"],
        defaults: [Value::None],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "exc_info",
      Value::Function(FunctionValue::{
        name: "sys.exc_info",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "exception",
      Value::Function(FunctionValue::{
        name: "sys.exception",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "intern",
      Value::Function(FunctionValue::{
        name: "sys.intern",
        params: ["s"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "getdefaultencoding",
      Value::Function(FunctionValue::{
        name: "sys.getdefaultencoding",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "getfilesystemencoding",
      Value::Function(FunctionValue::{
        name: "sys.getfilesystemencoding",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "getfilesystemencodeerrors",
      Value::Function(FunctionValue::{
        name: "sys.getfilesystemencodeerrors",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "getrecursionlimit",
      Value::Function(FunctionValue::{
        name: "sys.getrecursionlimit",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "gettrace",
      Value::Function(FunctionValue::{
        name: "sys.gettrace",
        params: [],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "setrecursionlimit",
      Value::Function(FunctionValue::{
        name: "sys.setrecursionlimit",
        params: ["limit"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "settrace",
      Value::Function(FunctionValue::{
        name: "sys.settrace",
        params: ["func"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "excepthook",
      Value::Function(FunctionValue::{
        name: "sys.excepthook",
        params: ["exctype", "value", "traceback"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__excepthook__",
      Value::Function(FunctionValue::{
        name: "sys.excepthook",
        params: ["exctype", "value", "traceback"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ])
}

///|
fn make_sysconfigdata_module(name : String) -> Value {
  // CPython generates this at build-time; we provide a minimal stub so the
  // vendored stdlib (sysconfig + test.support) can import and proceed.
  make_module_instance(name, [("build_time_vars", Value::Dict([]))])
}

///|
fn make_python_module(
  name : String,
  source : String,
  builtins : Array[(String, Value)],
  io : MockIO,
  config : Config,
  package_name? : String = "",
  filename? : String = "<module>",
  is_package? : Bool = false,
  package_path? : String = "",
) -> Result[Value, RuntimeError] {
  let filename_abs = resolve_path_from_initial_cwd(filename)
  let package_path_abs = if is_package {
    resolve_path_from_initial_cwd(package_path)
  } else {
    package_path
  }
  let program = match parse(source) {
    Ok(v) => v
    Err(err) => {
      // Include filename for stdlib/import syntax errors to make debugging and
      // conformance triage practical.
      let base = make_parse_runtime_error(err)
      let message = filename_abs + ": " + base.message
      return Err(RuntimeError::{
        kind: base.kind,
        message,
        span: base.span,
        traceback: base.traceback,
        exc_type: base.exc_type,
        exc_args: [message],
        exc_value: base.exc_value,
        exc_cause: base.exc_cause,
        exc_context: base.exc_context,
        exc_suppress_context: base.exc_suppress_context,
      })
    }
  }
  fn unwrap_stmt(node : Stmt) -> Stmt {
    match node {
      Stmt::WithSpan(span~, stmt~) => {
        let _ = span
        unwrap_stmt(stmt)
      }
      other => other
    }
  }

  let doc_value = if program.body.length() > 0 {
    match unwrap_stmt(program.body[0]) {
      Stmt::ExprStmt(Expr::Literal(Literal::Str(text))) => Value::Str(text)
      _ => Value::None
    }
  } else {
    Value::None
  }
  let spec_class = ClassValue::{ name: "ModuleSpec", bases: [], dict: [] }
  // A tiny placeholder loader object so CPython's importlib bootstrap doesn't
  // treat file-backed modules as namespace packages (loader=None), which would
  // currently raise NotImplementedError during `_init_module_attrs`.
  let loader_class = ClassValue::{
    name: "SourceFileLoader",
    bases: [],
    dict: [],
  }
  let loader_value = Value::Instance(InstanceValue::{
    class: loader_class,
    dict: [("name", Value::Str(name)), ("path", Value::Str(filename_abs))],
  })
  let submodule_locations = if is_package {
    Value::List([Value::Str(package_path_abs)])
  } else {
    Value::None
  }
  let spec_value = Value::Instance(InstanceValue::{
    class: spec_class,
    dict: [
      ("name", Value::Str(name)),
      ("origin", Value::Str(filename_abs)),
      ("loader", loader_value),
      ("parent", Value::Str(package_name)),
      ("submodule_search_locations", submodule_locations),
      ("cached", Value::None),
      ("loader_state", Value::None),
      ("_uninitialized_submodules", Value::List([])),
      ("has_location", Value::Bool(true)),
    ],
  })
  let module_globals : Array[(String, Value)] = [
    ("__name__", Value::Str(name)),
    ("__package__", Value::Str(package_name)),
    ("__file__", Value::Str(filename_abs)),
    ("__loader__", loader_value),
    ("__spec__", spec_value),
    ("__doc__", doc_value),
  ]
  let module_class = ClassValue::{ name: "module", bases: [], dict: [] }
  let module_value = Value::Instance(InstanceValue::{
    class: module_class,
    dict: module_globals,
  })
  module_cache_set(name, module_value)
  // Module-level execution must not inherit the caller's closure/scope stacks
  // (e.g. `import x` from inside a function should not make module code see
  // that function's locals as "closure" candidates).
  let saved_closure_env_stack = closure_env_stack.val
  let saved_scope_decls_stack = scope_decls_stack.val
  closure_env_stack.val = []
  scope_decls_stack.val = []
  push_traceback_frame("<module>".to_string(), filename)
  let _ = match
    eval_block(
      program.body,
      module_globals,
      module_globals,
      builtins,
      io,
      config,
    ) {
    Ok(_) => ()
    Err(err) => {
      pop_traceback_frame()
      closure_env_stack.val = saved_closure_env_stack
      scope_decls_stack.val = saved_scope_decls_stack
      // Imports that raise during module execution should not leave a partially
      // initialized module in the cache. This prevents follow-up imports from
      // silently "succeeding" with missing attributes (e.g. `ssl` when `_ssl`
      // is absent).
      module_cache_delete(name)
      return Err(err)
    }
  }
  pop_traceback_frame()
  closure_env_stack.val = saved_closure_env_stack
  scope_decls_stack.val = saved_scope_decls_stack
  Ok(module_value)
}

///|
fn candidate_module_paths(
  module_name : String,
  globals : Array[(String, Value)],
  config : Config,
) -> Array[String] {
  let rel = module_rel_path(module_name) + ".py"
  let paths : Array[String] = []
  match config.main_path {
    Some(main_path) => {
      // Use x/path.dirname to get containing directory.
      let base = @path.Path(main_path).dirname().to_string()
      if base.length() > 0 {
        paths.push(@path.Path(base).join(@path.Path(rel)).to_string())
      }
    }
    None => ()
  }

  // Current working directory (honors `os.chdir()` via runtime workdir tracking).
  let cwd = resolve_path_from_cwd(rel)
  paths.push(cwd)

  // Additional import roots.
  for root in config.import_paths {
    paths.push(@path.Path(root).join(@path.Path(rel)).to_string())
  }

  // Avoid unused warnings.
  let _ = globals
  paths
}

///|
fn candidate_package_paths(
  module_name : String,
  globals : Array[(String, Value)],
  config : Config,
) -> Array[String] {
  let rel = module_rel_path(module_name)
  let paths : Array[String] = []
  match config.main_path {
    Some(main_path) => {
      let base = @path.Path(main_path).dirname().to_string()
      if base.length() > 0 {
        paths.push(@path.Path(base).join(@path.Path(rel)).to_string())
      }
    }
    None => ()
  }
  paths.push(resolve_path_from_cwd(rel))
  for root in config.import_paths {
    paths.push(@path.Path(root).join(@path.Path(rel)).to_string())
  }
  let _ = globals
  paths
}

///|
fn load_module_from_filesystem(
  module_name : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  config : Config,
) -> Result[Value, RuntimeError] {
  let paths = candidate_module_paths(module_name, globals, config)
  for path in paths {
    if @fs.path_exists(path) {
      let source = @fs.read_file_to_string(path) catch {
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "ImportError: cannot read file: " + path,
            ),
          )
      }
      return make_python_module(
        module_name,
        source,
        builtins,
        io,
        config,
        package_name=module_parent_name(module_name),
        filename=path,
      )
    }
  }
  let package_paths = candidate_package_paths(module_name, globals, config)
  for path in package_paths {
    let init_path = @path.Path(path).join(@path.Path("__init__.py")).to_string()
    if @fs.path_exists(init_path) {
      let source = @fs.read_file_to_string(init_path) catch {
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "ImportError: cannot read file: " + init_path,
            ),
          )
      }
      let module_value = make_python_module(
        module_name,
        source,
        builtins,
        io,
        config,
        package_name=module_name,
        filename=init_path,
        is_package=true,
        package_path=path,
      )
      match module_value {
        Ok(Value::Instance(inst)) =>
          // Mark as a package so stdlib importlib can resolve submodules.
          set_named_value(
            inst.dict,
            "__path__",
            Value::List([Value::Str(resolve_path_from_initial_cwd(path))]),
          )
        _ => ()
      }
      return module_value
    }
    if @fs.path_exists(path) {
      let module_value = make_module_instance(module_name, [])
      match module_value {
        Value::Instance(inst) =>
          set_named_value(
            inst.dict,
            "__path__",
            Value::List([Value::Str(resolve_path_from_initial_cwd(path))]),
          )
        _ => ()
      }
      return Ok(module_value)
    }
  }
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      "ModuleNotFoundError: No module named '" + module_name + "'",
    ),
  )
}

///|
fn import_module(
  module_name : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  config : Config,
) -> Result[Value, RuntimeError] {
  // CPython's test suite imports a number of private C-extension-only helper
  // modules (e.g. `_testcapi`). moonpython doesn't support C extensions, so
  // treat these as "skipped" to avoid crashing test modules that assume the
  // extension exists.
  if module_name.has_prefix("_test") {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "SkipTest: test module requires CPython C extension " + module_name,
      ),
    )
  }
  if module_name.length() == 0 {
    if !config.allow_filesystem_imports {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ImportError: module  is not allowed",
        ),
      )
    }
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ImportError: cannot import empty module name",
      ),
    )
  }
  match module_cache_get(module_name) {
    Some(v) => {
      register_module_hierarchy(module_name, v)
      return Ok(v)
    }
    None => ()
  }
  if module_name.contains(".") {
    let parent = module_parent_name(module_name)
    if parent.length() > 0 {
      let _ = match import_module(parent, globals, builtins, io, config) {
        Ok(v) => v
        Err(err) => return Err(err)
      }

    }
    match module_cache_get(module_name) {
      Some(v) => {
        register_module_hierarchy(module_name, v)
        return Ok(v)
      }
      None => ()
    }
  }
  let module_value = if module_name == "builtins" {
    make_builtins_module(builtins)
  } else if module_name == "sys" {
    make_sys_module(builtins, config)
  } else if module_name == "platform" {
    make_platform_module()
  } else if module_name.has_prefix("_sysconfigdata_") {
    make_sysconfigdata_module(module_name)
  } else if module_name == "_struct" {
    make_struct_module(builtins)
  } else if module_name == "gc" {
    make_gc_module()
  } else if module_name == "binascii" {
    make_binascii_module(builtins)
  } else if module_name == "faulthandler" {
    make_faulthandler_module()
  } else if module_name == "atexit" {
    make_atexit_module()
  } else if module_name == "socket" {
    make_socket_module(builtins)
  } else if module_name == "select" {
    make_select_module()
  } else if module_name == "_thread" {
    make_thread_module(builtins)
  } else if module_name == "_warnings" {
    make_warnings_module()
  } else if module_name == "_string" {
    make_string_cmodule()
  } else if module_name == "_weakref" {
    make_weakref_module(builtins)
  } else if module_name == "itertools" {
    make_itertools_module()
  } else if module_name == "math" {
    make_math_module()
  } else if module_name == "time" {
    make_time_module(builtins)
  } else if module_name == "enum" {
    make_enum_module(builtins)
  } else if module_name == "asyncio" {
    // Prefer the CPython stdlib `asyncio` package when filesystem imports are
    // enabled. Fall back to a tiny builtin shim when the stdlib isn't present
    // (or filesystem imports are disabled).
    if config.allow_filesystem_imports {
      match
        load_module_from_filesystem(module_name, globals, builtins, io, config) {
        Ok(v) => v
        Err(err) =>
          if err.exc_type == "ModuleNotFoundError" {
            make_asyncio_module()
          } else {
            return Err(err)
          }
      }
    } else {
      make_asyncio_module()
    }
  } else {
    if !config.allow_filesystem_imports {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ImportError: module " + module_name + " is not allowed",
        ),
      )
    }
    match
      load_module_from_filesystem(module_name, globals, builtins, io, config) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  register_module_hierarchy(module_name, module_value)
  Ok(module_value)
}
