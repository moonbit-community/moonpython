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
fn make_module_instance(name : String, dict : Array[(String, Value)]) -> Value {
  let module_class = ClassValue::{ name: "module", bases: [], dict: [] }
  Value::Instance(InstanceValue::{
    class: module_class,
    dict: [("__name__", Value::Str(name))] + dict,
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
fn make_time_module() -> Value {
  make_module_instance("time", [
    ("time", module_function_stub("time.time")),
    ("monotonic", module_function_stub("time.monotonic")),
    ("perf_counter", module_function_stub("time.perf_counter")),
    ("perf_counter_ns", module_function_stub("time.perf_counter_ns")),
    ("process_time", module_function_stub("time.process_time")),
    ("process_time_ns", module_function_stub("time.process_time_ns")),
    ("sleep", module_function_stub("time.sleep")),
    ("strftime", module_function_stub("time.strftime")),
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
fn make_asyncio_module() -> Value {
  make_module_instance("asyncio", [
    ("run", module_function_stub("asyncio.run")),
    ("gather", module_function_stub("asyncio.gather")),
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
      if base.length() > 0 && base != "." {
        script_dir = base
      }
    }
    None => ()
  }
  path_values.push(Value::Str(script_dir))
  if script_dir.length() > 0 {
    path_values.push(Value::Str(""))
  }
  for root in config.import_paths {
    path_values.push(Value::Str(root))
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
    ("argv", Value::List(argv_values)),
    ("warnoptions", Value::List([])),
    ("stdout", stdout_value),
    ("stderr", stderr_value),
    ("__stdout__", stdout_value),
    ("__stderr__", stderr_value),
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
) -> Result[Value, RuntimeError] {
  let program = match parse(source) {
    Ok(v) => v
    Err(err) => {
      // Include filename for stdlib/import syntax errors to make debugging and
      // conformance triage practical.
      let base = make_parse_runtime_error(err)
      let message = filename + ": " + base.message
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
  let module_globals : Array[(String, Value)] = [
    ("__name__", Value::Str(name)),
    ("__package__", Value::Str(package_name)),
    ("__file__", Value::Str(filename)),
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
      return make_python_module(
        module_name,
        source,
        builtins,
        io,
        config,
        package_name=module_name,
        filename=init_path,
      )
    }
    if @fs.path_exists(path) {
      return Ok(make_module_instance(module_name, []))
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
  } else if module_name.has_prefix("_sysconfigdata_") {
    make_sysconfigdata_module(module_name)
  } else if module_name == "_struct" {
    make_struct_module(builtins)
  } else if module_name == "gc" {
    make_gc_module()
  } else if module_name == "faulthandler" {
    make_faulthandler_module()
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
    make_time_module()
  } else if module_name == "asyncio" && config.allow_filesystem_imports {
    make_asyncio_module()
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
