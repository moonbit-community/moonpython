///|
/// Class and function definition parsing for line blocks.

///|
fn parse_class_stmt(
  parser : LineParser,
  stmts : Array[Stmt],
  pending_decorators : Array[Expr],
  pending_decorator_token : Token?,
  line_text : String,
  line_index : Int,
  current_indent : Int,
  next_index : Int,
) -> Result[(Bool, Array[Expr], Token?), ParseError] {
  if !line_text.has_prefix("class ") {
    return Ok((false, pending_decorators, pending_decorator_token))
  }
  let decorators = pending_decorators
  let next_pending : Array[Expr] = []
  let next_token : Token? = None
  let colon_pos = find_top_level_colon(line_text)
  if colon_pos is None {
    let token = {
      kind: Eof,
      start: parser.offsets[parser.index] + current_indent,
      end: parser.offsets[parser.index] + current_indent + 1,
      line: parser.index + 1,
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
    Some(span) => substring(header, 0, span.0).trim(chars=" \t\n\r").to_string()
    None => header
  }
  let name_token = {
    kind: Eof,
    start: parser.offsets[parser.index] + current_indent + 6,
    end: parser.offsets[parser.index] + current_indent + 7,
    line: parser.index + 1,
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
                start: parser.offsets[parser.index] + current_indent + 6,
                end: parser.offsets[parser.index] + current_indent + 7,
                line: parser.index + 1,
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
                  start: parser.offsets[parser.index] + current_indent + 6,
                  end: parser.offsets[parser.index] + current_indent + 7,
                  line: parser.index + 1,
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
              start: parser.offsets[parser.index] + current_indent + 6,
              end: parser.offsets[parser.index] + current_indent + 7,
              line: parser.index + 1,
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
      start: parser.offsets[parser.index] + current_indent,
      end: parser.offsets[parser.index] + current_indent + 1,
      line: parser.index + 1,
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
      let base_offset = parser.offsets[parser.index] +
        current_indent +
        colon_pos.unwrap() +
        1 +
        offset
      let parsed = match
        parse_simple_statement(
          segment,
          parser.index,
          parser.offsets[parser.index],
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
    stmts.push(
      wrap_stmt_for_line(
        parser.offsets,
        line_index,
        current_indent,
        Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~),
      ),
    )
    parser.index = next_index
    return Ok((true, next_pending, next_token))
  }
  parser.index = next_index
  let next_indent = parser.peek_next_indent()
  if next_indent <= current_indent {
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
  let body = match parser.parse_block(next_indent) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  stmts.push(
    wrap_stmt_for_line(
      parser.offsets,
      line_index,
      current_indent,
      Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~),
    ),
  )
  Ok((true, next_pending, next_token))
}

///|
fn parse_def_stmt(
  parser : LineParser,
  stmts : Array[Stmt],
  pending_decorators : Array[Expr],
  pending_decorator_token : Token?,
  line_text_in : String,
  line : String,
  line_index : Int,
  current_indent : Int,
  next_index : Int,
) -> Result[(Bool, Array[Expr], Token?), ParseError] {
  let mut line_text = line_text_in
  let mut is_async_def = false
  if line_text.has_prefix("async def ") {
    is_async_def = true
    line_text = "def " + substring(line_text, 10, line_text.length())
  }
  if !line_text.has_prefix("def ") {
    return Ok((false, pending_decorators, pending_decorator_token))
  }
  let decorators = pending_decorators
  let next_pending : Array[Expr] = []
  let next_token : Token? = None
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
      start: parser.offsets[parser.index],
      end: parser.offsets[parser.index] + line.length(),
      line: parser.index + 1,
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
    start: parser.offsets[parser.index] + current_indent + 4,
    end: parser.offsets[parser.index] + current_indent + 5,
    line: parser.index + 1,
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
        start: parser.offsets[parser.index] + current_indent + 4 + i,
        end: parser.offsets[parser.index] + current_indent + 4 + i + 1,
        line: parser.index + 1,
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
      name = substring(trimmed_param, 0, eq_idx).trim(chars=" \t").to_string()
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
          start: parser.offsets[parser.index] + param_base + param_offset,
          end: parser.offsets[parser.index] + param_base + param_offset + 1,
          line: parser.index + 1,
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
        start: parser.offsets[parser.index] + param_base + param_offset,
        end: parser.offsets[parser.index] + param_base + param_offset + 1,
        line: parser.index + 1,
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
        start: parser.offsets[parser.index] + param_base + param_offset,
        end: parser.offsets[parser.index] + param_base + param_offset + 1,
        line: parser.index + 1,
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
        start: parser.offsets[parser.index] + param_base + param_offset,
        end: parser.offsets[parser.index] + param_base + param_offset + 1,
        line: parser.index + 1,
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
        let default_text = substring(raw_param, eq_idx + 1, raw_param.length())
          .trim(chars=" \t\n\r")
          .to_string()
        let tokens = match
          tokenize_expr(
            default_text,
            parser.index + 1,
            parser.offsets[parser.index] + param_base + param_start + eq_idx + 1,
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
  if !is_async_def && line_has_await_keyword(body_text) {
    let token = {
      kind: Eof,
      start: parser.offsets[parser.index] + current_indent,
      end: parser.offsets[parser.index] + current_indent + 1,
      line: parser.index + 1,
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
      let base_offset = parser.offsets[parser.index] +
        current_indent +
        4 +
        colon_pos.unwrap() +
        1 +
        offset
      let parsed = match
        parse_simple_statement(
          segment,
          parser.index,
          parser.offsets[parser.index],
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
                          start: parser.offsets[parser.index] +
                          current_indent +
                          4 +
                          colon_pos.unwrap() +
                          2,
                          end: parser.offsets[parser.index] +
                          current_indent +
                          4 +
                          colon_pos.unwrap() +
                          3,
                          line: parser.index + 1,
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
                      start: parser.offsets[parser.index] +
                      current_indent +
                      4 +
                      colon_pos.unwrap() +
                      2,
                      end: parser.offsets[parser.index] +
                      current_indent +
                      4 +
                      colon_pos.unwrap() +
                      3,
                      line: parser.index + 1,
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
        parser.offsets,
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
    parser.index = next_index
    return Ok((true, next_pending, next_token))
  }
  parser.index = next_index
  let body_start_index = parser.index
  let next_indent = parser.peek_next_indent()
  if next_indent <= current_indent {
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
  let (body, _) = if is_async_def {
    let mut idx = parser.index
    while idx < parser.lines.length() {
      let body_line = parser.lines[idx]
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
        while idx < parser.lines.length() {
          let next_line = parser.lines[idx]
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
          start: parser.offsets[idx] + body_indent,
          end: parser.offsets[idx] + body_indent + 1,
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
    let prev_async_depth = parser.async_depth
    parser.async_depth = 1
    parser.func_depth += 1
    let parsed = match parser.parse_block(next_indent) {
      Ok(value) => value
      Err(err) => {
        parser.func_depth -= 1
        parser.async_depth = prev_async_depth
        return Err(err)
      }
    }
    parser.func_depth -= 1
    parser.async_depth = prev_async_depth
    (parsed, false)
  } else {
    let prev_async_depth = parser.async_depth
    parser.async_depth = 0
    parser.func_depth += 1
    let parsed = match parser.parse_block(next_indent) {
      Ok(value) => value
      Err(err) => {
        parser.func_depth -= 1
        parser.async_depth = prev_async_depth
        return Err(err)
      }
    }
    parser.func_depth -= 1
    parser.async_depth = prev_async_depth
    (parsed, false)
  }
  let has_yield_ref : Ref[Bool] = { val: false }
  let has_yield_from_ref : Ref[Bool] = { val: false }
  let has_return_value_ref : Ref[Bool] = { val: false }
  fn scan_expr_for_yield(
    expr : Expr,
    has_yield_ref : Ref[Bool],
    has_yield_from_ref : Ref[Bool],
  ) -> Unit {
    match expr {
      Expr::Yield(value) => {
        has_yield_ref.val = true
        match value {
          Some(inner) =>
            scan_expr_for_yield(inner, has_yield_ref, has_yield_from_ref)
          None => ()
        }
      }
      Expr::YieldFrom(value) => {
        has_yield_ref.val = true
        has_yield_from_ref.val = true
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      }
      Expr::Tuple(items) | Expr::List(items) | Expr::Set(items) =>
        for item in items {
          scan_expr_for_yield(item, has_yield_ref, has_yield_from_ref)
        }
      Expr::Dict(pairs) =>
        for pair in pairs {
          scan_expr_for_yield(pair.0, has_yield_ref, has_yield_from_ref)
          scan_expr_for_yield(pair.1, has_yield_ref, has_yield_from_ref)
        }
      Expr::ListComp(elt~, clauses~, filters~)
      | Expr::GenExp(elt~, clauses~, filters~)
      | Expr::SetComp(elt~, clauses~, filters~) => {
        scan_expr_for_yield(elt, has_yield_ref, has_yield_from_ref)
        for clause in clauses {
          scan_expr_for_yield(clause.iter, has_yield_ref, has_yield_from_ref)
        }
        for filter_expr in filters {
          scan_expr_for_yield(filter_expr, has_yield_ref, has_yield_from_ref)
        }
      }
      Expr::DictComp(key~, value~, clauses~, filters~) => {
        scan_expr_for_yield(key, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
        for clause in clauses {
          scan_expr_for_yield(clause.iter, has_yield_ref, has_yield_from_ref)
        }
        for filter_expr in filters {
          scan_expr_for_yield(filter_expr, has_yield_ref, has_yield_from_ref)
        }
      }
      Expr::Lambda(..) => ()
      Expr::IfExpr(condition~, then_expr~, else_expr~) => {
        scan_expr_for_yield(condition, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(then_expr, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(else_expr, has_yield_ref, has_yield_from_ref)
      }
      Expr::NamedExpr(name=_, value~) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Expr::Await(value) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Expr::Slice(start~, end~, step~) => {
        match start {
          Some(value) =>
            scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
          None => ()
        }
        match end {
          Some(value) =>
            scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
          None => ()
        }
        match step {
          Some(value) =>
            scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
          None => ()
        }
      }
      Expr::Attribute(value~, attr=_) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Expr::Subscript(value~, index~) => {
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(index, has_yield_ref, has_yield_from_ref)
      }
      Expr::Call(callee~, args~) => {
        scan_expr_for_yield(callee, has_yield_ref, has_yield_from_ref)
        for arg in args {
          scan_expr_for_yield(arg, has_yield_ref, has_yield_from_ref)
        }
      }
      Expr::Keyword(name=_, value~) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Expr::Unary(op=_, expr~) =>
        scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
      Expr::Binary(op=_, left~, right~) => {
        scan_expr_for_yield(left, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(right, has_yield_ref, has_yield_from_ref)
      }
      Expr::BoolOp(op=_, values~) =>
        for value in values {
          scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
        }
      Expr::Compare(left~, ops=_, comparators~) => {
        scan_expr_for_yield(left, has_yield_ref, has_yield_from_ref)
        for value in comparators {
          scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
        }
      }
      _ => ()
    }
  }

  fn scan_target_for_yield(
    target : Target,
    has_yield_ref : Ref[Bool],
    has_yield_from_ref : Ref[Bool],
  ) -> Unit {
    match target {
      Target::Attribute(value~, attr=_) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Target::Subscript(value~, index~) => {
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(index, has_yield_ref, has_yield_from_ref)
      }
      Target::Tuple(items) | Target::List(items) =>
        for item in items {
          scan_target_for_yield(item, has_yield_ref, has_yield_from_ref)
        }
      Target::Starred(inner) =>
        scan_target_for_yield(inner, has_yield_ref, has_yield_from_ref)
      _ => ()
    }
  }

  fn scan_stmt_for_yield(
    stmt : Stmt,
    has_yield_ref : Ref[Bool],
    has_yield_from_ref : Ref[Bool],
    has_return_value_ref : Ref[Bool],
  ) -> Unit {
    match stmt {
      Stmt::WithSpan(span=_, stmt=inner) =>
        scan_stmt_for_yield(
          inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
        )
      Stmt::ExprStmt(expr) =>
        scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
      Stmt::Assign(target~, value~) => {
        scan_target_for_yield(target, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      }
      Stmt::AugAssign(target~, op=_, value~) => {
        scan_target_for_yield(target, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      }
      Stmt::TypeAlias(name=_, type_params=_, value~) =>
        scan_expr_for_yield(value, has_yield_ref, has_yield_from_ref)
      Stmt::Return(value) =>
        match value {
          Some(expr) => {
            has_return_value_ref.val = true
            scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
          }
          None => ()
        }
      Stmt::Yield(value) => {
        has_yield_ref.val = true
        match value {
          Some(expr) =>
            scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
          None => ()
        }
      }
      Stmt::YieldFrom(expr) => {
        has_yield_ref.val = true
        has_yield_from_ref.val = true
        scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
      }
      Stmt::If(condition~, body~, else_body~) => {
        scan_expr_for_yield(condition, has_yield_ref, has_yield_from_ref)
        for inner in body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
        for inner in else_body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
      }
      Stmt::Match(subject~, cases~) => {
        scan_expr_for_yield(subject, has_yield_ref, has_yield_from_ref)
        for case_item in cases {
          let case_guard = case_item.1
          let case_body = case_item.2
          match case_guard {
            Some(expr) =>
              scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
            None => ()
          }
          for inner in case_body {
            scan_stmt_for_yield(
              inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
            )
          }
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        scan_expr_for_yield(condition, has_yield_ref, has_yield_from_ref)
        for inner in body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
        for inner in else_body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
      }
      Stmt::For(target~, iter~, body~, else_body~)
      | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        scan_target_for_yield(target, has_yield_ref, has_yield_from_ref)
        scan_expr_for_yield(iter, has_yield_ref, has_yield_from_ref)
        for inner in body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
        for inner in else_body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
      }
      Stmt::Assert(condition~, message~) => {
        scan_expr_for_yield(condition, has_yield_ref, has_yield_from_ref)
        match message {
          Some(expr) =>
            scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
          None => ()
        }
      }
      Stmt::Raise(exc~, cause~) => {
        match exc {
          Some(expr) =>
            scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
          None => ()
        }
        match cause {
          Some(expr) =>
            scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
          None => ()
        }
      }
      Stmt::Del(targets) =>
        for target in targets {
          scan_target_for_yield(target, has_yield_ref, has_yield_from_ref)
        }
      Stmt::With(context~, target=_, body~)
      | Stmt::AsyncWith(context~, target=_, body~) => {
        scan_expr_for_yield(context, has_yield_ref, has_yield_from_ref)
        for inner in body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        for inner in body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
        for handler in handlers {
          match handler.exc {
            Some(expr) =>
              scan_expr_for_yield(expr, has_yield_ref, has_yield_from_ref)
            None => ()
          }
          for inner in handler.body {
            scan_stmt_for_yield(
              inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
            )
          }
        }
        for inner in else_body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
        for inner in finally_body {
          scan_stmt_for_yield(
            inner, has_yield_ref, has_yield_from_ref, has_return_value_ref,
          )
        }
      }
      Stmt::Function(..) | Stmt::Class(..) => ()
      _ => ()
    }
  }

  for stmt in body {
    scan_stmt_for_yield(
      stmt, has_yield_ref, has_yield_from_ref, has_return_value_ref,
    )
  }
  let is_generator = has_yield_ref.val || has_yield_from_ref.val
  if is_async_def {
    if has_yield_from_ref.val {
      let mut idx = body_start_index
      while idx < parser.lines.length() {
        let body_line = parser.lines[idx]
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
          while idx < parser.lines.length() {
            let next_line = parser.lines[idx]
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
            start: parser.offsets[idx] + body_indent,
            end: parser.offsets[idx] + body_indent + 1,
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
    }
    if is_generator && has_return_value_ref.val {
      let mut idx = body_start_index
      while idx < parser.lines.length() {
        let body_line = parser.lines[idx]
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
          while idx < parser.lines.length() {
            let next_line = parser.lines[idx]
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
            start: parser.offsets[idx] + body_indent,
            end: parser.offsets[idx] + body_indent + 1,
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
                    start: parser.offsets[parser.index - 1] + current_indent + 1,
                    end: parser.offsets[parser.index - 1] + current_indent + 2,
                    line: parser.index,
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
      parser.offsets,
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
  Ok((true, next_pending, next_token))
}
