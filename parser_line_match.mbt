///|
/// Match/case parsing for line blocks.

///|
fn parse_match_stmt(
  parser : LineParser,
  stmts : Array[Stmt],
  line_text : String,
  line_index : Int,
  current_indent : Int,
  next_index : Int,
) -> Result[Bool, ParseError] {
  if !line_text.has_prefix("match ") && !line_text.has_prefix("match(") {
    return Ok(false)
  }
  let colon_pos = find_top_level_colon(line_text)
  if colon_pos is None {
    return Ok(false)
  }
  let subject_text = substring(line_text, 5, colon_pos.unwrap())
    .trim(chars=" \t")
    .to_string()
  let subject_tokens = match
    tokenize_expr(
      subject_text,
      parser.index + 1,
      parser.offsets[parser.index] + current_indent + 5,
    ) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let subject_expr = match parse_tokens_expr(subject_tokens) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  parser.index = next_index
  let match_indent = parser.peek_next_indent()
  if match_indent <= current_indent {
    let missing_line = parser.clamp_line_index(
      parser.peek_next_significant_index().unwrap_or(parser.index),
    )
    let token = {
      kind: Eof,
      start: parser.offsets[missing_line],
      end: parser.offsets[missing_line] + 1,
      line: missing_line + 1,
      column: 1,
    }
    return Err(
      make_parse_error(
        ParseErrorKind::Indentation,
        "expected indented block".to_string(),
        token,
      ),
    )
  }
  let cases : Array[(Pattern, Expr?, Array[Stmt])] = []
  while parser.index < parser.lines.length() {
    let case_line = parser.lines[parser.index]
    let case_trimmed = case_line.trim(chars=" \t").to_string()
    if case_trimmed.length() == 0 || case_trimmed.has_prefix("#") {
      parser.index += 1
      continue
    }
    let case_indent = count_indent(case_line)
    if case_indent < match_indent {
      break
    }
    if case_indent > match_indent {
      let token = {
        kind: Eof,
        start: parser.offsets[parser.index] + match_indent,
        end: parser.offsets[parser.index] + match_indent + 1,
        line: parser.index + 1,
        column: match_indent + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Indentation,
          "unexpected indent".to_string(),
          token,
        ),
      )
    }
    let mut case_text = substring(case_line, case_indent, case_line.length())
      .trim(chars=" \t")
      .to_string()
    let mut case_next_index = parser.index + 1
    let mut balance = bracket_balance(case_text)
    while balance > 0 && case_next_index < parser.lines.length() {
      case_text = case_text + "\n" + parser.lines[case_next_index]
      case_next_index += 1
      balance = bracket_balance(case_text)
    }
    if !case_text.has_prefix("case ") && !case_text.has_prefix("case(") {
      let token = {
        kind: Eof,
        start: parser.offsets[parser.index] + case_indent,
        end: parser.offsets[parser.index] + case_indent + 1,
        line: parser.index + 1,
        column: case_indent + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    let case_no_comment = strip_inline_comment(case_text)
    let colon_pos = find_top_level_colon(case_no_comment)
    if colon_pos is None {
      let token = {
        kind: Eof,
        start: parser.offsets[parser.index] + case_indent,
        end: parser.offsets[parser.index] + case_indent + 1,
        line: parser.index + 1,
        column: case_indent + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    let header = substring(case_no_comment, 4, colon_pos.unwrap())
      .trim(chars=" \t")
      .to_string()
    let mut pattern_text = header
    let mut guard_text : String? = None
    if header.contains(" if ") {
      let parts : Array[String] = []
      for part in header.split(" if ") {
        parts.push(part.to_string())
      }
      if parts.length() >= 2 {
        pattern_text = parts[0].trim(chars=" \t").to_string()
        guard_text = Some(parts[1].trim(chars=" \t").to_string())
      }
    }
    let base_offset = parser.offsets[parser.index] + case_indent + 4
    let pattern = match parse_pattern(pattern_text, parser.index, base_offset) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let mut guard_expr : Expr? = None
    match guard_text {
      Some(text) => {
        let tokens = match tokenize_expr(text, parser.index + 1, base_offset) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let expr = match parse_tokens_expr(tokens) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        guard_expr = Some(expr)
      }
      None => ()
    }
    let mut body : Array[Stmt] = []
    let body_text = if case_text.contains("\n") {
      "".to_string()
    } else {
      strip_inline_comment(
        substring(
          case_no_comment,
          colon_pos.unwrap() + 1,
          case_no_comment.length(),
        ).to_string(),
      )
      .trim(chars=" \t")
      .to_string()
    }
    parser.index = case_next_index
    if body_text.length() > 0 {
      let segments = split_statements(body_text)
      for segment_pair in segments {
        let segment = segment_pair.0
        let offset = segment_pair.1
        if segment.length() == 0 {
          continue
        }
        let base_offset = parser.offsets[parser.index - 1] +
          case_indent +
          colon_pos.unwrap() +
          1 +
          offset
        let parsed = match
          parse_simple_statement(
            segment,
            parser.index - 1,
            parser.offsets[parser.index - 1],
            base_offset,
            parser.async_depth > 0,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for stmt in parsed {
          body.push(stmt)
        }
      }
    } else {
      let body_indent = parser.peek_next_indent()
      if body_indent <= match_indent {
        let missing_line = parser.clamp_line_index(
          parser.peek_next_significant_index().unwrap_or(parser.index),
        )
        let token = {
          kind: Eof,
          start: parser.offsets[missing_line],
          end: parser.offsets[missing_line] + 1,
          line: missing_line + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Indentation,
            "expected indented block".to_string(),
            token,
          ),
        )
      }
      body = match parser.parse_block(body_indent) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
    }
    cases.push((pattern, guard_expr, body))
  }
  stmts.push(
    wrap_stmt_for_line(
      parser.offsets,
      line_index,
      current_indent,
      Stmt::Match(subject=subject_expr, cases~),
    ),
  )
  Ok(true)
}
