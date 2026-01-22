///|
/// I/O builtins (input + file/open helpers).

///|
fn builtin_input(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("input", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 0 {
    io.write_stdout(value_to_string(positional[0]))
  }
  let line = io.read_line()
  if line is Some(line) {
    Ok(Value::Str(line))
  } else {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "EOF when reading a line".to_string(),
      ),
    )
  }
}

///|
fn file_unpack_state(
  target : Value,
  method_name : String,
) -> Result[(InstanceValue, Bool, Value, Int), RuntimeError] {
  let inst = match target {
    Value::Instance(inst) => inst
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          method_name + "() expects a file object".to_string(),
        ),
      )
  }
  match get_named_value(inst.dict, "__closed__") {
    Some(Value::Bool(true)) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: I/O operation on closed file.".to_string(),
        ),
      )
    _ => ()
  }
  let binary = match get_named_value(inst.dict, "__binary__") {
    Some(Value::Bool(v)) => v
    _ => false
  }
  let pos_val = match get_named_value(inst.dict, "__pos__") {
    Some(Value::Int(v)) => v
    _ => 0N
  }
  let pos = match bigint_to_int_checked(pos_val) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let content = match get_named_value(inst.dict, "__content__") {
    Some(value) => value
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: invalid file object".to_string(),
        ),
      )
  }
  Ok((inst, binary, content, pos))
}

///|
fn file_content_length(binary : Bool, content : Value) -> Result[Int, RuntimeError] {
  match (binary, content) {
    (true, Value::Bytes(values)) => Ok(values.length())
    (false, Value::Str(text)) => Ok(text.length())
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: invalid file content".to_string(),
        ),
      )
  }
}

///|
fn file_slice_content(
  binary : Bool,
  content : Value,
  start : Int,
  end : Int,
) -> Result[Value, RuntimeError] {
  if start >= end {
    if binary {
      return Ok(Value::Bytes([]))
    }
    return Ok(Value::Str(""))
  }
  match (binary, content) {
    (true, Value::Bytes(values)) => {
      let out : Array[Int] = []
      let mut i = start
      while i < end {
        out.push(values[i])
        i += 1
      }
      Ok(Value::Bytes(out))
    }
    (false, Value::Str(text)) =>
      Ok(Value::Str(substring(text, start, end)))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: invalid file content".to_string(),
        ),
      )
  }
}

///|
fn file_find_line_end(
  binary : Bool,
  content : Value,
  start : Int,
  limit : Int,
) -> Result[Int, RuntimeError] {
  match (binary, content) {
    (true, Value::Bytes(values)) => {
      let mut i = start
      while i < limit {
        if values[i] == 10 {
          return Ok(i + 1)
        }
        i += 1
      }
      Ok(limit)
    }
    (false, Value::Str(text)) => {
      let chars = text.to_array()
      let mut i = start
      while i < limit {
        if chars[i] == '\n' {
          return Ok(i + 1)
        }
        i += 1
      }
      Ok(limit)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: invalid file content".to_string(),
        ),
      )
  }
}

///|
fn builtin_file_read(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "read() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let size = if positional.length() == 2 {
    match positional[1] {
      Value::None => -1
      Value::Int(v) =>
        match bigint_to_int_checked(v) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      Value::Bool(v) => if v { 1 } else { 0 }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "read() size must be int".to_string(),
          ),
        )
    }
  } else {
    -1
  }
  let (inst, binary, content, pos) =
    match file_unpack_state(positional[0], "read") {
      Ok(value) => value
      Err(err) => return Err(err)
    }
  let length = match file_content_length(binary, content) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut start = pos
  if start < 0 {
    start = 0
  }
  if start > length {
    start = length
  }
  let mut end = if size < 0 { length } else { start + size }
  if end > length {
    end = length
  }
  let out = match file_slice_content(binary, content, start, end) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  set_named_value(inst.dict, "__pos__", Value::Int(@bigint.BigInt::from_int(end)))
  Ok(out)
}

///|
fn builtin_file_readline(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "readline() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let size = if positional.length() == 2 {
    match positional[1] {
      Value::None => -1
      Value::Int(v) =>
        match bigint_to_int_checked(v) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      Value::Bool(v) => if v { 1 } else { 0 }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "readline() size must be int".to_string(),
          ),
        )
    }
  } else {
    -1
  }
  let (inst, binary, content, pos) =
    match file_unpack_state(positional[0], "readline") {
      Ok(value) => value
      Err(err) => return Err(err)
    }
  let length = match file_content_length(binary, content) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut start = pos
  if start < 0 {
    start = 0
  }
  if start > length {
    start = length
  }
  let mut limit = if size < 0 { length } else { start + size }
  if limit > length {
    limit = length
  }
  let end = match file_find_line_end(binary, content, start, limit) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out = match file_slice_content(binary, content, start, end) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  set_named_value(inst.dict, "__pos__", Value::Int(@bigint.BigInt::from_int(end)))
  Ok(out)
}

///|
fn builtin_file_readlines(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "readlines() takes 1 argument".to_string(),
      ),
    )
  }
  let lines : Array[Value] = []
  while true {
    let line = match builtin_file_readline(
      [positional[0]],
      [],
      locals,
      globals,
      builtins,
      io,
    ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let is_empty = match line {
      Value::Str(text) => text.length() == 0
      Value::Bytes(values) => values.length() == 0
      _ => true
    }
    if is_empty {
      break
    }
    lines.push(line)
  }
  Ok(Value::List(lines))
}

///|
fn builtin_file_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__iter__() takes 1 argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_file_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__next__() takes 1 argument".to_string(),
      ),
    )
  }
  let line = match builtin_file_readline(
    [positional[0]],
    [],
    locals,
    globals,
    builtins,
    io,
  ) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let is_empty = match line {
    Value::Str(text) => text.length() == 0
    Value::Bytes(values) => values.length() == 0
    _ => true
  }
  if is_empty {
    return Err(make_runtime_error(RuntimeErrorKind::Runtime, "StopIteration".to_string()))
  }
  Ok(line)
}

///|
fn builtin_file_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "close() takes 1 argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      set_named_value(inst.dict, "__closed__", Value::Bool(true))
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "close() expects a file object".to_string(),
        ),
      )
  }
  Ok(Value::None)
}

///|
fn builtin_file_enter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__enter__() takes 1 argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_file_exit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  if positional.length() != 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__exit__() takes 4 arguments".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_open(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() == 0 {
    return Err(missing_required_argument_error("open", "file"))
  }
  let path = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "open() file must be str".to_string(),
        ),
      )
  }
  let mut mode = "r".to_string()
  let mut mode_from_keyword = false
  for item in keywords {
    if item.0 == "mode" {
      mode_from_keyword = true
      match item.1 {
        Value::Str(text) => mode = text
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "open() mode must be str".to_string(),
            ),
          )
      }
    } else if item.0 == "encoding" ||
      item.0 == "errors" ||
      item.0 == "newline" ||
      item.0 == "buffering" ||
      item.0 == "closefd" {
      let _ = item.1
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "open() got unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  if positional.length() >= 2 {
    if mode_from_keyword {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "open() got multiple values for argument 'mode'".to_string(),
        ),
      )
    }
    match positional[1] {
      Value::Str(text) => mode = text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "open() mode must be str".to_string(),
          ),
        )
    }
  }
  if mode.contains("w") ||
    mode.contains("a") ||
    mode.contains("+") ||
    mode.contains("x") {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "UnsupportedOperation: open() write modes are not supported".to_string(),
      ),
    )
  }
  let binary = mode.contains("b")
  let text_content = @fs.read_file_to_string(path) catch {
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "FileNotFoundError: cannot open file: " + path,
        ),
      )
  }
  let content = if binary {
    Value::Bytes(encode_string_utf8(text_content))
  } else {
    Value::Str(text_content)
  }
  let base_class = builtin_class_from_name("object", builtins)
  let file_class = ClassValue::{
    name: "file",
    bases: [Value::Class(base_class)],
    dict: [
      ("read", Value::Function(FunctionValue::{
        name: "file.read",
        params: ["self", "size"],
        defaults: [Value::Int(@bigint.BigInt::from_int(-1))],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("readline", Value::Function(FunctionValue::{
        name: "file.readline",
        params: ["self", "size"],
        defaults: [Value::Int(@bigint.BigInt::from_int(-1))],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("readlines", Value::Function(FunctionValue::{
        name: "file.readlines",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("close", Value::Function(FunctionValue::{
        name: "file.close",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("__iter__", Value::Function(FunctionValue::{
        name: "file.__iter__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("__next__", Value::Function(FunctionValue::{
        name: "file.__next__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("__enter__", Value::Function(FunctionValue::{
        name: "file.__enter__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
      ("__exit__", Value::Function(FunctionValue::{
        name: "file.__exit__",
        params: ["self", "exc_type", "exc", "tb"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      })),
    ],
  }
  let inst = Value::Instance(InstanceValue::{
    class: file_class,
    dict: [
      ("__content__", content),
      ("__pos__", Value::Int(0N)),
      ("__binary__", Value::Bool(binary)),
      ("__closed__", Value::Bool(false)),
    ],
  })
  Ok(inst)
}
