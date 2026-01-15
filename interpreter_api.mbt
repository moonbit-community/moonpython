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
      "int",
      Value::Function(FunctionValue::{ name: "int", params: [], body: [] }),
    ),
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
