///|
/// Expression evaluation for the mpython runtime.
///
/// Most runtime utilities are split into dedicated files:
/// - runtime_value.mbt
/// - runtime_error.mbt
/// - runtime_env.mbt
/// - runtime_assign.mbt
/// - runtime_comprehension.mbt
/// - runtime_pattern.mbt
/// - runtime_block.mbt
/// - interpreter_api.mbt

///|
fn stringify_value_with_env(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  let _ = globals
  let _ = builtins
  let _ = io
  Ok(value_to_string(value))
}

///|
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).to_char().unwrap()
  } else {
    ('a'.to_int() + (n - 10)).to_char().unwrap()
  }
}

///|
fn hex_width(codepoint : Int, width : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < width {
    let shift = 4 * (width - 1 - i)
    let digit = (codepoint >> shift) & 0xF
    buf.write_char(hex_digit(digit))
    i = i + 1
  }
  buf.to_string()
}

///|
fn ascii_escape(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text.to_array() {
    let code = ch.to_int()
    if code < 0x80 {
      buf.write_char(ch)
    } else if code <= 0xFFFF {
      buf.write_string("\\u")
      buf.write_string(hex_width(code, 4))
    } else {
      buf.write_string("\\U")
      buf.write_string(hex_width(code, 8))
    }
  }
  buf.to_string()
}

///|
fn fstring_value_to_text(
  value : Value,
  conv : Char?,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  match conv {
    None => stringify_value_with_env(value, globals, builtins, io)
    Some('s') =>
      match
        eval_builtin_call("str", [value], [], locals, globals, builtins, io) {
        Ok(Some(Value::Str(text))) => Ok(text)
        Ok(Some(other)) => Ok(value_to_string(other))
        Ok(None) => stringify_value_with_env(value, globals, builtins, io)
        Err(err) => Err(err)
      }
    Some('r') =>
      match
        eval_builtin_call("repr", [value], [], locals, globals, builtins, io) {
        Ok(Some(Value::Str(text))) => Ok(text)
        Ok(Some(other)) => Ok(value_to_string(other))
        Ok(None) => stringify_value_with_env(value, globals, builtins, io)
        Err(err) => Err(err)
      }
    Some('a') => {
      let base = match
        eval_builtin_call("repr", [value], [], locals, globals, builtins, io) {
        Ok(Some(Value::Str(text))) => text
        Ok(Some(other)) => value_to_string(other)
        Ok(None) => value_to_string(value)
        Err(err) => return Err(err)
      }
      Ok(ascii_escape(base))
    }
    Some(_) => stringify_value_with_env(value, globals, builtins, io)
  }
}

///|
fn format_string_width(
  text : String,
  spec : String,
  default_align : Char,
) -> String? {
  if spec.length() == 0 {
    return None
  }
  let chars = spec.to_array()
  let mut fill = ' '
  let mut align : Char? = None
  let mut i = 0
  if chars.length() >= 2 &&
    (chars[1] == '<' || chars[1] == '>' || chars[1] == '^') {
    fill = chars[0]
    align = Some(chars[1])
    i = 2
  } else if chars[0] == '<' || chars[0] == '>' || chars[0] == '^' {
    align = Some(chars[0])
    i = 1
  } else if is_digit(chars[0]) {
    align = Some(default_align)
    i = 0
  } else {
    return None
  }
  let start = i
  while i < chars.length() && is_digit(chars[i]) {
    i += 1
  }
  if start == i || i != chars.length() {
    return None
  }
  let width_text = substring(spec, start, i)
  let width = parse_decimal_int(width_text)
  if width <= 0 {
    return Some(text)
  }
  let len = text.length()
  if len >= width {
    return Some(text)
  }
  let pad = width - len
  let left = match align.unwrap_or(default_align) {
    '<' => 0
    '>' => pad
    '^' => pad / 2
    _ => 0
  }
  let right = pad - left
  let buf = StringBuilder::new()
  for i = 0; i < left; i = i + 1 {
    buf.write_char(fill)
  }
  buf.write_string(text)
  for i = 0; i < right; i = i + 1 {
    buf.write_char(fill)
  }
  Some(buf.to_string())
}

///|
fn parse_decimal_int(text : String) -> Int {
  let chars = text.to_array()
  let mut n = 0
  for c in chars {
    if is_digit(c) {
      n = n * 10 + (c.to_int() - 48)
    }
  }
  n
}

///|
fn fstring_int_to_base_string(
  value : @bigint.BigInt,
  base : Int,
  uppercase : Bool,
) -> String {
  if value == 0N {
    return "0"
  }
  let digits_table : Array[Char] = "0123456789abcdef".to_array()
  let upper_table : Array[Char] = "0123456789ABCDEF".to_array()
  let table = if uppercase { upper_table } else { digits_table }
  let mut n = value
  let b = @bigint.BigInt::from_int(base)
  let digits : Array[Char] = []
  while n > 0N {
    let d = (n % b).to_int()
    digits.push(table[d])
    n = n / b
  }
  let buf = StringBuilder::new()
  let mut i = digits.length()
  while i > 0 {
    i = i - 1
    buf.write_char(digits[i])
  }
  buf.to_string()
}

///|
fn format_int_with_spec(value : @bigint.BigInt, spec : String) -> String? {
  if spec.length() == 0 {
    return None
  }
  let chars = spec.to_array()
  let mut i = 0
  let mut alternate = false
  if chars[0] == '#' {
    alternate = true
    i = 1
  }
  let mut zero_pad = false
  if i < chars.length() && chars[i] == '0' {
    zero_pad = true
    i += 1
  }
  let width_start = i
  while i < chars.length() && is_digit(chars[i]) {
    i += 1
  }
  let width = if i > width_start {
    parse_decimal_int(substring(spec, width_start, i))
  } else {
    0
  }
  if i >= chars.length() {
    return None
  }
  let typ = chars[i]
  if i + 1 != chars.length() {
    return None
  }
  let neg = value < 0N
  let abs_value = if neg { -value } else { value }
  let (prefix, base, uppercase, decimal) = match typ {
    'd' => ("", 10, false, true)
    'x' => ("0x", 16, false, false)
    'X' => ("0X", 16, true, false)
    'o' => ("0o", 8, false, false)
    'b' => ("0b", 2, false, false)
    _ => return None
  }
  let digits = if decimal {
    abs_value.to_string()
  } else {
    fstring_int_to_base_string(abs_value, base, uppercase)
  }
  let sign = if neg { "-" } else { "" }
  let alt_prefix = if alternate && !decimal { prefix } else { "" }
  let mut core = sign.to_string() + alt_prefix + digits
  if width > 0 && core.length() < width {
    let pad = width - core.length()
    if zero_pad {
      let buf = StringBuilder::new()
      buf.write_string(sign)
      buf.write_string(alt_prefix)
      for i = 0; i < pad; i = i + 1 {
        buf.write_char('0')
      }
      buf.write_string(digits)
      core = buf.to_string()
    } else {
      let buf = StringBuilder::new()
      for i = 0; i < pad; i = i + 1 {
        buf.write_char(' ')
      }
      buf.write_string(core)
      core = buf.to_string()
    }
  }
  Some(core)
}

///|
fn eval_fstring_text(
  text : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  let buf = StringBuilder::new()
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '{' {
      if i + 1 < chars.length() && chars[i + 1] == '{' {
        buf.write_char('{')
        i += 2
        continue
      }
      let after_open = substring(text, i + 1, text.length())
      let close_rel = find_fstring_expr_close(after_open)
      if close_rel is None {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: f-string: expecting '}'".to_string(),
          ),
        )
      }
      let close = i + 1 + close_rel.unwrap()
      let inner = substring(text, i + 1, close)
      if inner.trim(chars=" \t").length() == 0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: f-string: empty expression not allowed".to_string(),
          ),
        )
      }
      let (expr_and_conv, format_spec_raw) = match
        find_top_level_format_colon(inner) {
        Some(pos) =>
          (substring(inner, 0, pos), substring(inner, pos + 1, inner.length()))
        None => (inner, "".to_string())
      }
      let (expr_raw, conv) = match
        find_top_level_fstring_conversion_bang(expr_and_conv) {
        Some(pos) =>
          if pos + 1 < expr_and_conv.length() {
            let conv_char = expr_and_conv.to_array()[pos + 1]
            (substring(expr_and_conv, 0, pos), Some(conv_char))
          } else {
            (expr_and_conv, None)
          }
        None => (expr_and_conv, None)
      }
      let debug_eq = find_top_level_fstring_debug_equal(expr_raw)
      let (expr_text, debug_prefix) = match debug_eq {
        Some(pos) => {
          let mut prefix_end = pos + 1
          let expr_chars = expr_raw.to_array()
          while prefix_end < expr_chars.length() {
            let c = expr_chars[prefix_end]
            if c == ' ' || c == '\t' {
              prefix_end += 1
            } else {
              break
            }
          }
          (
            substring(expr_raw, 0, pos).trim(chars=" \t").to_string(),
            Some(substring(expr_raw, 0, prefix_end)),
          )
        }
        None => (expr_raw.trim(chars=" \t").to_string(), None)
      }
      let expr = match parse_expr(expr_text) {
        Ok(value) => value
        Err(_) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: f-string: invalid syntax".to_string(),
            ),
          )
      }
      let value = match
        eval_expr_with_env(expr, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let rendered = match
        fstring_value_to_text(value, conv, locals, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let format_spec = if format_spec_raw.trim(chars=" \t").length() == 0 {
        "".to_string()
      } else if format_spec_raw.contains("{") || format_spec_raw.contains("}") {
        match
          eval_fstring_text(format_spec_raw, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
      } else {
        format_spec_raw
      }
      let formatted = if format_spec.length() == 0 {
        rendered
      } else {
        match conv {
          Some(_) =>
            match format_string_width(rendered, format_spec, '<') {
              Some(v) => v
              None => rendered
            }
          None =>
            match value {
              Value::Int(n) =>
                match format_int_with_spec(n, format_spec) {
                  Some(v) => v
                  None =>
                    match format_string_width(rendered, format_spec, '>') {
                      Some(v) => v
                      None => rendered
                    }
                }
              _ =>
                match format_string_width(rendered, format_spec, '<') {
                  Some(v) => v
                  None => rendered
                }
            }
        }
      }
      match debug_prefix {
        Some(prefix) => {
          buf.write_string(prefix)
          buf.write_string(formatted)
        }
        None => buf.write_string(formatted)
      }
      i = close + 1
      continue
    }
    if c == '}' {
      if i + 1 < chars.length() && chars[i + 1] == '}' {
        buf.write_char('}')
        i += 2
        continue
      }
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: f-string: single '}' is not allowed".to_string(),
        ),
      )
    }
    buf.write_char(c)
    i += 1
  }
  Ok(buf.to_string())
}

///|
fn bytes_subsequence_contains(
  haystack : Array[Int],
  needle : Array[Int],
) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  let limit = haystack.length() - needle.length()
  let mut i = 0
  while i <= limit {
    let mut matched = true
    let mut j = 0
    while j < needle.length() {
      if haystack[i + j] != needle[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn bytes_contains(haystack : Array[Int], needle : Value) -> Bool {
  match needle {
    Value::Int(v) => {
      let idx = match bigint_to_int_checked(v) {
        Ok(value) => value
        Err(_) => return false
      }
      if idx < 0 || idx > 255 {
        return false
      }
      for byte in haystack {
        if byte == idx {
          return true
        }
      }
      false
    }
    Value::Bool(v) => {
      let idx = if v { 1 } else { 0 }
      for byte in haystack {
        if byte == idx {
          return true
        }
      }
      false
    }
    Value::Bytes(values)
    | Value::ByteArray(values)
    | Value::MemoryView(values) => bytes_subsequence_contains(haystack, values)
    _ => false
  }
}

///|
fn to_complex(value : Value) -> Result[(Double, Double), RuntimeError] {
  match value {
    Value::Complex(real, imag) => Ok((real, imag))
    Value::Float(v) => Ok((v, 0.0))
    Value::Int(v) =>
      match bigint_to_double_checked(v) {
        Ok(value) => Ok((value, 0.0))
        Err(err) => Err(err)
      }
    Value::Bool(v) => Ok((if v { 1.0 } else { 0.0 }, 0.0))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "expected number".to_string(),
        ),
      )
  }
}

///|
fn value_repr_for_format(value : Value) -> String {
  match value {
    Value::Str(text) => "\"" + escape_string_for_repr(text) + "\""
    other => value_to_string(other)
  }
}

///|
fn pad_left(text : String, width : Int, pad_char : Char) -> String {
  if width <= text.length() {
    text
  } else {
    let buf = StringBuilder::new()
    let pad_len = width - text.length()
    for _i = 0; _i < pad_len; _i = _i + 1 {
      buf.write_char(pad_char)
    }
    buf.write_string(text)
    buf.to_string()
  }
}

///|
fn pad_numeric(text : String, width : Int, zero_pad : Bool) -> String {
  if !zero_pad {
    return pad_left(text, width, ' ')
  }
  if width <= text.length() {
    return text
  }
  match text.get_char(0) {
    Some('-') => {
      let chars = text.to_array()
      let rest_chars : Array[Char] = []
      for idx = 1; idx < chars.length(); idx = idx + 1 {
        rest_chars.push(chars[idx])
      }
      let rest = String::from_array(rest_chars)
      let pad_len = width - rest.length() - 1
      if pad_len <= 0 {
        text
      } else {
        let buf = StringBuilder::new()
        buf.write_char('-')
        for _i = 0; _i < pad_len; _i = _i + 1 {
          buf.write_char('0')
        }
        buf.write_string(rest)
        buf.to_string()
      }
    }
    _ => pad_left(text, width, '0')
  }
}

///|
fn format_decimal_value(value : Value) -> Result[String, RuntimeError] {
  match value {
    Value::Int(v) => Ok(v.to_string())
    Value::Bool(v) => Ok(if v { "1" } else { "0" })
    Value::Float(v) => Ok(v.to_int64().to_string())
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "expected number".to_string(),
        ),
      )
  }
}

///|
fn format_hex_value(
  value : Value,
  uppercase : Bool,
) -> Result[String, RuntimeError] {
  match value {
    Value::Int(v) => {
      let neg = v < 0N
      let abs_value = if neg { -v } else { v }
      let mut out = abs_value.to_hex(uppercase=uppercase)
      if neg {
        out = "-" + out
      }
      Ok(out)
    }
    Value::Bool(v) => Ok(if v { "1" } else { "0" })
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "expected number".to_string(),
        ),
      )
  }
}

///|
fn format_percent_string(
  format : String,
  value : Value,
) -> Result[String, RuntimeError] {
  let args = match value {
    Value::Tuple(values) => values
    _ => [value]
  }
  let buf = StringBuilder::new()
  let chars = format.to_array()
  let mut arg_index = 0
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch != '%' {
      buf.write_char(ch)
      i = i + 1
      continue
    }
    if i + 1 >= chars.length() {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "incomplete format".to_string(),
        ),
      )
    }
    if chars[i + 1] == '%' {
      buf.write_char('%')
      i = i + 2
      continue
    }
    let mut j = i + 1
    let mut zero_pad = false
    if chars[j] == '0' {
      zero_pad = true
      j = j + 1
    }
    let mut width = 0
    while j < chars.length() && chars[j].is_ascii_digit() {
      width = width * 10 + (chars[j].to_int() - '0'.to_int())
      j = j + 1
    }
    if j >= chars.length() {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "incomplete format".to_string(),
        ),
      )
    }
    if arg_index >= args.length() {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "not enough arguments for format string".to_string(),
        ),
      )
    }
    let arg = args[arg_index]
    arg_index = arg_index + 1
    let spec = chars[j]
    let raw = match spec {
      's' => Ok(value_to_string(arg))
      'r' => Ok(value_repr_for_format(arg))
      'd' | 'i' => format_decimal_value(arg)
      'x' => format_hex_value(arg, false)
      'X' => format_hex_value(arg, true)
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "unsupported format character".to_string(),
          ),
        )
    }
    let formatted = match raw {
      Ok(text) => {
        match spec {
          'd' | 'i' | 'x' | 'X' => pad_numeric(text, width, zero_pad)
          _ =>
            pad_left(
              text,
              width,
              if zero_pad { '0' } else { ' ' },
            )
        }
      }
      Err(err) => return Err(err)
    }
    buf.write_string(formatted)
    i = j + 1
  }
  if arg_index < args.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "not all arguments converted during string formatting".to_string(),
      ),
    )
  }
  Ok(buf.to_string())
}

///|
fn is_generic_alias_origin_name(name : String) -> Bool {
  match name {
    "list" |
    "dict" |
    "tuple" |
    "set" |
    "frozenset" |
    "type" => true
    _ => false
  }
}

///|
fn union_args_from_value(
  value : Value,
  builtins : Array[(String, Value)],
) -> Array[Value]? {
  match value {
    Value::Class(_) => Some([value])
    Value::Function(func) =>
      if func.body.length() == 0 && is_builtin_class_name(func.name) {
        Some([Value::Class(builtin_class_from_name(func.name, builtins))])
      } else {
        None
      }
    Value::Instance(inst) =>
      if inst.class.name == "UnionType" {
        match get_named_value(inst.dict, "__args__") {
          Some(Value::Tuple(values)) => Some(values)
          _ => Some([value])
        }
      } else if inst.class.name == "GenericAlias" {
        Some([value])
      } else {
        None
      }
    Value::None =>
      Some(
        [
          Value::Class(
            ClassValue::{ name: "NoneType", bases: [], dict: [] },
          ),
        ],
      )
    _ => None
  }
}

///|
fn eval_binary_op_values(
  op : BinaryOp,
  left_val : Value,
  right_val : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match op {
    BinaryOp::Add =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) =>
          Ok(Value::Complex(ar + br, ai + bi))
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar + br, ai + bi))
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar + br, ai + bi))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
        (Value::Int(a), Value::Float(b)) => {
          let aa = match bigint_to_double_checked(a) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(aa + b))
        }
        (Value::Float(a), Value::Int(b)) => {
          let bb = match bigint_to_double_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(a + bb))
        }
        (Value::Str(a), Value::Str(b)) => Ok(Value::Str(a + b))
        (Value::Bytes(a), Value::Bytes(b)) => {
          let merged : Array[Int] = []
          for item in a {
            merged.push(item)
          }
          for item in b {
            merged.push(item)
          }
          Ok(Value::Bytes(merged))
        }
        (Value::ByteArray(a), Value::ByteArray(b)) => {
          let merged : Array[Int] = []
          for item in a {
            merged.push(item)
          }
          for item in b {
            merged.push(item)
          }
          Ok(Value::ByteArray(merged))
        }
        (Value::List(a), Value::List(b)) => {
          let merged : Array[Value] = []
          for item in a {
            merged.push(item)
          }
          for item in b {
            merged.push(item)
          }
          Ok(Value::List(merged))
        }
        _ => {
          if left_val is Value::Instance(_) {
            match
              get_attr_from_value(left_val, "__add__", globals, builtins, io) {
              Ok(add_method) =>
                return call_callable_with_env(
                  add_method,
                  [right_val],
                  [],
                  globals,
                  builtins,
                  io,
                )
              Err(_) => ()
            }
          }
          if right_val is Value::Instance(_) {
            match
              get_attr_from_value(right_val, "__radd__", globals, builtins, io) {
              Ok(radd_method) =>
                return call_callable_with_env(
                  radd_method,
                  [left_val],
                  [],
                  globals,
                  builtins,
                  io,
                )
              Err(_) => ()
            }
          }
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for +".to_string(),
            ),
          )
        }
      }
    BinaryOp::Sub =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) =>
          Ok(Value::Complex(ar - br, ai - bi))
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar - br, ai - bi))
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar - br, ai - bi))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a - b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a - b))
        (Value::Int(a), Value::Float(b)) => {
          let aa = match bigint_to_double_checked(a) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(aa - b))
        }
        (Value::Float(a), Value::Int(b)) => {
          let bb = match bigint_to_double_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(a - bb))
        }
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) - (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) - b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a - (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Float(b)) =>
          Ok(Value::Float((if a { 1.0 } else { 0.0 }) - b))
        (Value::Float(a), Value::Bool(b)) =>
          Ok(Value::Float(a - (if b { 1.0 } else { 0.0 })))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for -".to_string(),
            ),
          )
      }
    BinaryOp::Mul =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) =>
          Ok(Value::Complex(ar * br - ai * bi, ar * bi + ai * br))
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar * br - ai * bi, ar * bi + ai * br))
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar * br - ai * bi, ar * bi + ai * br))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a * b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a * b))
        (Value::Int(a), Value::Float(b)) => {
          let aa = match bigint_to_double_checked(a) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(aa * b))
        }
        (Value::Float(a), Value::Int(b)) => {
          let bb = match bigint_to_double_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(a * bb))
        }
        (Value::Str(text), Value::Int(count))
        | (Value::Int(count), Value::Str(text)) =>
          if count <= 0N {
            Ok(Value::Str(""))
          } else {
            let buf = StringBuilder::new()
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for i = 0; i < count_i; i = i + 1 {
              buf.write_string(text)
            }
            Ok(Value::Str(buf.to_string()))
          }
        (Value::Bytes(bytes), Value::Int(count))
        | (Value::Int(count), Value::Bytes(bytes)) =>
          if count <= 0N {
            Ok(Value::Bytes([]))
          } else {
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let out : Array[Int] = []
            for i = 0; i < count_i; i = i + 1 {
              for byte in bytes {
                out.push(byte)
              }
            }
            Ok(Value::Bytes(out))
          }
        (Value::ByteArray(bytes), Value::Int(count))
        | (Value::Int(count), Value::ByteArray(bytes)) =>
          if count <= 0N {
            Ok(Value::ByteArray([]))
          } else {
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let out : Array[Int] = []
            for i = 0; i < count_i; i = i + 1 {
              for byte in bytes {
                out.push(byte)
              }
            }
            Ok(Value::ByteArray(out))
          }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for *".to_string(),
            ),
          )
      }
    BinaryOp::Div =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) => {
          let denom = br * br + bi * bi
          if denom == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(
            Value::Complex(
              (ar * br + ai * bi) / denom,
              (ai * br - ar * bi) / denom,
            ),
          )
        }
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let denom = br * br + bi * bi
          if denom == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(
            Value::Complex(
              (ar * br + ai * bi) / denom,
              (ai * br - ar * bi) / denom,
            ),
          )
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let denom = br * br + bi * bi
          if denom == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(
            Value::Complex(
              (ar * br + ai * bi) / denom,
              (ai * br - ar * bi) / denom,
            ),
          )
        }
        _ => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if right_num == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(Value::Float(left_num / right_num))
        }
      }
    BinaryOp::FloorDiv =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => {
          if b == 0N {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "integer division or modulo by zero".to_string(),
              ),
            )
          }
          let q0 = a / b
          let r0 = a % b
          let q = if r0 != 0N && (r0 < 0N) != (b < 0N) { q0 - 1N } else { q0 }
          Ok(Value::Int(q))
        }
        (Value::Bool(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::FloorDiv,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        (Value::Bool(a), Value::Int(b)) =>
          eval_binary_op_values(
            BinaryOp::FloorDiv,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(b),
            globals,
            builtins,
            io,
          )
        (Value::Int(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::FloorDiv,
            Value::Int(a),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        _ => {
          let (left_is_float, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (right_is_float, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if right_num == 0.0 {
            let msg = if left_is_float || right_is_float {
              "float floor division by zero".to_string()
            } else {
              "integer division or modulo by zero".to_string()
            }
            return Err(make_runtime_error(RuntimeErrorKind::ZeroDivision, msg))
          }
          Ok(Value::Float((left_num / right_num).floor()))
        }
      }
    BinaryOp::Mod =>
      match (left_val, right_val) {
        (Value::Str(format), value) => {
          let formatted = match format_percent_string(format, value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Str(formatted))
        }
        (Value::Int(a), Value::Int(b)) => {
          if b == 0N {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "integer modulo by zero".to_string(),
              ),
            )
          }
          let r0 = a % b
          let needs_adjust = r0 != 0N && (r0 < 0N) != (b < 0N)
          let r = if needs_adjust { r0 + b } else { r0 }
          Ok(Value::Int(r))
        }
        (Value::Bool(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::Mod,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        (Value::Bool(a), Value::Int(b)) =>
          eval_binary_op_values(
            BinaryOp::Mod,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(b),
            globals,
            builtins,
            io,
          )
        (Value::Int(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::Mod,
            Value::Int(a),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        _ => {
          let (left_is_float, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (right_is_float, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if right_num == 0.0 {
            let msg = if left_is_float || right_is_float {
              "float modulo".to_string()
            } else {
              "integer modulo by zero".to_string()
            }
            return Err(make_runtime_error(RuntimeErrorKind::ZeroDivision, msg))
          }
          Ok(Value::Float(left_num % right_num))
        }
      }
    BinaryOp::Pow =>
      match (left_val, right_val) {
        (Value::Int(left), Value::Int(right)) =>
          if right < 0N {
            Ok(
              Value::Float(
                @math.pow(
                  match bigint_to_double_checked(left) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  },
                  match bigint_to_double_checked(right) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  },
                ),
              ),
            )
          } else {
            Ok(Value::Int(left.pow(right)))
          }
        _ => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Float(@math.pow(left_num, right_num)))
        }
      }
    BinaryOp::MatMul =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "unsupported operand type for @".to_string(),
        ),
      )
    BinaryOp::ShiftLeft =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int(a << bb))
        }
        (Value::Bool(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int((if a { 1N } else { 0N }) << bb))
        }
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a << (if b { 1 } else { 0 })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) << (if b { 1 } else { 0 })))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for <<".to_string(),
            ),
          )
      }
    BinaryOp::ShiftRight =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int(a >> bb))
        }
        (Value::Bool(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int((if a { 1N } else { 0N }) >> bb))
        }
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a >> (if b { 1 } else { 0 })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) >> (if b { 1 } else { 0 })))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for >>".to_string(),
            ),
          )
      }
    BinaryOp::BitAnd =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a & b))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) & b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a & (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) & (if b { 1N } else { 0N })))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for &".to_string(),
            ),
          )
      }
    BinaryOp::BitXor =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a ^ b))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) ^ b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a ^ (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) ^ (if b { 1N } else { 0N })))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for ^".to_string(),
            ),
          )
      }
    BinaryOp::BitOr =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a | b))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) | b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a | (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) | (if b { 1N } else { 0N })))
        (Value::Set(left), Value::Set(right)) => {
          let values : Array[Value] = []
          for item in left {
            let _ = match set_add_unique(values, item) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
          }
          for item in right {
            let _ = match set_add_unique(values, item) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
          }
          Ok(Value::Set(values))
        }
        _ => {
          let left_args = union_args_from_value(left_val, builtins)
          let right_args = union_args_from_value(right_val, builtins)
          match (left_args, right_args) {
            (Some(left), Some(right)) => {
              let args : Array[Value] = []
              for value in left {
                args.push(value)
              }
              for value in right {
                args.push(value)
              }
              Ok(make_union_type(args))
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for |".to_string(),
                ),
              )
          }
        }
      }
  }
}

///|
fn lookup_name_value(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Result[Value, RuntimeError] {
  fn read_local_cell() -> Result[Value, RuntimeError] {
    match get_local_value(locals, name) {
      Some(v) =>
        if is_cell_value(v) {
          match cell_get_value(v) {
            Some(value) => Ok(value)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "UnboundLocalError: local variable '" +
                  name +
                  "' referenced before assignment",
                ),
              )
          }
        } else {
          Ok(v)
        }
      None =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
    }
  }

  fn read_closure_cell(cell : Value) -> Result[Value, RuntimeError] {
    match cell_get_value(cell) {
      Some(value) => Ok(value)
      None =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "free variable '" +
            name +
            "' referenced before assignment in enclosing scope",
          ),
        )
    }
  }

  if scope_name_is_global(name) {
    match get_global_value(globals, name) {
      Some(v) => Ok(v)
      None =>
        match get_global_value(builtins, name) {
          Some(v) => Ok(v)
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Name,
                "name '" + name + "' is not defined",
              ),
            )
        }
    }
  } else if scope_name_is_nonlocal(name) {
    match lookup_closure_cell(name) {
      Some(cell) => read_closure_cell(cell)
      None =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
    }
  } else {
    match get_local_value(locals, name) {
      Some(_) => read_local_cell()
      None =>
        match lookup_closure_cell(name) {
          Some(cell) => read_closure_cell(cell)
          None =>
            match get_global_value(globals, name) {
              Some(v) => Ok(v)
              None =>
                match get_global_value(builtins, name) {
                  Some(v) => Ok(v)
                  None =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Name,
                        "name '" + name + "' is not defined",
                      ),
                    )
                }
            }
        }
    }
  }
}

///|
fn eval_expr_with_env(
  expr : Expr,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match expr {
    Expr::Literal(literal) =>
      match literal {
        Literal::None => Ok(Value::None)
        Literal::Bool(value) => Ok(Value::Bool(value))
        Literal::Int(value) => Ok(Value::Int(value))
        Literal::Float(value) => Ok(Value::Float(value))
        Literal::Complex(real, imag) => Ok(Value::Complex(real, imag))
        Literal::Str(value) => Ok(Value::Str(value))
      }
    Expr::Name(name) => lookup_name_value(name, locals, globals, builtins)
    Expr::FString(text) =>
      match eval_fstring_text(text, locals, globals, builtins, io) {
        Ok(value) => Ok(Value::Str(value))
        Err(err) => Err(err)
      }
    Expr::NamedExpr(name~, value~) => {
      let evaluated = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      set_scoped_value(locals, globals, name, evaluated)
      Ok(evaluated)
    }
    Expr::Await(expr) =>
      if !coroutine_is_active() {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'await' outside async function".to_string(),
          ),
        )
      } else {
        let awaitable = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match awaitable {
          Value::Instance(inst) =>
            if inst.class.name == "coroutine" {
              coroutine_await(awaitable)
            } else {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "'" +
                  type_name_from_value(awaitable) +
                  "' object can't be used in 'await' expression",
                ),
              )
            }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" +
                type_name_from_value(awaitable) +
                "' object can't be used in 'await' expression",
              ),
            )
        }
      }
    Expr::Yield(_) | Expr::YieldFrom(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: 'yield' outside function".to_string(),
        ),
      )
    Expr::List(items) => {
      let values : Array[Value] = []
      for item in items {
        match item {
          Expr::Starred(value~) => {
            let iter_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let items = match iterable_values(iter_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for v in items {
              values.push(v)
            }
          }
          _ => {
            let value = match
              eval_expr_with_env(item, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            values.push(value)
          }
        }
      }
      Ok(Value::List(values))
    }
    Expr::ListComp(elt~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async && !coroutine_is_active() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
        )
      }
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[CompClause] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
      }
      let clauses = if clauses.length() > 0 {
        adjusted_clauses
      } else {
        clauses
      }
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
          }
        }
      }
      let values : Array[Value] = []
      let _ = match
        eval_list_comp_walk(
          0, elt, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Ok(Value::List(values))
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      let gen_locals = clone_locals(locals)
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
        }
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(gen_locals, name, Value::None)
          }
        }
      }
      if has_async {
        if !coroutine_is_active() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: 'async for' outside async function".to_string(),
            ),
          )
        }
        if clauses.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: invalid async generator expression".to_string(),
            ),
          )
        }
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let first_iterator = if clauses[0].is_async {
          let aiter_value = match
            get_attr_from_value(
              first_iter_value, "__aiter__", globals, builtins, io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match
            call_callable_with_env(aiter_value, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        } else {
          match
            iter_value_to_iterator(first_iter_value, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        }
        let iter_name = fresh_genexp_local(gen_locals)
        set_local_value(gen_locals, iter_name, first_iterator)
        let adjusted_clauses : Array[CompClause] = []
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
        return Ok(
          async_genexp_new(
            elt, adjusted_clauses, filters, gen_locals, globals, builtins, io,
          ),
        )
      }
      if clauses.length() == 0 {
        let body = genexp_to_generator_body(elt, clauses, filters)
        let filename = current_traceback_filename()
        return Ok(
          generator_new(
            body,
            gen_locals,
            globals,
            builtins,
            io,
            [],
            [],
            [],
            "<genexpr>".to_string(),
            filename,
          ),
        )
      }
      let first_iter_value = match
        eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let first_iterator = match
        iter_value_to_iterator(first_iter_value, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_name = fresh_genexp_local(gen_locals)
      set_local_value(gen_locals, iter_name, first_iterator)
      let adjusted_clauses : Array[CompClause] = []
      adjusted_clauses.push(CompClause::{
        is_async: false,
        targets: clauses[0].targets,
        iter: Expr::Name(iter_name),
      })
      for i = 1; i < clauses.length(); i = i + 1 {
        adjusted_clauses.push(clauses[i])
      }
      let body = genexp_to_generator_body(elt, adjusted_clauses, filters)
      let filename = current_traceback_filename()
      Ok(
        generator_new(
          body,
          gen_locals,
          globals,
          builtins,
          io,
          [],
          [],
          [],
          "<genexpr>".to_string(),
          filename,
        ),
      )
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async && !coroutine_is_active() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
        )
      }
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[CompClause] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
      }
      let clauses = if clauses.length() > 0 {
        adjusted_clauses
      } else {
        clauses
      }
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
          }
        }
      }
      let values : Array[Value] = []
      let _ = match
        eval_list_comp_walk(
          0, elt, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let unique : Array[Value] = []
      for item in values {
        let _ = match set_add_unique(unique, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }

      }
      Ok(Value::Set(unique))
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async && !coroutine_is_active() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
        )
      }
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[CompClause] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
      }
      let clauses = if clauses.length() > 0 {
        adjusted_clauses
      } else {
        clauses
      }
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
          }
        }
      }
      let values : Array[(Value, Value)] = []
      let _ = match
        eval_dict_comp_walk(
          0, key, value, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Ok(Value::Dict(values))
    }
    Expr::Dict(items) => {
      let values : Array[(Value, Value)] = []
      fn set_pair(
        pairs : Array[(Value, Value)],
        key : Value,
        value : Value,
      ) -> Result[Unit, RuntimeError] {
        match dict_set_item(pairs, key, value) {
          Ok(v) => Ok(v)
          Err(err) => Err(err)
        }
      }

      for item in items {
        match item.0 {
          Expr::DoubleStarred(value~) => {
            let mapping = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match mapping {
              Value::Dict(pairs) =>
                for pair in pairs {
                  let _ = match set_pair(values, pair.0, pair.1) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }

                }
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "dict update sequence element has wrong length".to_string(),
                  ),
                )
            }
          }
          _ => {
            let key = match
              eval_expr_with_env(item.0, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let value = match
              eval_expr_with_env(item.1, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = match set_pair(values, key, value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
        }
      }
      Ok(Value::Dict(values))
    }
    Expr::Set(items) => {
      let values : Array[Value] = []
      for item in items {
        match item {
          Expr::Starred(value~) => {
            let iter_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let items = match iterable_values(iter_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for value in items {
              let _ = match set_add_unique(values, value) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }

            }
          }
          _ => {
            let value = match
              eval_expr_with_env(item, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = match set_add_unique(values, value) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }

          }
        }
      }
      Ok(Value::Set(values))
    }
    Expr::Tuple(items) => {
      let values : Array[Value] = []
      for item in items {
        match item {
          Expr::Starred(value~) => {
            let iter_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let items = match iterable_values(iter_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for v in items {
              values.push(v)
            }
          }
          _ => {
            let value = match
              eval_expr_with_env(item, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            values.push(value)
          }
        }
      }
      Ok(Value::Tuple(values))
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let default_values : Array[Value] = []
      for expr in defaults {
        let value = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        default_values.push(value)
      }
      let is_generator = match body {
        Expr::Yield(_) | Expr::YieldFrom(_) => true
        _ => false
      }
      let func_body : Array[Stmt] =
        if is_generator {
          [Stmt::ExprStmt(body)]
        } else {
          [Stmt::Return(Some(body))]
        }
      let closure = capture_cell_closure(locals)
      let globals_marker = Value::Instance(InstanceValue::{
        class: ClassValue::{ name: "__mpython_globals__", bases: [], dict: [] },
        dict: globals,
      })
      closure.push(("$__mpython_globals__", globals_marker))
      Ok(
        Value::Function(FunctionValue::{
          name: "<lambda>",
          params,
          defaults: default_values,
          body: func_body,
          is_generator,
          is_async: false,
          closure,
        }),
      )
    }
    Expr::Attribute(value~, attr~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if attr == "__class__" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: unsupported value".to_string(),
          ),
        )
      }
      match target {
        Value::None
        | Value::Instance(_)
        | Value::Class(_)
        | Value::Str(_)
        | Value::List(_)
        | Value::Tuple(_)
        | Value::Dict(_)
        | Value::Set(_)
        | Value::Function(_) =>
          get_attr_from_value(target, attr, globals, builtins, io)
        _ =>
          match (target, attr) {
            (Value::Str(text), "upper") => Ok(Value::Str(text.to_upper()))
            (Value::Int(_), "__hash__") =>
              Ok(
                Value::Function(FunctionValue::{
                  name: "__hash__",
                  params: [],
                  defaults: [],
                  body: [],
                  is_generator: false,
                  is_async: false,
                  closure: [],
                }),
              )
            (Value::Function(_), "__hash__") =>
              Ok(
                Value::Function(FunctionValue::{
                  name: "__hash__",
                  params: [],
                  defaults: [],
                  body: [],
                  is_generator: false,
                  is_async: false,
                  closure: [],
                }),
              )
            (Value::Function(func), "__doc__") =>
              if func.body.length() > 0 {
                let first_stmt = match func.body[0] {
                  Stmt::WithSpan(span=_, stmt=inner) => inner
                  stmt => stmt
                }
                match first_stmt {
                  Stmt::ExprStmt(Expr::Literal(Literal::Str(text))) =>
                    Ok(Value::Str(text))
                  _ => Ok(Value::None)
                }
              } else {
                Ok(Value::None)
              }
            (Value::Function(func), "__name__") => Ok(Value::Str(func.name))
            (Value::Function(func), "__qualname__") => Ok(Value::Str(func.name))
            (Value::Function(_), "__code__") => Ok(Value::Str("<code>"))
            _ => {
              let type_name = match target {
                Value::Str(text) =>
                  if text == "<code>" {
                    "code"
                  } else {
                    "str"
                  }
                _ => type_name_from_value(target)
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "'" + type_name + "' object has no attribute '" + attr + "'",
                ),
              )
            }
          }
      }
    }
    Expr::Subscript(value~, index~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match index {
        Expr::Slice(start~, end~, step~) => {
          let start_value = match start {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          let end_value = match end {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          let step_value = match step {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          fn slice_list(values : Array[Value]) -> Result[Value, RuntimeError] {
            let indices = match
              slice_indices_from_values(
                values.length(),
                start_value,
                end_value,
                step_value,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            Ok(Value::List(slice_values_by_indices(values, indices)))
          }
          match target {
            Value::List(values) => slice_list(values)
            Value::Instance(inst) =>
              match get_named_value(inst.dict, list_storage_name) {
                Some(Value::List(values)) => slice_list(values)
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "subscript requires sequence".to_string(),
                    ),
                  )
              }
            Value::Tuple(values) => {
              let indices = match
                slice_indices_from_values(
                  values.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Tuple(slice_values_by_indices(values, indices)))
            }
            Value::Str(text) => {
              let chars = text.to_array()
              let indices = match
                slice_indices_from_values(
                  chars.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Str(slice_string_by_indices(chars, indices)))
            }
            Value::Bytes(bytes) => {
              let indices = match
                slice_indices_from_values(
                  bytes.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Bytes(slice_ints_by_indices(bytes, indices)))
            }
            Value::ByteArray(bytes) => {
              let indices = match
                slice_indices_from_values(
                  bytes.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::ByteArray(slice_ints_by_indices(bytes, indices)))
            }
            Value::MemoryView(bytes) => {
              let indices = match
                slice_indices_from_values(
                  bytes.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::MemoryView(slice_ints_by_indices(bytes, indices)))
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "subscript requires sequence".to_string(),
                ),
              )
          }
        }
        _ => {
          let idx_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match target {
            Value::Function(func) =>
              if func.body.length() == 0 &&
                is_generic_alias_origin_name(func.name) {
                let args = match idx_value {
                  Value::Tuple(values) => values
                  _ => [idx_value]
                }
                return Ok(
                  make_generic_alias(
                    Value::Class(builtin_class_from_name(func.name, builtins)),
                    args,
                  ),
                )
              }
            Value::Class(klass) =>
              if is_generic_alias_origin_name(klass.name) {
                let args = match idx_value {
                  Value::Tuple(values) => values
                  _ => [idx_value]
                }
                return Ok(
                  make_generic_alias(Value::Class(klass), args),
                )
              }
            _ => ()
          }
          match target {
            Value::Class(_) | Value::Function(_) =>
              match
                get_attr_from_value(
                  target,
                  "__class_getitem__",
                  globals,
                  builtins,
                  io,
                ) {
                Ok(class_getitem) => {
                  let args = match class_getitem {
                    Value::BoundMethod(_) => [idx_value]
                    Value::Function(_) => [target, idx_value]
                    _ => [idx_value]
                  }
                  return call_callable_with_env(
                    class_getitem,
                    args,
                    [],
                    globals,
                    builtins,
                    io,
                  )
                }
                Err(_) => ()
              }
            _ => ()
          }
          match idx_value {
            Value::Instance(inst) =>
              if inst.class.name == "slice" {
                let start_value = match get_named_value(inst.dict, "start") {
                  Some(v) => v
                  None => Value::None
                }
                let end_value = match get_named_value(inst.dict, "stop") {
                  Some(v) => v
                  None => Value::None
                }
                let step_value = match get_named_value(inst.dict, "step") {
                  Some(v) => v
                  None => Value::None
                }
                fn slice_list(values : Array[Value]) -> Result[Value, RuntimeError] {
                  let indices = match
                    slice_indices_from_values(
                      values.length(),
                      start_value,
                      end_value,
                      step_value,
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  Ok(Value::List(slice_values_by_indices(values, indices)))
                }
                return match target {
                  Value::List(values) => slice_list(values)
                  Value::Instance(list_inst) =>
                    match get_named_value(list_inst.dict, list_storage_name) {
                      Some(Value::List(values)) => slice_list(values)
                      _ =>
                        Err(
                          make_runtime_error(
                            RuntimeErrorKind::Type,
                            "subscript requires sequence".to_string(),
                          ),
                        )
                    }
                  Value::Tuple(values) => {
                    let indices = match
                      slice_indices_from_values(
                        values.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::Tuple(slice_values_by_indices(values, indices)))
                  }
                  Value::Str(text) => {
                    let chars = text.to_array()
                    let indices = match
                      slice_indices_from_values(
                        chars.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::Str(slice_string_by_indices(chars, indices)))
                  }
                  Value::Bytes(bytes) => {
                    let indices = match
                      slice_indices_from_values(
                        bytes.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::Bytes(slice_ints_by_indices(bytes, indices)))
                  }
                  Value::ByteArray(bytes) => {
                    let indices = match
                      slice_indices_from_values(
                        bytes.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::ByteArray(slice_ints_by_indices(bytes, indices)))
                  }
                  Value::MemoryView(bytes) => {
                    let indices = match
                      slice_indices_from_values(
                        bytes.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::MemoryView(slice_ints_by_indices(bytes, indices)))
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "subscript requires sequence".to_string(),
                      ),
                    )
                }
              }
            _ => ()
          }
          match target {
            Value::Dict(values) => {
              let index = match dict_find_index(values, idx_value) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              match index {
                Some(i) => Ok(values[i].1)
                None =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Key,
                      "key not found".to_string(),
                    ),
                  )
              }
            }
            _ => {
              let idx = match index_from_value(idx_value, 0) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              fn index_list(
                values : Array[Value],
                idx : Int,
              ) -> Result[Value, RuntimeError] {
                let norm = normalize_index(idx, values.length())
                if norm >= 0 && norm < values.length() {
                  Ok(values[norm])
                } else {
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Index,
                      "index out of range".to_string(),
                    ),
                  )
                }
              }
              match target {
                Value::List(values) => index_list(values, idx)
                Value::Instance(inst) =>
                  match get_named_value(inst.dict, list_storage_name) {
                    Some(Value::List(values)) => index_list(values, idx)
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "subscript requires sequence".to_string(),
                        ),
                      )
                  }
                Value::Tuple(values) => {
                  let norm = normalize_index(idx, values.length())
                  if norm >= 0 && norm < values.length() {
                    Ok(values[norm])
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                Value::Str(text) => {
                  let chars = text.to_array()
                  let norm = normalize_index(idx, chars.length())
                  if norm >= 0 && norm < chars.length() {
                    Ok(Value::Str(char_to_string(chars[norm])))
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                Value::Bytes(bytes)
                | Value::ByteArray(bytes)
                | Value::MemoryView(bytes) => {
                  let norm = normalize_index(idx, bytes.length())
                  if norm >= 0 && norm < bytes.length() {
                    Ok(Value::Int(@bigint.BigInt::from_int(bytes[norm])))
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "subscript requires sequence".to_string(),
                    ),
                  )
              }
            }
          }
        }
      }
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      let cond_value = match
        eval_expr_with_env(condition, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if bool_from_value(cond_value) {
        eval_expr_with_env(then_expr, locals, globals, builtins, io)
      } else {
        eval_expr_with_env(else_expr, locals, globals, builtins, io)
      }
    }
    Expr::Unary(op~, expr~) => {
      let value = match
        eval_expr_with_env(expr, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match op {
        UnaryOp::Neg => {
          match value {
            Value::Complex(real, imag) =>
              return Ok(Value::Complex(-real, -imag))
            _ => ()
          }
          let (is_float, num) = match number_value(value) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if is_float {
            Ok(Value::Float(-num))
          } else {
            match value {
              Value::Int(v) => Ok(Value::Int(-v))
              Value::Bool(v) => Ok(Value::Int(-(if v { 1N } else { 0N })))
              _ => Ok(Value::Int(-@bigint.BigInt::from_int64(num.to_int64())))
            }
          }
        }
        UnaryOp::Pos => Ok(value)
        UnaryOp::Not => Ok(Value::Bool(!bool_from_value(value)))
        UnaryOp::Invert =>
          match value {
            Value::Int(v) => Ok(Value::Int(-(v + 1N)))
            Value::Bool(v) => Ok(Value::Int(-((if v { 1N } else { 0N }) + 1N)))
            Value::Float(_) =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: 'float'".to_string(),
                ),
              )
            Value::Function(func) => {
              let type_name = if func.name == "int" ||
                func.name == "str" ||
                func.name == "bytes" ||
                func.name == "dict" {
                "type"
              } else {
                "function"
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: '" + type_name + "'",
                ),
              )
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: '" +
                  type_name_from_value(value) +
                  "'",
                ),
              )
          }
      }
    }
    Expr::Binary(op~, left~, right~) => {
      let left_val = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let right_val = match
        eval_expr_with_env(right, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      eval_binary_op_values(op, left_val, right_val, globals, builtins, io)
    }
    Expr::BoolOp(op~, values~) =>
      if values.length() == 0 {
        Ok(Value::Bool(false))
      } else {
        let mut result = match
          eval_expr_with_env(values[0], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for i = 1; i < values.length(); i = i + 1 {
          match op {
            BoolOp::And => if !bool_from_value(result) { return Ok(result) }
            BoolOp::Or => if bool_from_value(result) { return Ok(result) }
          }
          result = match
            eval_expr_with_env(values[i], locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        Ok(result)
      }
    Expr::Compare(left~, ops~, comparators~) => {
      let mut previous = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      for i = 0; i < ops.length(); i = i + 1 {
        let current = match
          eval_expr_with_env(comparators[i], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let ok = match ops[i] {
          CompareOp::Eq => eq_value(previous, current)
          CompareOp::NotEq => !eq_value(previous, current)
          CompareOp::Lt => {
            match (previous, current) {
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in left {
                  let hit = match set_find_index(right, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok && left.length() < right.length()
              }
              _ => {
                let (_, left_num) = match number_value(previous) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let (_, right_num) = match number_value(current) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                left_num < right_num
              }
            }
          }
          CompareOp::Lte => {
            match (previous, current) {
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in left {
                  let hit = match set_find_index(right, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok
              }
              _ => {
                let (_, left_num) = match number_value(previous) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let (_, right_num) = match number_value(current) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                left_num <= right_num
              }
            }
          }
          CompareOp::Gt => {
            match (previous, current) {
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in right {
                  let hit = match set_find_index(left, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok && left.length() > right.length()
              }
              _ => {
                let (_, left_num) = match number_value(previous) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let (_, right_num) = match number_value(current) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                left_num > right_num
              }
            }
          }
          CompareOp::Gte => {
            match (previous, current) {
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in right {
                  let hit = match set_find_index(left, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok
              }
              _ => {
                let (_, left_num) = match number_value(previous) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let (_, right_num) = match number_value(current) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                left_num >= right_num
              }
            }
          }
          CompareOp::Is =>
            match (previous, current) {
              (Value::Function(a), Value::Function(b)) => a.name == b.name
              _ => eq_value(previous, current)
            }
          CompareOp::IsNot =>
            match (previous, current) {
              (Value::Function(a), Value::Function(b)) => a.name != b.name
              _ => !eq_value(previous, current)
            }
          CompareOp::In =>
            match current {
              Value::List(values) | Value::Tuple(values) => {
                let mut found = false
                for item in values {
                  if eq_value(item, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Set(values) =>
                match set_find_index(values, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Bytes(bytes)
              | Value::ByteArray(bytes)
              | Value::MemoryView(bytes) => bytes_contains(bytes, previous)
              Value::Dict(pairs) =>
                match dict_find_index(pairs, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Str(text) =>
                match previous {
                  Value::Str(needle) => text.contains(needle)
                  _ => false
                }
              _ =>
                // 1) Prefer `__contains__` when available.
                match current {
                  Value::Instance(_) =>
                    match
                      get_attr_from_value(
                        current, "__contains__", globals, builtins, io,
                      ) {
                      Ok(contains_method) => {
                        let result = match
                          call_callable_with_env(
                            contains_method,
                            [previous],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        bool_from_value(result)
                      }
                      Err(err) =>
                        match err.kind {
                          RuntimeErrorKind::Attribute => {
                            // Fall back to iteration.
                            let iterator = match
                              iter_value_to_iterator(
                                current, globals, builtins, io,
                              ) {
                              Ok(v) => v
                              Err(e) => return Err(e)
                            }
                            let mut found = false
                            while true {
                              match
                                iterator_next(
                                  iterator,
                                  None,
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(item) =>
                                  if eq_value(item, previous) {
                                    found = true
                                    break
                                  }
                                Err(e) =>
                                  if e.exc_type == "StopIteration" {
                                    break
                                  } else {
                                    return Err(e)
                                  }
                              }
                            }
                            found
                          }
                          _ => return Err(err)
                        }
                    }
                  _ => {
                    let iterator = match
                      iter_value_to_iterator(current, globals, builtins, io) {
                      Ok(v) => v
                      Err(e) => return Err(e)
                    }
                    let mut found = false
                    while true {
                      match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(item) =>
                          if eq_value(item, previous) {
                            found = true
                            break
                          }
                        Err(e) =>
                          if e.exc_type == "StopIteration" {
                            break
                          } else {
                            return Err(e)
                          }
                      }
                    }
                    found
                  }
                }
            }
          CompareOp::NotIn =>
            !(match current {
              Value::List(values) | Value::Tuple(values) => {
                let mut found = false
                for item in values {
                  if eq_value(item, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Set(values) =>
                match set_find_index(values, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Bytes(bytes)
              | Value::ByteArray(bytes)
              | Value::MemoryView(bytes) => bytes_contains(bytes, previous)
              Value::Dict(pairs) =>
                match dict_find_index(pairs, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Str(text) =>
                match previous {
                  Value::Str(needle) => text.contains(needle)
                  _ => false
                }
              _ =>
                match current {
                  Value::Instance(_) =>
                    match
                      get_attr_from_value(
                        current, "__contains__", globals, builtins, io,
                      ) {
                      Ok(contains_method) => {
                        let result = match
                          call_callable_with_env(
                            contains_method,
                            [previous],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        bool_from_value(result)
                      }
                      Err(err) =>
                        match err.kind {
                          RuntimeErrorKind::Attribute => {
                            let iterator = match
                              iter_value_to_iterator(
                                current, globals, builtins, io,
                              ) {
                              Ok(v) => v
                              Err(e) => return Err(e)
                            }
                            let mut found = false
                            while true {
                              match
                                iterator_next(
                                  iterator,
                                  None,
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(item) =>
                                  if eq_value(item, previous) {
                                    found = true
                                    break
                                  }
                                Err(e) =>
                                  if e.exc_type == "StopIteration" {
                                    break
                                  } else {
                                    return Err(e)
                                  }
                              }
                            }
                            found
                          }
                          _ => return Err(err)
                        }
                    }
                  _ => {
                    let iterator = match
                      iter_value_to_iterator(current, globals, builtins, io) {
                      Ok(v) => v
                      Err(e) => return Err(e)
                    }
                    let mut found = false
                    while true {
                      match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(item) =>
                          if eq_value(item, previous) {
                            found = true
                            break
                          }
                        Err(e) =>
                          if e.exc_type == "StopIteration" {
                            break
                          } else {
                            return Err(e)
                          }
                      }
                    }
                    found
                  }
                }
            })
        }
        if !ok {
          return Ok(Value::Bool(false))
        }
        previous = current
      }
      Ok(Value::Bool(true))
    }
    Expr::Call(callee~, args~) =>
      match callee {
        Expr::Attribute(value~, attr~) =>
          if attr == "join" {
            let sep_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let sep = match sep_value {
              Value::Str(text) => text
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "join separator must be str".to_string(),
                  ),
                )
            }
            if args.length() != 1 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "join() takes exactly one argument".to_string(),
                ),
              )
            }
            let iter_value = match
              eval_expr_with_env(args[0], locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let parts : Array[String] = []
            match iter_value {
              Value::List(values) =>
                for v in values {
                  parts.push(value_to_string(v))
                }
              Value::Tuple(values) =>
                for v in values {
                  parts.push(value_to_string(v))
                }
              Value::Set(values) =>
                for v in values {
                  parts.push(value_to_string(v))
                }
              _ =>
                match iterable_values(iter_value) {
                  Ok(values) =>
                    for v in values {
                      parts.push(value_to_string(v))
                    }
                  Err(_) =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "can only join an iterable".to_string(),
                      ),
                    )
                }
            }
            let buf = StringBuilder::new()
            for i = 0; i < parts.length(); i = i + 1 {
              if i > 0 {
                buf.write_string(sep)
              }
              buf.write_string(parts[i])
            }
            Ok(Value::Str(buf.to_string()))
          } else {
            let callee_value = match
              eval_expr_with_env(
                Expr::Attribute(value~, attr~),
                locals,
                globals,
                builtins,
                io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (arg_values, keywords) = match
              eval_call_args(args, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match callee_value {
              Value::Function(func) =>
                if func.body.length() == 0 {
                  match
                    eval_builtin_call(
                      func.name,
                      arg_values,
                      keywords,
                      locals,
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(Some(value)) => Ok(value)
                    Ok(None) =>
                      call_callable_with_env(
                        callee_value, arg_values, keywords, globals, builtins, io,
                      )
                    Err(err) => Err(err)
                  }
                } else {
                  call_callable_with_env(
                    callee_value, arg_values, keywords, globals, builtins, io,
                  )
                }
              _ =>
                call_callable_with_env(
                  callee_value, arg_values, keywords, globals, builtins, io,
                )
            }
          }
        Expr::Name(name) => {
          let callee_value = match
            lookup_name_value(name, locals, globals, builtins) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match callee_value {
            Value::Function(func) =>
              if func.body.length() == 0 {
                let (arg_values, keywords) = match
                  eval_call_args(args, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                match
                  eval_builtin_call(
                    func.name,
                    arg_values,
                    keywords,
                    locals,
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(Some(value)) => Ok(value)
                  Ok(None) =>
                    call_callable_with_env(
                      callee_value, arg_values, keywords, globals, builtins, io,
                    )
                  Err(err) => Err(err)
                }
              } else {
                let (arg_values, keywords) = match
                  eval_call_args(args, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                call_callable_with_env(
                  callee_value, arg_values, keywords, globals, builtins, io,
                )
              }
            _ => {
              let (arg_values, keywords) = match
                eval_call_args(args, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              call_callable_with_env(
                callee_value, arg_values, keywords, globals, builtins, io,
              )
            }
          }
        }
        _ => {
          let callee_value = match
            eval_expr_with_env(callee, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (arg_values, keywords) = match
            eval_call_args(args, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          call_callable_with_env(
            callee_value, arg_values, keywords, globals, builtins, io,
          )
        }
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "expression not implemented".to_string(),
        ),
      )
  }
}

///|
fn genexp_targets_to_target(targets : Array[String]) -> Target {
  if targets.length() == 1 {
    Target::Name(targets[0])
  } else {
    let out : Array[Target] = []
    for name in targets {
      out.push(Target::Name(name))
    }
    Target::Tuple(out)
  }
}

///|
fn genexp_filters_to_condition(filters : Array[Expr]) -> Expr? {
  if filters.length() == 0 {
    None
  } else if filters.length() == 1 {
    Some(filters[0])
  } else {
    Some(Expr::BoolOp(op=BoolOp::And, values=filters))
  }
}

///|
fn genexp_to_generator_body(
  elt : Expr,
  clauses : Array[CompClause],
  filters : Array[Expr],
) -> Array[Stmt] {
  let inner : Array[Stmt] = [Stmt::Yield(Some(elt))]
  let conditioned = match genexp_filters_to_condition(filters) {
    Some(cond) => [Stmt::If(condition=cond, body=inner, else_body=[])]
    None => inner
  }
  let mut body = conditioned
  let mut i = clauses.length()
  while i > 0 {
    i = i - 1
    let clause = clauses[i]
    body = [
      Stmt::For(
        target=genexp_targets_to_target(clause.targets),
        iter=clause.iter,
        body~,
        else_body=[],
      ),
    ]
  }
  body
}

///|
fn genexp_local_taken(locals : Array[(String, Value)], name : String) -> Bool {
  for pair in locals {
    if pair.0 == name {
      return true
    }
  }
  false
}

///|
fn fresh_genexp_local(locals : Array[(String, Value)]) -> String {
  let base = "__mpython_genexp_iter".to_string()
  if !genexp_local_taken(locals, base) {
    return base
  }
  let mut i = 0
  while true {
    let candidate = base + "_" + i.to_string()
    if !genexp_local_taken(locals, candidate) {
      return candidate
    }
    i = i + 1
  }
  base
}

///|
fn eval_call_args(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[(Array[Value], Array[(String, Value)]), RuntimeError] {
  let positional : Array[Value] = []
  let keywords : Array[(String, Value)] = []
  for arg in args {
    match arg {
      Expr::Starred(value~) => {
        let iter_value = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let items = match iterable_values(iter_value) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        for item in items {
          positional.push(item)
        }
      }
      Expr::DoubleStarred(value~) => {
        let mapping = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match mapping {
          Value::Dict(pairs) =>
            for pair in pairs {
              match pair.0 {
                Value::Str(name) => keywords.push((name, pair.1))
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "keywords must be strings".to_string(),
                    ),
                  )
              }
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "keywords must be strings".to_string(),
              ),
            )
        }
      }
      Expr::Keyword(name~, value~) => {
        let eval_value = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        keywords.push((name, eval_value))
      }
      _ => {
        let eval_value = match
          eval_expr_with_env(arg, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        positional.push(eval_value)
      }
    }
  }
  Ok((positional, keywords))
}

///|
fn append_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn collect_scope_decl_names(
  body : Array[Stmt],
) -> (Array[String], Array[String]) {
  let globals : Array[String] = []
  let nonlocals : Array[String] = []
  fn walk(stmt : Stmt) -> Unit {
    match stmt {
      Stmt::WithSpan(span=_, stmt=inner) => walk(inner)
      Stmt::Global(ns) =>
        for n in ns {
          append_unique_name(globals, n)
        }
      Stmt::Nonlocal(ns) =>
        for n in ns {
          append_unique_name(nonlocals, n)
        }
      Stmt::If(condition~, body~, else_body~) => {
        let _ = condition
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        let _ = condition
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::For(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::With(context~, target~, body~) => {
        let _ = context
        let _ = target
        for s in body {
          walk(s)
        }
      }
      Stmt::AsyncWith(context~, target~, body~) => {
        let _ = context
        let _ = target
        for s in body {
          walk(s)
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        for s in body {
          walk(s)
        }
        for handler in handlers {
          let _ = handler.exc
          let _ = handler.name
          for s in handler.body {
            walk(s)
          }
        }
        for s in else_body {
          walk(s)
        }
        for s in finally_body {
          walk(s)
        }
      }
      Stmt::Match(subject~, cases~) => {
        let _ = subject
        for case in cases {
          let _ = case.0
          let _ = case.1
          for s in case.2 {
            walk(s)
          }
        }
      }
      Stmt::Function(..) | Stmt::Class(..) | Stmt::TypeAlias(..) => ()
      _ => ()
    }
  }

  for stmt in body {
    walk(stmt)
  }
  (globals, nonlocals)
}

///|
fn name_in_list(names : Array[String], name : String) -> Bool {
  for n in names {
    if n == name {
      return true
    }
  }
  false
}

///|
fn param_has_default_marker(param : String) -> Bool {
  if param == "*" || param == "/" {
    return false
  }
  if param.has_prefix("*") {
    return false
  }
  param.has_suffix("=")
}

///|
fn normalize_param_name(param : String) -> String? {
  if param == "*" || param == "/" {
    return None
  }
  let mut name = param
  if name.has_suffix("=") {
    name = substring(name, 0, name.length() - 1)
  }
  if name.has_prefix("**") {
    name = substring(name, 2, name.length())
  } else if name.has_prefix("*") {
    name = substring(name, 1, name.length())
  }
  if name.length() == 0 {
    None
  } else {
    Some(name)
  }
}

///|
fn param_list_has_name(params : Array[String], name : String) -> Bool {
  for param in params {
    match normalize_param_name(param) {
      Some(param_name) =>
        if param_name == name {
          return true
        }
      None => ()
    }
  }
  false
}

///|
fn param_is_kw_only_marker(param : String) -> Bool {
  param == "*"
}

///|
fn param_is_posonly_marker(param : String) -> Bool {
  param == "/"
}

///|
fn param_is_vararg(param : String) -> Bool {
  param.has_prefix("*") && !param.has_prefix("**") && param != "*"
}

///|
fn param_is_kwarg(param : String) -> Bool {
  param.has_prefix("**")
}

///|
let globals_capture_name = "$__mpython_globals__"

///|
fn resolve_function_globals(
  func : FunctionValue,
  fallback : Array[(String, Value)],
) -> Array[(String, Value)] {
  for pair in func.closure {
    if pair.0 == globals_capture_name {
      match pair.1 {
        Value::Instance(inst) => return inst.dict
        _ => ()
      }
    }
  }
  fallback
}

///|
fn check_scope_decl_conflicts(
  params : Array[String],
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Result[Unit, RuntimeError] {
  for name in global_names {
    if name_in_list(nonlocal_names, name) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: name '" + name + "' is nonlocal and global",
        ),
      )
    }
    if param_list_has_name(params, name) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: name '" + name + "' is parameter and global",
        ),
      )
    }
  }
  for name in nonlocal_names {
    if param_list_has_name(params, name) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: name '" + name + "' is parameter and nonlocal",
        ),
      )
    }
  }
  Ok(())
}

///|
fn collect_function_local_names(
  body : Array[Stmt],
  params : Array[String],
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Array[String] {
  let locals : Array[String] = []
  fn add_local(name : String) -> Unit {
    if name_in_list(global_names, name) || name_in_list(nonlocal_names, name) {
      return
    }
    append_unique_name(locals, name)
  }

  fn add_target(target : Target) -> Unit {
    match target {
      Target::Name(name) => add_local(name)
      Target::Tuple(items) | Target::List(items) =>
        for item in items {
          add_target(item)
        }
      _ => ()
    }
  }

  fn add_pattern(pat : Pattern) -> Unit {
    match pat {
      Pattern::Name(name) => add_local(name)
      Pattern::Tuple(items) =>
        for item in items {
          add_pattern(item)
        }
      _ => ()
    }
  }

  fn walk_expr(expr : Expr) -> Unit {
    match expr {
      Expr::NamedExpr(name~, value~) => {
        add_local(name)
        walk_expr(value)
      }
      Expr::Lambda(params~, defaults~, body~) => {
        let _ = params
        for d in defaults {
          walk_expr(d)
        }
        let _ = body

      }
      Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) =>
        for item in items {
          walk_expr(item)
        }
      Expr::ListComp(elt~, clauses~, filters~)
      | Expr::GenExp(elt~, clauses~, filters~)
      | Expr::SetComp(elt~, clauses~, filters~) => {
        for clause in clauses {
          let _ = clause.targets
          walk_expr(clause.iter)
        }
        for filter in filters {
          walk_expr(filter)
        }
        walk_expr(elt)
      }
      Expr::Dict(items) =>
        for pair in items {
          walk_expr(pair.0)
          walk_expr(pair.1)
        }
      Expr::DictComp(key~, value~, clauses~, filters~) => {
        for clause in clauses {
          let _ = clause.targets
          walk_expr(clause.iter)
        }
        for filter in filters {
          walk_expr(filter)
        }
        walk_expr(key)
        walk_expr(value)
      }
      Expr::IfExpr(condition~, then_expr~, else_expr~) => {
        walk_expr(condition)
        walk_expr(then_expr)
        walk_expr(else_expr)
      }
      Expr::Yield(value) =>
        match value {
          Some(v) => walk_expr(v)
          None => ()
        }
      Expr::YieldFrom(value) | Expr::Await(value) => walk_expr(value)
      Expr::Slice(start~, end~, step~) => {
        match start {
          Some(v) => walk_expr(v)
          None => ()
        }
        match end {
          Some(v) => walk_expr(v)
          None => ()
        }
        match step {
          Some(v) => walk_expr(v)
          None => ()
        }
      }
      Expr::Attribute(value~, attr~) => {
        let _ = attr
        walk_expr(value)
      }
      Expr::Subscript(value~, index~) => {
        walk_expr(value)
        walk_expr(index)
      }
      Expr::Call(callee~, args~) => {
        walk_expr(callee)
        for arg in args {
          walk_expr(arg)
        }
      }
      Expr::Keyword(name~, value~) => {
        let _ = name
        walk_expr(value)
      }
      Expr::Starred(value~) | Expr::DoubleStarred(value~) => walk_expr(value)
      Expr::Unary(op~, expr~) => {
        let _ = op
        walk_expr(expr)
      }
      Expr::Binary(op~, left~, right~) => {
        let _ = op
        walk_expr(left)
        walk_expr(right)
      }
      Expr::BoolOp(op~, values~) => {
        let _ = op
        for v in values {
          walk_expr(v)
        }
      }
      Expr::Compare(left~, ops~, comparators~) => {
        let _ = ops
        walk_expr(left)
        for v in comparators {
          walk_expr(v)
        }
      }
      _ => ()
    }
  }

  fn walk_stmt(stmt : Stmt) -> Unit {
    match stmt {
      Stmt::WithSpan(span=_, stmt=inner) => walk_stmt(inner)
      Stmt::Assign(target~, value~) => {
        add_target(target)
        walk_expr(value)
      }
      Stmt::AugAssign(target~, op~, value~) => {
        let _ = op
        add_target(target)
        walk_expr(value)
      }
      Stmt::TypeAlias(name~, type_params~, value~) => {
        let _ = type_params
        add_local(name)
        walk_expr(value)
      }
      Stmt::Del(targets) =>
        for t in targets {
          add_target(t)
        }
      Stmt::ExprStmt(expr) => walk_expr(expr)
      Stmt::Return(expr) =>
        match expr {
          Some(v) => walk_expr(v)
          None => ()
        }
      Stmt::If(condition~, body~, else_body~) => {
        walk_expr(condition)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        walk_expr(condition)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::For(target~, iter~, body~, else_body~) => {
        add_target(target)
        walk_expr(iter)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        add_target(target)
        walk_expr(iter)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::With(context~, target~, body~)
      | Stmt::AsyncWith(context~, target~, body~) => {
        walk_expr(context)
        match target {
          Some(name) => add_local(name)
          None => ()
        }
        for s in body {
          walk_stmt(s)
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        for s in body {
          walk_stmt(s)
        }
        for handler in handlers {
          let _ = handler.exc
          match handler.name {
            Some(name) => add_local(name)
            None => ()
          }
          for s in handler.body {
            walk_stmt(s)
          }
        }
        for s in else_body {
          walk_stmt(s)
        }
        for s in finally_body {
          walk_stmt(s)
        }
      }
      Stmt::Match(subject~, cases~) => {
        walk_expr(subject)
        for case in cases {
          add_pattern(case.0)
          match case.1 {
            Some(v) => walk_expr(v)
            None => ()
          }
          for s in case.2 {
            walk_stmt(s)
          }
        }
      }
      Stmt::Import(module_name~, alias_name~) => {
        let binding = match alias_name {
          Some(name) => name
          None => module_name
        }
        add_local(binding)
      }
      Stmt::FromImport(module_name~, names~) => {
        let _ = module_name
        for item in names {
          let name = item.0
          let alias_opt = item.1
          if name != "*" {
            add_local(
              match alias_opt {
                Some(alias_name) => alias_name
                None => name
              },
            )
          }
        }
      }
      Stmt::Function(
        name~,
        decorators~,
        type_params~,
        params~,
        defaults~,
        body~,
        is_generator~,
        is_async~
      ) => {
        add_local(name)
        for dec in decorators {
          walk_expr(dec)
        }
        for d in defaults {
          walk_expr(d)
        }
        let _ = type_params
        let _ = params
        let _ = body
        let _ = is_generator
        let _ = is_async

      }
      Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~) => {
        add_local(name)
        for dec in decorators {
          walk_expr(dec)
        }
        for b in bases {
          walk_expr(b)
        }
        for kw in keywords {
          let _ = kw.0
          walk_expr(kw.1)
        }
        let _ = type_params
        let _ = body

      }
      _ => ()
    }
  }

  for p in params {
    match normalize_param_name(p) {
      Some(name) => add_local(name)
      None => ()
    }
  }
  for stmt in body {
    walk_stmt(stmt)
  }
  locals
}

///|
fn prepare_function_locals(
  locals : Array[(String, Value)],
  body : Array[Stmt],
  params : Array[String],
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Unit {
  let local_names = collect_function_local_names(
    body, params, global_names, nonlocal_names,
  )
  for name in local_names {
    ensure_local_cell_unbound(locals, name)
  }
}

///|
fn eval_function_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals = match
    bind_function_args_with_kwargs(func, positional, keywords) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let active_globals = resolve_function_globals(func, globals)
  let (global_names, nonlocal_names) = collect_scope_decl_names(func.body)
  let _ = match
    check_scope_decl_conflicts(func.params, global_names, nonlocal_names) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  prepare_function_locals(
    locals,
    func.body,
    func.params,
    global_names,
    nonlocal_names,
  )
  let filename = current_traceback_filename()
  if func.is_async {
    if func.is_generator {
      return Ok(
        async_generator_new(
          func.body,
          locals,
          active_globals,
          builtins,
          io,
          global_names,
          nonlocal_names,
          func.closure,
          func.name,
          filename,
        ),
      )
    }
    return Ok(
      coroutine_new(
        func.body,
        locals,
        active_globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        func.name,
        filename,
        Config::default(),
      ),
    )
  }
  push_traceback_frame(func.name, filename)
  push_closure_env(func.closure)
  push_scope_decls_with_nonlocals(global_names, nonlocal_names)
  let result = eval_block(
    func.body,
    locals,
    active_globals,
    builtins,
    io,
    Config::default(),
  )
  pop_scope_decls()
  pop_closure_env()
  pop_traceback_frame()
  result
}

///|
fn bind_function_args_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
) -> Result[Array[(String, Value)], RuntimeError] {
  let pos_params : Array[String] = []
  let kw_only_params : Array[String] = []
  let mut vararg_name : String? = None
  let mut kwarg_name : String? = None
  let defaults_by_name : Array[(String, Value)] = []
  let mut default_idx = 0
  let mut kw_only = false

  for param in func.params {
    if param_is_posonly_marker(param) {
      continue
    }
    if param_is_kw_only_marker(param) {
      kw_only = true
      continue
    }
    if param_is_kwarg(param) {
      kwarg_name = normalize_param_name(param)
      kw_only = true
      continue
    }
    if param_is_vararg(param) {
      vararg_name = normalize_param_name(param)
      kw_only = true
      continue
    }
    match normalize_param_name(param) {
      Some(name) => {
        if kw_only {
          kw_only_params.push(name)
        } else {
          pos_params.push(name)
        }
        if param_has_default_marker(param) {
          if default_idx >= func.defaults.length() {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: bad function defaults".to_string(),
              ),
            )
          }
          defaults_by_name.push((name, func.defaults[default_idx]))
          default_idx += 1
        }
      }
      None => ()
    }
  }
  if default_idx != func.defaults.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "RuntimeError: bad function defaults".to_string(),
      ),
    )
  }

  if vararg_name is None && positional.length() > pos_params.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        func.name +
        "() takes " +
        pos_params.length().to_string() +
        " positional arguments but " +
        positional.length().to_string() +
        " were given",
      ),
    )
  }

  fn find_default(
    defaults_by_name : Array[(String, Value)],
    name : String,
  ) -> Value? {
    for entry in defaults_by_name {
      if entry.0 == name {
        return Some(entry.1)
      }
    }
    None
  }

  let pos_values : Array[(String, Value)] = []
  let pos_assigned : Array[Bool] = []
  for name in pos_params {
    pos_values.push((name, Value::None))
    pos_assigned.push(false)
  }
  let kw_values : Array[(String, Value)] = []
  let kw_assigned : Array[Bool] = []
  for name in kw_only_params {
    kw_values.push((name, Value::None))
    kw_assigned.push(false)
  }
  let vararg_values : Array[Value] = []
  let kwarg_values : Array[(Value, Value)] = []

  for i = 0; i < positional.length(); i = i + 1 {
    if i < pos_params.length() {
      pos_values[i] = (pos_params[i], positional[i])
      pos_assigned[i] = true
    } else {
      vararg_values.push(positional[i])
    }
  }

  for pair in keywords {
    let name = pair.0
    let value = pair.1
    let mut handled = false
    for i = 0; i < pos_params.length(); i = i + 1 {
      if pos_params[i] == name {
        handled = true
        if pos_assigned[i] {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        pos_values[i] = (name, value)
        pos_assigned[i] = true
        break
      }
    }
    if handled {
      continue
    }
    for i = 0; i < kw_only_params.length(); i = i + 1 {
      if kw_only_params[i] == name {
        handled = true
        if kw_assigned[i] {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        kw_values[i] = (name, value)
        kw_assigned[i] = true
        break
      }
    }
    if handled {
      continue
    }
    match kwarg_name {
      Some(_) => {
        let mut exists = false
        for entry in kwarg_values {
          match entry.0 {
            Value::Str(key) =>
              if key == name {
                exists = true
              }
            _ => ()
          }
        }
        if exists {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        kwarg_values.push((Value::Str(name), value))
      }
      None =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            func.name + "() got an unexpected keyword argument '" + name + "'",
          ),
        )
    }
  }

  let missing_pos : Array[String] = []
  for i = 0; i < pos_params.length(); i = i + 1 {
    if !pos_assigned[i] {
      match find_default(defaults_by_name, pos_params[i]) {
        Some(value) => {
          pos_values[i] = (pos_params[i], value)
          pos_assigned[i] = true
        }
        None => missing_pos.push(pos_params[i])
      }
    }
  }
  if missing_pos.length() > 0 {
    let buf = StringBuilder::new()
    buf.write_string(func.name)
    buf.write_string("() missing ")
    buf.write_string(missing_pos.length().to_string())
    buf.write_string(" required positional argument")
    if missing_pos.length() != 1 {
      buf.write_string("s")
    }
    buf.write_string(": ")
    for i = 0; i < missing_pos.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("'")
      buf.write_string(missing_pos[i])
      buf.write_string("'")
    }
    return Err(make_runtime_error(RuntimeErrorKind::Type, buf.to_string()))
  }

  let missing_kw : Array[String] = []
  for i = 0; i < kw_only_params.length(); i = i + 1 {
    if !kw_assigned[i] {
      match find_default(defaults_by_name, kw_only_params[i]) {
        Some(value) => {
          kw_values[i] = (kw_only_params[i], value)
          kw_assigned[i] = true
        }
        None => missing_kw.push(kw_only_params[i])
      }
    }
  }
  if missing_kw.length() > 0 {
    let buf = StringBuilder::new()
    buf.write_string(func.name)
    buf.write_string("() missing ")
    buf.write_string(missing_kw.length().to_string())
    buf.write_string(" required keyword-only argument")
    if missing_kw.length() != 1 {
      buf.write_string("s")
    }
    buf.write_string(": ")
    for i = 0; i < missing_kw.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("'")
      buf.write_string(missing_kw[i])
      buf.write_string("'")
    }
    return Err(make_runtime_error(RuntimeErrorKind::Type, buf.to_string()))
  }

  let locals : Array[(String, Value)] = []
  for item in pos_values {
    locals.push(item)
  }
  match vararg_name {
    Some(name) => locals.push((name, Value::Tuple(vararg_values)))
    None => ()
  }
  for item in kw_values {
    locals.push(item)
  }
  match kwarg_name {
    Some(name) => locals.push((name, Value::Dict(kwarg_values)))
    None => ()
  }
  Ok(locals)
}

///|
fn eval_generator_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals = match
    bind_function_args_with_kwargs(func, positional, keywords) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let active_globals = resolve_function_globals(func, globals)
  let (global_names, nonlocal_names) = collect_scope_decl_names(func.body)
  let _ = match
    check_scope_decl_conflicts(func.params, global_names, nonlocal_names) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  prepare_function_locals(
    locals,
    func.body,
    func.params,
    global_names,
    nonlocal_names,
  )
  let filename = current_traceback_filename()
  if func.is_async {
    Ok(
      async_generator_new(
        func.body,
        locals,
        active_globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        func.name,
        filename,
      ),
    )
  } else {
    Ok(
      generator_new(
        func.body,
        locals,
        active_globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        func.name,
        filename,
      ),
    )
  }
}

///|
let runtime_callbacks_ready : Ref[Bool] = { val: false }

///|
fn ensure_runtime_callbacks_ready() -> Unit {
  if runtime_callbacks_ready.val {
    return
  }
  set_eval_function_with_kwargs_callback(eval_function_with_kwargs)
  set_eval_generator_with_kwargs_callback(eval_generator_with_kwargs)
  runtime_callbacks_ready.val = true
}

///|
