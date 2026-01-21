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
    ("sqrt", module_function_stub("math.sqrt")),
    ("pow", module_function_stub("math.pow")),
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
    Some(Value::Class(object_class)) =>
      bases.push(Value::Class(object_class))
    _ => ()
  }
  let dict : Array[(String, Value)] = [
    (
      "__enter__",
      Value::Function(FunctionValue::{
        name: "__enter__",
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
        name: "__exit__",
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
        name: "acquire",
        params: ["self"],
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
        name: "release",
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
  make_module_instance("_thread", [
    ("get_ident", module_function_stub("_thread.get_ident")),
    ("allocate_lock", module_function_stub("_thread.allocate_lock")),
    ("RLock", Value::Class(rlock_class)),
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
    ("repeat", module_function_stub("itertools.repeat")),
    ("starmap", module_function_stub("itertools.starmap")),
    ("islice", module_function_stub("itertools.islice")),
  ])
}

///|
fn make_weakref_module() -> Value {
  make_module_instance("_weakref", [
    ("ref", module_function_stub("_weakref.ref")),
    ("proxy", module_function_stub("_weakref.proxy")),
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
fn make_sys_module(builtins : Array[(String, Value)]) -> Value {
  let _ = builtins
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
    dict: [
      ("name", Value::Str("mpython")),
      ("version", version_info),
    ],
  })
  make_module_instance("sys", [
    ("maxsize", Value::Int(9223372036854775807N)),
    ("version", Value::Str("3.12.0")),
    ("version_info", version_info),
    ("platform", Value::Str("mpython")),
    ("implementation", impl_value),
    ("modules", Value::Dict(sys_modules_ref.val)),
    ("path", Value::List([])),
    ("argv", Value::List([])),
  ])
}

///|
fn make_python_module(
  name : String,
  source : String,
  builtins : Array[(String, Value)],
  io : MockIO,
  config : Config,
) -> Result[Value, RuntimeError] {
  let program = match parse(source) {
    Ok(v) => v
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  let module_globals : Array[(String, Value)] = []
  module_globals.push(("__name__", Value::Str(name)))
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
    Err(err) => return Err(err)
  }
  Ok(make_module_instance(name, module_globals))
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

  // Current working directory.
  paths.push(rel)

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
  paths.push(rel)
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
      return make_python_module(module_name, source, builtins, io, config)
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
      return make_python_module(module_name, source, builtins, io, config)
    }
    if @fs.path_exists(path) {
      return Ok(make_module_instance(module_name, []))
    }
  }
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      "ImportError: cannot find module " + module_name,
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
  let module_value = if module_name == "builtins" {
    make_builtins_module(builtins)
  } else if module_name == "sys" {
    make_sys_module(builtins)
  } else if module_name == "_thread" {
    make_thread_module(builtins)
  } else if module_name == "_weakref" {
    make_weakref_module()
  } else if module_name == "itertools" {
    make_itertools_module()
  } else if module_name == "math" {
    make_math_module()
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
