///|
/// Line-level parsing helpers for moonpython.
///

///|
fn count_indent(line : String) -> Int {
  let chars = line.to_array()
  let mut count = 0
  for c in chars {
    if c == ' ' || c == '\t' {
      count += 1
    } else {
      break
    }
  }
  count
}

///|
fn has_triple_quote_after(line : String, quote : Char, start : Int) -> Bool {
  let chars = line.to_array()
  let mut idx = if start < 0 { 0 } else { start }
  while idx + 2 < chars.length() {
    if chars[idx] == quote && chars[idx + 1] == quote && chars[idx + 2] == quote {
      return true
    }
    idx += 1
  }
  false
}

///|
fn find_triple_quote(line : String) -> (Char, Int)? {
  let chars = line.to_array()
  let mut idx = 0
  let mut quote : Char? = None
  let mut escaped = false
  while idx < chars.length() {
    let c = chars[idx]
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if idx + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[idx + 1] == c &&
          chars[idx + 2] == c {
          return Some((c, idx))
        } else if c == '\'' || c == '"' {
          quote = Some(c)
          escaped = false
        }
    }
    idx += 1
  }
  None
}

///|
fn unclosed_triple_quote(text : String) -> Char? {
  // Best-effort triple-quote balancing for the lexical pre-scan. This is not a
  // full tokenizer, but it is good enough for common stdlib patterns like:
  //   x = """...""" + name + """.suffix\n...\n"""
  let chars = text.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escaped = false
  let mut triple_open : Char? = None
  while i < chars.length() {
    let c = chars[i]
    match triple_open {
      Some(open_q) => {
        if i + 2 < chars.length() &&
          chars[i] == open_q &&
          chars[i + 1] == open_q &&
          chars[i + 2] == open_q {
          triple_open = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) => {
        if escaped {
          escaped = false
          i += 1
          continue
        }
        if c == '\\' {
          escaped = true
          i += 1
          continue
        }
        if c == q {
          quote = None
        }
        i += 1
        continue
      }
      None => ()
    }
    if c == '#' {
      // Comment: ignore the rest of the line.
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
      continue
    }
    if i + 2 < chars.length() &&
      (c == '"' || c == '\'') &&
      chars[i + 1] == c &&
      chars[i + 2] == c {
      triple_open = Some(c)
      i += 3
      continue
    }
    if c == '"' || c == '\'' {
      quote = Some(c)
      escaped = false
      i += 1
      continue
    }
    i += 1
  }
  triple_open
}

///|
fn split_top_level_commas(text : String) -> Array[String] {
  let parts : Array[String] = []
  let chars = text.to_array()
  let mut start = 0
  let mut i = 0
  let mut quote : Char? = None
  let mut escaped = false
  let mut depth = 0
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if c == ',' && depth == 0 {
          parts.push(substring(text, start, i))
          start = i + 1
        }
    }
    i += 1
  }
  parts.push(substring(text, start, chars.length()))
  parts
}

///|
fn find_top_level_paren_span(text : String) -> (Int, Int)? {
  let chars = text.to_array()
  let mut quote : Char? = None
  let mut escaped = false
  let mut square_depth = 0
  let mut curly_depth = 0
  let mut paren_depth = 0
  let mut open : Int? = None
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '[' {
          square_depth += 1
        } else if c == ']' {
          if square_depth > 0 {
            square_depth -= 1
          }
        } else if c == '{' {
          curly_depth += 1
        } else if c == '}' {
          if curly_depth > 0 {
            curly_depth -= 1
          }
        } else if square_depth == 0 && curly_depth == 0 && c == '(' {
          if open is None {
            open = Some(i)
          }
          paren_depth += 1
        } else if square_depth == 0 && curly_depth == 0 && c == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          if paren_depth == 0 && open is Some(open_idx) {
            return Some((open_idx, i))
          }
        }
    }
  }
  None
}

///|
fn parse_type_param_header(
  header : String,
  token : Token,
) -> Result[(String, Array[String]), ParseError] {
  let trimmed = header.trim(chars=" \t").to_string()
  let open = find_char(trimmed, '[')
  if open is None {
    return Ok((trimmed, []))
  }
  let open = open.unwrap()
  let chars = trimmed.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut escaped = false
  let mut close : Int? = None
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '[' {
          depth += 1
        } else if c == ']' {
          if depth > 0 {
            depth -= 1
          }
          if depth == 0 {
            close = Some(i)
            break
          }
        }
    }
    i += 1
  }
  if close is None {
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        token,
      ),
    )
  }
  let close = close.unwrap()
  let tail = substring(trimmed, close + 1, trimmed.length())
    .trim(chars=" \t")
    .to_string()
  if tail.length() > 0 {
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        token,
      ),
    )
  }
  let name = substring(trimmed, 0, open).trim(chars=" \t").to_string()
  if name.length() == 0 {
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        token,
      ),
    )
  }
  let params_text = substring(trimmed, open + 1, close)
    .trim(chars=" \t\n\r")
    .to_string()
  if params_text.length() == 0 {
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        token,
      ),
    )
  }
  let params : Array[String] = []
  for part in split_top_level_commas(params_text) {
    let param = part.trim(chars=" \t\n\r").to_string()
    if param.length() == 0 {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    params.push(param)
  }
  Ok((name, params))
}

///|
fn split_statements(line : String) -> Array[(String, Int)] {
  let segments : Array[(String, Int)] = []
  let chars = line.to_array()
  let mut start = 0
  let mut i = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == ';' {
          let segment = substring(line, start, i).trim(chars=" \t").to_string()
          segments.push((segment, start))
          start = i + 1
        }
    }
    i += 1
  }
  let tail = substring(line, start, chars.length())
    .trim(chars=" \t")
    .to_string()
  segments.push((tail, start))
  segments
}

///|
fn bracket_balance(line : String) -> Int {
  let chars = line.to_array()
  let mut balance = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '(' || c == '[' || c == '{' {
          balance += 1
        } else if c == ')' || c == ']' || c == '}' {
          if balance > 0 {
            balance -= 1
          }
        }
    }
    i += 1
  }
  balance
}

///|
fn has_top_level_comma(text : String) -> Bool {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if c == ',' && depth == 0 {
          return true
        }
    }
    i += 1
  }
  false
}

///|
fn first_top_level_comma_pos(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if c == ',' && depth == 0 {
          return Some(i)
        }
    }
    i += 1
  }
  None
}

///|
fn find_top_level_colon(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '#' {
          i += 1
          while i < chars.length() && chars[i] != '\n' {
            i += 1
          }
          continue
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if c == ':' && depth == 0 {
          if i + 1 < chars.length() && chars[i + 1] == '=' {
            i += 1
            continue
          }
          return Some(i)
        }
    }
    i += 1
  }
  None
}

///|
fn find_top_level_as_pos(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i + 2 < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if depth == 0 &&
          c == 'a' &&
          chars[i + 1] == 's' &&
          i > 0 &&
          (chars[i - 1] == ' ' || chars[i - 1] == '\t') &&
          (chars[i + 2] == ' ' || chars[i + 2] == '\t') {
          return Some(i)
        }
    }
    i += 1
  }
  None
}

///|
fn strip_wrapping_parens(text : String) -> String {
  let trimmed = text.trim(chars=" \t").to_string()
  if !trimmed.has_prefix("(") || !trimmed.has_suffix(")") {
    return trimmed
  }
  let chars = trimmed.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut escaped = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escaped = false
        } else if c == '(' {
          depth += 1
        } else if c == ')' {
          if depth > 0 {
            depth -= 1
          }
          if depth == 0 && i != chars.length() - 1 {
            return trimmed
          }
        }
    }
  }
  if depth == 0 {
    substring(trimmed, 1, trimmed.length() - 1).trim(chars=" \t").to_string()
  } else {
    trimmed
  }
}

///|
fn find_top_level_augassign(text : String) -> (Int, String)? {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) => {
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
        i += 1
        continue
      }
      None => ()
    }
    if i + 2 < chars.length() &&
      (c == '\'' || c == '"') &&
      chars[i + 1] == c &&
      chars[i + 2] == c {
      triple = Some(c)
      i += 3
      continue
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      i += 1
      continue
    }
    if c == '(' || c == '[' || c == '{' {
      depth += 1
      i += 1
      continue
    }
    if c == ')' || c == ']' || c == '}' {
      if depth > 0 {
        depth -= 1
      }
      i += 1
      continue
    }
    if depth == 0 {
      // Prefer the longest operator match.
      if i + 2 < chars.length() &&
        c == '*' &&
        chars[i + 1] == '*' &&
        chars[i + 2] == '=' {
        return Some((i, "**=".to_string()))
      }
      if i + 2 < chars.length() &&
        c == '/' &&
        chars[i + 1] == '/' &&
        chars[i + 2] == '=' {
        return Some((i, "//=".to_string()))
      }
      if i + 2 < chars.length() &&
        c == '<' &&
        chars[i + 1] == '<' &&
        chars[i + 2] == '=' {
        return Some((i, "<<=".to_string()))
      }
      if i + 2 < chars.length() &&
        c == '>' &&
        chars[i + 1] == '>' &&
        chars[i + 2] == '=' {
        return Some((i, ">>=".to_string()))
      }
      if i + 1 < chars.length() && chars[i + 1] == '=' {
        if c == '+' ||
          c == '-' ||
          c == '*' ||
          c == '@' ||
          c == '/' ||
          c == '%' ||
          c == '&' ||
          c == '|' ||
          c == '^' {
          return Some((i, c.to_string() + "="))
        }
      }
    }
    i += 1
  }
  None
}

///|
/// Find the first top-level occurrence of a character, ignoring any nested
/// (), [], {}, and string literals (single/double/triple quoted).
fn find_top_level_char(text : String, target : Char) -> Int? {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escaped = false
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) => {
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
        i += 1
        continue
      }
      None => ()
    }
    if i + 2 < chars.length() &&
      (c == '\'' || c == '"') &&
      chars[i + 1] == c &&
      chars[i + 2] == c {
      triple = Some(c)
      i += 3
      continue
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      i += 1
      continue
    }
    if c == '(' || c == '[' || c == '{' {
      depth += 1
      i += 1
      continue
    }
    if c == ')' || c == ']' || c == '}' {
      if depth > 0 {
        depth -= 1
      }
      i += 1
      continue
    }
    if depth == 0 && c == target {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn strip_inline_comment(text : String) -> String {
  let chars = text.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escape = false
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '#' {
          return substring(text, 0, i).to_string()
        }
    }
    i += 1
  }
  text
}

///|
fn replace_newlines_with_spaces(text : String) -> String {
  // Used to flatten multi-line bracketed statements into a single logical line.
  //
  // Important: keep Python string literal semantics. In particular, a
  // backslash-newline pair inside a (non-triple-quoted) string literal is a
  // line continuation and should disappear, not turn into `\ `.
  let chars = text.to_array()
  let out : Array[Char] = []
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          // Backslash-newline line continuation inside string literal.
          if c == '\n' {
            if out.length() > 0 && out[out.length() - 1] == '\\' {
              let _ = out.pop()

            }
            escape = false
            i += 1
            continue
          }
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
        // Keep newlines inside non-triple-quoted strings so the lexer can
        // correctly report unterminated string errors.
        out.push(c)
      }
      None => {
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        }
        if c == '\n' {
          out.push(' ')
        } else {
          out.push(c)
        }
      }
    }
    i += 1
  }
  let buf = StringBuilder::new()
  for ch in out {
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
fn has_trailing_line_continuation(text : String) -> Bool {
  let chars = text.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  let mut last_significant : Char? = None
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
          last_significant = Some(c)
        } else if c == '#' {
          break
        } else if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          last_significant = Some(c)
        }
    }
    i += 1
  }
  match last_significant {
    Some(c) => c == '\\'
    None => false
  }
}

///|
fn scan_source_lexical_errors(source : String) -> Result[Unit, ParseError] {
  let lines : Array[String] = []
  for line in source.split("\n") {
    lines.push(line.to_string())
  }
  let offsets : Array[Int] = []
  let mut offset = 0
  for line in lines {
    offsets.push(offset)
    offset += line.length() + 1
  }
  let mut index = 0
  let mut open_quote : Char? = None
  let mut allow_indented = false
  let mut saw_syntax_error = false
  while index < lines.length() {
    let line = lines[index]
    let current_indent = count_indent(line)
    let raw_line = substring(line, current_indent, line.length()).to_string()
    let trimmed = raw_line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 {
      index += 1
      continue
    }
    match open_quote {
      Some(quote) => {
        if has_triple_quote_after(raw_line, quote, 0) {
          open_quote = None
        }
        index += 1
        continue
      }
      None => ()
    }
    if trimmed.has_prefix("#") {
      index += 1
      continue
    }
    if current_indent > 0 && !allow_indented && !saw_syntax_error {
      return Ok(())
    }
    let mut next_index = index + 1
    let mut line_text = raw_line
    match unclosed_triple_quote(line_text) {
      None => ()
      Some(quote) => {
        let mut combined = line_text
        let mut idx = next_index
        while idx < lines.length() {
          let next_line = substring(lines[idx], 0, lines[idx].length()).to_string()
          combined = combined + "\n" + next_line
          idx += 1
          if unclosed_triple_quote(combined) is None {
            next_index = idx
            line_text = combined
            break
          }
        }
        if idx == lines.length() && unclosed_triple_quote(combined) is Some(_) {
          line_text = combined
          next_index = idx
          open_quote = Some(quote)
        }
      }
    }
    while has_trailing_line_continuation(line_text) &&
          next_index < lines.length() {
      line_text = substring(line_text, 0, line_text.length() - 1)
        .trim(chars=" \t")
        .to_string()
      let next_line = lines[next_index]
      let appended = if find_triple_quote(next_line) is Some(_) {
        next_line
      } else {
        strip_inline_comment(next_line)
      }
      line_text = line_text + "\n" + appended
      next_index += 1
      line_text = line_text.trim(chars=" \t").to_string()
    }
    match unclosed_triple_quote(line_text) {
      None => ()
      Some(quote) => {
        let mut combined = line_text
        let mut idx = next_index
        while idx < lines.length() {
          let next_line = substring(lines[idx], 0, lines[idx].length()).to_string()
          combined = combined + "\n" + next_line
          idx += 1
          if unclosed_triple_quote(combined) is None {
            next_index = idx
            line_text = combined
            break
          }
        }
        if idx == lines.length() && unclosed_triple_quote(combined) is Some(_) {
          line_text = combined
          next_index = idx
          open_quote = Some(quote)
        }
      }
    }
    let mut balance = bracket_balance(line_text)
    while balance > 0 && next_index < lines.length() {
      let next_line = lines[next_index]
      let appended = if find_triple_quote(next_line) is Some(_) {
        next_line
      } else {
        strip_inline_comment(next_line)
      }
      line_text = line_text + "\n" + appended
      next_index += 1
      balance = bracket_balance(line_text)
    }
    let segments = split_statements(line_text)
    for segment_pair in segments {
      let segment = segment_pair.0
      let offset = segment_pair.1
      if segment.length() == 0 {
        continue
      }
      let segment_trimmed = segment.trim(chars=" \t").to_string()
      if has_keyword_prefix(segment_trimmed, "yield") {
        continue
      }
      let base_offset = offsets[index] + current_indent + offset
      match tokenize_expr(segment, index + 1, base_offset) {
        Ok(_) => ()
        Err(err) =>
          match err.kind {
            ParseErrorKind::UnexpectedToken => ()
            _ => return Err(err)
          }
      }
    }
    if current_indent == 0 && !saw_syntax_error {
      for segment_pair in segments {
        let segment = segment_pair.0.trim(chars=" \t").to_string()
        if segment.length() == 0 {
          continue
        }
        if segment.has_prefix("@") ||
          segment.has_prefix("if ") ||
          segment.has_prefix("while ") ||
          segment.has_prefix("for ") ||
          segment.has_prefix("def ") ||
          segment.has_prefix("class ") ||
          segment.has_prefix("try:") ||
          segment.has_prefix("with ") ||
          segment.has_prefix("match ") ||
          segment.has_prefix("case ") ||
          segment.has_prefix("elif ") ||
          segment.has_prefix("else:") ||
          segment.has_prefix("except") ||
          segment.has_prefix("finally:") ||
          segment.has_prefix("async ") {
          continue
        }
        let base_offset = offsets[index] + current_indent + segment_pair.1
        match
          parse_simple_statement(
            segment,
            index,
            offsets[index],
            base_offset,
            false,
          ) {
          Ok(_) => ()
          Err(_) => {
            saw_syntax_error = true
            break
          }
        }
      }
    }
    allow_indented = strip_inline_comment(line_text)
      .trim(chars=" \t")
      .to_string()
      .has_suffix(":")
    index = next_index
  }
  Ok(())
}

///|
fn first_bracket_mismatch_line(source : String) -> Int? {
  let chars = source.to_array()
  let stack : Array[Char] = []
  let mut i = 0
  let mut line = 1
  let mut quote : Char? = None
  let mut escape = false
  while i < chars.length() {
    let c = chars[i]
    if c == '\n' {
      line += 1
      i += 1
      continue
    }
    match quote {
      Some(q) => {
        if escape {
          escape = false
          i += 1
          continue
        }
        if c == '\\' {
          escape = true
          i += 1
          continue
        }
        if c == q {
          quote = None
        }
        i += 1
        continue
      }
      None => ()
    }
    if c == '#' {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
      continue
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      i += 1
      continue
    }
    if c == '(' || c == '[' || c == '{' {
      stack.push(c)
      i += 1
      continue
    }
    if c == ')' || c == ']' || c == '}' {
      if stack.length() == 0 {
        return Some(line)
      }
      let open = stack[stack.length() - 1]
      let _ = stack.pop()
      let matches = (open == '(' && c == ')') ||
        (open == '[' && c == ']') ||
        (open == '{' && c == '}')
      if !matches {
        return Some(line)
      }
      i += 1
      continue
    }
    i += 1
  }
  None
}

///|
fn bracket_name(c : Char) -> String {
  if c == '(' || c == ')' {
    "parenthesis"
  } else if c == '[' || c == ']' {
    "bracket"
  } else {
    "brace"
  }
}

///|
fn is_ascii_ident_char(c : Char) -> Bool {
  if c == '_' {
    return true
  }
  let code = c.to_int()
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122)
}

///|
fn line_has_yield_keyword(line : String) -> Bool {
  let chars = line.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '#' {
          break
        } else if c == 'y' && i + 4 < chars.length() {
          if chars[i + 1] == 'i' &&
            chars[i + 2] == 'e' &&
            chars[i + 3] == 'l' &&
            chars[i + 4] == 'd' {
            let before_ok = i == 0 || !is_ascii_ident_char(chars[i - 1])
            let after_pos = i + 5
            let after_ok = after_pos >= chars.length() ||
              !is_ascii_ident_char(chars[after_pos])
            if before_ok && after_ok {
              return true
            }
          }
        }
    }
    i += 1
  }
  false
}

///|
fn line_has_lambda_keyword(line : String) -> Bool {
  let chars = line.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '#' {
          break
        } else if c == 'l' && i + 5 < chars.length() {
          if chars[i + 1] == 'a' &&
            chars[i + 2] == 'm' &&
            chars[i + 3] == 'b' &&
            chars[i + 4] == 'd' &&
            chars[i + 5] == 'a' {
            let before_ok = i == 0 || !is_ascii_ident_char(chars[i - 1])
            let after_pos = i + 6
            let after_ok = after_pos >= chars.length() ||
              !is_ascii_ident_char(chars[after_pos])
            if before_ok && after_ok {
              return true
            }
          }
        }
    }
    i += 1
  }
  false
}

///|
fn line_has_await_keyword(line : String) -> Bool {
  let chars = line.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '#' {
          break
        } else if c == 'a' && i + 4 < chars.length() {
          if chars[i + 1] == 'w' &&
            chars[i + 2] == 'a' &&
            chars[i + 3] == 'i' &&
            chars[i + 4] == 't' {
            let before_ok = i == 0 || !is_ascii_ident_char(chars[i - 1])
            let after_pos = i + 5
            let after_ok = after_pos >= chars.length() ||
              !is_ascii_ident_char(chars[after_pos])
            if before_ok && after_ok {
              return true
            }
          }
        }
    }
    i += 1
  }
  false
}

///|

///|
fn has_bare_assign(text : String) -> Bool {
  let chars = text.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut triple : Char? = None
  let mut escape = false
  let mut depth = 0
  while i < chars.length() {
    let c = chars[i]
    match triple {
      Some(q) => {
        if i + 2 < chars.length() &&
          chars[i] == q &&
          chars[i + 1] == q &&
          chars[i + 2] == q {
          triple = None
          i += 3
          continue
        }
        i += 1
        continue
      }
      None => ()
    }
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if i + 2 < chars.length() &&
          (c == '\'' || c == '"') &&
          chars[i + 1] == c &&
          chars[i + 2] == c {
          triple = Some(c)
          i += 3
          continue
        } else if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if c == '=' {
          let prev = if i > 0 { chars[i - 1] } else { '\u{0}' }
          let next = if i + 1 < chars.length() { chars[i + 1] } else { '\u{0}' }
          if depth == 0 &&
            prev != '=' &&
            prev != '!' &&
            prev != '<' &&
            prev != '>' &&
            prev != ':' &&
            next != '=' {
            return true
          }
        }
    }
    i += 1
  }
  false
}

///|
fn find_top_level_from(text : String) -> Int? {
  fn is_space_char(c : Char) -> Bool {
    c == ' ' || c == '\t' || c == '\n' || c == '\r'
  }

  let chars = text.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  let mut depth = 0
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if depth == 0 && c == 'f' {
          if i + 3 < chars.length() &&
            chars[i + 1] == 'r' &&
            chars[i + 2] == 'o' &&
            chars[i + 3] == 'm' {
            let prev = if i > 0 { chars[i - 1] } else { ' ' }
            let next = if i + 4 < chars.length() { chars[i + 4] } else { ' ' }
            if is_space_char(prev) && is_space_char(next) {
              return Some(i)
            }
          }
        }
    }
    i += 1
  }
  None
}

///|
fn find_top_level_import(text : String) -> Int? {
  fn is_space_char(c : Char) -> Bool {
    c == ' ' || c == '\t' || c == '\n' || c == '\r'
  }

  let chars = text.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  let mut depth = 0
  while i < chars.length() {
    let c = chars[i]
    match quote {
      Some(q) =>
        if escape {
          escape = false
        } else if c == '\\' {
          escape = true
        } else if c == q {
          quote = None
        }
      None =>
        if c == '\'' || c == '"' {
          quote = Some(c)
          escape = false
        } else if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        } else if depth == 0 && c == 'i' {
          if i + 5 < chars.length() &&
            chars[i + 1] == 'm' &&
            chars[i + 2] == 'p' &&
            chars[i + 3] == 'o' &&
            chars[i + 4] == 'r' &&
            chars[i + 5] == 't' {
            let prev = if i > 0 { chars[i - 1] } else { ' ' }
            let next = if i + 6 < chars.length() { chars[i + 6] } else { ' ' }
            if is_space_char(prev) && is_space_char(next) {
              return Some(i)
            }
          }
        }
    }
    i += 1
  }
  None
}

///|
fn parse_int64_digits(text : String) -> Int64 {
  let chars = text.to_array()
  let mut value = 0L
  for c in chars {
    if is_digit(c) {
      value = value * 10L + (c.to_int() - 48).to_int64()
    }
  }
  value
}
