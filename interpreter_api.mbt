///|
/// Public interpreter APIs.

///|
fn function_stub(name : String) -> Value {
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
pub fn Config::default() -> Config {
  Config::{
    max_recursion: 1000,
    traceback_limit: 20,
    track_spans: true,
    allow_filesystem_imports: false,
    import_paths: [],
    main_path: None,
  }
}

///|
pub fn Config::for_cli(
  import_paths : Array[String],
  main_path : String?,
) -> Config {
  let base = Config::default()
  Config::{
    max_recursion: base.max_recursion,
    traceback_limit: base.traceback_limit,
    track_spans: base.track_spans,
    allow_filesystem_imports: true,
    import_paths,
    main_path,
  }
}

///|
pub fn MockIO::new(stdin : Array[String]) -> MockIO {
  MockIO::{
    stdin,
    stdin_pos: { val: 0 },
    stdout: StringBuilder::new(),
    stderr: StringBuilder::new(),
  }
}

///|
pub fn MockIO::read_line(self : MockIO) -> String? {
  if self.stdin_pos.val >= self.stdin.length() {
    None
  } else {
    let line = self.stdin[self.stdin_pos.val]
    self.stdin_pos.val += 1
    Some(line)
  }
}

///|
pub fn MockIO::write_stdout(self : MockIO, text : String) -> Unit {
  self.stdout.write_string(text)
}

///|
pub fn MockIO::write_stderr(self : MockIO, text : String) -> Unit {
  self.stderr.write_string(text)
}

///|
pub fn MockIO::take_stdout(self : MockIO) -> String {
  self.stdout.to_string()
}

///|
pub fn MockIO::take_stderr(self : MockIO) -> String {
  self.stderr.to_string()
}

///|
pub fn Interpreter::new() -> Interpreter {
  let config = Config::{
    max_recursion: 1000,
    traceback_limit: 20,
    track_spans: true,
    allow_filesystem_imports: true,
    import_paths: [],
    main_path: None,
  }
  Interpreter::with_io(config, MockIO::new([]))
}

///|
pub fn Interpreter::with_config(config : Config) -> Interpreter {
  Interpreter::with_io(config, MockIO::new([]))
}

///|
pub fn Interpreter::new_spec() -> Interpreter {
  let config = Config::default()
  let object_dict : Array[(String, Value)] = []
  object_dict.push(
    (
      "__getattribute__",
      Value::Function(FunctionValue::{
        name: "__getattribute__",
        params: ["self", "name"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__setattr__",
      Value::Function(FunctionValue::{
        name: "__setattr__",
        params: ["self", "name", "value"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__delattr__",
      Value::Function(FunctionValue::{
        name: "__delattr__",
        params: ["self", "name"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__init__",
      Value::Function(FunctionValue::{
        name: "__init__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__eq__",
      Value::Function(FunctionValue::{
        name: "__eq__",
        params: ["self", "other"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__ne__",
      Value::Function(FunctionValue::{
        name: "__ne__",
        params: ["self", "other"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__str__",
      Value::Function(FunctionValue::{
        name: "__str__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  let object_class = ClassValue::{
    name: "object",
    bases: [],
    dict: object_dict,
  }
  let ellipsis_class = ClassValue::{
    name: "ellipsis",
    bases: [Value::Class(object_class)],
    dict: [],
  }
  let not_implemented_class = ClassValue::{
    name: "NotImplementedType",
    bases: [Value::Class(object_class)],
    dict: [],
  }
  let ellipsis_value = Value::Instance(InstanceValue::{
    class: ellipsis_class,
    dict: [],
  })
  let not_implemented_value = Value::Instance(InstanceValue::{
    class: not_implemented_class,
    dict: [],
  })
  let base_exception_dict : Array[(String, Value)] = []
  base_exception_dict.push(
    (
      "with_traceback",
      Value::Function(FunctionValue::{
        name: "with_traceback",
        params: ["self", "tb"],
        defaults: [],
        body: [Stmt::Return(Some(Expr::Name("self")))],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  let base_exception_class = ClassValue::{
    name: "BaseException",
    bases: [Value::Class(object_class)],
    dict: base_exception_dict,
  }
  let exception_class = ClassValue::{
    name: "Exception",
    bases: [Value::Class(base_exception_class)],
    dict: [],
  }
  let base_exception_group_class = ClassValue::{
    name: "BaseExceptionGroup",
    bases: [Value::Class(base_exception_class)],
    dict: [],
  }
  let exception_group_class = ClassValue::{
    name: "ExceptionGroup",
    bases: [
      Value::Class(base_exception_group_class),
      Value::Class(exception_class),
    ],
    dict: [],
  }
  let builtins : Array[(String, Value)] = []
  builtins.push(("__debug__", Value::Bool(true)))
  let builtin_fn_names : Array[String] = [
    "__mpython_run", "__mpython_asyncgenexp_next", "__mpython_asyncgen_next", "__mpython_asyncgen_send",
    "__mpython_asyncgen_throw", "__mpython_asyncgen_close", "print", "len", "range",
    "str", "bytes", "bytearray", "memoryview", "int", "float", "complex", "list",
    "dict", "set", "frozenset", "tuple", "enumerate", "zip", "map", "filter", "any", "all", "sum",
    "property", "staticmethod", "classmethod", "delattr", "super", "eval", "exec",
    "__import__",
  ]
  for fn_name in builtin_fn_names {
    builtins.push((fn_name, function_stub(fn_name)))
  }
  builtins.push(("object", Value::Class(object_class)))
  builtins.push(("Ellipsis", ellipsis_value))
  builtins.push(("NotImplemented", not_implemented_value))
  builtins.push(("BaseException", Value::Class(base_exception_class)))
  builtins.push(("Exception", Value::Class(exception_class)))
  builtins.push(
    ("BaseExceptionGroup", Value::Class(base_exception_group_class)),
  )
  builtins.push(("ExceptionGroup", Value::Class(exception_group_class)))
  Interpreter::with_builtins(builtins, config)
}

///|
pub fn Interpreter::with_builtins(
  builtins : Array[(String, Value)],
  config : Config,
) -> Interpreter {
  Interpreter::{ config, globals: [], builtins, io: MockIO::new([]) }
}

///|
pub fn Interpreter::with_io(config : Config, io : MockIO) -> Interpreter {
  let object_dict : Array[(String, Value)] = []
  object_dict.push(
    (
      "__getattribute__",
      Value::Function(FunctionValue::{
        name: "__getattribute__",
        params: ["self", "name"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__setattr__",
      Value::Function(FunctionValue::{
        name: "__setattr__",
        params: ["self", "name", "value"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__delattr__",
      Value::Function(FunctionValue::{
        name: "__delattr__",
        params: ["self", "name"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__init__",
      Value::Function(FunctionValue::{
        name: "__init__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__eq__",
      Value::Function(FunctionValue::{
        name: "__eq__",
        params: ["self", "other"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__ne__",
      Value::Function(FunctionValue::{
        name: "__ne__",
        params: ["self", "other"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  object_dict.push(
    (
      "__str__",
      Value::Function(FunctionValue::{
        name: "__str__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  let object_class = ClassValue::{
    name: "object",
    bases: [],
    dict: object_dict,
  }
  let ellipsis_class = ClassValue::{
    name: "ellipsis",
    bases: [Value::Class(object_class)],
    dict: [],
  }
  let not_implemented_class = ClassValue::{
    name: "NotImplementedType",
    bases: [Value::Class(object_class)],
    dict: [],
  }
  let ellipsis_value = Value::Instance(InstanceValue::{
    class: ellipsis_class,
    dict: [],
  })
  let not_implemented_value = Value::Instance(InstanceValue::{
    class: not_implemented_class,
    dict: [],
  })
  let base_exception_dict : Array[(String, Value)] = []
  base_exception_dict.push(
    (
      "with_traceback",
      Value::Function(FunctionValue::{
        name: "with_traceback",
        params: ["self", "tb"],
        defaults: [],
        body: [Stmt::Return(Some(Expr::Name("self")))],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  let base_exception_class = ClassValue::{
    name: "BaseException",
    bases: [Value::Class(object_class)],
    dict: base_exception_dict,
  }
  let exception_class = ClassValue::{
    name: "Exception",
    bases: [Value::Class(base_exception_class)],
    dict: [],
  }
  let base_exception_group_class = ClassValue::{
    name: "BaseExceptionGroup",
    bases: [Value::Class(base_exception_class)],
    dict: [],
  }
  let exception_group_class = ClassValue::{
    name: "ExceptionGroup",
    bases: [
      Value::Class(base_exception_group_class),
      Value::Class(exception_class),
    ],
    dict: [],
  }
  let name_error_class = ClassValue::{
    name: "NameError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let unbound_local_error_class = ClassValue::{
    name: "UnboundLocalError",
    bases: [Value::Class(name_error_class)],
    dict: [],
  }
  let type_error_class = ClassValue::{
    name: "TypeError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let attribute_error_class = ClassValue::{
    name: "AttributeError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let index_error_class = ClassValue::{
    name: "IndexError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let key_error_class = ClassValue::{
    name: "KeyError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let not_implemented_error_class = ClassValue::{
    name: "NotImplementedError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let zero_division_error_class = ClassValue::{
    name: "ZeroDivisionError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let overflow_error_class = ClassValue::{
    name: "OverflowError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let value_error_class = ClassValue::{
    name: "ValueError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let import_error_class = ClassValue::{
    name: "ImportError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let assertion_error_class = ClassValue::{
    name: "AssertionError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let syntax_error_class = ClassValue::{
    name: "SyntaxError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let indentation_error_class = ClassValue::{
    name: "IndentationError",
    bases: [Value::Class(syntax_error_class)],
    dict: [],
  }
  let eof_error_class = ClassValue::{
    name: "EOFError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let stop_iteration_class = ClassValue::{
    name: "StopIteration",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let stop_async_iteration_class = ClassValue::{
    name: "StopAsyncIteration",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let runtime_error_class = ClassValue::{
    name: "RuntimeError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let builtins : Array[(String, Value)] = [
    ("print", function_stub("print")),
    ("input", function_stub("input")),
    ("__debug__", Value::Bool(true)),
    ("__mpython_run", function_stub("__mpython_run")),
    ("__mpython_asyncgenexp_next", function_stub("__mpython_asyncgenexp_next")),
    ("__mpython_asyncgen_next", function_stub("__mpython_asyncgen_next")),
    ("__mpython_asyncgen_send", function_stub("__mpython_asyncgen_send")),
    ("__mpython_asyncgen_throw", function_stub("__mpython_asyncgen_throw")),
    ("__mpython_asyncgen_close", function_stub("__mpython_asyncgen_close")),
    ("str", function_stub("str")),
    ("bytes", function_stub("bytes")),
    ("bytearray", function_stub("bytearray")),
    ("memoryview", function_stub("memoryview")),
    ("dict", function_stub("dict")),
    ("list", function_stub("list")),
    ("tuple", function_stub("tuple")),
    ("set", function_stub("set")),
    ("frozenset", function_stub("frozenset")),
    ("len", function_stub("len")),
    ("range", function_stub("range")),
    ("sum", function_stub("sum")),
    ("max", function_stub("max")),
    ("min", function_stub("min")),
    ("any", function_stub("any")),
    ("all", function_stub("all")),
    ("enumerate", function_stub("enumerate")),
    ("zip", function_stub("zip")),
    ("map", function_stub("map")),
    ("filter", function_stub("filter")),
    ("reversed", function_stub("reversed")),
    ("sorted", function_stub("sorted")),
    ("int", function_stub("int")),
    ("float", function_stub("float")),
    ("complex", function_stub("complex")),
    ("iter", function_stub("iter")),
    ("next", function_stub("next")),
    ("bool", function_stub("bool")),
    ("property", function_stub("property")),
    ("staticmethod", function_stub("staticmethod")),
    ("classmethod", function_stub("classmethod")),
    ("delattr", function_stub("delattr")),
    ("super", function_stub("super")),
    ("repr", function_stub("repr")),
    ("abs", function_stub("abs")),
    ("round", function_stub("round")),
    ("pow", function_stub("pow")),
    ("divmod", function_stub("divmod")),
    ("chr", function_stub("chr")),
    ("ord", function_stub("ord")),
    ("bin", function_stub("bin")),
    ("oct", function_stub("oct")),
    ("hex", function_stub("hex")),
    ("callable", function_stub("callable")),
    ("isinstance", function_stub("isinstance")),
    ("type", function_stub("type")),
    ("id", function_stub("id")),
    ("hash", function_stub("hash")),
    ("globals", function_stub("globals")),
    ("locals", function_stub("locals")),
    ("eval", function_stub("eval")),
    ("exec", function_stub("exec")),
    ("__import__", function_stub("__import__")),
    ("dir", function_stub("dir")),
    ("getattr", function_stub("getattr")),
    ("hasattr", function_stub("hasattr")),
    ("setattr", function_stub("setattr")),
    ("object", Value::Class(object_class)),
    ("Ellipsis", ellipsis_value),
    ("NotImplemented", not_implemented_value),
    ("BaseException", Value::Class(base_exception_class)),
    ("Exception", Value::Class(exception_class)),
    ("BaseExceptionGroup", Value::Class(base_exception_group_class)),
    ("ExceptionGroup", Value::Class(exception_group_class)),
    ("NameError", Value::Class(name_error_class)),
    ("UnboundLocalError", Value::Class(unbound_local_error_class)),
    ("TypeError", Value::Class(type_error_class)),
    ("AttributeError", Value::Class(attribute_error_class)),
    ("IndexError", Value::Class(index_error_class)),
    ("KeyError", Value::Class(key_error_class)),
    ("NotImplementedError", Value::Class(not_implemented_error_class)),
    ("ZeroDivisionError", Value::Class(zero_division_error_class)),
    ("OverflowError", Value::Class(overflow_error_class)),
    ("ValueError", Value::Class(value_error_class)),
    ("ImportError", Value::Class(import_error_class)),
    ("AssertionError", Value::Class(assertion_error_class)),
    ("SyntaxError", Value::Class(syntax_error_class)),
    ("IndentationError", Value::Class(indentation_error_class)),
    ("EOFError", Value::Class(eof_error_class)),
    ("StopIteration", Value::Class(stop_iteration_class)),
    ("StopAsyncIteration", Value::Class(stop_async_iteration_class)),
    ("RuntimeError", Value::Class(runtime_error_class)),
  ]
  Interpreter::{
    config,
    globals: [("__name__", Value::Str("__main__"))],
    builtins,
    io,
  }
}

///|
pub fn Interpreter::exec(
  self : Interpreter,
  program : Module,
) -> Result[RunResult, RuntimeError] {
  ensure_runtime_callbacks_ready()
  let filename = match self.config.main_path {
    Some(path) => path
    None => "<module>".to_string()
  }
  push_traceback_frame("<module>".to_string(), filename)
  let value_result = eval_block(
    program.body,
    self.globals,
    self.globals,
    self.builtins,
    self.io,
    self.config,
  )
  pop_traceback_frame()
  let value = match value_result {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match value {
    Value::Function(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: unsupported value".to_string(),
        ),
      )
    _ => ()
  }
  Ok(RunResult::{
    value,
    stdout: self.io.take_stdout(),
    stderr: self.io.take_stderr(),
    globals: self.globals,
  })
}

///|
pub fn Interpreter::exec_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let program = match parse(source) {
    Ok(value) => value
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  self.exec(program)
}

///|
pub fn Interpreter::execute_test_dir(
  self : Interpreter,
  path : String,
) -> TestResult raise MpythonError {
  let _ = self
  if !@fs.path_exists(path) {
    let err = make_runtime_error(
      RuntimeErrorKind::Runtime,
      "RuntimeError: test dir not found: " + path,
    )
    raise MpythonError::MpythonError(err)
  }
  TestResult::{ passed: 0, failed: 0, errors: [] }
}

///|
pub fn Interpreter::eval_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let expr = match parse_expr(source) {
    Ok(value) => value
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  ensure_runtime_callbacks_ready()
  let filename = match self.config.main_path {
    Some(path) => path
    None => "<expr>".to_string()
  }
  push_traceback_frame("<expr>".to_string(), filename)
  push_active_config(self.config)
  let value_result = eval_expr_with_env(
    expr,
    self.globals,
    self.globals,
    self.builtins,
    self.io,
  )
  pop_active_config()
  pop_traceback_frame()
  let value = match value_result {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match value {
    Value::Function(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: unsupported value".to_string(),
        ),
      )
    Value::Instance(inst) =>
      if inst.class.name == "generator" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: unsupported value".to_string(),
          ),
        )
      }
    _ => ()
  }
  Ok(RunResult::{
    value,
    stdout: self.io.take_stdout(),
    stderr: self.io.take_stderr(),
    globals: self.globals,
  })
}

///|
pub fn Interpreter::eval(
  self : Interpreter,
  expr : Expr,
) -> Result[Value, RuntimeError] {
  ensure_runtime_callbacks_ready()
  eval_expr_with_env(expr, self.globals, self.globals, self.builtins, self.io)
}

///|
pub fn Interpreter::get_global(self : Interpreter, name : String) -> Value? {
  for pair in self.globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
pub fn Interpreter::set_global(
  self : Interpreter,
  name : String,
  value : Value,
) -> Unit {
  set_global_value(self.globals, name, value)
}
