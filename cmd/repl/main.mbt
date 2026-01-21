///|
fn bytes_hex_digit(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).to_char().unwrap()
  } else {
    ('a'.to_int() + (n - 10)).to_char().unwrap()
  }
}

///|
fn bytes_hex_byte(value : Int) -> String {
  let buf = StringBuilder::new()
  let hi = (value >> 4) & 0xF
  let lo = value & 0xF
  buf.write_char(bytes_hex_digit(hi))
  buf.write_char(bytes_hex_digit(lo))
  buf.to_string()
}

///|
fn bytes_repr(values : Array[Int]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("b'")
  for byte in values {
    let v = byte & 0xFF
    if v == 0x5c {
      buf.write_string("\\\\")
    } else if v == 0x27 {
      buf.write_string("\\'")
    } else if v == 0x09 {
      buf.write_string("\\t")
    } else if v == 0x0a {
      buf.write_string("\\n")
    } else if v == 0x0d {
      buf.write_string("\\r")
    } else if v >= 0x20 && v <= 0x7e {
      buf.write_char(v.to_char().unwrap())
    } else {
      buf.write_string("\\x")
      buf.write_string(bytes_hex_byte(v))
    }
  }
  buf.write_char('\'')
  buf.to_string()
}

///|
fn complex_to_string(real : Double, imag : Double) -> String {
  if real == 0.0 {
    if imag == 0.0 {
      "0j"
    } else {
      imag.to_string() + "j"
    }
  } else {
    let sign = if imag >= 0.0 { "+" } else { "-" }
    let imag_abs = if imag < 0.0 { -imag } else { imag }
    "(" + real.to_string() + sign + imag_abs.to_string() + "j)"
  }
}

///|
fn value_to_string(value : @mpython.Value) -> String {
  match value {
    @mpython.Value::None => "None"
    @mpython.Value::Bool(v) => if v { "True" } else { "False" }
    @mpython.Value::Int(v) => v.to_string()
    @mpython.Value::Float(v) => v.to_string()
    @mpython.Value::Complex(real, imag) => complex_to_string(real, imag)
    @mpython.Value::Str(v) => v
    @mpython.Value::Bytes(values) => bytes_repr(values)
    @mpython.Value::ByteArray(values) => "bytearray(" + bytes_repr(values) + ")"
    @mpython.Value::MemoryView(values) =>
      "memoryview(" + bytes_repr(values) + ")"
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
    @mpython.Value::BoundMethod(bound_method) =>
      "<bound method " + bound_method.function.name + ">"
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
fn print_usage() -> Unit {
  println("usage: moon run cmd/repl -- [--stdlib PATH]")
}

///|
fn main {
  let args = @sys.get_cli_args()
  let stdlib_paths : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      print_usage()
      @sys.exit(0)
    }
    if arg == "--stdlib" || arg == "--stdlib-path" {
      if i + 1 >= args.length() {
        println("missing value for " + arg)
        print_usage()
        @sys.exit(1)
      }
      stdlib_paths.push(args[i + 1])
      i += 2
      continue
    }
    println("unexpected argument: " + arg)
    print_usage()
    @sys.exit(1)
  }
  println("mpython REPL (Ctrl-D to exit)")
  let source = @fs.read_file_to_string("/dev/stdin") catch { _ => "" }
  let config = @mpython.Config::for_cli(stdlib_paths, None)
  let interpreter = @mpython.Interpreter::with_config(config)
  for line in source.split("\n") {
    run_line(interpreter, line.to_string())
  }
}
