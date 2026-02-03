///|
/// Line/block parser for moonpython.
///
/// Implementation is split across:
/// - parser_line_core.mbt
/// - parser_line_match.mbt
/// - parser_line_defs.mbt
///

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
      // Remember the indent level we just dedented from. If the next statement
      // is indented to a level that doesn't match any active block, CPython
      // reports it as "unindent does not match any outer indentation level".
      self.last_dedent_from = Some(indent)
      break
    }
    if current_indent > indent {
      match self.last_dedent_from {
        Some(prev_indent) =>
          if current_indent < prev_indent {
            let error_start = if current_indent > 0 {
              current_indent - 1
            } else {
              0
            }
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
                "unindent does not match any outer indentation level".to_string(),
                token,
              ),
            )
          }
        None => ()
      }
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
    // At a stable indentation level, clear any dedent marker.
    self.last_dedent_from = None
    let line_index = self.index
    let raw_line = substring(line, current_indent, line.length()).to_string()
    let mut line_text = raw_line.trim(chars=" \t").to_string()
    if find_triple_quote(raw_line) is None {
      line_text = strip_inline_comment(line_text).trim(chars=" \t").to_string()
    }
    if line_text.has_prefix("async for(") {
      line_text = "async for " + substring(line_text, 9, line_text.length())
    }
    if line_text.has_prefix("for(") {
      line_text = "for " + substring(line_text, 3, line_text.length())
    }
    if line_text.has_prefix("while(") {
      line_text = "while " + substring(line_text, 5, line_text.length())
    }
    let mut next_index = self.index + 1
    match unclosed_triple_quote(raw_line) {
      None => ()
      Some(_) => {
        let mut combined = raw_line
        let mut idx = self.index + 1
        while idx < self.lines.length() {
          let next_line = self.lines[idx]
          combined = combined + "\n" + next_line
          idx += 1
          if unclosed_triple_quote(combined) is None {
            next_index = idx
            line_text = combined
            break
          }
        }
        if idx == self.lines.length() &&
          unclosed_triple_quote(combined) is Some(_) {
          line_text = combined
          next_index = idx
        }
      }
    }
    while has_unclosed_string_line_continuation(line_text) &&
          next_index < self.lines.length() {
      // Backslash-newline inside a non-triple-quoted string literal (e.g.
      // `"foo\\\nbar"`). Join physical lines so the lexer can treat the
      // `\\\n` pair as a line continuation inside the string.
      let next_line = self.lines[next_index]
      line_text = line_text + "\n" + next_line
      next_index += 1
    }
    while has_trailing_line_continuation(line_text) &&
          next_index < self.lines.length() {
      let next_line = self.lines[next_index]
      // For explicit `\\` line continuations we drop the backslash and join
      // with a space. Keeping raw newlines here would break statement/header
      // parsing for `def ... \\` signatures in the stdlib (e.g. Lib/traceback.py).
      line_text = substring(line_text, 0, line_text.length() - 1)
        .trim(chars=" \t")
        .to_string()
      let appended = if find_triple_quote(next_line) is Some(_) {
        next_line
      } else {
        strip_inline_comment(next_line)
      }
      line_text = line_text + " " + appended
      next_index += 1
      line_text = line_text.trim(chars=" \t").to_string()
    }
    match unclosed_triple_quote(line_text) {
      None => ()
      Some(_) => {
        let mut combined = line_text
        let mut idx = next_index
        while idx < self.lines.length() {
          let next_line = self.lines[idx]
          combined = combined + "\n" + next_line
          idx += 1
          if unclosed_triple_quote(combined) is None {
            next_index = idx
            line_text = combined
            break
          }
        }
        if idx == self.lines.length() &&
          unclosed_triple_quote(combined) is Some(_) {
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
      // Preserve physical newlines so the lexer can track correct token
      // line/column offsets for multi-line expressions (PEP 657 caret tests).
      line_text = line_text.trim(chars=" \t").to_string()
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
    // `await` legality is checked after parsing the whole block, so we can
    // allow `await` inside generator expressions in sync code.
    let handled = match
      parse_match_stmt(
        self, stmts, line_text, line_index, current_indent, next_index,
      ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if handled {
      continue
    }
    if line_text.has_prefix("@") {
      let decorator_line_index = self.index
      let mut expr_text = substring(line_text, 1, line_text.length())
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
      let mut decorator_next_index = next_index
      while has_trailing_line_continuation(expr_text) &&
            decorator_next_index < self.lines.length() {
        expr_text = substring(expr_text, 0, expr_text.length() - 1)
          .trim(chars=" \t")
          .to_string()
        let next_line = self.lines[decorator_next_index]
        let appended = if find_triple_quote(next_line) is Some(_) {
          next_line
        } else {
          strip_inline_comment(next_line)
        }
        expr_text = expr_text + " " + appended
        decorator_next_index += 1
        expr_text = expr_text.trim(chars=" \t").to_string()
      }
      let mut balance = bracket_balance(expr_text)
      while balance > 0 && decorator_next_index < self.lines.length() {
        let next_line = self.lines[decorator_next_index]
        let appended = if find_triple_quote(next_line) is Some(_) {
          next_line
        } else {
          strip_inline_comment(next_line)
        }
        expr_text = expr_text + "\n" + appended
        decorator_next_index += 1
        balance = bracket_balance(expr_text)
      }
      if find_triple_quote(expr_text) is None {
        expr_text = expr_text.trim(chars=" \t").to_string()
      }
      let tokens = match
        tokenize_expr(
          expr_text,
          decorator_line_index + 1,
          self.offsets[decorator_line_index] + current_indent + 1,
          current_indent + 2,
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
          start: self.offsets[decorator_line_index] + current_indent,
          end: self.offsets[decorator_line_index] + current_indent + 1,
          line: decorator_line_index + 1,
          column: 1,
        })
      }
      self.index = decorator_next_index
      continue
    }
    let (handled, next_pending, next_token) = match
      parse_class_stmt(
        self, stmts, pending_decorators, pending_decorator_token, line_text, line_index,
        current_indent, next_index,
      ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    pending_decorators = next_pending
    pending_decorator_token = next_token
    if handled {
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
      let mut header_text = substring(line_text, 10, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      header_text = strip_wrapping_parens(header_text)
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
          current_indent + 11,
        ) {
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
      // `for` targets allow starred assignment targets like `for a, *_ in xs:`.
      let target = match
        target_from_assignment_tokens(target_tokens, target_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_tokens = match
        tokenize_expr(
          iter_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 10 + pos + 4,
          current_indent + 10 + pos + 4 + 1,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_expr = match parse_tokens_expr(iter_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let raw_body_text = substring(
        line_text,
        colon_pos.unwrap() + 1,
        line_text.length(),
      ).to_string()
      let body_leading = count_indent(raw_body_text)
      let body_text = raw_body_text.trim(chars=" \t").to_string()
      let body : Array[Stmt] = []
      if body_text.length() > 0 {
        let base_offset = self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          1 +
          body_leading
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
      let mut item_text = header_text
      if item_text.has_prefix("(") && item_text.has_suffix(")") {
        item_text = substring(item_text, 1, item_text.length() - 1).to_string()
      }
      let with_items : Array[(Expr, String?)] = []
      for raw_item in split_top_level_commas(item_text) {
        let item = raw_item.trim(chars=" \t\n\r").to_string()
        if item.length() == 0 {
          // Allow trailing commas inside `async with (...)`.
          continue
        }
        let mut context_text = item
        let mut target : String? = None
        match find_top_level_as_pos(item) {
          Some(pos) => {
            context_text = substring(item, 0, pos)
              .trim(chars=" \t\n\r")
              .to_string()
            let mut name_text = substring(item, pos + 2, item.length())
              .trim(chars=" \t\n\r")
              .to_string()
            let comma_pos = find_char(name_text, ',')
            if comma_pos is Some(pos) {
              name_text = substring(name_text, 0, pos)
                .trim(chars=" \t")
                .to_string()
            }
            let close_pos = find_char(name_text, ')')
            if close_pos is Some(pos) {
              name_text = substring(name_text, 0, pos)
                .trim(chars=" \t")
                .to_string()
            }
            if name_text.length() > 0 {
              target = Some(name_text)
            }
          }
          None => ()
        }
        let context_tokens = match
          tokenize_expr(
            context_text,
            self.index + 1,
            self.offsets[self.index] + current_indent + 10,
            current_indent + 11,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let context = match parse_tokens_expr(context_tokens) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        with_items.push((context, target))
      }
      if with_items.length() == 0 {
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
      let raw_body_text = substring(
        full_line_text,
        colon_pos.unwrap() + 1,
        full_line_text.length(),
      ).to_string()
      let body_leading = count_indent(raw_body_text)
      let body_text = raw_body_text.trim(chars=" \t").to_string()
      if body_text.length() > 0 {
        let body : Array[Stmt] = []
        let base_offset = self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          1 +
          body_leading
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
        let mut nested_body = body
        for i = with_items.length() - 1; i >= 0; i = i - 1 {
          let (context, target) = with_items[i]
          nested_body = [
            wrap_stmt_for_line(
              self.offsets,
              line_index,
              current_indent,
              Stmt::AsyncWith(context~, target~, body=nested_body),
            ),
          ]
        }
        stmts.push(nested_body[0])
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
      let mut nested_body = body
      for i = with_items.length() - 1; i >= 0; i = i - 1 {
        let (context, target) = with_items[i]
        nested_body = [
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::AsyncWith(context~, target~, body=nested_body),
          ),
        ]
      }
      stmts.push(nested_body[0])
      continue
    }
    let (handled, next_pending, next_token) = match
      parse_def_stmt(
        self, stmts, pending_decorators, pending_decorator_token, line_text, line,
        line_index, current_indent, next_index,
      ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    pending_decorators = next_pending
    pending_decorator_token = next_token
    if handled {
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
          current_indent + 3,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let condition = match parse_tokens_expr(condition_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let raw_body_text = substring(
        line_text,
        colon_pos.unwrap() + 1,
        line_text.length(),
      ).to_string()
      let body_leading = count_indent(raw_body_text)
      let body_text = raw_body_text.trim(chars=" \t").to_string()
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
          // Inline suite statements belong to the physical `if` line (even when
          // the header spans multiple lines due to bracket continuation).
          let base_offset = self.offsets[if_line_index] +
            if_indent +
            colon_pos.unwrap() +
            1 +
            body_leading +
            offset
          let parsed = match
            parse_simple_statement(
              segment,
              if_line_index,
              self.offsets[if_line_index],
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
        let mut next_text = substring(
            next_line,
            next_indent,
            next_line.length(),
          )
          .trim(chars=" \t")
          .to_string()
        if find_triple_quote(next_text) is None {
          next_text = strip_inline_comment(next_text)
            .trim(chars=" \t")
            .to_string()
        }
        if next_text.has_prefix("elif ") || next_text.has_prefix("elif(") {
          let elif_line_index = self.index
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
            elif_text = elif_text + " " + appended
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
            elif_text = elif_text.trim(chars=" \t").to_string()
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
              next_indent + 5,
            ) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let cond = match parse_tokens_expr(cond_tokens) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let raw_body_text = substring(
            elif_text,
            colon_pos.unwrap() + 1,
            elif_text.length(),
          ).to_string()
          let body_leading = count_indent(raw_body_text)
          let body_text = raw_body_text.trim(chars=" \t").to_string()
          self.index = elif_next_index
          if body_text.length() > 0 {
            let elif_body : Array[Stmt] = []
            let segments = split_statements(body_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              // Inline suite statements belong to the physical `elif` line.
              let base_offset = self.offsets[elif_line_index] +
                next_indent +
                colon_pos.unwrap() +
                1 +
                body_leading +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  elif_line_index,
                  self.offsets[elif_line_index],
                  base_offset,
                  self.async_depth > 0,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                elif_body.push(stmt)
              }
            }
            clauses.push((cond, elif_body))
            continue
          }
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
          let raw_body_text = substring(
            next_text,
            colon_pos.unwrap() + 1,
            next_text.length(),
          ).to_string()
          let body_leading = count_indent(raw_body_text)
          let body_text = raw_body_text.trim(chars=" \t").to_string()
          self.index += 1
          if body_text.length() > 0 {
            else_body = []
            let segments = split_statements(body_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[self.index - 1] +
                next_indent +
                colon_pos.unwrap() +
                1 +
                body_leading +
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
      let mut header_text = substring(line_text, 4, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      header_text = strip_wrapping_parens(header_text)
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
          current_indent + 5,
        ) {
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
      // `for` targets allow starred assignment targets like `for a, *_ in xs:`.
      let target = match
        target_from_assignment_tokens(target_tokens, target_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_tokens = match
        tokenize_expr(
          iter_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 4,
          current_indent + 5,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_expr = match parse_tokens_expr(iter_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let raw_body_text = substring(
        line_text,
        colon_pos.unwrap() + 1,
        line_text.length(),
      ).to_string()
      let body_leading = count_indent(raw_body_text)
      let body_text = raw_body_text.trim(chars=" \t").to_string()
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
            body_leading +
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
      let mut cond_text = substring(line_text, 5, colon_pos.unwrap())
        .trim(chars=" \t")
        .to_string()
      cond_text = strip_wrapping_parens(cond_text)
      let cond_tokens = match
        tokenize_expr(
          cond_text,
          self.index + 1,
          self.offsets[self.index] + current_indent + 5,
          current_indent + 6,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let cond_expr = match parse_tokens_expr(cond_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let raw_body_text = substring(
        line_text,
        colon_pos.unwrap() + 1,
        line_text.length(),
      ).to_string()
      let body_leading = count_indent(raw_body_text)
      let body_text = raw_body_text.trim(chars=" \t").to_string()
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
            body_leading +
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
    if has_keyword_prefix(line_text, "try") {
      let colon_pos = find_top_level_colon(line_text)
      if colon_pos is None ||
        substring(line_text, 3, colon_pos.unwrap()).trim(chars=" \t").length() >
        0 {
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
      let try_start_index = self.index
      let try_body : Array[Stmt] = []
      let body_text = strip_inline_comment(
          substring(line_text, colon_pos.unwrap() + 1, line_text.length()).to_string(),
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
          let header_start_index = self.index
          let mut full_header = next_trimmed
          let mut header_end_index = self.index + 1
          let mut balance = bracket_balance(full_header)
          while balance > 0 && header_end_index < self.lines.length() {
            let part = self.lines[header_end_index]
              .trim(chars=" \t")
              .to_string()
            full_header = full_header + "\n" + part
            header_end_index += 1
            balance = bracket_balance(full_header)
          }
          let next_trimmed = full_header
          fn is_space_char(c : Char) -> Bool {
            c == ' ' || c == '\t' || c == '\n' || c == '\r'
          }

          let header_chars = next_trimmed.to_array()
          let mut is_star = false
          // Offset where the exception expression (if any) begins.
          // This must account for `except*`, and also for `except *T` where `*`
          // is separated by whitespace/newlines.
          let mut header_offset = 6
          if next_trimmed.has_prefix("except*") {
            is_star = true
            header_offset = 7
          }
          // Also accept `except *TypeError` (PEP 654) where the `*` is separated.
          let mut idx = header_offset
          while idx < header_chars.length() && is_space_char(header_chars[idx]) {
            idx += 1
          }
          if idx < header_chars.length() && header_chars[idx] == '*' {
            is_star = true
            idx += 1
            while idx < header_chars.length() &&
                  is_space_char(header_chars[idx]) {
              idx += 1
            }
            header_offset = idx
          } else {
            header_offset = idx
          }
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
              start: self.offsets[header_start_index] + current_indent,
              end: self.offsets[header_start_index] + current_indent + 1,
              line: header_start_index + 1,
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
              start: self.offsets[header_start_index] + current_indent,
              end: self.offsets[header_start_index] + current_indent + 1,
              line: header_start_index + 1,
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
              start: self.offsets[header_start_index] + current_indent,
              end: self.offsets[header_start_index] + current_indent + 1,
              line: header_start_index + 1,
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
              let base_offset = self.offsets[header_start_index] +
                current_indent +
                header_offset
              let tokens = match
                tokenize_expr(
                  expr_text,
                  header_start_index + 1,
                  base_offset,
                  base_offset - self.offsets[header_start_index] + 1,
                ) {
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
          self.index = header_end_index
          let handler_body : Array[Stmt] = []
          if inline_text.length() > 0 {
            let segments = split_statements(inline_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[header_start_index] +
                current_indent +
                colon_pos.unwrap_or(6) +
                1 +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  header_start_index,
                  self.offsets[header_start_index],
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
          let start = self.offsets[header_start_index] + current_indent
          let mut end = if header_start_index + 1 < self.offsets.length() {
            self.offsets[header_start_index + 1] - 1
          } else {
            start + 1
          }
          if end <= start {
            end = start + 1
          }
          let header_span = Span::{
            start,
            end,
            line: header_start_index + 1,
            column: current_indent + 1,
          }
          handlers.push(ExceptHandler::{
            span: header_span,
            is_star,
            exc: exc_expr_opt,
            name: name_opt,
            body: handler_body,
          })
          continue
        }
        if next_trimmed.has_prefix("else") {
          let else_header_index = self.index
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
            let mut suite_text = inline_text
            let mut suite_end_index = self.index
            let mut balance = bracket_balance(suite_text)
            while balance > 0 && suite_end_index < self.lines.length() {
              let next_line = self.lines[suite_end_index]
              let appended = if find_triple_quote(next_line) is Some(_) {
                next_line
              } else {
                strip_inline_comment(next_line)
              }
              suite_text = suite_text + "\n" + appended
              suite_end_index += 1
              balance = bracket_balance(suite_text)
            }
            self.index = suite_end_index
            let segments = split_statements(suite_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[else_header_index] +
                current_indent +
                colon_pos.unwrap_or(4) +
                1 +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  else_header_index,
                  self.offsets[else_header_index],
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
          let finally_header_index = self.index
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
            let mut suite_text = inline_text
            let mut suite_end_index = self.index
            let mut balance = bracket_balance(suite_text)
            while balance > 0 && suite_end_index < self.lines.length() {
              let next_line = self.lines[suite_end_index]
              let appended = if find_triple_quote(next_line) is Some(_) {
                next_line
              } else {
                strip_inline_comment(next_line)
              }
              suite_text = suite_text + "\n" + appended
              suite_end_index += 1
              balance = bracket_balance(suite_text)
            }
            self.index = suite_end_index
            let segments = split_statements(suite_text)
            for segment_pair in segments {
              let segment = segment_pair.0
              let offset = segment_pair.1
              if segment.length() == 0 {
                continue
              }
              let base_offset = self.offsets[finally_header_index] +
                current_indent +
                colon_pos.unwrap_or(7) +
                1 +
                offset
              let parsed = match
                parse_simple_statement(
                  segment,
                  finally_header_index,
                  self.offsets[finally_header_index],
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
      let mut item_text = header_text
      match find_top_level_paren_span(item_text) {
        Some(span) =>
          if span.0 == 0 && span.1 == item_text.length() - 1 {
            item_text = substring(item_text, 1, item_text.length() - 1).to_string()
          }
        None => ()
      }
      let with_items : Array[(Expr, String?)] = []
      for raw_item in split_top_level_commas(item_text) {
        let item = raw_item.trim(chars=" \t\n\r").to_string()
        if item.length() == 0 {
          // Allow trailing commas inside `with (...)`.
          continue
        }
        let mut context_text = item
        let mut target : String? = None
        match find_top_level_as_pos(item) {
          Some(pos) => {
            context_text = substring(item, 0, pos)
              .trim(chars=" \t\n\r")
              .to_string()
            let mut name_text = substring(item, pos + 2, item.length())
              .trim(chars=" \t\n\r")
              .to_string()
            let comma_pos = find_char(name_text, ',')
            if comma_pos is Some(pos) {
              name_text = substring(name_text, 0, pos)
                .trim(chars=" \t")
                .to_string()
            }
            let close_pos = find_char(name_text, ')')
            if close_pos is Some(pos) {
              name_text = substring(name_text, 0, pos)
                .trim(chars=" \t")
                .to_string()
            }
            if name_text.length() > 0 {
              target = Some(name_text)
            }
          }
          None => ()
        }
        let context_tokens = match
          tokenize_expr(
            context_text,
            self.index + 1,
            self.offsets[self.index] + current_indent + 4,
            current_indent + 5,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let context = match parse_tokens_expr(context_tokens) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        with_items.push((context, target))
      }
      if with_items.length() == 0 {
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
      let raw_body_text = substring(
        full_line_text,
        colon_pos.unwrap() + 1,
        full_line_text.length(),
      ).to_string()
      let body_leading = count_indent(raw_body_text)
      let body_text = raw_body_text.trim(chars=" \t").to_string()
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
            body_leading +
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
        let mut nested_body = body
        for i = with_items.length() - 1; i >= 0; i = i - 1 {
          let (context, target) = with_items[i]
          nested_body = [
            wrap_stmt_for_line(
              self.offsets,
              line_index,
              current_indent,
              Stmt::With(context~, target~, body=nested_body),
            ),
          ]
        }
        stmts.push(nested_body[0])
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
      let mut nested_body = body
      for i = with_items.length() - 1; i >= 0; i = i - 1 {
        let (context, target) = with_items[i]
        nested_body = [
          wrap_stmt_for_line(
            self.offsets,
            line_index,
            current_indent,
            Stmt::With(context~, target~, body=nested_body),
          ),
        ]
      }
      stmts.push(nested_body[0])
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
  if self.async_depth == 0 {
    match stmts_first_illegal_await_line(stmts) {
      Some(line) => {
        let line_index = if line <= 0 { 0 } else { line - 1 }
        let base = self.offsets[line_index]
        let token = { kind: Eof, start: base, end: base + 1, line, column: 1 }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      None => ()
    }
  }
  Ok(stmts)
}
