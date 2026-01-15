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
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println("usage: moon run cmd/main -- program.py")
    @sys.exit(1)
  }
  let script_path = args[1]
  let source = @fs.read_file_to_string(script_path) catch {
    _ =>
      return {
        println("cannot read file: " + script_path)
        @sys.exit(1)
      }
  }
  let interpreter = @mpython.Interpreter::new()
  match interpreter.exec_source(source) {
    Ok(run) => print_run(run)
    Err(err) => {
      println(@mpython.format_runtime_error(err))
      @sys.exit(1)
    }
  }
}
