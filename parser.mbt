///|
/// Parser entrypoints for moonpython (see parser_*.mbt for implementation).
///

///|
pub fn parse(source : String) -> Result[Module, ParseError] {
  let lex_source = source.to_string()
  match scan_source_lexical_errors(lex_source) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let mismatch_hint = first_bracket_mismatch_line(source.to_string())
  let chars = source.to_array()
  let mut i = 0
  let mut line = 1
  let mut line_start = 0
  let mut quote : Char? = None
  let mut escape = false
  let bracket_stack : Array[(Char, Int, Int, Int)] = []
  let mut unclosed_open : (Char, Int, Int, Int)? = None
  while i < chars.length() {
    let c = chars[i]
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
    if c == '\n' {
      line += 1
      i += 1
      line_start = i
      continue
    }
    if c == '#' {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
      continue
    }
    if c == '\'' || c == '"' {
      // Skip over triple-quoted strings so bracket mismatch detection doesn't
      // accidentally inspect parentheses/brackets inside docstrings.
      if i + 2 < chars.length() && chars[i + 1] == c && chars[i + 2] == c {
        let q = c
        i += 3
        while i < chars.length() {
          if chars[i] == '\n' {
            line += 1
            i += 1
            line_start = i
            continue
          }
          if i + 2 < chars.length() &&
            chars[i] == q &&
            chars[i + 1] == q &&
            chars[i + 2] == q {
            i += 3
            break
          }
          i += 1
        }
        continue
      }
      quote = Some(c)
      escape = false
      i += 1
      continue
    }
    if c == '(' {
      let column = i - line_start + 1
      bracket_stack.push((c, i, line, column))
      i += 1
      continue
    }
    if c == '[' {
      let column = i - line_start + 1
      bracket_stack.push((c, i, line, column))
      i += 1
      continue
    }
    if c == '{' {
      let column = i - line_start + 1
      bracket_stack.push((c, i, line, column))
      i += 1
      continue
    }
    if c == ')' {
      if bracket_stack.length() == 0 {
        let token = {
          kind: Eof,
          start: i,
          end: i + 1,
          line,
          column: i - line_start + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "unmatched ')'".to_string(),
            token,
          ),
        )
      }
      let open = bracket_stack[bracket_stack.length() - 1]
      let _ = bracket_stack.pop()
      if open.0 != '(' {
        let token = {
          kind: Eof,
          start: i,
          end: i + 1,
          line,
          column: i - line_start + 1,
        }
        let message = "closing " +
          bracket_name(c) +
          " '" +
          c.to_string() +
          "' does not match opening " +
          bracket_name(open.0) +
          " '" +
          open.0.to_string() +
          "'"
        return Err(make_parse_error(ParseErrorKind::Syntax, message, token))
      }
      i += 1
      continue
    }
    if c == ']' {
      if bracket_stack.length() == 0 {
        let token = {
          kind: Eof,
          start: i,
          end: i + 1,
          line,
          column: i - line_start + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "unmatched ']'".to_string(),
            token,
          ),
        )
      }
      let open = bracket_stack[bracket_stack.length() - 1]
      let _ = bracket_stack.pop()
      if open.0 != '[' {
        let token = {
          kind: Eof,
          start: i,
          end: i + 1,
          line,
          column: i - line_start + 1,
        }
        let message = "closing " +
          bracket_name(c) +
          " '" +
          c.to_string() +
          "' does not match opening " +
          bracket_name(open.0) +
          " '" +
          open.0.to_string() +
          "'"
        return Err(make_parse_error(ParseErrorKind::Syntax, message, token))
      }
      i += 1
      continue
    }
    if c == '}' {
      if bracket_stack.length() == 0 {
        let token = {
          kind: Eof,
          start: i,
          end: i + 1,
          line,
          column: i - line_start + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "unmatched '}'".to_string(),
            token,
          ),
        )
      }
      let open = bracket_stack[bracket_stack.length() - 1]
      let _ = bracket_stack.pop()
      if open.0 != '{' {
        let token = {
          kind: Eof,
          start: i,
          end: i + 1,
          line,
          column: i - line_start + 1,
        }
        let message = "closing " +
          bracket_name(c) +
          " '" +
          c.to_string() +
          "' does not match opening " +
          bracket_name(open.0) +
          " '" +
          open.0.to_string() +
          "'"
        return Err(make_parse_error(ParseErrorKind::Syntax, message, token))
      }
      i += 1
      continue
    }
    i += 1
  }
  if bracket_stack.length() > 0 {
    unclosed_open = Some(bracket_stack[bracket_stack.length() - 1])
  }
  let parser = LineParser::new(source)
  match parser.parse_block(0) {
    Ok(body) =>
      match unclosed_open {
        Some(open) => {
          let token = {
            kind: Eof,
            start: open.1,
            end: open.1 + 1,
            line: open.2,
            column: open.3,
          }
          let message = "'" + open.0.to_string() + "' was never closed"
          Err(make_parse_error(ParseErrorKind::Syntax, message, token))
        }
        None => Ok(Module::{ body, })
      }
    Err(err) =>
      match err.kind {
        ParseErrorKind::Indentation => Err(err)
        _ => {
          let mut final_err = err
          match unclosed_open {
            Some(open) =>
              match final_err.kind {
                ParseErrorKind::Syntax =>
                  if final_err.span.line == open.2 {
                    let token = {
                      kind: Eof,
                      start: open.1,
                      end: open.1 + 1,
                      line: open.2,
                      column: open.3,
                    }
                    let message = "'" +
                      open.0.to_string() +
                      "' was never closed"
                    final_err = make_parse_error(
                      ParseErrorKind::Syntax,
                      message,
                      token,
                    )
                  }
                _ => ()
              }
            None => ()
          }
          match mismatch_hint {
            Some(mismatch_line) =>
              if final_err.span.line == 1 && mismatch_line > 1 {
                Err(ParseError::{
                  kind: final_err.kind,
                  message: final_err.message,
                  span: Span::{
                    start: final_err.span.start,
                    end: final_err.span.end,
                    line: mismatch_line,
                    column: 1,
                  },
                })
              } else {
                Err(final_err)
              }
            None => Err(final_err)
          }
        }
      }
  }
}

///|
pub fn parse_expr(source : String) -> Result[Expr, ParseError] {
  // `eval()`-style expression parsing: allow multi-line expressions only when
  // they are continued via brackets, backslash-newlines, or f-string braces.
  let mut expr_source = source
  if expr_source.contains("\n") {
    let lines : Array[String] = []
    for part in expr_source.split("\n") {
      lines.push(part.to_string())
    }
    // Skip leading blank/comment-only lines.
    let mut start_index = 0
    while start_index < lines.length() &&
          strip_inline_comment(lines[start_index]).trim(chars=" \t\r").length() ==
          0 {
      start_index += 1
    }
    if start_index >= lines.length() {
      return Err(
        make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
          kind: Eof,
          start: 0,
          end: 1,
          line: 1,
          column: 1,
        }),
      )
    }
    let raw_line = lines[start_index]
    let mut line_text = raw_line.trim(chars=" \t").to_string()
    if find_triple_quote(raw_line) is None {
      line_text = strip_inline_comment(line_text).trim(chars=" \t").to_string()
    }
    let mut next_index = start_index + 1
    match unclosed_triple_quote(raw_line) {
      None => ()
      Some(_) => {
        let mut combined = raw_line
        let mut idx = start_index + 1
        while idx < lines.length() {
          let next_line = lines[idx]
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
        }
      }
    }
    while has_unclosed_string_line_continuation(line_text) &&
          next_index < lines.length() {
      let next_line = lines[next_index]
      line_text = line_text + "\n" + next_line
      next_index += 1
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
      Some(_) => {
        let mut combined = line_text
        let mut idx = next_index
        while idx < lines.length() {
          let next_line = lines[idx]
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
    if find_triple_quote(line_text) is None {
      line_text = replace_newlines_with_spaces(line_text)
        .trim(chars=" \t")
        .to_string()
    }
    // Reject additional non-empty lines that are not part of a continued
    // expression (eval-mode).
    let mut extra_index = next_index
    while extra_index < lines.length() &&
          strip_inline_comment(lines[extra_index]).trim(chars=" \t\r").length() ==
          0 {
      extra_index += 1
    }
    if extra_index < lines.length() {
      return Err(
        make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
          kind: Eof,
          start: 0,
          end: 1,
          line: extra_index + 1,
          column: 1,
        }),
      )
    }
    expr_source = line_text
  }
  let tokens = match tokenize_expr(expr_source, 1, 0, 1) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let expr = match parse_tokens_expr(tokens) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if expr_has_async_comprehension(expr) {
    return Err(
      make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
        kind: Eof,
        start: 0,
        end: 1,
        line: 1,
        column: 1,
      }),
    )
  }
  // `eval()` mode: `yield` / `await` are not allowed outside (async) functions.
  if expr_has_yield_or_await(expr) {
    return Err(
      make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
        kind: Eof,
        start: 0,
        end: 1,
        line: 1,
        column: 1,
      }),
    )
  }
  Ok(expr)
}
