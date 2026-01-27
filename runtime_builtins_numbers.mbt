///|
/// Numeric builtins (int/float/complex + abs/round/pow/divmod/chr/ord/bin/oct/hex).

///|
fn int_parse_digit(ch : Char) -> Int? {
  if ch.is_ascii_digit() {
    Some(ch.to_int() - '0'.to_int())
  } else if ch.is_ascii_lowercase() {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch.is_ascii_uppercase() {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn int_text_from_value(value : Value) -> Result[String, RuntimeError] {
  match value {
    Value::Str(text) => Ok(text)
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => {
      let chars : Array[Char] = []
      for byte in values {
        chars.push(byte.unsafe_to_char())
      }
      Ok(String::from_array(chars))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int() argument must be a string or a number".to_string(),
        ),
      )
  }
}

///|
fn parse_bigint_from_string(
  text : String,
  base_in : Int,
) -> Result[@bigint.BigInt, RuntimeError] {
  let trimmed = text.trim().to_string()
  let chars = trimmed.to_array()
  if chars.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: invalid literal for int()".to_string(),
      ),
    )
  }
  let mut idx = 0
  let mut negative = false
  if chars[idx] == '-' {
    negative = true
    idx = idx + 1
  } else if chars[idx] == '+' {
    idx = idx + 1
  }
  let mut base = base_in
  if base == 0 {
    if idx + 1 < chars.length() && chars[idx] == '0' {
      match chars[idx + 1] {
        'x' | 'X' => {
          base = 16
          idx = idx + 2
        }
        'o' | 'O' => {
          base = 8
          idx = idx + 2
        }
        'b' | 'B' => {
          base = 2
          idx = idx + 2
        }
        _ => base = 10
      }
    } else {
      base = 10
    }
  } else {
    if base < 2 || base > 36 {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int() base must be >= 2 and <= 36".to_string(),
        ),
      )
    }
    if idx + 1 < chars.length() && chars[idx] == '0' {
      if base == 16 && (chars[idx + 1] == 'x' || chars[idx + 1] == 'X') {
        idx = idx + 2
      } else if base == 8 && (chars[idx + 1] == 'o' || chars[idx + 1] == 'O') {
        idx = idx + 2
      } else if base == 2 && (chars[idx + 1] == 'b' || chars[idx + 1] == 'B') {
        idx = idx + 2
      }
    }
  }
  if base < 2 || base > 36 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int() base must be >= 2 and <= 36".to_string(),
      ),
    )
  }
  let base_big = @bigint.BigInt::from_int(base)
  let mut acc = 0N
  let mut saw_digit = false
  while idx < chars.length() {
    let ch = chars[idx]
    idx = idx + 1
    if ch == '_' {
      continue
    }
    let digit = match int_parse_digit(ch) {
      Some(v) => v
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: invalid literal for int()".to_string(),
          ),
        )
    }
    if digit >= base {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "ValueError: invalid literal for int()".to_string(),
        ),
      )
    }
    acc = acc * base_big + @bigint.BigInt::from_int(digit)
    saw_digit = true
  }
  if !saw_digit {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: invalid literal for int()".to_string(),
      ),
    )
  }
  if negative {
    acc = -acc
  }
  Ok(acc)
}

///|
fn builtin_int(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int() takes at most 2 arguments".to_string(),
      ),
    )
  }
  let base_value = if positional.length() > 1 {
    Some(positional[1])
  } else {
    None
  }
  if positional.length() == 0 {
    Ok(Value::Int(0N))
  } else {
    if base_value is Some(base_arg) {
      let base_int = match base_arg {
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
              "int() base must be an integer".to_string(),
            ),
          )
      }
      let text = match int_text_from_value(positional[0]) {
        Ok(v) => v
        Err(_) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "int() can't convert non-string with explicit base".to_string(),
            ),
          )
      }
      let parsed = match parse_bigint_from_string(text, base_int) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      return Ok(Value::Int(parsed))
    }
    match positional[0] {
      Value::Instance(_) => {
        let int_method = match
          get_attr_from_value(positional[0], "__int__", globals, builtins, io) {
          Ok(v) => v
          Err(_) =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "int() argument must be a string or a number".to_string(),
              ),
            )
        }
        let value = match
          call_callable_with_env(int_method, [], [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match value {
          Value::Int(v) => Ok(Value::Int(v))
          Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "int() argument must be a string or a number".to_string(),
              ),
            )
        }
      }
      Value::Int(v) => Ok(Value::Int(v))
      Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
      Value::Float(v) =>
        Ok(Value::Int(@bigint.BigInt::from_int64(v.to_int64())))
      Value::Str(text) => {
        let parsed = match parse_bigint_from_string(text, 10) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Int(parsed))
      }
      Value::Bytes(_) | Value::ByteArray(_) | Value::MemoryView(_) => {
        let text = match int_text_from_value(positional[0]) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let parsed = match parse_bigint_from_string(text, 10) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Int(parsed))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "int() argument must be a string or a number".to_string(),
          ),
        )
    }
  }
}

///|
fn builtin_int_new(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.__new__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__new__() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let cls = match positional[0] {
    Value::Class(klass) => klass
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.__new__() expects a type as the first argument".to_string(),
        ),
      )
  }
  if cls.name == "bool" {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__new__(bool) is not safe, use bool.__new__()".to_string(),
      ),
    )
  }
  if !class_has_base_name(cls, "int") {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__new__() expects an int subtype as the first argument".to_string(),
      ),
    )
  }
  let value = if positional.length() == 1 {
    0N
  } else {
    match positional[1] {
      Value::Int(v) => v
      Value::Bool(v) => if v { 1N } else { 0N }
      Value::Float(v) => @bigint.BigInt::from_int64(v.to_int64())
      Value::Str(text) => {
        let parsed = @strconv.parse_int(text) catch {
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: invalid literal for int()".to_string(),
              ),
            )
        }
        @bigint.BigInt::from_int(parsed)
      }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "int.__new__() argument must be a string or a number".to_string(),
          ),
        )
    }
  }
  if cls.name == "int" ||
    class_has_base_name(cls, "Enum") ||
    class_has_base_name(cls, "Flag") ||
    class_has_base_name(cls, "IntFlag") ||
    class_has_base_name(cls, "StrEnum") {
    return Ok(Value::Int(value))
  }
  Ok(
    Value::Instance(InstanceValue::{
      class: cls,
      dict: [(int_storage_name, Value::Int(value))],
    }),
  )
}

///|
fn int_value_for_builtin(
  name : String,
  value : Value,
) -> Result[@bigint.BigInt, RuntimeError] {
  match value {
    Value::Int(v) => Ok(v)
    Value::Bool(v) => Ok(if v { 1N } else { 0N })
    Value::Instance(inst) =>
      match get_named_value(inst.dict, int_storage_name) {
        Some(Value::Int(v)) => Ok(v)
        Some(Value::Bool(v)) => Ok(if v { 1N } else { 0N })
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              name + " expects an int".to_string(),
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + " expects an int".to_string(),
        ),
      )
  }
}

///|
fn builtin_int_bool(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.__bool__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__bool__() takes exactly one argument".to_string(),
      ),
    )
  }
  let n = match int_value_for_builtin("int.__bool__()", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(n != 0N))
}

///|
fn builtin_int_repr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.__repr__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__repr__() takes exactly one argument".to_string(),
      ),
    )
  }
  let n = match int_value_for_builtin("int.__repr__()", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Str(n.to_string()))
}

///|
fn builtin_int_index(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.__index__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.__index__() takes exactly one argument".to_string(),
      ),
    )
  }
  let n = match int_value_for_builtin("int.__index__()", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Int(n))
}

///|
fn builtin_int_from_bytes(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut signed = false
  for item in keywords {
    if item.0 == "signed" {
      signed = bool_from_value(item.1)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.from_bytes() got unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  if positional.length() < 2 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.from_bytes() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 4 {
    signed = bool_from_value(positional[3])
  }
  let bytes = match positional[1] {
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => values
    other =>
      match
        bytes_from_iterable("int.from_bytes", other, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
  }
  let byteorder = if positional.length() >= 3 {
    match positional[2] {
      Value::Str(text) => text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "int.from_bytes() byteorder must be str".to_string(),
          ),
        )
    }
  } else {
    "big".to_string()
  }
  let mut value = 0N
  if byteorder == "big" {
    for b in bytes {
      value = value * 256 + @bigint.BigInt::from_int(b)
    }
  } else if byteorder == "little" {
    let mut factor = 1N
    for b in bytes {
      value = value + @bigint.BigInt::from_int(b) * factor
      factor = factor * 256
    }
  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.from_bytes() byteorder must be 'little' or 'big'".to_string(),
      ),
    )
  }
  if signed && bytes.length() > 0 {
    let sign_byte = if byteorder == "big" {
      bytes[0]
    } else {
      bytes[bytes.length() - 1]
    }
    if (sign_byte & 0x80) != 0 {
      let mut modulus = 1N
      let mut i = 0
      while i < bytes.length() {
        modulus = modulus * 256
        i += 1
      }
      value = value - modulus
    }
  }
  Ok(Value::Int(value))
}

///|
fn builtin_bool_from_bytes(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let value = match
    builtin_int_from_bytes(positional, keywords, locals, globals, builtins, io) {
    Ok(Value::Int(v)) => v
    Ok(Value::Bool(v)) => if v { 1N } else { 0N }
    Ok(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "bool.from_bytes() internal error".to_string(),
        ),
      )
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(value != 0N))
}

///|
fn builtin_bool_new(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("bool.__new__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 1 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "bool.__new__() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Class(cls) =>
      if cls.name != "bool" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "bool.__new__() expects bool as the first argument".to_string(),
          ),
        )
      }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "bool.__new__() expects bool as the first argument".to_string(),
        ),
      )
  }
  if positional.length() == 1 {
    return Ok(Value::Bool(false))
  }
  let arg = positional[1]
  let truthy = match truthy_from_value_with_env(arg, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(truthy))
}

///|
fn builtin_int_to_bytes(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut signed = false
  for item in keywords {
    if item.0 == "signed" {
      signed = bool_from_value(item.1)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.to_bytes() got unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  if positional.length() < 2 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.to_bytes() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 4 {
    signed = bool_from_value(positional[3])
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.to_bytes() expects an int".to_string(),
        ),
      )
  }
  let length_val = match positional[1] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.to_bytes() length must be int".to_string(),
        ),
      )
  }
  let length = match bigint_to_int_checked(length_val) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if length < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: length argument must be non-negative".to_string(),
      ),
    )
  }
  let byteorder = if positional.length() >= 3 {
    match positional[2] {
      Value::Str(text) => text
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "int.to_bytes() byteorder must be str".to_string(),
          ),
        )
    }
  } else {
    "big".to_string()
  }
  if byteorder != "big" && byteorder != "little" {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.to_bytes() byteorder must be 'little' or 'big'".to_string(),
      ),
    )
  }
  let mut modulus = 1N
  let mut i = 0
  while i < length {
    modulus = modulus * 256
    i += 1
  }
  let mut unsigned_value = value
  if signed {
    let limit = modulus / 2
    if value < -limit || value >= limit {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OverflowError: int too big to convert".to_string(),
        ),
      )
    }
    if value < 0N {
      unsigned_value = value + modulus
    }
  } else {
    if value < 0N {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OverflowError: can't convert negative int to unsigned".to_string(),
        ),
      )
    }
    if value >= modulus {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "OverflowError: int too big to convert".to_string(),
        ),
      )
    }
  }
  let out : Array[Int] = []
  let mut v = unsigned_value
  i = 0
  while i < length {
    let byte_val = v % 256N
    let byte_int = match bigint_to_int_checked(byte_val) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    out.push(byte_int)
    v = v / 256N
    i += 1
  }
  if byteorder == "big" {
    let ordered : Array[Int] = []
    let mut j = out.length() - 1
    while j >= 0 {
      ordered.push(out[j])
      j -= 1
    }
    return Ok(Value::Bytes(ordered))
  }
  Ok(Value::Bytes(out))
}

///|
fn builtin_int_bit_length(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.bit_length", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.bit_length() takes exactly one argument".to_string(),
      ),
    )
  }
  let mut value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.bit_length() expects an int".to_string(),
        ),
      )
  }
  if value < 0N {
    value = -value
  }
  if value == 0N {
    return Ok(Value::Int(0N))
  }
  let text = bigint_to_base_string(value, 2, "0b")
  let bits = text.length() - 2
  Ok(Value::Int(@bigint.BigInt::from_int(bits)))
}

///|
fn builtin_int_conjugate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("int.conjugate", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "int.conjugate() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "int.conjugate() expects an int".to_string(),
        ),
      )
  }
}

///|
fn builtin_float_conjugate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("float.conjugate", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "float.conjugate() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Float(v) => Ok(Value::Float(v))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "float.conjugate() expects a float".to_string(),
        ),
      )
  }
}

///|
fn builtin_complex_conjugate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("complex.conjugate", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "complex.conjugate() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Complex(real, imag) => Ok(Value::Complex(real, -imag))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "complex.conjugate() expects a complex".to_string(),
        ),
      )
  }
}

///|
fn builtin_float(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("float", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    Ok(Value::Float(0.0))
  } else {
    match positional[0] {
      Value::Float(v) => Ok(Value::Float(v))
      Value::Int(v) => {
        let d = match bigint_to_double_checked(v) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Float(d))
      }
      Value::Bool(v) => Ok(Value::Float(if v { 1.0 } else { 0.0 }))
      Value::Instance(_) => {
        let converted = match
          real_to_double(positional[0], "__float__", globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Float(converted))
      }
      Value::Str(text) => {
        let parsed = @strconv.parse_double(text) catch {
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: could not convert string to float".to_string(),
              ),
            )
        }
        Ok(Value::Float(parsed))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "float() argument must be a string or a number".to_string(),
          ),
        )
    }
  }
}

///|
fn call_method0_on_instance(
  target : Value,
  method_name : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value?, RuntimeError] {
  let callable_value = match
    get_attr_from_value(target, method_name, globals, builtins, io) {
    Ok(v) => v
    Err(err) =>
      match err.kind {
        RuntimeErrorKind::Attribute => return Ok(None)
        _ => return Err(err)
      }
  }
  let v = match callable_value {
    Value::BoundMethod(bound) =>
      (eval_function_with_kwargs_ref.val)(
        bound.function,
        [bound.self],
        [],
        globals,
        builtins,
        io,
      )
    Value::Function(func) =>
      (eval_function_with_kwargs_ref.val)(
        func,
        [target],
        [],
        globals,
        builtins,
        io,
      )
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          method_name + " must be a function",
        ),
      )
  }
  match v {
    Ok(value) => Ok(Some(value))
    Err(err) => Err(err)
  }
}

///|
fn real_to_double(
  value : Value,
  primary_dunder : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Double, RuntimeError] {
  match value {
    Value::Float(v) => Ok(v)
    Value::Int(v) => bigint_to_double_checked(v)
    Value::Bool(v) => Ok(if v { 1.0 } else { 0.0 })
    Value::Instance(_) => {
      let primary = match
        call_method0_on_instance(value, primary_dunder, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if primary is Some(ret) {
        match ret {
          Value::Float(v) => return Ok(v)
          Value::Int(v) => return bigint_to_double_checked(v)
          Value::Bool(v) => return Ok(if v { 1.0 } else { 0.0 })
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                primary_dunder + " returned non-float",
              ),
            )
        }
      }
      let index = match
        call_method0_on_instance(value, "__index__", globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if index is Some(ret) {
        match ret {
          Value::Int(v) => return bigint_to_double_checked(v)
          Value::Bool(v) => return Ok(if v { 1.0 } else { 0.0 })
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "__index__ returned non-int".to_string(),
              ),
            )
        }
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "float() argument must be a string or a number".to_string(),
        ),
      )
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "float() argument must be a string or a number".to_string(),
        ),
      )
  }
}

///|
fn complex_to_double(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Double, RuntimeError] {
  match value {
    Value::Str(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "complex() argument must be a number".to_string(),
        ),
      )
    Value::Complex(_, _) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "complex() argument must be a real number".to_string(),
        ),
      )
    _ => real_to_double(value, "__float__", globals, builtins, io)
  }
}

///|
fn builtin_float_repr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("float.__repr__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "float.__repr__() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Float(v) => Ok(Value::Str(v.to_string()))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "float.__repr__() expects a float".to_string(),
        ),
      )
  }
}

///|
fn builtin_float_getformat(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("float.__getformat__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "float.__getformat__() takes exactly one argument".to_string(),
      ),
    )
  }
  let kind = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "float.__getformat__() argument must be str".to_string(),
        ),
      )
  }
  // CPython returns strings like "IEEE, little-endian". Most stdlib probes only
  // check that it starts with "IEEE".
  if kind == "double" || kind == "float" {
    Ok(Value::Str("IEEE, little-endian"))
  } else {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: unknown float format".to_string(),
      ),
    )
  }
}

///|
fn builtin_complex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("complex", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::Complex(0.0, 0.0))
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "complex() takes at most two arguments".to_string(),
      ),
    )
  }
  if positional.length() == 1 {
    match positional[0] {
      Value::Complex(real, imag) => Ok(Value::Complex(real, imag))
      Value::Float(v) => Ok(Value::Complex(v, 0.0))
      Value::Int(v) =>
        match bigint_to_double_checked(v) {
          Ok(value) => Ok(Value::Complex(value, 0.0))
          Err(err) => Err(err)
        }
      Value::Bool(v) => Ok(Value::Complex(if v { 1.0 } else { 0.0 }, 0.0))
      Value::Instance(_) => {
        let complex_value = match
          call_method0_on_instance(
            positional[0],
            "__complex__",
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if complex_value is Some(ret) {
          match ret {
            Value::Complex(r, i) => return Ok(Value::Complex(r, i))
            Value::Float(r) => return Ok(Value::Complex(r, 0.0))
            Value::Int(i) =>
              return Ok(
                Value::Complex(
                  match bigint_to_double_checked(i) {
                    Ok(d) => d
                    Err(err) => return Err(err)
                  },
                  0.0,
                ),
              )
            Value::Bool(b) =>
              return Ok(Value::Complex(if b { 1.0 } else { 0.0 }, 0.0))
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__complex__ returned non-complex".to_string(),
                ),
              )
          }
        }
        let real = match
          complex_to_double(positional[0], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Complex(real, 0.0))
      }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "complex() argument must be a number".to_string(),
          ),
        )
    }
  } else {
    let real = match positional[0] {
      Value::Complex(_, _) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "complex() can't take second arg if first is complex".to_string(),
          ),
        )
      _ =>
        match complex_to_double(positional[0], globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
    }
    let imag = match positional[1] {
      Value::Complex(_, _) =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "complex() second argument must be a real number".to_string(),
          ),
        )
      _ =>
        match complex_to_double(positional[1], globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
    }
    Ok(Value::Complex(real, imag))
  }
}

///|
fn builtin_abs(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("abs", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "abs() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(if v < 0N { -v } else { v }))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) => Ok(Value::Float(if v < 0.0 { -v } else { v }))
    Value::Complex(real, imag) =>
      Ok(Value::Float(@math.pow(real * real + imag * imag, 0.5)))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "bad operand type for abs()".to_string(),
        ),
      )
  }
}

///|
fn round_float_to_int(value : Double) -> Int64 {
  if value >= 0.0 {
    @math.floor(value + 0.5).to_int64()
  } else {
    @math.ceil(value - 0.5).to_int64()
  }
}

///|
fn builtin_round(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("round", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "round() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  // `ndigits` is accepted but ignored for now.
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(round_float_to_int(v))))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "round() argument must be a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_pow(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("pow", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "pow() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let modulus_opt : @bigint.BigInt? = if positional.length() == 3 {
    match positional[2] {
      Value::Int(v) => Some(v)
      Value::Bool(v) => Some(if v { 1N } else { 0N })
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "pow() 3rd argument must be int".to_string(),
          ),
        )
    }
  } else {
    None
  }
  match (positional[0], positional[1], modulus_opt) {
    (Value::Int(a), Value::Int(b), Some(m)) =>
      if b < 0N {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "pow() exponent must be >= 0 when modulus is provided".to_string(),
          ),
        )
      } else if m == 0N {
        Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "integer modulo by zero".to_string(),
          ),
        )
      } else {
        Ok(Value::Int(a.pow(b, modulus=m)))
      }
    (Value::Int(a), Value::Int(b), None) =>
      if b < 0N {
        let aa = match bigint_to_double_checked(a) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let bb = match bigint_to_double_checked(b) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::Float(@math.pow(aa, bb)))
      } else {
        Ok(Value::Int(a.pow(b)))
      }
    _ => {
      let (_, aa) = match number_value(positional[0]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let (_, bb) = match number_value(positional[1]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Value::Float(@math.pow(aa, bb)))
    }
  }
}

///|
fn floor_divmod_int(
  a : @bigint.BigInt,
  b : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt) {
  // Python-style floor division adjustment.
  let mut q = a / b
  let mut r = a % b
  if r != 0N && (r > 0N) != (b > 0N) {
    q = q - 1N
    r = r + b
  }
  (q, r)
}

///|
fn builtin_divmod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("divmod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "divmod() takes exactly two arguments".to_string(),
      ),
    )
  }
  if positional[0] is Value::Instance(_) {
    match
      get_attr_from_value(positional[0], "__divmod__", globals, builtins, io) {
      Ok(callable_value) =>
        return call_callable_with_env(
          callable_value,
          [positional[1]],
          [],
          globals,
          builtins,
          io,
        )
      Err(_) => ()
    }
  }
  if positional[1] is Value::Instance(_) {
    match
      get_attr_from_value(positional[1], "__rdivmod__", globals, builtins, io) {
      Ok(callable_value) =>
        return call_callable_with_env(
          callable_value,
          [positional[0]],
          [],
          globals,
          builtins,
          io,
        )
      Err(_) => ()
    }
  }
  match (positional[0], positional[1]) {
    (Value::Int(a), Value::Int(b)) =>
      if b == 0N {
        Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "integer division or modulo by zero".to_string(),
          ),
        )
      } else {
        let (q, r) = floor_divmod_int(a, b)
        Ok(Value::Tuple([Value::Int(q), Value::Int(r)]))
      }
    _ => {
      let (_, aa) = match number_value(positional[0]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let (_, bb) = match number_value(positional[1]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if bb == 0.0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "division by zero".to_string(),
          ),
        )
      }
      let q = @math.floor(aa / bb)
      let r = aa - q * bb
      Ok(Value::Tuple([Value::Float(q), Value::Float(r)]))
    }
  }
}

///|
fn builtin_chr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("chr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "chr() takes exactly one argument".to_string(),
      ),
    )
  }
  let codepoint = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "chr() argument must be int".to_string(),
        ),
      )
  }
  if codepoint < 0N || codepoint > @bigint.BigInt::from_int(0x10FFFF) {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: chr() arg not in range(0x110000)".to_string(),
      ),
    )
  }
  Ok(
    Value::Str(
      char_to_string(Int::unsafe_to_char(codepoint.to_int64().to_int())),
    ),
  )
}

///|
fn builtin_ord(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("ord", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "ord() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(text) => {
      let chars = text.to_array()
      if chars.length() != 1 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "ord() expected a character".to_string(),
          ),
        )
      }
      Ok(Value::Int(@bigint.BigInt::from_int(chars[0].to_int())))
    }
    Value::Bytes(values) | Value::ByteArray(values) => {
      if values.length() != 1 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "ord() expected a character".to_string(),
          ),
        )
      }
      Ok(Value::Int(@bigint.BigInt::from_int(values[0])))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "ord() expected a character".to_string(),
        ),
      )
  }
}

///|
fn builtin_bin(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("bin", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "bin() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "bin() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(bigint_to_base_string(value, 2, "0b")))
}

///|
fn builtin_oct(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("oct", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "oct() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "oct() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(bigint_to_base_string(value, 8, "0o")))
}

///|
fn builtin_hex(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("hex", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "hex() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "hex() argument must be int".to_string(),
        ),
      )
  }
  Ok(Value::Str(bigint_to_base_string(value, 16, "0x")))
}
