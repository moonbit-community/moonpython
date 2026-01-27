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
fn builtin_sys_stdout_write(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("write", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "write() takes exactly one argument".to_string(),
      ),
    )
  }
  let text = value_to_string(positional[1])
  io.write_stdout(text)
  Ok(Value::Int(@bigint.BigInt::from_int(text.length())))
}

///|
fn builtin_sys_stdout_flush(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("flush", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "flush() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_sys_stdout_reconfigure(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  // CPython signature: reconfigure(*, encoding=None, errors=None, newline=None, ...)
  // We accept common keywords and treat them as no-ops (but store on the instance dict).
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "reconfigure() takes no positional arguments".to_string(),
      ),
    )
  }
  for kw in keywords {
    let name = kw.0
    if name == "encoding" ||
      name == "errors" ||
      name == "newline" ||
      name == "line_buffering" ||
      name == "write_through" {
      match positional[0] {
        Value::Instance(inst) =>
          // Store the most common introspected fields.
          if name == "encoding" || name == "errors" || name == "newline" {
            set_named_value(inst.dict, name, kw.1)
          }
        _ => ()
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "reconfigure() got an unexpected keyword '" + name + "'",
        ),
      )
    }
  }
  Ok(Value::None)
}

///|
fn builtin_sys_stderr_write(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("write", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "write() takes exactly one argument".to_string(),
      ),
    )
  }
  let text = value_to_string(positional[1])
  io.write_stderr(text)
  Ok(Value::Int(@bigint.BigInt::from_int(text.length())))
}

///|
fn builtin_sys_stderr_flush(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("flush", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "flush() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_sys_stderr_reconfigure(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  // Reuse stdout implementation: semantics are identical for our shim.
  builtin_sys_stdout_reconfigure(
    positional, keywords, locals, globals, builtins, io,
  )
}

///|
fn builtin_sys_excepthook(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.excepthook", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "excepthook() takes exactly three arguments".to_string(),
      ),
    )
  }
  // Minimal stub: do nothing. CPython prints the exception; for now we just
  // provide the hook so stdlib (e.g. threading) can import and run.
  Ok(Value::None)
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
fn file_content_length(
  binary : Bool,
  content : Value,
) -> Result[Int, RuntimeError] {
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
    (false, Value::Str(text)) => Ok(Value::Str(substring(text, start, end)))
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
  let (inst, binary, content, pos) = match
    file_unpack_state(positional[0], "read") {
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
  set_named_value(
    inst.dict,
    "__pos__",
    Value::Int(@bigint.BigInt::from_int(end)),
  )
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
  let (inst, binary, content, pos) = match
    file_unpack_state(positional[0], "readline") {
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
  set_named_value(
    inst.dict,
    "__pos__",
    Value::Int(@bigint.BigInt::from_int(end)),
  )
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
    let line = match
      builtin_file_readline([positional[0]], [], locals, globals, builtins, io) {
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
fn builtin_file_write(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("write", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "write() takes exactly 2 arguments".to_string(),
      ),
    )
  }
  let (inst, binary, content, pos) = match
    file_unpack_state(positional[0], "write") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let writable = match get_named_value(inst.dict, "__writable__") {
    Some(Value::Bool(v)) => v
    _ => false
  }
  if !writable {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "UnsupportedOperation: not writable".to_string(),
      ),
    )
  }
  let mut write_len = 0
  match (binary, content) {
    (true, Value::Bytes(buf)) => {
      let data = match positional[1] {
        Value::Bytes(values)
        | Value::ByteArray(values)
        | Value::MemoryView(values) => values
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "write() argument must be bytes-like".to_string(),
            ),
          )
      }
      let mut p = pos
      if p < 0 {
        p = 0
      }
      if p > buf.length() {
        p = buf.length()
      }
      for i = 0; i < data.length(); i = i + 1 {
        let idx = p + i
        if idx < buf.length() {
          buf[idx] = data[i]
        } else {
          buf.push(data[i])
        }
      }
      write_len = data.length()
      set_named_value(inst.dict, "__content__", Value::Bytes(buf))
      set_named_value(
        inst.dict,
        "__pos__",
        Value::Int(@bigint.BigInt::from_int(p + write_len)),
      )
    }
    (false, Value::Str(text)) => {
      let data = match positional[1] {
        Value::Str(s) => s
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "write() argument must be str".to_string(),
            ),
          )
      }
      let mut p = pos
      if p < 0 {
        p = 0
      }
      if p > text.length() {
        p = text.length()
      }
      let data_len = data.length()
      let prefix = substring(text, 0, p)
      let suffix_start = p + data_len
      let suffix = if suffix_start < text.length() {
        substring(text, suffix_start, text.length())
      } else {
        "".to_string()
      }
      let next_text = prefix + data + suffix
      write_len = data_len
      set_named_value(inst.dict, "__content__", Value::Str(next_text))
      set_named_value(
        inst.dict,
        "__pos__",
        Value::Int(@bigint.BigInt::from_int(p + write_len)),
      )
    }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: invalid file content".to_string(),
        ),
      )
  }
  set_named_value(inst.dict, "__dirty__", Value::Bool(true))
  Ok(Value::Int(@bigint.BigInt::from_int(write_len)))
}

///|
fn builtin_file_flush(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("flush", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "flush() takes exactly 1 argument".to_string(),
      ),
    )
  }
  // For the in-memory file implementation, flush is a no-op. We persist on close().
  let _ = match file_unpack_state(positional[0], "flush") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(Value::None)
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
  let line = match
    builtin_file_readline([positional[0]], [], locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let is_empty = match line {
    Value::Str(text) => text.length() == 0
    Value::Bytes(values) => values.length() == 0
    _ => true
  }
  if is_empty {
    return Err(
      make_runtime_error(RuntimeErrorKind::Runtime, "StopIteration".to_string()),
    )
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
    Value::Instance(inst) => {
      match get_named_value(inst.dict, "__closed__") {
        Some(Value::Bool(true)) => return Ok(Value::None)
        _ => ()
      }
      let writable = match get_named_value(inst.dict, "__writable__") {
        Some(Value::Bool(v)) => v
        _ => false
      }
      let dirty = match get_named_value(inst.dict, "__dirty__") {
        Some(Value::Bool(v)) => v
        _ => false
      }
      let path_opt = match get_named_value(inst.dict, "__path__") {
        Some(Value::Str(p)) => Some(p)
        _ => None
      }
      if writable && dirty && path_opt is Some(path) {
        let binary = match get_named_value(inst.dict, "__binary__") {
          Some(Value::Bool(v)) => v
          _ => false
        }
        let content = match get_named_value(inst.dict, "__content__") {
          Some(v) => v
          None => Value::None
        }
        match (binary, content) {
          (true, Value::Bytes(values)) => {
            let out : Array[Byte] = []
            for b in values {
              out.push((b & 0xFF).to_byte())
            }
            let bytes = Bytes::from_array(out)
            let _ = @fs.write_bytes_to_file(path, bytes) catch {
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "OSError: cannot write file".to_string(),
                  ),
                )
            }

          }
          (false, Value::Str(text)) => {
            let _ = @fs.write_string_to_file(path, text) catch {
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "OSError: cannot write file".to_string(),
                  ),
                )
            }

          }
          _ => ()
        }
        set_named_value(inst.dict, "__dirty__", Value::Bool(false))
      }
      set_named_value(inst.dict, "__closed__", Value::Bool(true))
    }
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
  if positional.length() != 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__exit__() takes 4 arguments".to_string(),
      ),
    )
  }
  // Close on scope exit (best-effort).
  let _ = match
    builtin_file_close([positional[0]], [], locals, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_file_seek(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("seek", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "seek() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let offset = match positional[1] {
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
          "seek() offset must be int".to_string(),
        ),
      )
  }
  let whence = if positional.length() == 3 {
    match positional[2] {
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
            "seek() whence must be int".to_string(),
          ),
        )
    }
  } else {
    0
  }
  let (inst, binary, content, pos) = match
    file_unpack_state(positional[0], "seek") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let length = match file_content_length(binary, content) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let base = if whence == 0 {
    0
  } else if whence == 1 {
    pos
  } else if whence == 2 {
    length
  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: invalid whence".to_string(),
      ),
    )
  }
  let next_pos = base + offset
  if next_pos < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: negative seek position".to_string(),
      ),
    )
  }
  set_named_value(
    inst.dict,
    "__pos__",
    Value::Int(@bigint.BigInt::from_int(next_pos)),
  )
  Ok(Value::Int(@bigint.BigInt::from_int(next_pos)))
}

///|
fn builtin_file_tell(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("tell", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "tell() takes exactly 1 argument".to_string(),
      ),
    )
  }
  let (_, _, _, pos) = match file_unpack_state(positional[0], "tell") {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(Value::Int(@bigint.BigInt::from_int(pos)))
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
  let binary = mode.contains("b")
  let wants_write = mode.contains("w") ||
    mode.contains("a") ||
    mode.contains("+") ||
    mode.contains("x")
  let truncate = mode.contains("w")
  let append = mode.contains("a")
  let exclusive = mode.contains("x")
  let resolved_path = resolve_path_from_cwd(path)
  if exclusive && @fs.path_exists(resolved_path) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileExistsError: cannot open file: " + path,
      ),
    )
  }
  fn read_bytes_ints(path : String) -> Array[Int]? {
    let bytes = @fs.read_file_to_bytes(path) catch { _ => return None }
    let out : Array[Int] = []
    for b in bytes {
      out.push(b.to_int())
    }
    Some(out)
  }

  let content = if wants_write {
    if truncate && !append {
      if binary {
        Value::Bytes([])
      } else {
        Value::Str("")
      }
      // Append / update: try to load existing content, else start empty.
    } else if binary {
      match read_bytes_ints(resolved_path) {
        Some(values) => Value::Bytes(values)
        None => Value::Bytes([])
      }
    } else {
      let text = @fs.read_file_to_string(resolved_path) catch {
        _ => "".to_string()
      }
      Value::Str(text)
    }
  } else if binary {
    match read_bytes_ints(resolved_path) {
      Some(values) => Value::Bytes(values)
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "FileNotFoundError: cannot open file: " + path,
          ),
        )
    }
  } else {
    let text_content = @fs.read_file_to_string(resolved_path) catch {
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "FileNotFoundError: cannot open file: " + path,
          ),
        )
    }
    Value::Str(text_content)
  }
  let pos0 = if wants_write && append {
    match content {
      Value::Str(text) => text.length()
      Value::Bytes(values) => values.length()
      _ => 0
    }
  } else {
    0
  }
  let base_class = builtin_class_from_name("object", builtins)
  let file_class = ClassValue::{
    name: "file",
    bases: [Value::Class(base_class)],
    dict: [
      (
        "read",
        Value::Function(FunctionValue::{
          name: "file.read",
          params: ["self", "size"],
          defaults: [Value::Int(@bigint.BigInt::from_int(-1))],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "readline",
        Value::Function(FunctionValue::{
          name: "file.readline",
          params: ["self", "size"],
          defaults: [Value::Int(@bigint.BigInt::from_int(-1))],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "readlines",
        Value::Function(FunctionValue::{
          name: "file.readlines",
          params: ["self"],
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
          name: "file.close",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "write",
        Value::Function(FunctionValue::{
          name: "file.write",
          params: ["self", "s"],
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
          name: "file.flush",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "seek",
        Value::Function(FunctionValue::{
          name: "file.seek",
          params: ["self", "offset", "whence"],
          defaults: [Value::Int(0N)],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "tell",
        Value::Function(FunctionValue::{
          name: "file.tell",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "__iter__",
        Value::Function(FunctionValue::{
          name: "file.__iter__",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "__next__",
        Value::Function(FunctionValue::{
          name: "file.__next__",
          params: ["self"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
      (
        "__enter__",
        Value::Function(FunctionValue::{
          name: "file.__enter__",
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
          name: "file.__exit__",
          params: ["self", "exc_type", "exc", "tb"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    ],
  }
  let inst = Value::Instance(InstanceValue::{
    class: file_class,
    dict: [
      ("__content__", content),
      ("__pos__", Value::Int(@bigint.BigInt::from_int(pos0))),
      ("__binary__", Value::Bool(binary)),
      ("__closed__", Value::Bool(false)),
      ("__writable__", Value::Bool(wants_write)),
      (
        "__dirty__",
        Value::Bool(wants_write && (truncate || append || exclusive)),
      ),
      ("__path__", Value::Str(resolved_path)),
    ],
  })
  Ok(inst)
}

///|
/// Host filesystem-backed helpers for the stdlib's `os`/`tempfile` needs.

///|
priv struct PosixFdEntry {
  path : String
  buffer : Array[Byte]
  pos : Int
  dirty : Bool
  appending : Bool
}

///|
let posix_next_fd : Ref[Int] = { val: 3 }

///|
let posix_fd_table : Ref[Array[(Int, PosixFdEntry)]] = { val: [] }

///|
fn posix_lookup_fd(fd : Int) -> PosixFdEntry? {
  for pair in posix_fd_table.val {
    if pair.0 == fd {
      return Some(pair.1)
    }
  }
  None
}

///|
fn posix_update_fd(fd : Int, entry : PosixFdEntry) -> Unit {
  for i = 0; i < posix_fd_table.val.length(); i = i + 1 {
    if posix_fd_table.val[i].0 == fd {
      posix_fd_table.val[i] = (fd, entry)
      return
    }
  }
  posix_fd_table.val.push((fd, entry))
}

///|
fn posix_remove_fd(fd : Int) -> PosixFdEntry? {
  for i = 0; i < posix_fd_table.val.length(); i = i + 1 {
    if posix_fd_table.val[i].0 == fd {
      let entry = posix_fd_table.val[i].1
      let _ = posix_fd_table.val.remove(i)
      return Some(entry)
    }
  }
  None
}

///|
fn posix_fspath_from_value(
  value : Value,
  name : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  match value {
    Value::Str(s) => Ok(s)
    Value::Bytes(bytes) => decode_bytes_utf8(name, bytes, "surrogateescape")
    Value::Instance(_) => {
      let callable = match
        get_attr_from_value(value, "__fspath__", globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let out = match
        call_callable_with_env(callable, [], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match out {
        Value::Str(s) => Ok(s)
        Value::Bytes(bytes) => decode_bytes_utf8(name, bytes, "surrogateescape")
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              name + "() path must be str or bytes",
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() path must be str or bytes",
        ),
      )
  }
}

///|
fn posix_bytes_from_value(
  value : Value,
  name : String,
) -> Result[Array[Byte], RuntimeError] {
  match value {
    Value::Bytes(items) => {
      let out : Array[Byte] = []
      for b in items {
        out.push((b & 0xFF).to_byte())
      }
      Ok(out)
    }
    Value::ByteArray(items) => {
      let out : Array[Byte] = []
      for b in items {
        out.push((b & 0xFF).to_byte())
      }
      Ok(out)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() data must be bytes-like",
        ),
      )
  }
}

///|
fn builtin_mpython_posix_open(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_open() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let path = match
    posix_fspath_from_value(
      positional[0],
      "__mpython_posix_open",
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let path = resolve_path_from_cwd(path)
  let flags = match index_from_value(positional[1], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _mode = if positional.length() == 3 {
    match index_from_value(positional[2], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    0o777
  }
  let o_creat = 0x40
  let o_excl = 0x80
  let o_trunc = 0x200
  let o_append = 0x400
  let creating = (flags & o_creat) != 0
  let exclusive = (flags & o_excl) != 0
  let truncating = (flags & o_trunc) != 0
  let appending = (flags & o_append) != 0
  let existed = @fs.path_exists(path)
  if creating && exclusive && @fs.path_exists(path) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileExistsError: file exists".to_string(),
      ),
    )
  }
  if !creating && !@fs.path_exists(path) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileNotFoundError: no such file".to_string(),
      ),
    )
  }
  let buffer : Array[Byte] = if truncating || !existed {
    []
  } else {
    let bytes = @fs.read_file_to_bytes(path) catch { _ => b"" }
    let out : Array[Byte] = []
    for b in bytes {
      out.push(b)
    }
    out
  }
  let fd = posix_next_fd.val
  posix_next_fd.val = posix_next_fd.val + 1
  let pos = if appending { buffer.length() } else { 0 }
  let dirty = truncating || (creating && !existed)
  posix_fd_table.val.push(
    (fd, PosixFdEntry::{ path, buffer, pos, dirty, appending }),
  )
  Ok(Value::Int(@bigint.BigInt::from_int(fd)))
}

///|
fn builtin_mpython_posix_write(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_write() takes 2 arguments".to_string(),
      ),
    )
  }
  let fd = match index_from_value(positional[0], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let entry = match posix_lookup_fd(fd) {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: bad file descriptor",
        ),
      )
  }
  let bytes = match
    posix_bytes_from_value(positional[1], "__mpython_posix_write") {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut pos = if entry.appending { entry.buffer.length() } else { entry.pos }
  while pos > entry.buffer.length() {
    entry.buffer.push((0).to_byte())
  }
  for b in bytes {
    if pos < entry.buffer.length() {
      entry.buffer[pos] = b
    } else {
      entry.buffer.push(b)
    }
    pos = pos + 1
  }
  posix_update_fd(fd, PosixFdEntry::{
    path: entry.path,
    buffer: entry.buffer,
    pos,
    dirty: true,
    appending: entry.appending,
  })
  Ok(Value::Int(@bigint.BigInt::from_int(bytes.length())))
}

///|
fn builtin_mpython_posix_read(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_read() takes 2 arguments".to_string(),
      ),
    )
  }
  let fd = match index_from_value(positional[0], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let n = match index_from_value(positional[1], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if n < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: os.read() size must be non-negative".to_string(),
      ),
    )
  }
  let entry = match posix_lookup_fd(fd) {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: bad file descriptor",
        ),
      )
  }
  let start = entry.pos
  let end = if start + n > entry.buffer.length() {
    entry.buffer.length()
  } else {
    start + n
  }
  let out : Array[Int] = []
  for i = start; i < end; i = i + 1 {
    out.push(entry.buffer[i].to_int())
  }
  posix_update_fd(fd, PosixFdEntry::{
    path: entry.path,
    buffer: entry.buffer,
    pos: end,
    dirty: entry.dirty,
    appending: entry.appending,
  })
  Ok(Value::Bytes(out))
}

///|
fn builtin_mpython_posix_lseek(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_lseek() takes 3 arguments".to_string(),
      ),
    )
  }
  let fd = match index_from_value(positional[0], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let offset = match index_from_value(positional[1], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let whence = match index_from_value(positional[2], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let entry = match posix_lookup_fd(fd) {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: bad file descriptor",
        ),
      )
  }
  let base = if whence == 0 {
    0
  } else if whence == 1 {
    entry.pos
  } else if whence == 2 {
    entry.buffer.length()
  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: os.lseek() invalid whence".to_string(),
      ),
    )
  }
  let new_pos = base + offset
  if new_pos < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OSError: invalid argument".to_string(),
      ),
    )
  }
  posix_update_fd(fd, PosixFdEntry::{
    path: entry.path,
    buffer: entry.buffer,
    pos: new_pos,
    dirty: entry.dirty,
    appending: entry.appending,
  })
  Ok(Value::Int(@bigint.BigInt::from_int(new_pos)))
}

///|
fn builtin_mpython_posix_close(
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
        "__mpython_posix_close() takes 1 argument".to_string(),
      ),
    )
  }
  let fd = match index_from_value(positional[0], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let entry = match posix_remove_fd(fd) {
    Some(v) => v
    None => return Ok(Value::None)
  }
  if entry.dirty {
    let bytes = Bytes::from_array(entry.buffer)
    let _ = @fs.write_bytes_to_file(entry.path, bytes) catch {
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "OSError: cannot write file".to_string(),
          ),
        )
    }

  }
  Ok(Value::None)
}

///|
fn builtin_mpython_posix_fstat(
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
        "__mpython_posix_fstat() takes 1 argument".to_string(),
      ),
    )
  }
  let fd = match index_from_value(positional[0], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let entry = match posix_lookup_fd(fd) {
    Some(v) => v
    None =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: bad file descriptor",
        ),
      )
  }
  let st_mode = 0o100000 | 0o666
  let st_size = entry.buffer.length()
  Ok(
    Value::Tuple([
      Value::Int(@bigint.BigInt::from_int(st_mode)), // st_mode
      Value::Int(0N), // st_ino
      Value::Int(0N), // st_dev
      Value::Int(1N), // st_nlink
      Value::Int(0N), // st_uid
      Value::Int(0N), // st_gid
      Value::Int(@bigint.BigInt::from_int(st_size)), // st_size
      Value::Int(0N), // st_atime
      Value::Int(0N), // st_mtime
      Value::Int(0N), // st_ctime
    ]),
  )
}

///|
fn builtin_mpython_posix_unlink(
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
        "__mpython_posix_unlink() takes 1 argument".to_string(),
      ),
    )
  }
  let path = match
    posix_fspath_from_value(
      positional[0],
      "__mpython_posix_unlink",
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let path = resolve_path_from_cwd(path)
  if !@fs.path_exists(path) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileNotFoundError: no such file".to_string(),
      ),
    )
  }
  let _ = @fs.remove_file(path) catch {
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: cannot unlink".to_string(),
        ),
      )
  }
  Ok(Value::None)
}

///|
fn builtin_mpython_posix_mkdir(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() < 1 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_mkdir() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let path = match
    posix_fspath_from_value(
      positional[0],
      "__mpython_posix_mkdir",
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let path = resolve_path_from_cwd(path)
  let _mode = if positional.length() == 2 {
    match index_from_value(positional[1], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    0o777
  }
  if @fs.path_exists(path) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileExistsError: file exists".to_string(),
      ),
    )
  }
  let _ = @fs.create_dir(path) catch {
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: cannot create directory".to_string(),
        ),
      )
  }
  Ok(Value::None)
}

///|
fn builtin_mpython_posix_rmdir(
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
        "__mpython_posix_rmdir() takes 1 argument".to_string(),
      ),
    )
  }
  let path = match
    posix_fspath_from_value(
      positional[0],
      "__mpython_posix_rmdir",
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let path = resolve_path_from_cwd(path)
  let _ = @fs.remove_dir(path) catch {
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OSError: cannot remove directory".to_string(),
        ),
      )
  }
  Ok(Value::None)
}

///|
fn builtin_mpython_posix_stat(
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
        "__mpython_posix_stat() takes 1 argument".to_string(),
      ),
    )
  }
  let path = match
    posix_fspath_from_value(
      positional[0],
      "__mpython_posix_stat",
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let path = resolve_path_from_cwd(path)
  if !@fs.path_exists(path) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileNotFoundError: no such file".to_string(),
      ),
    )
  }
  let is_dir = @fs.is_dir(path) catch { _ => false }
  let st_mode = if is_dir { 0o040000 | 0o777 } else { 0o100000 | 0o666 }
  let st_size = if is_dir {
    0
  } else {
    let bytes = @fs.read_file_to_bytes(path) catch { _ => b"" }
    bytes.length()
  }
  Ok(
    Value::Tuple([
      Value::Int(@bigint.BigInt::from_int(st_mode)), // st_mode
      Value::Int(0N), // st_ino
      Value::Int(0N), // st_dev
      Value::Int(1N), // st_nlink
      Value::Int(0N), // st_uid
      Value::Int(0N), // st_gid
      Value::Int(@bigint.BigInt::from_int(st_size)), // st_size
      Value::Int(0N), // st_atime
      Value::Int(0N), // st_mtime
      Value::Int(0N), // st_ctime
    ]),
  )
}

///|
fn builtin_mpython_posix_getcwd(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_getcwd() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Str(current_workdir()))
}

///|
fn builtin_mpython_posix_chdir(
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
        "__mpython_posix_chdir() takes 1 argument".to_string(),
      ),
    )
  }
  let path = match
    posix_fspath_from_value(
      positional[0],
      "__mpython_posix_chdir",
      globals,
      builtins,
      io,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let resolved = resolve_path_from_cwd(path)
  let is_dir = @fs.is_dir(resolved) catch { _ => false }
  if !is_dir {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "FileNotFoundError: no such directory".to_string(),
      ),
    )
  }
  set_current_workdir(resolved)
  Ok(Value::None)
}

///|
fn builtin_mpython_posix_listdir(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_posix_listdir() takes 0 or 1 arguments".to_string(),
      ),
    )
  }
  let mut return_bytes = false
  let path = if positional.length() == 0 {
    ".".to_string()
  } else {
    match positional[0] {
      Value::Bytes(_) => return_bytes = true
      _ => ()
    }
    match
      posix_fspath_from_value(
        positional[0],
        "__mpython_posix_listdir",
        globals,
        builtins,
        io,
      ) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  let path = resolve_path_from_cwd(path)
  let entries = @fs.read_dir(path) catch {
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "FileNotFoundError: no such directory".to_string(),
        ),
      )
  }
  let out : Array[Value] = []
  for name in entries {
    if return_bytes {
      out.push(
        Value::Bytes(encode_string_utf8_with_errors(name, "surrogateescape")),
      )
    } else {
      out.push(Value::Str(name))
    }
  }
  Ok(Value::List(out))
}
