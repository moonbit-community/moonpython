///|
/// Object text helpers (ASCII checks, strip, formatting).

///|
fn is_ascii_alpha(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int())
}

///|
fn is_ascii_lower(c : Char) -> Bool {
  let code = c.to_int()
  code >= 'a'.to_int() && code <= 'z'.to_int()
}

///|
fn is_ascii_upper(c : Char) -> Bool {
  let code = c.to_int()
  code >= 'A'.to_int() && code <= 'Z'.to_int()
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  let code = c.to_int()
  code >= '0'.to_int() && code <= '9'.to_int()
}

///|
fn is_ascii_alnum(c : Char) -> Bool {
  is_ascii_alpha(c) || is_ascii_digit(c)
}

///|
fn is_ascii_whitespace(c : Char) -> Bool {
  let code = c.to_int()
  code == ' '.to_int() ||
  code == '\t'.to_int() ||
  code == '\n'.to_int() ||
  code == '\r'.to_int() ||
  code == 0x0b ||
  code == 0x0c
}

///|
fn is_python_whitespace(c : Char) -> Bool {
  if is_ascii_whitespace(c) {
    return true
  }
  let code = c.to_int()
  code == 0x0085 ||
  code == 0x00a0 ||
  code == 0x1680 ||
  (code >= 0x2000 && code <= 0x200a) ||
  code == 0x2028 ||
  code == 0x2029 ||
  code == 0x202f ||
  code == 0x205f ||
  code == 0x3000
}

///|
priv enum StripMode {
  Both
  Left
  Right
} derive(Eq)

///|
fn parse_strip_chars(
  name : String,
  value_opt : Value?,
) -> Result[Array[Char]?, RuntimeError] {
  match value_opt {
    None => Ok(None)
    Some(Value::None) => Ok(None)
    Some(Value::Str(text)) => Ok(Some(text.to_array()))
    Some(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + "() expects a str".to_string(),
        ),
      )
  }
}

///|
fn strip_has_char(c : Char, chars_opt : Array[Char]?) -> Bool {
  match chars_opt {
    None => is_python_whitespace(c)
    Some(chars) => {
      for item in chars {
        if item == c {
          return true
        }
      }
      false
    }
  }
}

///|
fn strip_text(
  text : String,
  chars_opt : Array[Char]?,
  mode : StripMode,
) -> String {
  let chars = text.to_array()
  let mut start = 0
  let mut end = chars.length()
  if mode == StripMode::Both || mode == StripMode::Left {
    while start < end && strip_has_char(chars[start], chars_opt) {
      start += 1
    }
  }
  if mode == StripMode::Both || mode == StripMode::Right {
    while end > start && strip_has_char(chars[end - 1], chars_opt) {
      end -= 1
    }
  }
  substring(text, start, end)
}

///|
fn lookup_keyword_value(
  keywords : Array[(String, Value)],
  name : String,
) -> Value? {
  for pair in keywords {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn format_value_with_spec(
  value : Value,
  spec : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  fn stringify_for_default_format(
    value : Value,
  ) -> Result[String, RuntimeError] {
    match value {
      Value::Str(text) => Ok(text)
      Value::Instance(_) =>
        match get_attr_from_value(value, "__str__", globals, builtins, io) {
          Ok(callable) =>
            match callable {
              Value::BoundMethod(bound) =>
                if bound.function.body.length() > 0 {
                  match
                    (eval_function_with_kwargs_ref.val)(
                      bound.function,
                      [bound.self],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(Value::Str(text)) => Ok(text)
                    Ok(_) =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "__str__ returned non-string".to_string(),
                        ),
                      )
                    Err(err) => Err(err)
                  }
                } else {
                  Ok(value_to_string(value))
                }
              Value::Function(func) =>
                if func.body.length() > 0 {
                  match
                    (eval_function_with_kwargs_ref.val)(
                      func,
                      [value],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(Value::Str(text)) => Ok(text)
                    Ok(_) =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "__str__ returned non-string".to_string(),
                        ),
                      )
                    Err(err) => Err(err)
                  }
                } else {
                  Ok(value_to_string(value))
                }
              _ => Ok(value_to_string(value))
            }
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => Ok(value_to_string(value))
              _ => Err(err)
            }
        }
      _ => Ok(value_to_string(value))
    }
  }

  if spec.length() == 0 {
    return stringify_for_default_format(value)
  }
  let chars = spec.to_array()
  let mut type_char : Char? = None
  let mut end = chars.length()
  if chars.length() > 0 && chars[chars.length() - 1].is_ascii_alphabetic() {
    type_char = Some(chars[chars.length() - 1])
    end = chars.length() - 1
  }
  let mut zero_pad = false
  let mut width = 0
  let mut idx = 0
  if end > 0 && chars[0] == '0' {
    zero_pad = true
    idx = 1
  }
  while idx < end && chars[idx].is_ascii_digit() {
    width = width * 10 + (chars[idx].to_int() - '0'.to_int())
    idx += 1
  }
  if idx != end {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "unsupported format string".to_string(),
      ),
    )
  }
  match type_char {
    None | Some('s') => {
      let out = match stringify_for_default_format(value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(pad_left(out, width, if zero_pad { '0' } else { ' ' }))
    }
    Some('d') | Some('i') => {
      let raw = match format_decimal_value(value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(pad_numeric(raw, width, zero_pad))
    }
    Some('x') => {
      let raw = match format_hex_value(value, false) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(pad_numeric(raw, width, zero_pad))
    }
    Some('X') => {
      let raw = match format_hex_value(value, true) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(pad_numeric(raw, width, zero_pad))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "unsupported format string".to_string(),
        ),
      )
  }
}

///|
fn format_string_with_args(
  text : String,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  let chars = text.to_array()
  let buf = StringBuilder::new()
  let mut auto_index = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '{' {
      if i + 1 < chars.length() && chars[i + 1] == '{' {
        buf.write_char('{')
        i += 2
        continue
      }
      let mut close = i + 1
      while close < chars.length() && chars[close] != '}' {
        close += 1
      }
      if close >= chars.length() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "unmatched '{' in format string".to_string(),
          ),
        )
      }
      let field = substring(text, i + 1, close)
      let field_chars = field.to_array()
      let mut colon : Int? = None
      for j = 0; j < field_chars.length(); j = j + 1 {
        if field_chars[j] == ':' {
          colon = Some(j)
          break
        }
      }
      // Basic conversion support: `{name!r}` / `{0!s}` / `{name!a}`.
      let head = match colon {
        Some(pos) => substring(field, 0, pos)
        None => field
      }
      let head_trimmed = head.trim(chars=" \t").to_string()
      let head_chars = head_trimmed.to_array()
      let mut bang : Int? = None
      for j = 0; j < head_chars.length(); j = j + 1 {
        if head_chars[j] == '!' {
          bang = Some(j)
          break
        }
      }
      let (field_name, conv) = match bang {
        Some(pos) => {
          let name = substring(head_trimmed, 0, pos)
            .trim(chars=" \t")
            .to_string()
          let conv_char = if pos + 1 < head_chars.length() {
            Some(head_chars[pos + 1])
          } else {
            None
          }
          (name, conv_char)
        }
        None => (head_trimmed, None)
      }
      let spec = match colon {
        Some(pos) => substring(field, pos + 1, field.length())
        None => "".to_string()
      }
      let value = if field_name.length() == 0 {
        if auto_index >= positional.length() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "not enough arguments for format string".to_string(),
            ),
          )
        }
        let v = positional[auto_index]
        auto_index += 1
        v
      } else {
        let mut is_number = true
        for ch in field_name.to_array() {
          if !ch.is_ascii_digit() {
            is_number = false
            break
          }
        }
        if is_number {
          let index = @strconv.parse_int(field_name) catch {
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "invalid format index".to_string(),
                ),
              )
          }
          if index < 0 || index >= positional.length() {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "not enough arguments for format string".to_string(),
              ),
            )
          }
          positional[index]
        } else {
          match lookup_keyword_value(keywords, field_name) {
            Some(v) => v
            None =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "missing format keyword".to_string(),
                ),
              )
          }
        }
      }
      fn repr_string(value : Value) -> String {
        match value {
          Value::Str(text) => {
            let buf = StringBuilder::new()
            for c in text.to_array() {
              if c == '\\' {
                buf.write_string("\\\\")
              } else if c == '\'' {
                buf.write_string("\\'")
              } else if c == '\n' {
                buf.write_string("\\n")
              } else if c == '\r' {
                buf.write_string("\\r")
              } else if c == '\t' {
                buf.write_string("\\t")
              } else {
                buf.write_char(c)
              }
            }
            "'" + buf.to_string() + "'"
          }
          _ => value_to_string(value)
        }
      }

      let value_for_format = match conv {
        Some('r') | Some('a') => Value::Str(repr_string(value))
        Some('s') =>
          match
            format_value_with_spec(value, "".to_string(), globals, builtins, io) {
            Ok(v) => Value::Str(v)
            Err(err) => return Err(err)
          }
        _ => value
      }
      let formatted = match
        format_value_with_spec(value_for_format, spec, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      buf.write_string(formatted)
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
          RuntimeErrorKind::Type,
          "single '}' encountered in format string".to_string(),
        ),
      )
    }
    buf.write_char(c)
    i += 1
  }
  Ok(buf.to_string())
}
