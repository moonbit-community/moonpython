///|
fn value_to_string(value : @mpython.Value) -> String {
  match value {
    @mpython.Value::None => "None"
    @mpython.Value::Bool(v) => if v { "True" } else { "False" }
    @mpython.Value::Int(v) => v.to_string()
    @mpython.Value::Float(v) => v.to_string()
    @mpython.Value::Str(v) => v
    @mpython.Value::List(values) => {
      let buf = StringBuilder::new()
      buf.write_char('[')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char(']')
      buf.to_string()
    }
    @mpython.Value::Tuple(values) => {
      let buf = StringBuilder::new()
      buf.write_char('(')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      if values.length() == 1 {
        buf.write_string(",")
      }
      buf.write_char(')')
      buf.to_string()
    }
    @mpython.Value::Dict(_) => "{}"
    @mpython.Value::Set(values) => {
      let buf = StringBuilder::new()
      buf.write_char('{')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char('}')
      buf.to_string()
    }
    @mpython.Value::Function(func) => "<function " + func.name + ">"
    @mpython.Value::Class(klass) => "<class '" + klass.name + "'>"
    @mpython.Value::Instance(inst) => "<" + inst.class.name + " object>"
    @mpython.Value::BoundMethod(method) =>
      "<bound method " + method.function.name + ">"
  }
}

///|
fn print_run(run : @mpython.RunResult) -> Unit {
  if run.stdout.length() > 0 {
    @fs.write_string_to_file("/dev/stdout", run.stdout) catch {
      _ => ()
    }
  }
  if run.stderr.length() > 0 {
    @fs.write_string_to_file("/dev/stderr", run.stderr) catch {
      _ => ()
    }
  }
  match run.value {
    @mpython.Value::None => ()
    _ => println(value_to_string(run.value))
  }
}

///|
fn run_line(interpreter : @mpython.Interpreter, line : String) -> Unit {
  let trimmed = line.trim(chars=" \t").to_string()
  if trimmed.length() == 0 {
    return
  }
  if trimmed == ":quit" || trimmed == ":exit" {
    @sys.exit(0)
  }
  match interpreter.exec_source(line) {
    Ok(run) => print_run(run)
    Err(err) => println(@mpython.format_runtime_error(err))
  }
}

///|
fn main {
  println("mpython REPL (Ctrl-D to exit)")
  let source = @fs.read_file_to_string("/dev/stdin") catch { _ => "" }
  let interpreter = @mpython.Interpreter::new()
  for line in source.split("\n") {
    run_line(interpreter, line.to_string())
  }
}
