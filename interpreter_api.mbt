///|
/// Public interpreter APIs.

///|
pub fn Config::default() -> Config {
  Config::{ max_recursion: 1000, traceback_limit: 20, track_spans: true }
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
  Interpreter::with_io(Config::default(), MockIO::new([]))
}

///|
pub fn Interpreter::with_config(config : Config) -> Interpreter {
  Interpreter::with_io(config, MockIO::new([]))
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
  let object_class = ClassValue::{ name: "object", bases: [], dict: [] }
  let base_exception_class = ClassValue::{
    name: "BaseException",
    bases: [Value::Class(object_class)],
    dict: [],
  }
  let exception_class = ClassValue::{
    name: "Exception",
    bases: [Value::Class(base_exception_class)],
    dict: [],
  }
  let name_error_class = ClassValue::{
    name: "NameError",
    bases: [Value::Class(exception_class)],
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
  let runtime_error_class = ClassValue::{
    name: "RuntimeError",
    bases: [Value::Class(exception_class)],
    dict: [],
  }
  let builtins : Array[(String, Value)] = [
    (
      "print",
      Value::Function(FunctionValue::{ name: "print", params: [], body: [] }),
    ),
    (
      "input",
      Value::Function(FunctionValue::{ name: "input", params: [], body: [] }),
    ),
    ("__debug__", Value::Bool(true)),
    (
      "str",
      Value::Function(FunctionValue::{ name: "str", params: [], body: [] }),
    ),
    (
      "bytes",
      Value::Function(FunctionValue::{ name: "bytes", params: [], body: [] }),
    ),
    (
      "dict",
      Value::Function(FunctionValue::{ name: "dict", params: [], body: [] }),
    ),
    (
      "list",
      Value::Function(FunctionValue::{ name: "list", params: [], body: [] }),
    ),
    (
      "tuple",
      Value::Function(FunctionValue::{ name: "tuple", params: [], body: [] }),
    ),
    (
      "set",
      Value::Function(FunctionValue::{ name: "set", params: [], body: [] }),
    ),
    (
      "len",
      Value::Function(FunctionValue::{ name: "len", params: [], body: [] }),
    ),
    (
      "range",
      Value::Function(FunctionValue::{ name: "range", params: [], body: [] }),
    ),
    (
      "int",
      Value::Function(FunctionValue::{ name: "int", params: [], body: [] }),
    ),
    (
      "float",
      Value::Function(FunctionValue::{ name: "float", params: [], body: [] }),
    ),
    ("object", Value::Class(object_class)),
    ("BaseException", Value::Class(base_exception_class)),
    ("Exception", Value::Class(exception_class)),
    ("NameError", Value::Class(name_error_class)),
    ("TypeError", Value::Class(type_error_class)),
    ("AttributeError", Value::Class(attribute_error_class)),
    ("IndexError", Value::Class(index_error_class)),
    ("KeyError", Value::Class(key_error_class)),
    ("NotImplementedError", Value::Class(not_implemented_error_class)),
    ("ZeroDivisionError", Value::Class(zero_division_error_class)),
    ("ValueError", Value::Class(value_error_class)),
    ("ImportError", Value::Class(import_error_class)),
    ("AssertionError", Value::Class(assertion_error_class)),
    ("SyntaxError", Value::Class(syntax_error_class)),
    ("IndentationError", Value::Class(indentation_error_class)),
    ("EOFError", Value::Class(eof_error_class)),
    ("RuntimeError", Value::Class(runtime_error_class)),
  ]
  Interpreter::{ config, globals: [], builtins, io }
}

///|
pub fn Interpreter::exec(
  self : Interpreter,
  program : Module,
) -> Result[RunResult, RuntimeError] {
  let value = match
    eval_block(program.body, [], self.globals, self.builtins, self.io) {
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
pub fn Interpreter::eval_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let expr = match parse_expr(source) {
    Ok(value) => value
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  let value = match
    eval_expr_with_env(expr, [], self.globals, self.builtins, self.io) {
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
pub fn Interpreter::eval(
  self : Interpreter,
  expr : Expr,
) -> Result[Value, RuntimeError] {
  eval_expr_with_env(expr, [], self.globals, self.builtins, self.io)
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
