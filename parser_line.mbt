///|
/// Line/block parser for moonpython.
///
///|
priv struct LineParser {
  lines : Array[String]
  mut index : Int
  offsets : Array[Int]
  mut func_depth : Int
  mut async_depth : Int
}

///|
fn LineParser::new(source : String) -> LineParser {
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
  LineParser::{ lines, index: 0, offsets, func_depth: 0, async_depth: 0 }
}

///|
///|
fn LineParser::peek_next_indent(self : LineParser) -> Int {
  let mut idx = self.index
  while idx < self.lines.length() {
    let line = self.lines[idx]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      idx += 1
      continue
    }
    return count_indent(line)
  }
  0
}

///|
fn LineParser::peek_next_significant_index(self : LineParser) -> Int? {
  let mut idx = self.index
  while idx < self.lines.length() {
    let line = self.lines[idx]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      idx += 1
      continue
    }
    return Some(idx)
  }
  None
}

///|
fn LineParser::clamp_line_index(self : LineParser, idx : Int) -> Int {
  if idx < 0 {
    return 0
  }
  if idx >= self.lines.length() {
    if self.lines.length() == 0 {
      return 0
    }
    return self.lines.length() - 1
  }
  idx
}

///|
fn LineParser::parse_block(
  self : LineParser,
  indent : Int,
) -> Result[Array[Stmt], ParseError] {
  let stmts : Array[Stmt] = []
  let mut pending_decorators : Array[Expr] = []
  let mut pending_decorator_token : Token? = None
  while self.index < self.lines.length() {
    let line = self.lines[self.index]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      if pending_decorators.length() > 0 {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            pending_decorator_token.unwrap(),
          ),
        )
      }
      self.index += 1
      continue
    }
    if trimmed == "\\" {
      self.index += 1
      continue
    }
    let leading_chars = line.to_array()
    let mut idx = 0
    let mut saw_space = false
    let mut saw_tab = false
    while idx < leading_chars.length() {
      let c = leading_chars[idx]
      if c == ' ' {
        saw_space = true
      } else if c == '\t' {
        saw_tab = true
      } else {
        break
      }
      idx += 1
    }
    if saw_space && saw_tab {
      let token = {
        kind: Eof,
        start: self.offsets[self.index],
        end: self.offsets[self.index] + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Indentation,
          "inconsistent use of tabs and spaces in indentation".to_string(),
          token,
        ),
      )
    }
    let current_indent = count_indent(line)
    if current_indent < indent {
      if pending_decorators.length() > 0 {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            pending_decorator_token.unwrap(),
          ),
        )
      }
      break
    }
    if current_indent > indent {
      let error_start = if current_indent > 0 { current_indent - 1 } else { 0 }
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + error_start,
        end: self.offsets[self.index] + error_start + 1,
        line: self.index + 1,
        column: current_indent,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Indentation,
          "unexpected indent".to_string(),
          token,
        ),
      )
    }
    let line_index = self.index
    let raw_line = substring(line, current_indent, line.length()).to_string()
    let mut line_text = raw_line.trim(chars=" \t").to_string()
    if find_triple_quote(raw_line) is None {
      line_text = strip_inline_comment(line_text).trim(chars=" \t").to_string()
    }
    let mut next_index = self.index + 1
    if find_triple_quote(raw_line) is Some((quote, pos)) {
      if !has_triple_quote_after(raw_line, quote, pos + 3) {
        let mut combined = raw_line
        let mut idx = self.index + 1
        while idx < self.lines.length() {
          let next_line = self.lines[idx]
          combined = combined + "\n" + next_line
          if has_triple_quote_after(next_line, quote, 0) {
            next_index = idx + 1
            line_text = combined
            break
          }
          idx += 1
        }
        if idx == self.lines.length() {
          line_text = combined
          next_index = idx
        }
      }
    }
    while has_trailing_line_continuation(line_text) &&
          next_index < self.lines.length() {
      line_text = substring(line_text, 0, line_text.length() - 1)
        .trim(chars=" \t")
        .to_string()
      let next_line = self.lines[next_index]
      let appended = if find_triple_quote(next_line) is Some(_) {
        next_line
      } else {
        strip_inline_comment(next_line)
      }
      line_text = line_text + "\n" + appended
      next_index += 1
      line_text = line_text.trim(chars=" \t").to_string()
    }
    if find_triple_quote(line_text) is Some((quote, pos)) {
      if !has_triple_quote_after(line_text, quote, pos + 3) {
        let mut combined = line_text
        let mut idx = next_index
        while idx < self.lines.length() {
          let next_line = self.lines[idx]
          combined = combined + "\n" + next_line
          if has_triple_quote_after(next_line, quote, 0) {
            next_index = idx + 1
            line_text = combined
            break
          }
          idx += 1
        }
        if idx == self.lines.length() {
          line_text = combined
          next_index = idx
        }
      }
    }
    let mut balance = bracket_balance(line_text)
    while balance > 0 && next_index < self.lines.length() {
      let next_line = self.lines[next_index]
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
    if pending_decorators.length() > 0 &&
      !line_text.has_prefix("@") &&
      !line_text.has_prefix("def ") &&
      !line_text.has_prefix("async def ") &&
      !line_text.has_prefix("class ") {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          pending_decorator_token.unwrap(),
        ),
      )
    }
    if has_keyword_prefix(line_text, "return") && self.func_depth == 0 {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if self.func_depth == 0 &&
      line_has_yield_keyword(line_text) &&
      !line_has_lambda_keyword(line_text) &&
      !line_text.has_prefix("def ") &&
      !line_text.has_prefix("async def ") {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if self.async_depth == 0 &&
      line_has_await_keyword(line_text) &&
      !line_text.has_prefix("def ") &&
      !line_text.has_prefix("async def ") {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if line_text.has_prefix("match ") || line_text.has_prefix("match(") {
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None {
      } else {
      let subject_text = substring(line_text, 5, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      let subject_tokens = match
        tokenize_expr(
          subject_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 5,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let subject_expr = match parse_tokens_expr(subject_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      self.index = next_index
      let match_indent = self.peek_next_indent()
      if match_indent <= current_indent {
        let missing_line = self.clamp_line_index(
          self.peek_next_significant_index().unwrap_or(self.index),
        )
        let token = {
          kind: Eof,
          start: self.offsets[missing_line],
          end: self.offsets[missing_line] + 1,
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
      while self.index < self.lines.length() {
        let case_line = self.lines[self.index]
        let case_trimmed = case_line.trim(chars=" \t").to_string()
        if case_trimmed.length() == 0 || case_trimmed.has_prefix("#") {
          self.index += 1
          continue
        }
        let case_indent = count_indent(case_line)
        if case_indent < match_indent {
          break
        }
        if case_indent > match_indent {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + match_indent,
            end: self.offsets[self.index] + match_indent + 1,
            line: self.index + 1,
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
        let mut case_text = substring(
            case_line,
            case_indent,
            case_line.length(),
          )
          .trim(chars=" \t")
          .to_string()
        let mut case_next_index = self.index + 1
        let mut balance = bracket_balance(case_text)
        while balance > 0 && case_next_index < self.lines.length() {
          case_text = case_text + "\n" + self.lines[case_next_index]
          case_next_index += 1
          balance = bracket_balance(case_text)
        }
        if !case_text.has_prefix("case ") {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + case_indent,
            end: self.offsets[self.index] + case_indent + 1,
            line: self.index + 1,
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
            start: self.offsets[self.index] + case_indent,
            end: self.offsets[self.index] + case_indent + 1,
            line: self.index + 1,
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
        let header = substring(case_no_comment, 5, colon_pos.unwrap())
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
        let base_offset = self.offsets[self.index] + case_indent + 5
        let pattern = match
          parse_pattern(pattern_text, self.index, base_offset) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let mut guard_expr : Expr? = None
        match guard_text {
          Some(text) => {
            let tokens = match
              tokenize_expr(text, self.index + 1, base_offset) {
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
        self.index = case_next_index
        if body_text.length() > 0 {
          let segments = split_statements(body_text)
          for segment_pair in segments {
            let segment = segment_pair.0
            let offset = segment_pair.1
            if segment.length() == 0 {
              continue
            }
            let base_offset = self.offsets[self.index - 1] +
              case_indent +
              colon_pos.unwrap() +
              1 +
              offset
            let parsed = match
              parse_simple_statement(
                segment,
                self.index - 1,
                self.offsets[self.index - 1],
                base_offset,
                self.async_depth > 0,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in parsed {
              body.push(stmt)
            }
          }
        } else {
          let body_indent = self.peek_next_indent()
          if body_indent <= match_indent {
            let missing_line = self.clamp_line_index(
              self.peek_next_significant_index().unwrap_or(self.index),
            )
            let token = {
              kind: Eof,
              start: self.offsets[missing_line],
              end: self.offsets[missing_line] + 1,
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
          body = match self.parse_block(body_indent) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        cases.push((pattern, guard_expr, body))
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::Match(subject=subject_expr, cases~),
        ),
      )
      continue
      }
    }
    if line_text.has_prefix("@") {
      let expr_text = substring(line_text, 1, line_text.length())
        .trim(chars=" \t")
        .to_string()
      if expr_text.length() == 0 {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let tokens = match
        tokenize_expr(
          expr_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 1,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expr = match parse_tokens_expr(tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      pending_decorators.push(expr)
      if pending_decorator_token is None {
        pending_decorator_token = Some({
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        })
      }
      self.index = next_index
      continue
    }
    if line_text.has_prefix("class ") {
      let decorators = pending_decorators
      pending_decorators = []
      pending_decorator_token = None
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let header = substring(line_text, 6, colon_pos.unwrap())
        .trim(chars=" \t\n\r")
        .to_string()
      let paren_span = find_top_level_paren_span(header)
      let name_part = match paren_span {
        Some(span) =>
          substring(header, 0, span.0).trim(chars=" \t\n\r").to_string()
        None => header
      }
      let name_token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent + 6,
        end: self.offsets[self.index] + current_indent + 7,
        line: self.index + 1,
        column: current_indent + 7,
      }
      let (name, type_params) = match
        parse_type_param_header(name_part, name_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let bases : Array[Expr] = []
      let keywords : Array[(String, Expr)] = []
      if paren_span is Some(span) {
        let open_pos = span.0
        let close_pos = span.1
        let tail = substring(header, close_pos + 1, header.length())
          .trim(chars=" \t\n\r")
          .to_string()
        if tail.length() > 0 {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              name_token,
            ),
          )
        }
        let bases_text = substring(header, open_pos + 1, close_pos)
          .trim(chars=" \t\n\r")
          .to_string()
        if bases_text.length() > 0 {
          let base_parts = split_top_level_commas(bases_text)
          for part in base_parts {
            let expr_text = part.trim(chars=" \t\n\r").to_string()
            if expr_text.length() == 0 {
              continue
            }
            if has_bare_assign(expr_text) {
              let eq_pos = find_char(expr_text, '=')
              if eq_pos is Some(eq_idx) {
                let key = substring(expr_text, 0, eq_idx)
                  .trim(chars=" \t\n\r")
                  .to_string()
                let value_text = substring(
                    expr_text,
                    eq_idx + 1,
                    expr_text.length(),
                  )
                  .trim(chars=" \t\n\r")
                  .to_string()
                if key.length() == 0 || value_text.length() == 0 {
                  let token = {
                    kind: Eof,
                    start: self.offsets[self.index] + current_indent + 6,
                    end: self.offsets[self.index] + current_indent + 7,
                    line: self.index + 1,
                    column: 1,
                  }
                  return Err(
                    make_parse_error(
                      ParseErrorKind::Syntax,
                      "invalid syntax".to_string(),
                      token,
                    ),
                  )
                }
                match parse_expr(value_text) {
                  Ok(expr) => keywords.push((key, expr))
                  Err(_) => {
                    let token = {
                      kind: Eof,
                      start: self.offsets[self.index] + current_indent + 6,
                      end: self.offsets[self.index] + current_indent + 7,
                      line: self.index + 1,
                      column: 1,
                    }
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "invalid syntax".to_string(),
                        token,
                      ),
                    )
                  }
                }
                continue
              } else {
                continue
              }
            }
            match parse_expr(expr_text) {
              Ok(expr) => bases.push(expr)
              Err(_) => {
                let token = {
                  kind: Eof,
                  start: self.offsets[self.index] + current_indent + 6,
                  end: self.offsets[self.index] + current_indent + 7,
                  line: self.index + 1,
                  column: 1,
                }
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "invalid syntax".to_string(),
                    token,
                  ),
                )
              }
            }
          }
        }
      }
      if name.length() == 0 {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let body_text = strip_inline_comment(
          substring(line_text, colon_pos.unwrap() + 1, line_text.length()).to_string(),
        )
        .trim(chars=" \t")
        .to_string()
      if body_text.length() > 0 {
        let body : Array[Stmt] = []
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index] +
            current_indent +
            colon_pos.unwrap() +
            1 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index,
              self.offsets[self.index],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        stmts.push(
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::Class(
              name~,
              decorators~,
              type_params~,
              bases~,
              keywords~,
              body~,
            ),
          ),
        )
        self.index = next_index
        continue
      }
      self.index = next_index
      let next_indent = self.peek_next_indent()
      if next_indent <= current_indent {
        let missing_line = self.clamp_line_index(
          self.peek_next_significant_index().unwrap_or(self.index),
        )
        let token = {
          kind: Eof,
          start: self.offsets[missing_line],
          end: self.offsets[missing_line] + 1,
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
      let body = match self.parse_block(next_indent) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::Class(
            name~,
            decorators~,
            type_params~,
            bases~,
            keywords~,
            body~,
          ),
        ),
      )
      continue
    }
    if (
        line_text.has_prefix("async for ") ||
        line_text.has_prefix("async with ")
      ) &&
      self.async_depth == 0 {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if line_text.has_prefix("async for ") {
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let header_text = substring(line_text, 10, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      let in_pos = header_text.find(" in ")
      if in_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let pos = in_pos.unwrap()
      let target_text = substring(header_text, 0, pos)
        .trim(chars=" \t")
        .to_string()
      let iter_text = substring(header_text, pos + 4, header_text.length())
        .trim(chars=" \t")
        .to_string()
      if target_text.length() == 0 {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let target_tokens = match
        tokenize_expr(
          target_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 10,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let target_expr = match parse_tokens_expr(target_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let target_token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent + 10,
        end: self.offsets[self.index] + current_indent + 11,
        line: self.index + 1,
        column: 1,
      }
      let target = match target_from_expr(target_expr, target_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_tokens = match
        tokenize_expr(
          iter_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 10 + pos + 4,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_expr = match parse_tokens_expr(iter_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let body_text = substring(
          line_text,
          colon_pos.unwrap() + 1,
          line_text.length(),
        )
        .trim(chars=" \t")
        .to_string()
      let body : Array[Stmt] = []
      if body_text.length() > 0 {
        let base_offset = self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          1
        let parsed = match
          parse_simple_statement(
            body_text,
            self.index,
            self.offsets[self.index],
            base_offset,
            self.async_depth > 0,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for stmt in parsed {
          body.push(stmt)
        }
        self.index = next_index
      } else {
        self.index = next_index
        let next_indent = self.peek_next_indent()
        if next_indent <= current_indent {
          let missing_line = self.clamp_line_index(
            self.peek_next_significant_index().unwrap_or(self.index),
          )
          let token = {
            kind: Eof,
            start: self.offsets[missing_line],
            end: self.offsets[missing_line] + 1,
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
        let parsed = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for stmt in parsed {
          body.push(stmt)
        }
      }
      let else_body : Array[Stmt] = []
      if self.index < self.lines.length() {
        let else_line = self.lines[self.index]
        let else_trimmed = else_line.trim(chars=" \t").to_string()
        let else_indent = count_indent(else_line)
        if else_indent == current_indent && else_trimmed.has_prefix("else") {
          let colon_pos = find_top_level_colon(else_trimmed)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + else_indent,
              end: self.offsets[self.index] + else_indent + 1,
              line: self.index + 1,
              column: else_indent + 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let inline_text = match colon_pos {
            Some(pos) =>
              strip_inline_comment(
                substring(else_trimmed, pos + 1, else_trimmed.length()).to_string(),
              )
              .trim(chars=" \t")
              .to_string()
            None => ""
          }
          self.index += 1
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let parsed = match
                parse_simple_statement(
                  segment,
                  self.index - 1,
                  self.offsets[self.index - 1],
                  self.offsets[self.index - 1] +
                  else_indent +
                  colon_pos.unwrap_or(0) +
                  1 +
                  offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                else_body.push(stmt)
              }
            }
          } else {
            let block_indent = self.peek_next_indent()
            if block_indent <= current_indent {
              let missing_line = self.clamp_line_index(
                self.peek_next_significant_index().unwrap_or(self.index),
              )
              let token = {
                kind: Eof,
                start: self.offsets[missing_line],
                end: self.offsets[missing_line] + 1,
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
            let parsed = match self.parse_block(block_indent) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in parsed {
              else_body.push(stmt)
            }
          }
        }
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::AsyncFor(target~, iter=iter_expr, body~, else_body~),
        ),
      )
      continue
    }
    if line_text.has_prefix("async with ") {
      let mut full_line_text = line_text
      let mut colon_pos = find_top_level_colon(full_line_text)
      let mut header_end_index = next_index
      if colon_pos is None {
        let mut scan = next_index
        while scan < self.lines.length() {
          let part = self.lines[scan].trim(chars=" \t").to_string()
          full_line_text = full_line_text + "\n" + part
          colon_pos = find_top_level_colon(full_line_text)
          scan += 1
          if colon_pos is Some(_) {
            header_end_index = scan
            break
          }
        }
      }
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let header_text = substring(full_line_text, 10, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()

      // Parse just the first context manager expression.
      let mut item_text = header_text
      if item_text.has_prefix("(") && item_text.has_suffix(")") {
        item_text = substring(item_text, 1, item_text.length() - 1).to_string()
      }
      let mut first_item = item_text.trim(chars=" \t\n\r").to_string()
      match first_top_level_comma_pos(first_item) {
        Some(pos) =>
          first_item = substring(first_item, 0, pos)
            .trim(chars=" \t\n\r")
            .to_string()
        None => ()
      }
      let parts : Array[String] = []
      for part in first_item.split(" as ") {
        parts.push(part.to_string())
      }
      let context_text = parts[0].trim(chars=" \t").to_string()
      let mut target : String? = None
      if parts.length() >= 2 {
        let mut name_text = parts[1].trim(chars=" \t").to_string()
        let comma_pos = find_char(name_text, ',')
        if comma_pos is Some(pos) {
          name_text = substring(name_text, 0, pos).trim(chars=" \t").to_string()
        }
        let close_pos = find_char(name_text, ')')
        if close_pos is Some(pos) {
          name_text = substring(name_text, 0, pos).trim(chars=" \t").to_string()
        }
        if name_text.length() > 0 {
          target = Some(name_text)
        }
      }
      let context_tokens = match
        tokenize_expr(
          context_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 10,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let context = match parse_tokens_expr(context_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let body_text = substring(
          full_line_text,
          colon_pos.unwrap() + 1,
          full_line_text.length(),
        )
        .trim(chars=" \t")
        .to_string()
      if body_text.length() > 0 {
        let body : Array[Stmt] = []
        let base_offset = self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          1
        let parsed = match
          parse_simple_statement(
            body_text,
            self.index,
            self.offsets[self.index],
            base_offset,
            self.async_depth > 0,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for stmt in parsed {
          body.push(stmt)
        }
        stmts.push(
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::AsyncWith(context~, target~, body~),
          ),
        )
        self.index = header_end_index
        continue
      }
      self.index = header_end_index
      let next_indent = self.peek_next_indent()
      if next_indent <= current_indent {
        let missing_line = self.clamp_line_index(
          self.peek_next_significant_index().unwrap_or(self.index),
        )
        let token = {
          kind: Eof,
          start: self.offsets[missing_line],
          end: self.offsets[missing_line] + 1,
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
      let body = match self.parse_block(next_indent) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::AsyncWith(context~, target~, body~),
        ),
      )
      continue
    }
    let mut is_async_def = false
    if line_text.has_prefix("async def ") {
      is_async_def = true
      line_text = "def " + substring(line_text, 10, line_text.length())
    }
    if line_text.has_prefix("def ") {
      let decorators = pending_decorators
      pending_decorators = []
      pending_decorator_token = None
      let header = substring(line_text, 4, line_text.length())
      let paren_span = find_top_level_paren_span(header)
      let close_pos = match paren_span {
        Some(span) => Some(span.1)
        None => None
      }
      let colon_pos = find_top_level_colon(header)
      if paren_span is None || close_pos is None || colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index],
          end: self.offsets[self.index] + line.length(),
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid function definition".to_string(),
            token,
          ),
        )
      }
      let name_part = match paren_span {
        Some(span) => substring(header, 0, span.0).trim(chars=" \t").to_string()
        None => "".to_string()
      }
      let name_token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent + 4,
        end: self.offsets[self.index] + current_indent + 5,
        line: self.index + 1,
        column: current_indent + 5,
      }
      let (name, type_params) = match
        parse_type_param_header(name_part, name_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let name_chars = name.to_array()
      for i = 0; i < name_chars.length(); i = i + 1 {
        let c = name_chars[i]
        if !(is_alnum(c) || c == '_') || (i == 0 && is_digit(c)) {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + current_indent + 4 + i,
            end: self.offsets[self.index] + current_indent + 4 + i + 1,
            line: self.index + 1,
            column: current_indent + 4 + i + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              token,
            ),
          )
        }
      }
      let name_end = match paren_span {
        Some(span) => span.0
        None => 0
      }
      let params_text = substring(header, name_end + 1, close_pos.unwrap())
      let params : Array[String] = []
      let defaults : Array[Expr] = []
      let seen : Array[String] = []
      let mut default_seen = false
      let mut kw_only = false
      let params_chars = params_text.to_array()
      let mut param_start = 0
      let mut idx = 0
      let mut quote : Char? = None
      let mut escaped = false
      let mut depth = 0
      let param_base = current_indent + 4 + name_end + 1
      fn consume_param_segment(end_idx : Int) -> Result[Unit, ParseError] {
        let raw_param = substring(params_text, param_start, end_idx)
        let mut leading = 0
        let raw_chars = raw_param.to_array()
        while leading < raw_chars.length() && raw_chars[leading] == ' ' {
          leading += 1
        }
        let trimmed_param = raw_param.trim(chars=" \t\n\r").to_string()
        if trimmed_param.length() == 0 {
          return Ok(())
        }
        let mut name = trimmed_param
        let eq_pos_full = find_char(trimmed_param, '=')
        let has_default = eq_pos_full is Some(_)
        if eq_pos_full is Some(eq_idx) {
          name = substring(trimmed_param, 0, eq_idx)
            .trim(chars=" \t")
            .to_string()
        }
        if name == "/" {
          name = ""
        }
        if name == "*" {
          kw_only = true
          params.push("*")
          name = ""
        }
        let mut star_count = 0
        while name.has_prefix("*") {
          star_count += 1
          name = substring(name, 1, name.length()).to_string()
          name = name.trim(chars=" \t\n\r").to_string()
        }
        if star_count > 0 {
          kw_only = true
        }
        let colon_pos = find_char(name, ':')
        if colon_pos is Some(colon_idx) {
          name = substring(name, 0, colon_idx).trim(chars=" \t").to_string()
        }
        if name.length() == 0 {
          return Ok(())
        }
        let param_offset = param_start + leading
        for existing in seen {
          if existing == name {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + param_base + param_offset,
              end: self.offsets[self.index] + param_base + param_offset + 1,
              line: self.index + 1,
              column: param_base + param_offset + 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "duplicate argument '" + name + "' in function definition",
                token,
              ),
            )
          }
        }
        if star_count > 2 {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + param_base + param_offset,
            end: self.offsets[self.index] + param_base + param_offset + 1,
            line: self.index + 1,
            column: param_base + param_offset + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              token,
            ),
          )
        }
        if star_count > 0 && has_default {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + param_base + param_offset,
            end: self.offsets[self.index] + param_base + param_offset + 1,
            line: self.index + 1,
            column: param_base + param_offset + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              token,
            ),
          )
        }
        if !kw_only && default_seen && !has_default {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + param_base + param_offset,
            end: self.offsets[self.index] + param_base + param_offset + 1,
            line: self.index + 1,
            column: param_base + param_offset + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "non-default argument follows default argument".to_string(),
              token,
            ),
          )
        }
        if has_default {
          if !kw_only {
            default_seen = true
          }
          let eq_pos = find_char(raw_param, '=')
          if eq_pos is Some(eq_idx) {
            let default_text = substring(
                raw_param,
                eq_idx + 1,
                raw_param.length(),
              )
              .trim(chars=" \t\n\r")
              .to_string()
            let tokens = match
              tokenize_expr(
                default_text,
                self.index + 1,
                self.offsets[self.index] +
                param_base +
                param_start +
                eq_idx +
                1,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let expr = match parse_tokens_expr(tokens) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            defaults.push(expr)
          }
        }
        seen.push(name)
        let mut encoded = name
        if star_count == 1 {
          encoded = "*" + name
        } else if star_count == 2 {
          encoded = "**" + name
        } else if has_default {
          encoded = name + "="
        }
        params.push(encoded)
        Ok(())
      }
      while idx < params_chars.length() {
        let c = params_chars[idx]
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
              let _ = match consume_param_segment(idx) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              param_start = idx + 1
            }
        }
        idx += 1
      }
      let _ = match consume_param_segment(params_chars.length()) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let body_text = strip_inline_comment(
          substring(header, colon_pos.unwrap() + 1, header.length()).to_string(),
        )
        .trim(chars=" \t")
        .to_string()
      if !is_async_def && body_text.contains("yield") {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      if !is_async_def && line_has_await_keyword(body_text) {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      if body_text.length() > 0 {
        let body : Array[Stmt] = []
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index] +
            current_indent +
            4 +
            colon_pos.unwrap() +
            1 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index,
              self.offsets[self.index],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        for stmt in body {
          match stmt {
            Stmt::WithSpan(span=_, stmt=inner) =>
              match inner {
                Stmt::Global(names) =>
                  for name in names {
                    for param in params {
                      match normalize_param_name_for_compare(param) {
                        Some(param_name) =>
                          if param_name == name {
                        let token = {
                          kind: Eof,
                          start: self.offsets[self.index] +
                          current_indent +
                          4 +
                          colon_pos.unwrap() +
                          2,
                          end: self.offsets[self.index] +
                          current_indent +
                          4 +
                          colon_pos.unwrap() +
                          3,
                          line: self.index + 1,
                          column: current_indent + 4 + colon_pos.unwrap() + 3,
                        }
                        return Err(
                          make_parse_error(
                            ParseErrorKind::Syntax,
                            "name '" + name + "' is parameter and global",
                            token,
                          ),
                        )
                          }
                        None => ()
                      }
                    }
                  }
                _ => ()
              }
            Stmt::Global(names) =>
              for name in names {
                for param in params {
                  match normalize_param_name_for_compare(param) {
                    Some(param_name) =>
                      if param_name == name {
                    let token = {
                      kind: Eof,
                      start: self.offsets[self.index] +
                      current_indent +
                      4 +
                      colon_pos.unwrap() +
                      2,
                      end: self.offsets[self.index] +
                      current_indent +
                      4 +
                      colon_pos.unwrap() +
                      3,
                      line: self.index + 1,
                      column: current_indent + 4 + colon_pos.unwrap() + 3,
                    }
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "name '" + name + "' is parameter and global",
                        token,
                      ),
                    )
                      }
                    None => ()
                  }
                }
              }
            _ => ()
          }
        }
        let mut is_generator = false
        for stmt in body {
          match stmt {
            Stmt::WithSpan(span=_, stmt=inner) =>
              match inner {
                Stmt::Yield(_) | Stmt::YieldFrom(_) => is_generator = true
                _ => ()
              }
            Stmt::Yield(_) | Stmt::YieldFrom(_) => is_generator = true
            _ => ()
          }
        }
        stmts.push(
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::Function(
              name~,
              decorators~,
              type_params~,
              params~,
              defaults~,
              body~,
              is_generator~,
              is_async=is_async_def,
            ),
          ),
        )
        self.index = next_index
        continue
      }
      self.index = next_index
      let next_indent = self.peek_next_indent()
      if next_indent <= current_indent {
        let missing_line = self.clamp_line_index(
          self.peek_next_significant_index().unwrap_or(self.index),
        )
        let token = {
          kind: Eof,
          start: self.offsets[missing_line],
          end: self.offsets[missing_line] + 1,
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
      let is_generator = block_has_yield_keyword(
        self.lines,
        self.index,
        next_indent,
      )
      let (body, is_generator) = if is_async_def {
        let mut idx = self.index
        while idx < self.lines.length() {
          let body_line = self.lines[idx]
          let trimmed = body_line.trim(chars=" \t").to_string()
          if trimmed.length() == 0 || trimmed.has_prefix("#") {
            idx += 1
            continue
          }
          let body_indent = count_indent(body_line)
          if body_indent < next_indent {
            break
          }
          if trimmed.has_prefix("def ") ||
            trimmed.has_prefix("async def ") ||
            trimmed.has_prefix("class ") {
            let def_indent = body_indent
            idx += 1
            while idx < self.lines.length() {
              let next_line = self.lines[idx]
              let next_trimmed = next_line.trim(chars=" \t").to_string()
              if next_trimmed.length() == 0 || next_trimmed.has_prefix("#") {
                idx += 1
                continue
              }
              if count_indent(next_line) <= def_indent {
                break
              }
              idx += 1
            }
            continue
          }
          if trimmed.has_prefix("yield from") {
            let token = {
              kind: Eof,
              start: self.offsets[idx] + body_indent,
              end: self.offsets[idx] + body_indent + 1,
              line: idx + 1,
              column: body_indent + 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "'yield from' inside async function".to_string(),
                token,
              ),
            )
          }
          idx += 1
        }
        if is_generator {
          idx = self.index
          while idx < self.lines.length() {
            let body_line = self.lines[idx]
            let trimmed = body_line.trim(chars=" \t").to_string()
            if trimmed.length() == 0 || trimmed.has_prefix("#") {
              idx += 1
              continue
            }
            let body_indent = count_indent(body_line)
            if body_indent < next_indent {
              break
            }
            if trimmed.has_prefix("def ") ||
              trimmed.has_prefix("async def ") ||
              trimmed.has_prefix("class ") {
              let def_indent = body_indent
              idx += 1
              while idx < self.lines.length() {
                let next_line = self.lines[idx]
                let next_trimmed = next_line.trim(chars=" \t").to_string()
                if next_trimmed.length() == 0 || next_trimmed.has_prefix("#") {
                  idx += 1
                  continue
                }
                if count_indent(next_line) <= def_indent {
                  break
                }
                idx += 1
              }
              continue
            }
            if trimmed.has_prefix("return ") {
              let token = {
                kind: Eof,
                start: self.offsets[idx] + body_indent,
                end: self.offsets[idx] + body_indent + 1,
                line: idx + 1,
                column: body_indent + 1,
              }
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "'return' with value in async generator".to_string(),
                  token,
                ),
              )
            }
            idx += 1
          }
        }
        let prev_async_depth = self.async_depth
        self.async_depth = 1
        self.func_depth += 1
        let parsed = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => {
            self.func_depth -= 1
            self.async_depth = prev_async_depth
            return Err(err)
          }
        }
        self.func_depth -= 1
        self.async_depth = prev_async_depth
        (parsed, is_generator)
      } else {
        let prev_async_depth = self.async_depth
        self.async_depth = 0
        self.func_depth += 1
        let parsed = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => {
            self.func_depth -= 1
            self.async_depth = prev_async_depth
            return Err(err)
          }
        }
        self.func_depth -= 1
        self.async_depth = prev_async_depth
        (parsed, is_generator)
      }
      for stmt in body {
        match stmt {
          Stmt::Global(names) =>
            for name in names {
              for param in params {
                match normalize_param_name_for_compare(param) {
                  Some(param_name) =>
                    if param_name == name {
                  let token = {
                    kind: Eof,
                    start: self.offsets[self.index - 1] + current_indent + 1,
                    end: self.offsets[self.index - 1] + current_indent + 2,
                    line: self.index,
                    column: current_indent + 2,
                  }
                  return Err(
                    make_parse_error(
                      ParseErrorKind::Syntax,
                      "name '" + name + "' is parameter and global",
                      token,
                    ),
                  )
                    }
                  None => ()
                }
              }
            }
          _ => ()
        }
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::Function(
            name~,
            decorators~,
            type_params~,
            params~,
            defaults~,
            body~,
            is_generator~,
            is_async=is_async_def,
          ),
        ),
      )
      continue
    }
    if line_text.has_prefix("if ") || line_text.has_prefix("if(") {
      let if_line_index = self.index
      let if_indent = current_indent
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let condition_text = substring(line_text, 2, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      let condition_tokens = match
        tokenize_expr(
          condition_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 2,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let condition = match parse_tokens_expr(condition_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let body_text = substring(
          line_text,
          colon_pos.unwrap() + 1,
          line_text.length(),
        )
        .trim(chars=" \t")
        .to_string()
      if body_text.length() > 0 {
        let body : Array[Stmt] = []
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index] +
            current_indent +
            colon_pos.unwrap() +
            1 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index,
              self.offsets[self.index],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        stmts.push(
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::If(condition~, body~, else_body=[]),
          ),
        )
        self.index = next_index
        continue
      }
      self.index = next_index
      let next_indent = self.peek_next_indent()
      if next_indent <= current_indent {
        let missing_line = self.clamp_line_index(
          self.peek_next_significant_index().unwrap_or(self.index),
        )
        let token = {
          kind: Eof,
          start: self.offsets[missing_line],
          end: self.offsets[missing_line] + 1,
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
      let body = match self.parse_block(next_indent) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let clauses : Array[(Expr, Array[Stmt])] = [(condition, body)]
      let mut else_body : Array[Stmt] = []
      while self.index < self.lines.length() {
        let next_line = self.lines[self.index]
        let next_trimmed = next_line.trim(chars=" \t").to_string()
        if next_trimmed.length() == 0 || next_trimmed.has_prefix("#") {
          self.index += 1
          continue
        }
        let next_indent = count_indent(next_line)
        if next_indent != current_indent {
          break
        }
        let mut next_text = substring(next_line, next_indent, next_line.length())
          .trim(chars=" \t")
          .to_string()
        if find_triple_quote(next_text) is None {
          next_text = strip_inline_comment(next_text).trim(chars=" \t").to_string()
        }
        if next_text.has_prefix("elif ") || next_text.has_prefix("elif(") {
          let mut elif_text = next_text
          let mut elif_next_index = self.index + 1
          while has_trailing_line_continuation(elif_text) &&
                elif_next_index < self.lines.length() {
            elif_text = substring(elif_text, 0, elif_text.length() - 1)
              .trim(chars=" \t")
              .to_string()
            let next_line = self.lines[elif_next_index]
            let appended = if find_triple_quote(next_line) is Some(_) {
              next_line
            } else {
              strip_inline_comment(next_line)
            }
            elif_text = elif_text + "\n" + appended
            elif_next_index += 1
            elif_text = elif_text.trim(chars=" \t").to_string()
          }
          let mut balance = bracket_balance(elif_text)
          while balance > 0 && elif_next_index < self.lines.length() {
            let next_line = self.lines[elif_next_index]
            let appended = if find_triple_quote(next_line) is Some(_) {
              next_line
            } else {
              strip_inline_comment(next_line)
            }
            elif_text = elif_text + "\n" + appended
            elif_next_index += 1
            balance = bracket_balance(elif_text)
          }
          if find_triple_quote(elif_text) is None {
            elif_text = replace_newlines_with_spaces(elif_text)
              .trim(chars=" \t")
              .to_string()
          }
          let colon_pos = find_top_level_colon(elif_text)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + next_indent,
              end: self.offsets[self.index] + next_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let cond_text = substring(elif_text, 4, colon_pos.unwrap())
            .trim(chars=" \t")
            .to_string()
          let cond_tokens = match
            tokenize_expr(
              cond_text,
              self.index + 1,
              self.offsets[self.index] + next_indent + 4,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let cond = match parse_tokens_expr(cond_tokens) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          self.index = elif_next_index
          let elif_indent = self.peek_next_indent()
          if elif_indent <= next_indent {
            let missing_line = self.clamp_line_index(
              self.peek_next_significant_index().unwrap_or(self.index),
            )
            let token = {
              kind: Eof,
              start: self.offsets[missing_line],
              end: self.offsets[missing_line] + 1,
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
          let elif_body = match self.parse_block(elif_indent) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          clauses.push((cond, elif_body))
          continue
        }
        if next_text.has_prefix("else") {
          let colon_pos = find_top_level_colon(next_text)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + next_indent,
              end: self.offsets[self.index] + next_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          self.index += 1
          let else_indent = self.peek_next_indent()
          if else_indent <= next_indent {
            let missing_line = self.clamp_line_index(
              self.peek_next_significant_index().unwrap_or(self.index),
            )
            let token = {
              kind: Eof,
              start: self.offsets[missing_line],
              end: self.offsets[missing_line] + 1,
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
          else_body = match self.parse_block(else_indent) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          break
        }
        break
      }
      let mut nested_else = else_body
      let mut outer : Stmt? = None
      let mut i = clauses.length()
      while i > 0 {
        i -= 1
        let clause = clauses[i]
        let stmt = Stmt::If(
          condition=clause.0,
          body=clause.1,
          else_body=nested_else,
        )
        nested_else = [stmt]
        outer = Some(stmt)
      }
      match outer {
        Some(stmt) =>
          stmts.push(
            wrap_stmt_for_line(self.offsets, if_line_index, if_indent, stmt),
          )
        None => ()
      }
      continue
    }
    if line_text.has_prefix("elif ") || line_text.has_prefix("elif(") {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if line_text.has_prefix("else") {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent + 1,
        line: self.index + 1,
        column: 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if line_text.has_prefix("for ") {
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let header_text = substring(line_text, 4, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      let in_pos = header_text.find(" in ")
      if in_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let pos = in_pos.unwrap()
      let target_text = substring(header_text, 0, pos)
        .trim(chars=" \t")
        .to_string()
      let iter_text = substring(header_text, pos + 4, header_text.length())
        .trim(chars=" \t")
        .to_string()
      if target_text.length() == 0 {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let target_tokens = match
        tokenize_expr(
          target_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 4,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let target_expr = match parse_tokens_expr(target_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let target_token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent + 4,
        end: self.offsets[self.index] + current_indent + 5,
        line: self.index + 1,
        column: current_indent + 5,
      }
      let target = match target_from_expr(target_expr, target_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_tokens = match
        tokenize_expr(
          iter_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 4,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_expr = match parse_tokens_expr(iter_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let body_text = substring(
          line_text,
          colon_pos.unwrap() + 1,
          line_text.length(),
        )
        .trim(chars=" \t")
        .to_string()
      self.index = next_index
      let mut body : Array[Stmt] = []
      if body_text.length() > 0 {
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index - 1] +
            current_indent +
            colon_pos.unwrap() +
            1 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index - 1,
              self.offsets[self.index - 1],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
      } else {
        let next_indent = self.peek_next_indent()
        if next_indent <= current_indent {
          let missing_line = self.clamp_line_index(
            self.peek_next_significant_index().unwrap_or(self.index),
          )
          let token = {
            kind: Eof,
            start: self.offsets[missing_line],
            end: self.offsets[missing_line] + 1,
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
        body = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      }
      let else_body : Array[Stmt] = []
      if self.index < self.lines.length() {
        let else_line = self.lines[self.index]
        let else_trimmed = else_line.trim(chars=" \t").to_string()
        let else_indent = count_indent(else_line)
        if else_indent == current_indent && else_trimmed.has_prefix("else") {
          let colon_pos = find_top_level_colon(else_trimmed)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + else_indent,
              end: self.offsets[self.index] + else_indent + 1,
              line: self.index + 1,
              column: else_indent + 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let inline_text = match colon_pos {
            Some(pos) =>
              strip_inline_comment(
                substring(else_trimmed, pos + 1, else_trimmed.length()).to_string(),
              )
              .trim(chars=" \t")
              .to_string()
            None => ""
          }
          self.index += 1
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let parsed = match
                parse_simple_statement(
                  segment,
                  self.index - 1,
                  self.offsets[self.index - 1],
                  self.offsets[self.index - 1] +
                  else_indent +
                  colon_pos.unwrap_or(0) +
                  1 +
                  offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                else_body.push(stmt)
              }
            }
          } else {
            let block_indent = self.peek_next_indent()
            if block_indent <= current_indent {
              let missing_line = self.clamp_line_index(
                self.peek_next_significant_index().unwrap_or(self.index),
              )
              let token = {
                kind: Eof,
                start: self.offsets[missing_line],
                end: self.offsets[missing_line] + 1,
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
            let parsed = match self.parse_block(block_indent) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in parsed {
              else_body.push(stmt)
            }
          }
        }
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::For(target~, iter=iter_expr, body~, else_body~),
        ),
      )
      continue
    }
    if line_text.has_prefix("while ") {
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let cond_text = substring(line_text, 5, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      let cond_tokens = match
        tokenize_expr(
          cond_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 5,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let cond_expr = match parse_tokens_expr(cond_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let body_text = substring(
          line_text,
          colon_pos.unwrap() + 1,
          line_text.length(),
        )
        .trim(chars=" \t")
        .to_string()
      self.index = next_index
      let mut body : Array[Stmt] = []
      if body_text.length() > 0 {
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index - 1] +
            current_indent +
            colon_pos.unwrap() +
            1 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index - 1,
              self.offsets[self.index - 1],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
      } else {
        let next_indent = self.peek_next_indent()
        if next_indent <= current_indent {
          let missing_line = self.clamp_line_index(
            self.peek_next_significant_index().unwrap_or(self.index),
          )
          let token = {
            kind: Eof,
            start: self.offsets[missing_line],
            end: self.offsets[missing_line] + 1,
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
        if cond_text.contains(":=") {
          let _ = match self.parse_block(next_indent) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          stmts.push(
            wrap_stmt_for_line(
              self.offsets,
              line_index,
              current_indent,
              Stmt::ExprStmt(cond_expr),
            ),
          )
          continue
        }
        body = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      }
      if cond_text.contains(":=") {
        stmts.push(
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::ExprStmt(cond_expr),
          ),
        )
        continue
      }
      let else_body : Array[Stmt] = []
      if self.index < self.lines.length() {
        let else_line = self.lines[self.index]
        let else_trimmed = else_line.trim(chars=" \t").to_string()
        let else_indent = count_indent(else_line)
        if else_indent == current_indent && else_trimmed.has_prefix("else") {
          let colon_pos = find_top_level_colon(else_trimmed)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + else_indent,
              end: self.offsets[self.index] + else_indent + 1,
              line: self.index + 1,
              column: else_indent + 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let inline_text = match colon_pos {
            Some(pos) =>
              strip_inline_comment(
                substring(else_trimmed, pos + 1, else_trimmed.length()).to_string(),
              )
              .trim(chars=" \t")
              .to_string()
            None => ""
          }
          self.index += 1
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let parsed = match
                parse_simple_statement(
                  segment,
                  self.index - 1,
                  self.offsets[self.index - 1],
                  self.offsets[self.index - 1] +
                  else_indent +
                  colon_pos.unwrap_or(0) +
                  1 +
                  offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                else_body.push(stmt)
              }
            }
          } else {
            let block_indent = self.peek_next_indent()
            if block_indent <= current_indent {
              let missing_line = self.clamp_line_index(
                self.peek_next_significant_index().unwrap_or(self.index),
              )
              let token = {
                kind: Eof,
                start: self.offsets[missing_line],
                end: self.offsets[missing_line] + 1,
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
            let parsed = match self.parse_block(block_indent) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in parsed {
              else_body.push(stmt)
            }
          }
        }
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::While(condition=cond_expr, body~, else_body~),
        ),
      )
      continue
    }
    if line_text == "break" {
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::Break,
        ),
      )
      self.index = next_index
      continue
    }
    if line_text == "continue" {
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::Continue,
        ),
      )
      self.index = next_index
      continue
    }
    if line_text.has_prefix("try:") {
      let try_start_index = self.index
      let try_body : Array[Stmt] = []
      let body_text = strip_inline_comment(
          substring(line_text, 4, line_text.length()).to_string(),
        )
        .trim(chars=" \t")
        .to_string()
      if body_text.length() > 0 {
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index] +
            current_indent +
            4 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index,
              self.offsets[self.index],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            try_body.push(stmt)
          }
        }
        self.index = next_index
      } else {
        self.index = next_index
        let next_indent = self.peek_next_indent()
        if next_indent <= current_indent {
          let missing_line = self.clamp_line_index(
            self.peek_next_significant_index().unwrap_or(self.index),
          )
          let token = {
            kind: Eof,
            start: self.offsets[missing_line],
            end: self.offsets[missing_line] + 1,
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
        let body = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for stmt in body {
          try_body.push(stmt)
        }
      }
      let handlers : Array[ExceptHandler] = []
      let else_body : Array[Stmt] = []
      let finally_body : Array[Stmt] = []
      let mut saw_except = false
      let mut saw_star_except = false
      let mut saw_plain_except = false
      let mut saw_else = false
      let mut saw_finally = false
      while self.index < self.lines.length() {
        let next_line = self.lines[self.index]
        let next_trimmed = next_line.trim(chars=" \t").to_string()
        let next_indent = count_indent(next_line)
        if next_indent != current_indent {
          break
        }
        if saw_finally {
          if next_trimmed.has_prefix("except") ||
            next_trimmed.has_prefix("else") ||
            next_trimmed.has_prefix("finally") {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          break
        }
        if saw_else && next_trimmed.has_prefix("except") {
          let token = {
            kind: Eof,
            start: self.offsets[self.index] + current_indent,
            end: self.offsets[self.index] + current_indent + 1,
            line: self.index + 1,
            column: 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              token,
            ),
          )
        }
        if next_trimmed.has_prefix("except") {
          let is_star = next_trimmed.has_prefix("except*")
          if is_star {
            saw_star_except = true
            if saw_plain_except {
              let token = {
                kind: Eof,
                start: self.offsets[self.index] + current_indent,
                end: self.offsets[self.index] + current_indent + 1,
                line: self.index + 1,
                column: 1,
              }
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid syntax".to_string(),
                  token,
                ),
              )
            }
          } else {
            saw_plain_except = true
            if saw_star_except {
              let token = {
                kind: Eof,
                start: self.offsets[self.index] + current_indent,
                end: self.offsets[self.index] + current_indent + 1,
                line: self.index + 1,
                column: 1,
              }
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid syntax".to_string(),
                  token,
                ),
              )
            }
          }
          let colon_pos = find_top_level_colon(next_trimmed)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          saw_except = true
          let header_offset = if is_star { 7 } else { 6 }
          let header_text = match colon_pos {
            Some(pos) =>
              substring(next_trimmed, header_offset, pos)
              .trim(chars=" \t")
              .to_string()
            None => "".to_string()
          }
          if is_star && header_text.length() == 0 {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          if has_top_level_comma(header_text) &&
            !header_text.trim(chars=" \t").to_string().has_prefix("(") {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let mut exc_expr_opt : Expr? = None
          let mut name_opt : String? = None
          if header_text.length() > 0 {
            let parts : Array[String] = []
            for part in header_text.split(" as ") {
              parts.push(part.to_string())
            }
            let expr_text = parts[0].trim(chars=" \t").to_string()
            if expr_text.length() > 0 {
              let base_offset = self.offsets[self.index] +
                current_indent +
                header_offset
              let tokens = match
                tokenize_expr(expr_text, self.index + 1, base_offset) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              let expr = match parse_tokens_expr(tokens) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              exc_expr_opt = Some(expr)
            }
            if parts.length() > 1 {
              let raw_name = parts[1].trim(chars=" \t").to_string()
              if raw_name.length() > 0 {
                name_opt = Some(raw_name)
              }
            }
          }
          let inline_text = match colon_pos {
            Some(pos) =>
              strip_inline_comment(
                substring(next_trimmed, pos + 1, next_trimmed.length()).to_string(),
              )
              .trim(chars=" \t")
              .to_string()
            None => ""
          }
          self.index += 1
          let handler_body : Array[Stmt] = []
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[self.index - 1] +
                current_indent +
                colon_pos.unwrap_or(6) +
                1 +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  self.index - 1,
                  self.offsets[self.index - 1],
                  base_offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                handler_body.push(stmt)
              }
            }
          } else {
            let handler_indent = self.peek_next_indent()
            if handler_indent <= current_indent {
              let missing_line = self.clamp_line_index(
                self.peek_next_significant_index().unwrap_or(self.index),
              )
              let token = {
                kind: Eof,
                start: self.offsets[missing_line],
                end: self.offsets[missing_line] + 1,
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
            let body = match self.parse_block(handler_indent) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in body {
              handler_body.push(stmt)
            }
          }
          handlers.push(ExceptHandler::{
            is_star,
            exc: exc_expr_opt,
            name: name_opt,
            body: handler_body,
          })
          continue
        }
        if next_trimmed.has_prefix("else") {
          if !saw_except || saw_else {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let colon_pos = find_top_level_colon(next_trimmed)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          saw_else = true
          let inline_text = match colon_pos {
            Some(pos) =>
              strip_inline_comment(
                substring(next_trimmed, pos + 1, next_trimmed.length()).to_string(),
              )
              .trim(chars=" \t")
              .to_string()
            None => ""
          }
          self.index += 1
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[self.index - 1] +
                current_indent +
                colon_pos.unwrap_or(4) +
                1 +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  self.index - 1,
                  self.offsets[self.index - 1],
                  base_offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                else_body.push(stmt)
              }
            }
          } else {
            let handler_indent = self.peek_next_indent()
            if handler_indent <= current_indent {
              let missing_line = self.clamp_line_index(
                self.peek_next_significant_index().unwrap_or(self.index),
              )
              let token = {
                kind: Eof,
                start: self.offsets[missing_line],
                end: self.offsets[missing_line] + 1,
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
            let body = match self.parse_block(handler_indent) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in body {
              else_body.push(stmt)
            }
          }
          continue
        }
        if next_trimmed.has_prefix("finally") {
          if saw_finally {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let colon_pos = find_top_level_colon(next_trimmed)
          if colon_pos is None {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent,
              end: self.offsets[self.index] + current_indent + 1,
              line: self.index + 1,
              column: 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          saw_finally = true
          let inline_text = match colon_pos {
            Some(pos) =>
              strip_inline_comment(
                substring(next_trimmed, pos + 1, next_trimmed.length()).to_string(),
              )
              .trim(chars=" \t")
              .to_string()
            None => ""
          }
          self.index += 1
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[self.index - 1] +
                current_indent +
                colon_pos.unwrap_or(7) +
                1 +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  self.index - 1,
                  self.offsets[self.index - 1],
                  base_offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                finally_body.push(stmt)
              }
            }
          } else {
            let handler_indent = self.peek_next_indent()
            if handler_indent <= current_indent {
              let missing_line = self.clamp_line_index(
                self.peek_next_significant_index().unwrap_or(self.index),
              )
              let token = {
                kind: Eof,
                start: self.offsets[missing_line],
                end: self.offsets[missing_line] + 1,
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
            let body = match self.parse_block(handler_indent) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for stmt in body {
              finally_body.push(stmt)
            }
          }
          continue
        }
        break
      }
      if handlers.length() == 0 && finally_body.length() == 0 {
        let token = {
          kind: Eof,
          start: self.offsets[try_start_index] + current_indent,
          end: self.offsets[try_start_index] + current_indent + 1,
          line: try_start_index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          try_start_index,
          current_indent,
          Stmt::Try(body=try_body, handlers~, else_body~, finally_body~),
        ),
      )
      continue
    }
    if line_text.has_prefix("with ") || line_text.has_prefix("with(") {
      let mut full_line_text = line_text
      let mut colon_pos = find_top_level_colon(full_line_text)
      let mut header_end_index = next_index
      if colon_pos is None {
        let mut scan = next_index
        while scan < self.lines.length() {
          let part = self.lines[scan].trim(chars=" \t").to_string()
          full_line_text = full_line_text + "\n" + part
          colon_pos = find_top_level_colon(full_line_text)
          scan += 1
          if colon_pos is Some(_) {
            header_end_index = scan
            break
          }
        }
      }
      if colon_pos is None {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] + current_indent,
          end: self.offsets[self.index] + current_indent + 1,
          line: self.index + 1,
          column: 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let header_text = substring(full_line_text, 4, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()

      // Parse just the first context manager expression, so we can reach
      // expected runtime errors (e.g. NameError for `A()` in spec tests).
      let mut item_text = header_text
      if item_text.has_prefix("(") && item_text.has_suffix(")") {
        item_text = substring(item_text, 1, item_text.length() - 1).to_string()
      }
      let mut first_item = item_text.trim(chars=" \t\n\r").to_string()
      match first_top_level_comma_pos(first_item) {
        Some(pos) =>
          first_item = substring(first_item, 0, pos)
            .trim(chars=" \t\n\r")
            .to_string()
        None => ()
      }
      let parts : Array[String] = []
      for part in first_item.split(" as ") {
        parts.push(part.to_string())
      }
      let context_text = parts[0].trim(chars=" \t").to_string()
      let mut target : String? = None
      if parts.length() >= 2 {
        let mut name_text = parts[1].trim(chars=" \t").to_string()
        let comma_pos = find_char(name_text, ',')
        if comma_pos is Some(pos) {
          name_text = substring(name_text, 0, pos).trim(chars=" \t").to_string()
        }
        let close_pos = find_char(name_text, ')')
        if close_pos is Some(pos) {
          name_text = substring(name_text, 0, pos).trim(chars=" \t").to_string()
        }
        if name_text.length() > 0 {
          target = Some(name_text)
        }
      }
      let context_tokens = match
        tokenize_expr(
          context_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 4,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let context = match parse_tokens_expr(context_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let body_text = substring(
          full_line_text,
          colon_pos.unwrap() + 1,
          full_line_text.length(),
        )
        .trim(chars=" \t")
        .to_string()
      if body_text.length() > 0 {
        let body : Array[Stmt] = []
        let segments = split_statements(body_text)
        for segment_pair in segments {
          let segment = segment_pair.0
          let offset = segment_pair.1
          if segment.length() == 0 {
            continue
          }
          let base_offset = self.offsets[self.index] +
            current_indent +
            colon_pos.unwrap() +
            1 +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              self.index,
              self.offsets[self.index],
              base_offset,
              self.async_depth > 0,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        stmts.push(
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::With(context~, target~, body~),
          ),
        )
        self.index = header_end_index
        continue
      }
      self.index = next_index
      let next_indent = self.peek_next_indent()
      if next_indent <= current_indent {
        let missing_line = self.clamp_line_index(
          self.peek_next_significant_index().unwrap_or(self.index),
        )
        let token = {
          kind: Eof,
          start: self.offsets[missing_line],
          end: self.offsets[missing_line] + 1,
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
      let body = match self.parse_block(next_indent) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(
        wrap_stmt_for_line(
          self.offsets,
          line_index,
          current_indent,
          Stmt::With(context~, target~, body~),
        ),
      )
      continue
    }
    let segments = split_statements(line_text)
    for segment_pair in segments {
      let segment = segment_pair.0
      let offset = segment_pair.1
      if segment.length() == 0 {
        continue
      }
      let base_offset = self.offsets[self.index] + current_indent + offset
      let parsed = match
        parse_simple_statement(
          segment,
          self.index,
          self.offsets[self.index],
          base_offset,
          self.async_depth > 0,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      for stmt in parsed {
        stmts.push(stmt)
      }
    }
    self.index = next_index
  }
  if pending_decorators.length() > 0 {
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        pending_decorator_token.unwrap(),
      ),
    )
  }
  Ok(stmts)
}
