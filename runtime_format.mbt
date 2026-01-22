///|
/// Formatting and value conversion helpers.

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
  let mut mapping_pairs : Array[(Value, Value)]? = None
  let args = match value {
    Value::Tuple(values) => values
    Value::Dict(pairs) => {
      mapping_pairs = Some(pairs)
      [value]
    }
    _ => [value]
  }
  let buf = StringBuilder::new()
  let chars = format.to_array()
  let mut arg_index = 0
  let mut used_positional = false
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
    let mut key_name : String? = None
    if chars[j] == '(' {
      let mut k = j + 1
      while k < chars.length() && chars[k] != ')' {
        k = k + 1
      }
      if k >= chars.length() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "incomplete format".to_string(),
          ),
        )
      }
      let key_chars : Array[Char] = []
      for idx = j + 1; idx < k; idx = idx + 1 {
        key_chars.push(chars[idx])
      }
      key_name = Some(String::from_array(key_chars))
      j = k + 1
    }
    if j >= chars.length() {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "incomplete format".to_string(),
        ),
      )
    }
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
    let arg = match key_name {
      Some(key) => {
        let pairs = match mapping_pairs {
          Some(pairs) => pairs
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "format requires a mapping".to_string(),
              ),
            )
        }
        let key_value = Value::Str(key)
        let index = match dict_find_index(pairs, key_value) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match index {
          Some(pos) => pairs[pos].1
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Key,
                "key not found".to_string(),
              ),
            )
        }
      }
      None => {
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
        used_positional = true
        arg
      }
    }
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
  if used_positional && arg_index < args.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "not all arguments converted during string formatting".to_string(),
      ),
    )
  }
  Ok(buf.to_string())
}
