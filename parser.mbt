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
  let tokens = match tokenize_expr(source, 1, 0) {
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
  Ok(expr)
}
