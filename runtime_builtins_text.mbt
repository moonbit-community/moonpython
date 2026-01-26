///|
/// Text/encoding builtins (str + bytes/bytearray/memoryview + sys encoding hooks).

///|
fn builtin_str(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("str", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Str(""))
  } else {
    Ok(Value::Str(value_to_string(positional[0])))
  }
}

///|
fn builtin_str_maketrans(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("str.maketrans", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "maketrans() takes 1 to 3 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Dict(pairs) => {
        let out : Array[(Value, Value)] = []
        for pair in pairs {
          let key = match pair.0 {
            Value::Int(v) => Value::Int(v)
            Value::Bool(v) =>
              Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
            Value::Str(text) =>
              if text.length() != 1 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "string keys in maketrans() must be length 1".to_string(),
                  ),
                )
              } else {
                let code = text.to_array()[0].to_int()
                Value::Int(@bigint.BigInt::from_int(code))
              }
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "maketrans() keys must be int or str".to_string(),
                ),
              )
          }
          let value = match pair.1 {
            Value::Int(v) => Value::Int(v)
            Value::Bool(v) =>
              Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
            Value::Str(text) => Value::Str(text)
            Value::None => Value::None
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "maketrans() values must be int, str, or None".to_string(),
                ),
              )
          }
          let _ = match dict_set_item(out, key, value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }

        }
        Ok(Value::Dict(out))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "maketrans() expects a dict".to_string(),
          ),
        )
    }
  } else {
    let from_text = match positional[0] {
      Value::Str(text) => text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "maketrans() expects string arguments".to_string(),
          ),
        )
    }
    let to_text = match positional[1] {
      Value::Str(text) => text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "maketrans() expects string arguments".to_string(),
          ),
        )
    }
    if from_text.length() != to_text.length() {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: the first two maketrans arguments must have equal length".to_string(),
        ),
      )
    }
    let out : Array[(Value, Value)] = []
    let from_chars = from_text.to_array()
    let to_chars = to_text.to_array()
    for i = 0; i < from_chars.length(); i = i + 1 {
      let key = Value::Int(@bigint.BigInt::from_int(from_chars[i].to_int()))
      let value = Value::Int(@bigint.BigInt::from_int(to_chars[i].to_int()))
      let _ = match dict_set_item(out, key, value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }

    }
    if positional.length() == 3 {
      let delete_text = match positional[2] {
        Value::Str(text) => text
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "maketrans() expects string arguments".to_string(),
            ),
          )
      }
      let delete_chars = delete_text.to_array()
      for ch in delete_chars {
        let key = Value::Int(@bigint.BigInt::from_int(ch.to_int()))
        let _ = match dict_set_item(out, key, Value::None) {
          Ok(v) => v
          Err(err) => return Err(err)
        }

      }
    }
    Ok(Value::Dict(out))
  }
}

///|
fn builtin_sys_intern(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.intern", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "intern() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(_) => Ok(positional[0])
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "intern() argument must be str".to_string(),
        ),
      )
  }
}

///|
fn builtin_sys_getfilesystemencoding(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.getfilesystemencoding", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getfilesystemencoding() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Str("utf-8"))
}

///|
fn builtin_sys_getfilesystemencodeerrors(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.getfilesystemencodeerrors", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getfilesystemencodeerrors() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Str("surrogateescape"))
}

///|
fn builtin_sys_getrecursionlimit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.getrecursionlimit", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getrecursionlimit() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(@bigint.BigInt::from_int(current_config().max_recursion)))
}

///|
fn builtin_sys_setrecursionlimit(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.setrecursionlimit", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "setrecursionlimit() takes exactly one argument".to_string(),
      ),
    )
  }
  let limit = match positional[0] {
    Value::Int(v) =>
      match bigint_to_int_checked(v) {
        Ok(n) => n
        Err(err) => return Err(err)
      }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "recursion limit must be int".to_string(),
        ),
      )
  }
  if limit < 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: recursion limit must be >= 1".to_string(),
      ),
    )
  }
  let cfg = current_config()
  let updated = Config::{
    max_recursion: limit,
    traceback_limit: cfg.traceback_limit,
    track_spans: cfg.track_spans,
    allow_filesystem_imports: cfg.allow_filesystem_imports,
    import_paths: cfg.import_paths,
    argv: cfg.argv,
    main_path: cfg.main_path,
  }
  if active_config_stack.val.length() == 0 {
    active_config_stack.val.push(updated)
  } else {
    active_config_stack.val[active_config_stack.val.length() - 1] = updated
  }
  Ok(Value::None)
}

///|
fn copy_ints(values : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for value in values {
    out.push(value)
  }
  out
}

///|
fn encode_string_utf8(text : String) -> Array[Int] {
  let out : Array[Int] = []
  for ch in text.to_array() {
    let code = ch.to_int()
    if code <= 0x7F {
      out.push(code)
    } else if code <= 0x7FF {
      out.push(0xC0 | (code >> 6))
      out.push(0x80 | (code & 0x3F))
    } else if code <= 0xFFFF {
      out.push(0xE0 | (code >> 12))
      out.push(0x80 | ((code >> 6) & 0x3F))
      out.push(0x80 | (code & 0x3F))
    } else {
      out.push(0xF0 | (code >> 18))
      out.push(0x80 | ((code >> 12) & 0x3F))
      out.push(0x80 | ((code >> 6) & 0x3F))
      out.push(0x80 | (code & 0x3F))
    }
  }
  out
}

///|
let surrogateescape_pua_base = 0xF0000

///|
fn surrogateescape_char_from_byte(b : Int) -> Char {
  // MoonBit strings cannot represent surrogate code points (U+DCxx),
  // so we use a private-use marker range to round-trip surrogateescape.
  (surrogateescape_pua_base + (b & 0xFF)).to_char().unwrap()
}

///|
fn surrogateescape_byte_from_char(ch : Char) -> Int? {
  let code = ch.to_int()
  if code >= surrogateescape_pua_base && code < surrogateescape_pua_base + 256 {
    Some(code - surrogateescape_pua_base)
  } else {
    None
  }
}

///|
fn encode_string_utf8_with_errors(text : String, errors : String) -> Array[Int] {
  if errors != "surrogateescape" {
    return encode_string_utf8(text)
  }
  let out : Array[Int] = []
  for ch in text.to_array() {
    match surrogateescape_byte_from_char(ch) {
      Some(b) => out.push(b)
      None => {
        let code = ch.to_int()
        if code <= 0x7F {
          out.push(code)
        } else if code <= 0x7FF {
          out.push(0xC0 | (code >> 6))
          out.push(0x80 | (code & 0x3F))
        } else if code <= 0xFFFF {
          out.push(0xE0 | (code >> 12))
          out.push(0x80 | ((code >> 6) & 0x3F))
          out.push(0x80 | (code & 0x3F))
        } else {
          out.push(0xF0 | (code >> 18))
          out.push(0x80 | ((code >> 12) & 0x3F))
          out.push(0x80 | ((code >> 6) & 0x3F))
          out.push(0x80 | (code & 0x3F))
        }
      }
    }
  }
  out
}

///|
fn encode_string_ascii(text : String) -> Result[Array[Int], RuntimeError] {
  let out : Array[Int] = []
  for ch in text.to_array() {
    let code = ch.to_int()
    if code > 0x7F {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "UnicodeEncodeError: 'ascii' codec can't encode character".to_string(),
        ),
      )
    }
    out.push(code)
  }
  Ok(out)
}

///|
fn encode_string_ascii_with_errors(
  name : String,
  text : String,
  errors : String,
) -> Result[Array[Int], RuntimeError] {
  let _ = name
  if errors != "surrogateescape" {
    return encode_string_ascii(text)
  }
  let out : Array[Int] = []
  for ch in text.to_array() {
    match surrogateescape_byte_from_char(ch) {
      Some(b) => out.push(b)
      None => {
        let code = ch.to_int()
        if code > 0x7F {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "UnicodeEncodeError: 'ascii' codec can't encode character".to_string(),
            ),
          )
        }
        out.push(code)
      }
    }
  }
  Ok(out)
}

///|
fn encode_string_with_encoding(
  name : String,
  text : String,
  encoding_value : Value,
  errors_value : Value?,
) -> Result[Array[Int], RuntimeError] {
  let encoding = match encoding_value {
    Value::Str(value) => value
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() encoding must be str".to_string(),
        ),
      )
  }
  let errors = match errors_value {
    Some(Value::Str(errs)) =>
      if errs != "strict" && errs != "surrogateescape" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "LookupError: unknown error handler".to_string(),
          ),
        )
      } else {
        errs
      }
    Some(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() errors must be str".to_string(),
        ),
      )
    None => "strict"
  }
  if encoding == "utf-8" || encoding == "utf8" {
    Ok(encode_string_utf8_with_errors(text, errors))
  } else if encoding == "ascii" {
    encode_string_ascii_with_errors(name, text, errors)
  } else {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "LookupError: unknown encoding".to_string(),
      ),
    )
  }
}

///|
fn decode_bytes_utf8(
  name : String,
  bytes : Array[Int],
  errors : String,
) -> Result[String, RuntimeError] {
  let _ = name
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i] & 0xFF
    if b0 < 0x80 {
      buf.write_char(b0.to_char().unwrap())
      i += 1
      continue
    }
    let (need, code0) = if (b0 & 0xE0) == 0xC0 {
      (1, b0 & 0x1F)
    } else if (b0 & 0xF0) == 0xE0 {
      (2, b0 & 0x0F)
    } else if (b0 & 0xF8) == 0xF0 {
      (3, b0 & 0x07)
    } else {
      if errors == "surrogateescape" {
        // Map invalid bytes to U+DCxx, matching Python's surrogateescape.
        buf.write_char(surrogateescape_char_from_byte(b0))
        i += 1
        continue
      }
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "UnicodeDecodeError: invalid start byte".to_string(),
        ),
      )
    }
    let mut code = code0
    if i + need >= bytes.length() {
      if errors == "surrogateescape" {
        // Truncated sequence: treat remaining bytes as undecodable.
        while i < bytes.length() {
          let b = bytes[i] & 0xFF
          buf.write_char(surrogateescape_char_from_byte(b))
          i += 1
        }
        break
      }
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "UnicodeDecodeError: unexpected end of data".to_string(),
        ),
      )
    }
    let mut bad_lead = false
    let mut j = 0
    while j < need {
      let b = bytes[i + 1 + j] & 0xFF
      if (b & 0xC0) != 0x80 {
        if errors == "surrogateescape" {
          // Bad continuation: treat the lead byte as undecodable and retry from next byte.
          buf.write_char(surrogateescape_char_from_byte(b0))
          i += 1
          bad_lead = true
          break
        }
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "UnicodeDecodeError: invalid continuation byte".to_string(),
          ),
        )
      }
      code = (code << 6) | (b & 0x3F)
      j += 1
    }
    if bad_lead {
      continue
    }
    buf.write_char(code.to_char().unwrap())
    i += 1 + need
  }
  Ok(buf.to_string())
}

///|
fn decode_bytes_ascii(
  name : String,
  bytes : Array[Int],
  errors : String,
) -> Result[String, RuntimeError] {
  let _ = name
  let buf = StringBuilder::new()
  for b in bytes {
    let v = b & 0xFF
    if v > 0x7F {
      if errors == "surrogateescape" {
        buf.write_char(surrogateescape_char_from_byte(v))
        continue
      }
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "UnicodeDecodeError: 'ascii' codec can't decode byte".to_string(),
        ),
      )
    }
    buf.write_char(v.to_char().unwrap())
  }
  Ok(buf.to_string())
}

///|
fn decode_bytes_with_encoding(
  name : String,
  bytes : Array[Int],
  encoding_value : Value,
  errors_value : Value?,
) -> Result[String, RuntimeError] {
  let encoding = match encoding_value {
    Value::Str(value) => value
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() encoding must be str".to_string(),
        ),
      )
  }
  let errors = match errors_value {
    Some(Value::Str(errs)) =>
      if errs != "strict" && errs != "surrogateescape" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "LookupError: unknown error handler".to_string(),
          ),
        )
      } else {
        errs
      }
    Some(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() errors must be str".to_string(),
        ),
      )
    None => "strict"
  }
  if encoding == "utf-8" || encoding == "utf8" {
    decode_bytes_utf8(name, bytes, errors)
  } else if encoding == "ascii" {
    decode_bytes_ascii(name, bytes, errors)
  } else {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "LookupError: unknown encoding".to_string(),
      ),
    )
  }
}

///|
fn byte_from_value(name : String, value : Value) -> Result[Int, RuntimeError] {
  match value {
    Value::Int(v) => {
      let int_val = match bigint_to_int_checked(v) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if int_val < 0 || int_val > 255 {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: byte must be in range(0, 256)".to_string(),
          ),
        )
      } else {
        Ok(int_val)
      }
    }
    Value::Bool(v) => Ok(if v { 1 } else { 0 })
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() an integer is required".to_string(),
        ),
      )
  }
}

///|
fn bytes_from_iterable(
  name : String,
  value : Value,
) -> Result[Array[Int], RuntimeError] {
  let items = match iterable_values(value) {
    Ok(values) => values
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  for item in items {
    let byte = match byte_from_value(name, item) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    out.push(byte)
  }
  Ok(out)
}

///|
fn bytes_from_count(
  name : String,
  count : @bigint.BigInt,
) -> Result[Array[Int], RuntimeError] {
  let _ = name
  if count < 0N {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: negative count".to_string(),
      ),
    )
  }
  let count_i = match bigint_to_int_checked(count) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  for i = 0; i < count_i; i = i + 1 {
    out.push(0)
  }
  Ok(out)
}

///|
fn hex_digit_value(ch : Char) -> Int? {
  let code = ch.to_int()
  if code >= '0'.to_int() && code <= '9'.to_int() {
    Some(code - '0'.to_int())
  } else if code >= 'a'.to_int() && code <= 'f'.to_int() {
    Some(10 + (code - 'a'.to_int()))
  } else if code >= 'A'.to_int() && code <= 'F'.to_int() {
    Some(10 + (code - 'A'.to_int()))
  } else {
    None
  }
}

///|
fn bytes_fromhex_parse(text : String) -> Result[Array[Int], RuntimeError] {
  let out : Array[Int] = []
  let chars = text.to_array()
  let mut have_hi = false
  let mut hi = 0
  for i = 0; i < chars.length(); i = i + 1 {
    let ch = chars[i]
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      continue
    }
    match hex_digit_value(ch) {
      Some(n) =>
        if have_hi {
          out.push((hi << 4) | n)
          have_hi = false
        } else {
          hi = n
          have_hi = true
        }
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: non-hexadecimal number found in fromhex() arg at position " +
            i.to_string(),
          ),
        )
    }
  }
  if have_hi {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: non-hexadecimal number found in fromhex() arg at position " +
        chars.length().to_string(),
      ),
    )
  }
  Ok(out)
}

///|
fn builtin_bytes(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytes", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::Bytes([]))
  }
  if positional.length() > 3 {
    return Err(too_many_arguments_error("bytes", positional.length()))
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Int(count) =>
        return Ok(
          Value::Bytes(
            match bytes_from_count("bytes", count) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
      Value::Bytes(values) => return Ok(Value::Bytes(copy_ints(values)))
      Value::ByteArray(values) => return Ok(Value::Bytes(copy_ints(values)))
      Value::MemoryView(values) => return Ok(Value::Bytes(copy_ints(values)))
      Value::Str(_) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "string argument without an encoding".to_string(),
          ),
        )
      other =>
        return Ok(
          Value::Bytes(
            match bytes_from_iterable("bytes", other) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
    }
  }
  match positional[0] {
    Value::Str(text) => {
      let encoding = positional[1]
      let errors_value = if positional.length() > 2 {
        Some(positional[2])
      } else {
        None
      }
      let bytes = match
        encode_string_with_encoding("bytes", text, encoding, errors_value) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Value::Bytes(bytes))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "encoding without a string argument".to_string(),
        ),
      )
  }
}

///|
fn builtin_bytes_fromhex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytes.fromhex", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "fromhex() takes exactly one argument".to_string(),
      ),
    )
  }
  let text = match positional[1] {
    Value::Str(s) => s
    other =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "fromhex() argument must be str, not '" +
          type_name_from_value(other) +
          "'",
        ),
      )
  }
  Ok(
    Value::Bytes(
      match bytes_fromhex_parse(text) {
        Ok(v) => v
        Err(err) => return Err(err)
      },
    ),
  )
}

///|
fn bytes_like_ints_for_translate(
  name : String,
  value : Value,
) -> Result[Array[Int], RuntimeError] {
  let _ = name
  match value {
    Value::Bytes(bytes) | Value::ByteArray(bytes) | Value::MemoryView(bytes) =>
      Ok(bytes)
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "a bytes-like object is required".to_string(),
        ),
      )
  }
}

///|
fn builtin_bytes_maketrans(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytes.maketrans", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "maketrans() takes exactly two arguments".to_string(),
      ),
    )
  }
  let from_bytes = match
    bytes_like_ints_for_translate("bytes.maketrans", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let to_bytes = match
    bytes_like_ints_for_translate("bytes.maketrans", positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if from_bytes.length() != to_bytes.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: maketrans arguments must have equal length".to_string(),
      ),
    )
  }
  let table : Array[Int] = []
  for i = 0; i < 256; i = i + 1 {
    table.push(i)
  }
  for i = 0; i < from_bytes.length(); i = i + 1 {
    let from_b = from_bytes[i] & 0xFF
    let to_b = to_bytes[i] & 0xFF
    if from_b >= 0 && from_b < 256 {
      table[from_b] = to_b
    }
  }
  Ok(Value::Bytes(table))
}

///|
fn builtin_bytes_translate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytes.translate", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "translate() takes exactly one argument".to_string(),
      ),
    )
  }
  let src = match positional[0] {
    Value::Bytes(bytes) | Value::MemoryView(bytes) => bytes
    Value::ByteArray(bytes) => bytes
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "translate() expects a bytes-like object".to_string(),
        ),
      )
  }
  let table = match
    bytes_like_ints_for_translate("bytes.translate", positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if table.length() != 256 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: translation table must be 256 bytes long".to_string(),
      ),
    )
  }
  let out : Array[Int] = []
  for byte in src {
    let b = byte & 0xFF
    out.push(table[b])
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_bytearray(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytearray", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::ByteArray([]))
  }
  if positional.length() > 3 {
    return Err(too_many_arguments_error("bytearray", positional.length()))
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Int(count) =>
        return Ok(
          Value::ByteArray(
            match bytes_from_count("bytearray", count) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
      Value::Bytes(values) => return Ok(Value::ByteArray(copy_ints(values)))
      Value::ByteArray(values) => return Ok(Value::ByteArray(copy_ints(values)))
      Value::MemoryView(values) =>
        return Ok(Value::ByteArray(copy_ints(values)))
      Value::Str(_) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "string argument without an encoding".to_string(),
          ),
        )
      other =>
        return Ok(
          Value::ByteArray(
            match bytes_from_iterable("bytearray", other) {
              Ok(value) => value
              Err(err) => return Err(err)
            },
          ),
        )
    }
  }
  match positional[0] {
    Value::Str(text) => {
      let encoding = positional[1]
      let errors_value = if positional.length() > 2 {
        Some(positional[2])
      } else {
        None
      }
      let bytes = match
        encode_string_with_encoding("bytearray", text, encoding, errors_value) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Value::ByteArray(bytes))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "encoding without a string argument".to_string(),
        ),
      )
  }
}

///|
fn builtin_bytearray_fromhex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("bytearray.fromhex", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "fromhex() takes exactly one argument".to_string(),
      ),
    )
  }
  let text = match positional[1] {
    Value::Str(s) => s
    other =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "fromhex() argument must be str, not '" +
          type_name_from_value(other) +
          "'",
        ),
      )
  }
  Ok(
    Value::ByteArray(
      match bytes_fromhex_parse(text) {
        Ok(v) => v
        Err(err) => return Err(err)
      },
    ),
  )
}

///|
fn builtin_bytearray_copy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("bytearray.copy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "copy() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::ByteArray(values) => Ok(Value::ByteArray(copy_ints(values)))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "copy() expects a bytearray".to_string(),
        ),
      )
  }
}

///|
fn builtin_memoryview(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("memoryview", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "memoryview() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Bytes(values) => Ok(Value::MemoryView(copy_ints(values)))
    Value::ByteArray(values) => Ok(Value::MemoryView(copy_ints(values)))
    Value::MemoryView(values) => Ok(Value::MemoryView(copy_ints(values)))
    other =>
      Ok(
        Value::MemoryView(
          match bytes_from_iterable("memoryview", other) {
            Ok(value) => value
            Err(err) => return Err(err)
          },
        ),
      )
  }
}
