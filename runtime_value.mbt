///|
/// Core value utilities for the mpython runtime.

///|
fn bool_from_value(value : Value) -> Bool {
  match value {
    Value::None => false
    Value::Bool(v) => v
    Value::Int(v) => v != 0N
    Value::Float(v) => v != 0.0
    Value::Str(v) => v.length() > 0
    Value::Bytes(v) => v.length() > 0
    Value::ByteArray(v) => v.length() > 0
    Value::MemoryView(v) => v.length() > 0
    Value::List(v) => v.length() > 0
    Value::Tuple(v) => v.length() > 0
    Value::Dict(v) => v.length() > 0
    Value::Set(v) => v.length() > 0
    Value::Function(_) => true
    Value::Class(_) => true
    Value::Instance(_) => true
    Value::BoundMethod(_) => true
  }
}

///|
fn type_name_from_value(value : Value) -> String {
  match value {
    Value::None => "NoneType"
    Value::Bool(_) => "bool"
    Value::Int(_) => "int"
    Value::Float(_) => "float"
    Value::Str(_) => "str"
    Value::Bytes(_) => "bytes"
    Value::ByteArray(_) => "bytearray"
    Value::MemoryView(_) => "memoryview"
    Value::List(_) => "list"
    Value::Tuple(_) => "tuple"
    Value::Dict(_) => "dict"
    Value::Set(_) => "set"
    Value::Function(_) => "function"
    Value::Class(_) => "type"
    Value::Instance(inst) => inst.class.name
    Value::BoundMethod(_) => "method"
  }
}

///|
fn not_callable_message(value : Value) -> String {
  "'" + type_name_from_value(value) + "' object is not callable"
}

///|
fn is_exception_class_name(name : String) -> Bool {
  name == "BaseException" ||
  name == "Exception" ||
  name == "BaseExceptionGroup" ||
  name == "ExceptionGroup" ||
  name == "RuntimeError" ||
  name == "NameError" ||
  name == "UnboundLocalError" ||
  name == "TypeError" ||
  name == "AttributeError" ||
  name == "IndexError" ||
  name == "KeyError" ||
  name == "NotImplementedError" ||
  name == "ZeroDivisionError" ||
  name == "OverflowError" ||
  name == "ValueError" ||
  name == "ImportError" ||
  name == "AssertionError" ||
  name == "SyntaxError" ||
  name == "IndentationError" ||
  name == "EOFError" ||
  name == "StopIteration"
}

///|
fn lookup_instance_field(
  dict : Array[(String, Value)],
  name : String,
) -> Value? {
  for pair in dict {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

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
fn bytes_repr(bytes : Array[Int]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("b'")
  for byte in bytes {
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
fn value_to_string(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Str(v) => v
    Value::Bytes(values) => bytes_repr(values)
    Value::ByteArray(values) => "bytearray(" + bytes_repr(values) + ")"
    Value::MemoryView(values) => "memoryview(" + bytes_repr(values) + ")"
    Value::List(values) => {
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
    Value::Tuple(values) => {
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
    Value::Dict(pairs) => {
      let buf = StringBuilder::new()
      buf.write_char('{')
      for i = 0; i < pairs.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(pairs[i].0))
        buf.write_string(": ")
        buf.write_string(value_to_string(pairs[i].1))
      }
      buf.write_char('}')
      buf.to_string()
    }
    Value::Set(values) => {
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
    Value::Function(func) => "<function " + func.name + ">"
    Value::Class(klass) => "<class '" + klass.name + "'>"
    Value::Instance(inst) =>
      if is_exception_class_name(inst.class.name) {
        match lookup_instance_field(inst.dict, "message") {
          Some(Value::Str(text)) => text
          Some(other) => value_to_string(other)
          None => "".to_string()
        }
      } else {
        "<" + inst.class.name + " object>"
      }
    Value::BoundMethod(method) => "<bound method " + method.function.name + ">"
  }
}

///|
fn find_top_level_format_colon(inner : String) -> Int? {
  let chars = inner.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == ':' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      return Some(i)
    }
  }
  None
}

///|
fn find_fstring_expr_close(after_open : String) -> Int? {
  let chars = after_open.to_array()
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace == 0 {
        return Some(i)
      }
      depth_brace -= 1
      continue
    }
  }
  None
}

///|
fn find_top_level_fstring_conversion_bang(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == '!' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      if i + 1 < chars.length() {
        let next = chars[i + 1]
        if next != '=' {
          return Some(i)
        }
      }
    }
  }
  None
}

///|
fn find_top_level_fstring_debug_equal(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == '=' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      let prev = if i > 0 { Some(chars[i - 1]) } else { None }
      let next = if i + 1 < chars.length() { Some(chars[i + 1]) } else { None }
      let prev_is_op = match prev {
        Some('=') | Some('!') | Some('<') | Some('>') => true
        _ => false
      }
      let next_is_eq = match next {
        Some('=') => true
        _ => false
      }
      if !prev_is_op && !next_is_eq {
        return Some(i)
      }
    }
  }
  None
}

///|
fn eq_value(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::None, Value::None) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Int(a), Value::Int(b)) => a == b
    (Value::Float(a), Value::Float(b)) => a == b
    (Value::Str(a), Value::Str(b)) => a == b
    (Value::Bytes(a), Value::Bytes(b))
    | (Value::ByteArray(a), Value::ByteArray(b))
    | (Value::MemoryView(a), Value::MemoryView(b))
    | (Value::Bytes(a), Value::ByteArray(b))
    | (Value::Bytes(a), Value::MemoryView(b))
    | (Value::ByteArray(a), Value::Bytes(b))
    | (Value::ByteArray(a), Value::MemoryView(b))
    | (Value::MemoryView(a), Value::Bytes(b))
    | (Value::MemoryView(a), Value::ByteArray(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if a[i] != b[i] {
            equal = false
            break
          }
        }
        equal
      }
    (Value::List(a), Value::List(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Tuple(a), Value::Tuple(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Set(a), Value::Set(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for item in a {
          let mut found = false
          for other in b {
            if eq_value(item, other) {
              found = true
              break
            }
          }
          if !found {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Dict(a), Value::Dict(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for pair in a {
          let mut found = false
          for other in b {
            if eq_value(pair.0, other.0) && eq_value(pair.1, other.1) {
              found = true
              break
            }
          }
          if !found {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Class(a), Value::Class(b)) => a.name == b.name
    (Value::Instance(a), Value::Instance(b)) => a.class.name == b.class.name
    _ => false
  }
}

///|
fn bigint_to_int_checked(v : @bigint.BigInt) -> Result[Int, RuntimeError] {
  let min : Int = -0x80000000
  let max : Int = 0x7fffffff
  if v.compare_int(min) < 0 || v.compare_int(max) > 0 {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OverflowError: cannot fit 'int' into an index-sized integer".to_string(),
      ),
    )
  } else {
    Ok(v.to_int())
  }
}

///|
fn bigint_to_int64_checked(v : @bigint.BigInt) -> Result[Int64, RuntimeError] {
  let min : Int64 = -0x8000000000000000L
  let max : Int64 = 0x7fffffffffffffffL
  if v.compare_int64(min) < 0 || v.compare_int64(max) > 0 {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OverflowError: int too large to convert to int64".to_string(),
      ),
    )
  } else {
    Ok(v.to_int64())
  }
}

///|
fn bigint_to_double_checked(v : @bigint.BigInt) -> Result[Double, RuntimeError] {
  // CPython-like integer -> float conversion:
  // - exact for <= 53 bits
  // - round to nearest, ties to even
  // - overflow to inf raises OverflowError
  if v == 0N {
    return Ok(0.0)
  }
  let neg = v < 0N
  let abs = if neg { -v } else { v }
  let nbits = abs.bit_length()

  // Fast path: if it fits in 64 bits, rely on IEEE-754 hardware rounding.
  // This matches CPython's round-to-nearest, ties-to-even behavior.
  if nbits <= 64 {
    let u = abs.to_uint64()
    let d = Double::convert_uint64(u)
    return Ok(if neg { -d } else { d })
  }

  // Largest finite double is < 2^1024.
  // If abs >= 2^1024, conversion overflows.
  if nbits > 1024 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OverflowError: int too large to convert to float".to_string(),
      ),
    )
  }

  // Extract the top 53 bits (implicit 1 + 52 mantissa bits), then round.
  let shift = nbits - 53
  let mut top53 = if shift > 0 {
    abs >> shift
  } else if shift < 0 {
    abs << -shift
  } else {
    abs
  }
  let mut exp = nbits - 1
  if shift > 0 {
    let dropped = abs - (top53 << shift)
    let half = 1N << (shift - 1)
    let round_up = if dropped > half {
      true
    } else if dropped < half {
      false
    } else {
      // tie: round to even
      (top53 & 1N) != 0N
    }
    if round_up {
      top53 = top53 + 1N
      // carry out of the 53-bit window
      if top53 == 1N << 53 {
        top53 = top53 >> 1
        exp = exp + 1
        if exp > 1023 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "OverflowError: int too large to convert to float".to_string(),
            ),
          )
        }
      }
    }
  }

  // Build IEEE-754 bits.
  let mantissa_mask = (1N << 52) - 1N
  let mantissa = (top53 & mantissa_mask).to_uint64()
  let exponent_bits : UInt64 = (exp + 1023).to_uint64()
  let sign_bits : UInt64 = if neg { 1UL << 63 } else { 0UL }
  let bits = sign_bits | (exponent_bits << 52) | mantissa
  Ok(bits.reinterpret_as_double())
}

///|
fn number_value(value : Value) -> Result[(Bool, Double), RuntimeError] {
  match value {
    Value::Int(v) =>
      match bigint_to_double_checked(v) {
        Ok(d) => Ok((false, d))
        Err(err) => Err(err)
      }
    Value::Float(v) => Ok((true, v))
    Value::Bool(v) => Ok((false, if v { 1.0 } else { 0.0 }))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "expected number".to_string(),
        ),
      )
  }
}
