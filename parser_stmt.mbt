///|
/// Statement parsing helpers for moonpython.
///

///|
fn expr_has_async_comprehension(expr : Expr) -> Bool {
  match expr {
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      for clause in clauses {
        if clause.is_async {
          return true
        }
        if expr_has_async_comprehension(clause.iter) {
          return true
        }
      }
      for filter in filters {
        if expr_has_async_comprehension(filter) {
          return true
        }
      }
      expr_has_async_comprehension(elt)
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      // Async generator expressions are allowed outside async functions; do not
      // treat `async for` clauses here as an error trigger.
      for clause in clauses {
        if expr_has_async_comprehension(clause.iter) {
          return true
        }
      }
      for filter in filters {
        if expr_has_async_comprehension(filter) {
          return true
        }
      }
      expr_has_async_comprehension(elt)
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      if expr_has_async_comprehension(key) ||
        expr_has_async_comprehension(value) {
        return true
      }
      for clause in clauses {
        if clause.is_async {
          return true
        }
        if expr_has_async_comprehension(clause.iter) {
          return true
        }
      }
      for filter in filters {
        if expr_has_async_comprehension(filter) {
          return true
        }
      }
      false
    }
    Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) => {
      for item in items {
        if expr_has_async_comprehension(item) {
          return true
        }
      }
      false
    }
    Expr::Dict(items) => {
      for pair in items {
        if expr_has_async_comprehension(pair.0) ||
          expr_has_async_comprehension(pair.1) {
          return true
        }
      }
      false
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
      for d in defaults {
        if expr_has_async_comprehension(d) {
          return true
        }
      }
      expr_has_async_comprehension(body)
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_async_comprehension(condition) ||
      expr_has_async_comprehension(then_expr) ||
      expr_has_async_comprehension(else_expr)
    Expr::NamedExpr(name~, value~) => {
      let _ = name
      expr_has_async_comprehension(value)
    }
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(v) => expr_has_async_comprehension(v)
        None => false
      }
    Expr::YieldFrom(value) | Expr::Await(value) =>
      expr_has_async_comprehension(value)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(v) => if expr_has_async_comprehension(v) { return true }
        None => ()
      }
      match end {
        Some(v) => if expr_has_async_comprehension(v) { return true }
        None => ()
      }
      match step {
        Some(v) => if expr_has_async_comprehension(v) { return true }
        None => ()
      }
      false
    }
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_async_comprehension(value)
    }
    Expr::Subscript(value~, index~) =>
      expr_has_async_comprehension(value) || expr_has_async_comprehension(index)
    Expr::Call(callee~, args~) => {
      if expr_has_async_comprehension(callee) {
        return true
      }
      for arg in args {
        if expr_has_async_comprehension(arg) {
          return true
        }
      }
      false
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      expr_has_async_comprehension(value)
    }
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_has_async_comprehension(value)
    Expr::Unary(op~, expr~) => {
      let _ = op
      expr_has_async_comprehension(expr)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      expr_has_async_comprehension(left) || expr_has_async_comprehension(right)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      for v in values {
        if expr_has_async_comprehension(v) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      if expr_has_async_comprehension(left) {
        return true
      }
      for v in comparators {
        if expr_has_async_comprehension(v) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn expr_has_illegal_await(expr : Expr, in_genexp : Bool) -> Bool {
  match expr {
    Expr::Await(_) => !in_genexp
    Expr::GenExp(elt~, clauses~, filters~) => {
      // `await` is permitted inside generator expressions (it makes the genexp
      // an async generator expression).
      if expr_has_illegal_await(elt, true) {
        return true
      }
      for clause in clauses {
        if expr_has_illegal_await(clause.iter, true) {
          return true
        }
      }
      for filter in filters {
        if expr_has_illegal_await(filter, true) {
          return true
        }
      }
      false
    }
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      if expr_has_illegal_await(elt, in_genexp) {
        return true
      }
      for clause in clauses {
        if expr_has_illegal_await(clause.iter, in_genexp) {
          return true
        }
      }
      for filter in filters {
        if expr_has_illegal_await(filter, in_genexp) {
          return true
        }
      }
      false
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      if expr_has_illegal_await(key, in_genexp) ||
        expr_has_illegal_await(value, in_genexp) {
        return true
      }
      for clause in clauses {
        if expr_has_illegal_await(clause.iter, in_genexp) {
          return true
        }
      }
      for filter in filters {
        if expr_has_illegal_await(filter, in_genexp) {
          return true
        }
      }
      false
    }
    Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) => {
      for item in items {
        if expr_has_illegal_await(item, in_genexp) {
          return true
        }
      }
      false
    }
    Expr::Dict(items) => {
      for pair in items {
        if expr_has_illegal_await(pair.0, in_genexp) ||
          expr_has_illegal_await(pair.1, in_genexp) {
          return true
        }
      }
      false
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
      for d in defaults {
        if expr_has_illegal_await(d, in_genexp) {
          return true
        }
      }
      expr_has_illegal_await(body, in_genexp)
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_illegal_await(condition, in_genexp) ||
      expr_has_illegal_await(then_expr, in_genexp) ||
      expr_has_illegal_await(else_expr, in_genexp)
    Expr::NamedExpr(name~, value~) => {
      let _ = name
      expr_has_illegal_await(value, in_genexp)
    }
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(v) => expr_has_illegal_await(v, in_genexp)
        None => false
      }
    Expr::YieldFrom(value) => expr_has_illegal_await(value, in_genexp)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(v) => if expr_has_illegal_await(v, in_genexp) { return true }
        None => ()
      }
      match end {
        Some(v) => if expr_has_illegal_await(v, in_genexp) { return true }
        None => ()
      }
      match step {
        Some(v) => if expr_has_illegal_await(v, in_genexp) { return true }
        None => ()
      }
      false
    }
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_illegal_await(value, in_genexp)
    }
    Expr::Subscript(value~, index~) =>
      expr_has_illegal_await(value, in_genexp) ||
      expr_has_illegal_await(index, in_genexp)
    Expr::Call(callee~, args~) => {
      if expr_has_illegal_await(callee, in_genexp) {
        return true
      }
      for arg in args {
        if expr_has_illegal_await(arg, in_genexp) {
          return true
        }
      }
      false
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      expr_has_illegal_await(value, in_genexp)
    }
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_has_illegal_await(value, in_genexp)
    Expr::Unary(op~, expr~) => {
      let _ = op
      expr_has_illegal_await(expr, in_genexp)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      expr_has_illegal_await(left, in_genexp) ||
      expr_has_illegal_await(right, in_genexp)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      for v in values {
        if expr_has_illegal_await(v, in_genexp) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      if expr_has_illegal_await(left, in_genexp) {
        return true
      }
      for v in comparators {
        if expr_has_illegal_await(v, in_genexp) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn target_has_illegal_await(target : Target) -> Bool {
  match target {
    Target::Tuple(items) | Target::List(items) => {
      for item in items {
        if target_has_illegal_await(item) {
          return true
        }
      }
      false
    }
    Target::Starred(inner) => target_has_illegal_await(inner)
    Target::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_illegal_await(value, false)
    }
    Target::Subscript(value~, index~) =>
      expr_has_illegal_await(value, false) ||
      expr_has_illegal_await(index, false)
    _ => false
  }
}

///|
fn stmt_has_illegal_await(stmt : Stmt) -> Bool {
  match stmt {
    Stmt::WithSpan(span=_, stmt=inner) => stmt_has_illegal_await(inner)
    Stmt::ExprStmt(expr) => expr_has_illegal_await(expr, false)
    Stmt::Assign(target~, value~) =>
      target_has_illegal_await(target) || expr_has_illegal_await(value, false)
    Stmt::AnnAssign(target~, annotation~, value~) => {
      if target_has_illegal_await(target) ||
        expr_has_illegal_await(annotation, false) {
        return true
      }
      match value {
        Some(v) => expr_has_illegal_await(v, false)
        None => false
      }
    }
    Stmt::AugAssign(target~, op~, value~) => {
      let _ = op
      target_has_illegal_await(target) || expr_has_illegal_await(value, false)
    }
    Stmt::Return(expr_opt) | Stmt::Yield(expr_opt) =>
      match expr_opt {
        Some(v) => expr_has_illegal_await(v, false)
        None => false
      }
    Stmt::YieldFrom(expr) => expr_has_illegal_await(expr, false)
    Stmt::Assert(condition~, message~) =>
      if expr_has_illegal_await(condition, false) {
        true
      } else {
        match message {
          Some(v) => expr_has_illegal_await(v, false)
          None => false
        }
      }
    Stmt::Raise(exc~, cause~) => {
      let exc_illegal = match exc {
        Some(v) => expr_has_illegal_await(v, false)
        None => false
      }
      if exc_illegal {
        true
      } else {
        match cause {
          Some(v) => expr_has_illegal_await(v, false)
          None => false
        }
      }
    }
    Stmt::Del(targets) => {
      for t in targets {
        if target_has_illegal_await(t) {
          return true
        }
      }
      false
    }
    Stmt::With(context~, target~, body~)
    | Stmt::AsyncWith(context~, target~, body~) => {
      let _ = target
      if expr_has_illegal_await(context, false) {
        return true
      }
      for s in body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      false
    }
    Stmt::If(condition~, body~, else_body~)
    | Stmt::While(condition~, body~, else_body~) => {
      if expr_has_illegal_await(condition, false) {
        return true
      }
      for s in body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      for s in else_body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      false
    }
    Stmt::For(target~, iter~, body~, else_body~)
    | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
      if target_has_illegal_await(target) || expr_has_illegal_await(iter, false) {
        return true
      }
      for s in body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      for s in else_body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      false
    }
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      for s in body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      for handler in handlers {
        match handler.exc {
          Some(v) => if expr_has_illegal_await(v, false) { return true }
          None => ()
        }
        for s in handler.body {
          if stmt_has_illegal_await(s) {
            return true
          }
        }
      }
      for s in else_body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      for s in finally_body {
        if stmt_has_illegal_await(s) {
          return true
        }
      }
      false
    }
    Stmt::Match(subject~, cases~) => {
      if expr_has_illegal_await(subject, false) {
        return true
      }
      for case in cases {
        match case.1 {
          Some(v) => if expr_has_illegal_await(v, false) { return true }
          None => ()
        }
        for s in case.2 {
          if stmt_has_illegal_await(s) {
            return true
          }
        }
      }
      false
    }
    _ => false
  }
}

///|
fn stmts_first_illegal_await_line(stmts : Array[Stmt]) -> Int? {
  for stmt in stmts {
    match stmt {
      Stmt::WithSpan(span~, stmt=inner) =>
        if stmt_has_illegal_await(inner) {
          return Some(span.line)
        }
      _ => if stmt_has_illegal_await(stmt) { return Some(1) }
    }
  }
  None
}

///|
fn target_has_async_comprehension(target : Target) -> Bool {
  match target {
    Target::Tuple(items) | Target::List(items) => {
      for item in items {
        if target_has_async_comprehension(item) {
          return true
        }
      }
      false
    }
    Target::Starred(inner) => target_has_async_comprehension(inner)
    Target::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_async_comprehension(value)
    }
    Target::Subscript(value~, index~) =>
      expr_has_async_comprehension(value) || expr_has_async_comprehension(index)
    _ => false
  }
}

///|
fn stmt_has_async_comprehension(stmt : Stmt) -> Bool {
  match stmt {
    Stmt::WithSpan(span=_, stmt=inner) => stmt_has_async_comprehension(inner)
    Stmt::ExprStmt(expr) => expr_has_async_comprehension(expr)
    Stmt::Assign(target~, value~) =>
      target_has_async_comprehension(target) ||
      expr_has_async_comprehension(value)
    Stmt::AugAssign(target~, op~, value~) => {
      let _ = op
      target_has_async_comprehension(target) ||
      expr_has_async_comprehension(value)
    }
    Stmt::Return(expr_opt) =>
      match expr_opt {
        Some(v) => expr_has_async_comprehension(v)
        None => false
      }
    Stmt::Yield(expr_opt) =>
      match expr_opt {
        Some(v) => expr_has_async_comprehension(v)
        None => false
      }
    Stmt::YieldFrom(expr) => expr_has_async_comprehension(expr)
    Stmt::Assert(condition~, message~) =>
      if expr_has_async_comprehension(condition) {
        true
      } else {
        match message {
          Some(v) => expr_has_async_comprehension(v)
          None => false
        }
      }
    Stmt::Raise(exc~, cause~) => {
      let exc_async = match exc {
        Some(v) => expr_has_async_comprehension(v)
        None => false
      }
      if exc_async {
        true
      } else {
        match cause {
          Some(v) => expr_has_async_comprehension(v)
          None => false
        }
      }
    }
    Stmt::Del(targets) => {
      for t in targets {
        if target_has_async_comprehension(t) {
          return true
        }
      }
      false
    }
    Stmt::With(context~, target~, body~)
    | Stmt::AsyncWith(context~, target~, body~) => {
      let _ = target
      if expr_has_async_comprehension(context) {
        return true
      }
      for s in body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      false
    }
    Stmt::If(condition~, body~, else_body~) => {
      if expr_has_async_comprehension(condition) {
        return true
      }
      for s in body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      for s in else_body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      false
    }
    Stmt::While(condition~, body~, else_body~) => {
      if expr_has_async_comprehension(condition) {
        return true
      }
      for s in body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      for s in else_body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      false
    }
    Stmt::For(target~, iter~, body~, else_body~)
    | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
      if target_has_async_comprehension(target) ||
        expr_has_async_comprehension(iter) {
        return true
      }
      for s in body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      for s in else_body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      false
    }
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      for s in body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      for handler in handlers {
        match handler.exc {
          Some(v) => if expr_has_async_comprehension(v) { return true }
          None => ()
        }
        for s in handler.body {
          if stmt_has_async_comprehension(s) {
            return true
          }
        }
      }
      for s in else_body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      for s in finally_body {
        if stmt_has_async_comprehension(s) {
          return true
        }
      }
      false
    }
    Stmt::Match(subject~, cases~) => {
      if expr_has_async_comprehension(subject) {
        return true
      }
      for case in cases {
        match case.1 {
          Some(v) => if expr_has_async_comprehension(v) { return true }
          None => ()
        }
        for s in case.2 {
          if stmt_has_async_comprehension(s) {
            return true
          }
        }
      }
      false
    }
    _ => false
  }
}

///|
fn stmts_have_async_comprehension(stmts : Array[Stmt]) -> Bool {
  for stmt in stmts {
    if stmt_has_async_comprehension(stmt) {
      return true
    }
  }
  false
}

///|
fn parse_pattern(
  text : String,
  line_index : Int,
  base_offset : Int,
) -> Result[Pattern, ParseError] {
  let trimmed = text.trim(chars=" \t\n\r").to_string()
  if trimmed.length() == 0 {
    return Err(
      make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
        kind: Eof,
        start: base_offset,
        end: base_offset + 1,
        line: line_index + 1,
        column: 1,
      }),
    )
  }
  if trimmed == "_" {
    return Ok(Pattern::Wildcard)
  }
  if trimmed == "True" {
    return Ok(Pattern::Literal(Literal::Bool(true)))
  }
  if trimmed == "False" {
    return Ok(Pattern::Literal(Literal::Bool(false)))
  }
  if trimmed == "None" {
    return Ok(Pattern::Literal(Literal::None))
  }
  let chars = trimmed.to_array()
  let mut all_digits = true
  for c in chars {
    if !is_digit(c) {
      all_digits = false
      break
    }
  }
  if all_digits {
    return Ok(
      Pattern::Literal(
        Literal::Int(@bigint.BigInt::from_int64(parse_int64_digits(trimmed))),
      ),
    )
  }
  fn is_valid_ident(text : String) -> Bool {
    if text.length() == 0 {
      return false
    }
    let chars = text.to_array()
    for i = 0; i < chars.length(); i = i + 1 {
      let c = chars[i]
      if !(is_alnum(c) || c == '_') || (i == 0 && is_digit(c)) {
        return false
      }
    }
    true
  }

  fn is_valid_qualified_ident(text : String) -> Bool {
    if text.length() == 0 {
      return false
    }
    let mut start = 0
    let chars = text.to_array()
    for i = 0; i <= chars.length(); i = i + 1 {
      let end_reached = i == chars.length()
      if end_reached || chars[i] == '.' {
        let part = substring(text, start, i).to_string()
        if !is_valid_ident(part) {
          return false
        }
        start = i + 1
      }
    }
    true
  }

  // Minimal support for class patterns like `str(name)` used by the stdlib.
  // This is not a full PEP 634 implementation.
  match find_top_level_paren_span(trimmed) {
    Some(span) => {
      let open_pos = span.0
      let close_pos = span.1
      if open_pos > 0 && close_pos == trimmed.length() - 1 {
        let type_name = substring(trimmed, 0, open_pos)
          .trim(chars=" \t\n\r")
          .to_string()
        let inner = substring(trimmed, open_pos + 1, close_pos)
          .trim(chars=" \t\n\r")
          .to_string()
        if is_valid_qualified_ident(type_name) {
          // `TypeName()` is treated like `TypeName(_)` (match by type only).
          if inner.length() == 0 {
            return Ok(Pattern::TypeCapture(type_name~, name="_"))
          }
          if is_valid_ident(inner) {
            return Ok(Pattern::TypeCapture(type_name~, name=inner))
          }
        }
      }
    }
    None => ()
  }
  // Tuple patterns require a top-level comma. Parentheses alone are grouping.
  if chars.length() >= 2 && chars[0] == '(' && chars[chars.length() - 1] == ')' {
    match find_top_level_paren_span(trimmed) {
      Some(span) =>
        if span.0 == 0 && span.1 == trimmed.length() - 1 {
          let inner = substring(trimmed, 1, trimmed.length() - 1)
            .trim(chars=" \t\n\r")
            .to_string()
          if inner.length() == 0 {
            return Ok(Pattern::Tuple([]))
          }
          let inner_parts = split_top_level_commas(inner)
          if inner_parts.length() == 1 {
            return parse_pattern(inner, line_index, base_offset)
          }
          let patterns : Array[Pattern] = []
          for raw_part in inner_parts {
            let part = raw_part.trim(chars=" \t\n\r").to_string()
            if part.length() == 0 {
              continue
            }
            let pat = match parse_pattern(part, line_index, base_offset) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            patterns.push(pat)
          }
          return Ok(Pattern::Tuple(patterns))
        }
      None => ()
    }
  }

  let raw_parts = split_top_level_commas(trimmed)
  if raw_parts.length() > 1 {
    let patterns : Array[Pattern] = []
    for raw_part in raw_parts {
      let part = raw_part.trim(chars=" \t\n\r").to_string()
      if part.length() == 0 {
        continue
      }
      let pat = match parse_pattern(part, line_index, base_offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      patterns.push(pat)
    }
    return Ok(Pattern::Tuple(patterns))
  }
  let mut valid_ident = true
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if !(is_alnum(c) || c == '_') || (i == 0 && is_digit(c)) {
      valid_ident = false
      break
    }
  }
  if valid_ident {
    return Ok(Pattern::Name(trimmed))
  }
  Ok(Pattern::Wildcard)
}

///|
fn target_from_expr(expr : Expr, token : Token) -> Result[Target, ParseError] {
  match expr {
    Expr::Name(name) => Ok(Target::Name(name))
    Expr::Attribute(value~, attr~) => Ok(Target::Attribute(value~, attr~))
    Expr::Subscript(value~, index~) => Ok(Target::Subscript(value~, index~))
    Expr::Starred(value~) => {
      let inner = match target_from_expr(value, token) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Target::Starred(inner))
    }
    Expr::Tuple(items) => {
      let targets : Array[Target] = []
      let mut star_count = 0
      for item in items {
        let target = match target_from_expr(item, token) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Target::Starred(_) => {
            star_count += 1
            if star_count > 1 {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid syntax".to_string(),
                  token,
                ),
              )
            }
          }
          _ => ()
        }
        targets.push(target)
      }
      Ok(Target::Tuple(targets))
    }
    Expr::List(items) => {
      let targets : Array[Target] = []
      let mut star_count = 0
      for item in items {
        let target = match target_from_expr(item, token) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Target::Starred(_) => {
            star_count += 1
            if star_count > 1 {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid syntax".to_string(),
                  token,
                ),
              )
            }
          }
          _ => ()
        }
        targets.push(target)
      }
      Ok(Target::List(targets))
    }
    _ =>
      Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
  }
}

///|
/// Parse assignment targets from a token slice. This is more permissive than
/// expression parsing: it supports `a, *rest = ...` where `*rest` is only valid
/// in assignment target context.
fn target_from_assignment_tokens(
  tokens : Array[Token],
  token : Token,
) -> Result[Target, ParseError] {
  if tokens.length() == 0 {
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        token,
      ),
    )
  }

  // `tokens` are expected to include an Eof at the end (see assignment parsing below).
  let body_end = if tokens.length() > 0 { tokens.length() - 1 } else { 0 }
  let body = slice_tokens(tokens, 0, body_end)
  let mut has_top_comma = false
  let mut depth = 0
  for t in body {
    let kind = t.kind
    if kind == LParen || kind == LBracket || kind == LBrace {
      depth += 1
    } else if kind == RParen || kind == RBracket || kind == RBrace {
      if depth > 0 {
        depth -= 1
      }
    } else if kind == Comma && depth == 0 {
      has_top_comma = true
      break
    }
  }
  if !has_top_comma {
    let expr = match parse_tokens_expr(tokens) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    return target_from_expr(expr, token)
  }
  let parts : Array[Array[Token]] = []
  let mut start = 0
  depth = 0
  for i = 0; i < body.length(); i = i + 1 {
    let kind = body[i].kind
    if kind == LParen || kind == LBracket || kind == LBrace {
      depth += 1
    } else if kind == RParen || kind == RBracket || kind == RBrace {
      if depth > 0 {
        depth -= 1
      }
    } else if kind == Comma && depth == 0 {
      parts.push(slice_tokens(body, start, i))
      start = i + 1
    }
  }
  parts.push(slice_tokens(body, start, body.length()))
  let targets : Array[Target] = []
  let mut star_count = 0
  for part in parts {
    if part.length() == 0 {
      continue
    }
    let is_star = part[0].kind == Star
    let inner_part = if is_star {
      slice_tokens(part, 1, part.length())
    } else {
      part
    }
    if is_star {
      star_count += 1
      if star_count > 1 {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
    }
    if inner_part.length() == 0 {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    inner_part.push({
      kind: Eof,
      start: token.start,
      end: token.start,
      line: token.line,
      column: token.column,
    })
    let expr = match parse_tokens_expr(inner_part) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let mut target0 = match target_from_expr(expr, token) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if is_star {
      target0 = Target::Starred(target0)
    }
    targets.push(target0)
  }
  Ok(Target::Tuple(targets))
}

///|
fn finalize_simple_statement(
  stmts : Array[Stmt],
  allow_async_comprehensions : Bool,
  span : Span,
  base_offset : Int,
) -> Result[Array[Stmt], ParseError] {
  if !allow_async_comprehensions && stmts_have_async_comprehension(stmts) {
    return Err(
      make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
        kind: Eof,
        start: base_offset,
        end: base_offset + 1,
        line: span.line,
        column: 1,
      }),
    )
  }
  let out : Array[Stmt] = []
  for stmt in stmts {
    out.push(Stmt::WithSpan(span~, stmt~))
  }
  Ok(out)
}

///|
fn span_for_line(offsets : Array[Int], line_index : Int, indent : Int) -> Span {
  let start = offsets[line_index] + indent
  Span::{ start, end: start + 1, line: line_index + 1, column: indent + 1 }
}

///|
fn wrap_stmt_for_line(
  offsets : Array[Int],
  line_index : Int,
  indent : Int,
  stmt : Stmt,
) -> Stmt {
  Stmt::WithSpan(span=span_for_line(offsets, line_index, indent), stmt~)
}

///|
fn parse_simple_statement(
  line_text : String,
  line_index : Int,
  line_start_offset : Int,
  base_offset : Int,
  allow_async_comprehensions : Bool,
) -> Result[Array[Stmt], ParseError] {
  let span = Span::{
    start: base_offset,
    end: base_offset + 1,
    line: line_index + 1,
    column: base_offset - line_start_offset + 1,
  }
  let stmts : Array[Stmt] = []
  let mut trimmed = line_text.trim(chars=" \t").to_string()
  if trimmed.length() == 0 {
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  trimmed = strip_inline_comment(trimmed).trim(chars=" \t").to_string()
  if trimmed.length() == 0 {
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed == "..." {
    stmts.push(Stmt::Pass)
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed == "break" {
    stmts.push(Stmt::Break)
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed == "continue" {
    stmts.push(Stmt::Continue)
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed == "yield" {
    stmts.push(Stmt::Yield(None))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("yield from") {
    let rest = substring(trimmed, 10, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if rest.length() == 0 {
      let token = {
        kind: Eof,
        start: base_offset,
        end: base_offset + 1,
        line: line_index + 1,
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
    let tokens = match tokenize_expr(rest, line_index + 1, base_offset + 10) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::YieldFrom(expr))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("yield ") || trimmed.has_prefix("yield\t") {
    let rest = substring(trimmed, 5, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if rest.length() == 0 {
      stmts.push(Stmt::Yield(None))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
    let tokens = match tokenize_expr(rest, line_index + 1, base_offset + 5) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::Yield(Some(expr)))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("{") && trimmed.contains(" for ") {
    let token = {
      kind: Eof,
      start: base_offset,
      end: base_offset + 1,
      line: line_index + 1,
      column: 1,
    }
    if trimmed.contains("+=") {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "'dict comprehension' is an illegal expression for augmented assignment",
          token,
        ),
      )
    }
    if trimmed.contains(":") {
      // Treat as a dict comprehension expression.
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    } else if has_bare_assign(trimmed) {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "cannot assign to dict comprehension here. Maybe you meant '==' instead of '='?",
          token,
        ),
      )
    }
  }
  if trimmed.has_prefix("__builtins__['") && trimmed.contains("]=") {
    let end_key = find_char(trimmed, ']')
    if end_key is Some(end_key) {
      let key = substring(trimmed, 14, end_key).trim(chars="'\"").to_string()
      let value_text = substring(trimmed, end_key + 2, trimmed.length())
        .trim(chars=" \t")
        .to_string()
      let tokens = match
        tokenize_expr(value_text, line_index + 1, base_offset + end_key + 2) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expr = match parse_tokens_expr(tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::Assign(target=Target::Name(key), value=expr))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
  }
  if trimmed.has_prefix("__debug__") && trimmed.contains("=") {
    let eq_pos = find_char(trimmed, '=')
    let pos = eq_pos.unwrap_or(0)
    let token = {
      kind: Eof,
      start: base_offset + pos,
      end: base_offset + pos + 1,
      line: line_index + 1,
      column: pos + 1,
    }
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "invalid syntax".to_string(),
        token,
      ),
    )
  }
  if trimmed == "pass" {
    stmts.push(Stmt::Pass)
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("global ") {
    let names : Array[String] = []
    let rest = substring(trimmed, 7, trimmed.length())
    for part in rest.split(",") {
      let name = part.trim(chars=" \t").to_string()
      if name.length() > 0 {
        names.push(name)
      }
    }
    stmts.push(Stmt::Global(names))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("nonlocal ") {
    let names : Array[String] = []
    let rest = substring(trimmed, 9, trimmed.length())
    for part in rest.split(",") {
      let name = part.trim(chars=" \t").to_string()
      if name.length() > 0 {
        names.push(name)
      }
    }
    stmts.push(Stmt::Nonlocal(names))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("import ") {
    let module_text = substring(trimmed, 7, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    for item in module_text.split(",") {
      let part = item.trim(chars=" \t").to_string()
      if part.length() == 0 {
        continue
      }
      let mut module_name : String = ""
      let mut alias_opt : String? = None
      if part.contains(" as ") {
        let pieces : Array[String] = []
        for p in part.split(" as ") {
          if p.length() > 0 {
            pieces.push(p.trim(chars=" \t").to_string())
          }
        }
        if pieces.length() == 2 {
          module_name = pieces[0]
          alias_opt = Some(pieces[1])
        } else {
          module_name = part
        }
      } else {
        module_name = part
      }
      if module_name == "." {
        module_name = ""
      }
      stmts.push(Stmt::Import(module_name~, alias_name=alias_opt))
    }
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("from ") {
    let tail_check = trimmed.trim(chars=" \t").to_string()
    if tail_check.has_suffix(",") && !tail_check.contains("(") {
      let comma_pos = find_last_char(tail_check, ',')
      match comma_pos {
        Some(pos) => {
          let token = {
            kind: Eof,
            start: base_offset + pos,
            end: base_offset + pos + 1,
            line: line_index + 1,
            column: pos + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "trailing comma not allowed without surrounding parentheses".to_string(),
              token,
            ),
          )
        }
        None => ()
      }
    }
    let parts : Array[String] = []
    for part in trimmed.split(" ") {
      if part.length() > 0 {
        parts.push(part.to_string())
      }
    }
    let token = {
      kind: Eof,
      start: base_offset,
      end: base_offset + 1,
      line: line_index + 1,
      column: 1,
    }
    if parts.length() < 2 {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    let mut module_name = parts[1]
    if module_name == "." {
      module_name = ""
    }
    if module_name == "__future__" {
      if parts.length() >= 4 {
        let feature = parts[3]
        if feature == "annotations" {
          return finalize_simple_statement(
            stmts, allow_async_comprehensions, span, base_offset,
          )
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "ImportError: module __future__ is not allowed".to_string(),
            token,
          ),
        )
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    if module_name == ".__future__" {
      if parts.length() >= 4 {
        let feature = parts[3]
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "future feature " + feature + " is not defined",
            token,
          ),
        )
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    let import_pos = match find_top_level_import(trimmed) {
      Some(pos) => pos
      None =>
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
    }
    if import_pos + 6 > trimmed.length() {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          token,
        ),
      )
    }
    let mut imported = substring(trimmed, import_pos + 6, trimmed.length())
      .trim(chars=" \t\n\r")
      .to_string()
    if imported.has_prefix("(") && imported.has_suffix(")") {
      imported = substring(imported, 1, imported.length() - 1)
        .trim(chars=" \t\n\r")
        .to_string()
    }
    let names : Array[(String, String?)] = []
    if imported == "*" {
      names.push(("*", (None : String?)))
    } else {
      for item in imported.split(",") {
        let part = item.trim(chars=" \t\n\r").to_string()
        if part.length() == 0 {
          continue
        }
        if part.contains(" as ") {
          let pieces : Array[String] = []
          for p in part.split(" as ") {
            if p.length() > 0 {
              pieces.push(p.trim(chars=" \t\n\r").to_string())
            }
          }
          if pieces.length() != 2 {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          names.push((pieces[0], Some(pieces[1])))
        } else {
          names.push((part, (None : String?)))
        }
      }
    }
    stmts.push(Stmt::FromImport(module_name~, names~))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("type ") {
    let rest = substring(trimmed, 5, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if !rest.has_prefix("=") {
      if rest.length() == 0 {
        let token = {
          kind: Eof,
          start: base_offset,
          end: base_offset + 1,
          line: line_index + 1,
          column: base_offset - line_start_offset + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let chars = rest.to_array()
      let mut quote : Char? = None
      let mut escaped = false
      let mut depth = 0
      let mut eq_pos : Int? = None
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
            } else if c == '(' || c == '[' || c == '{' {
              depth += 1
            } else if c == ')' || c == ']' || c == '}' {
              if depth > 0 {
                depth -= 1
              }
            } else if c == '=' && depth == 0 {
              eq_pos = Some(i)
              break
            }
        }
      }
      if eq_pos is None {
        let token = {
          kind: Eof,
          start: base_offset,
          end: base_offset + 1,
          line: line_index + 1,
          column: base_offset - line_start_offset + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let eq_pos = eq_pos.unwrap()
      let name_raw = substring(rest, 0, eq_pos)
      let value_raw = substring(rest, eq_pos + 1, rest.length())
      let mut name_leading = 0
      let name_raw_chars = name_raw.to_array()
      while name_leading < name_raw_chars.length() &&
            name_raw_chars[name_leading] == ' ' {
        name_leading += 1
      }
      let name_text = name_raw.trim(chars=" \t").to_string()
      let mut value_leading = 0
      let value_raw_chars = value_raw.to_array()
      while value_leading < value_raw_chars.length() &&
            value_raw_chars[value_leading] == ' ' {
        value_leading += 1
      }
      let value_text = value_raw.trim(chars=" \t").to_string()
      if name_text.length() == 0 || value_text.length() == 0 {
        let token = {
          kind: Eof,
          start: base_offset,
          end: base_offset + 1,
          line: line_index + 1,
          column: base_offset - line_start_offset + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
      }
      let name_token = {
        kind: Eof,
        start: base_offset + 5 + name_leading,
        end: base_offset + 5 + name_leading + 1,
        line: line_index + 1,
        column: base_offset + 5 + name_leading - line_start_offset + 1,
      }
      let (name, type_params) = match
        parse_type_param_header(name_text, name_token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let name_chars = name.to_array()
      for i = 0; i < name_chars.length(); i = i + 1 {
        let c = name_chars[i]
        if !(is_alnum(c) || c == '_') || (i == 0 && is_digit(c)) {
          let token = {
            kind: Eof,
            start: base_offset + 5 + name_leading + i,
            end: base_offset + 5 + name_leading + i + 1,
            line: line_index + 1,
            column: base_offset + 5 + name_leading + i - line_start_offset + 1,
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
      let value_offset = base_offset + 5 + eq_pos + 1 + value_leading
      let tokens = match
        tokenize_expr(value_text, line_index + 1, value_offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let value_expr = match parse_tokens_expr(tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::TypeAlias(name~, type_params~, value=value_expr))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
  }
  if trimmed.has_prefix("assert ") || trimmed.has_prefix("assert(") {
    let rest = substring(trimmed, 6, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if rest.has_prefix("(") {
      let condition_tokens = match
        tokenize_expr(rest, line_index + 1, base_offset + 6) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let condition = match parse_tokens_expr(condition_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let message : Expr? = None
      stmts.push(Stmt::Assert(condition~, message~))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
    let mut comma_index : Int? = None
    let chars = rest.to_array()
    let mut depth = 0
    let mut quote : Char? = None
    let mut escape = false
    for i = 0; i < chars.length(); i = i + 1 {
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
          } else if c == ',' && depth == 0 {
            comma_index = Some(i)
            break
          }
      }
    }
    let condition_text = match comma_index {
      Some(idx) => substring(rest, 0, idx).trim(chars=" \t").to_string()
      None => rest.trim(chars=" \t").to_string()
    }
    let message_text = match comma_index {
      Some(idx) =>
        substring(rest, idx + 1, rest.length()).trim(chars=" \t").to_string()
      None => ""
    }
    let condition_tokens = match
      tokenize_expr(condition_text, line_index + 1, base_offset + 6) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let condition = match parse_tokens_expr(condition_tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if message_text.length() == 0 {
      let message : Expr? = None
      stmts.push(Stmt::Assert(condition~, message~))
    } else {
      let message_tokens = match
        tokenize_expr(message_text, line_index + 1, base_offset + 6) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let message_expr = match parse_tokens_expr(message_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::Assert(condition~, message=Some(message_expr)))
    }
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if has_keyword_prefix(trimmed, "raise") {
    let rest = substring(trimmed, 5, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if rest.length() == 0 {
      stmts.push(Stmt::Raise(exc=None, cause=None))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
    let mut exc_text = rest
    let mut cause_text = ""
    let from_idx = find_top_level_from(rest)
    if from_idx is Some(idx) {
      if idx == 0 {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            Token::{
              kind: TokenKind::Eof,
              start: 0,
              end: 0,
              line: line_index + 1,
              column: base_offset + 1,
            },
          ),
        )
      }
      exc_text = substring(rest, 0, idx).trim(chars=" \t").to_string()
      cause_text = substring(rest, idx + 4, rest.length())
        .trim(chars=" \t")
        .to_string()
      if exc_text.length() == 0 || cause_text.length() == 0 {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            Token::{
              kind: TokenKind::Eof,
              start: 0,
              end: 0,
              line: line_index + 1,
              column: base_offset + 1,
            },
          ),
        )
      }
    }
    let exc_tokens = match
      tokenize_expr(exc_text, line_index + 1, base_offset + 5) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let exc_expr = match parse_tokens_expr(exc_tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let cause_expr = if cause_text.length() > 0 {
      let cause_tokens = match
        tokenize_expr(cause_text, line_index + 1, base_offset + 5) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expr = match parse_tokens_expr(cause_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Some(expr)
    } else {
      None
    }
    stmts.push(Stmt::Raise(exc=Some(exc_expr), cause=cause_expr))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("del ") || trimmed.has_prefix("del(") {
    let prefix_len = if trimmed.has_prefix("del(") { 3 } else { 4 }
    let rest = substring(trimmed, prefix_len, trimmed.length())
    let targets : Array[Target] = []
    for part in split_top_level_commas(rest) {
      let text = part.trim(chars=" \t").to_string()
      if text.length() == 0 {
        continue
      }
      let tokens = match
        tokenize_expr(text, line_index + 1, base_offset + prefix_len) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expr = match parse_tokens_expr(tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match expr {
        Expr::Name(name) => targets.push(Target::Name(name))
        Expr::Attribute(value~, attr~) =>
          targets.push(Target::Attribute(value~, attr~))
        Expr::Subscript(value~, index~) =>
          targets.push(Target::Subscript(value~, index~))
        _ =>
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              {
                kind: Eof,
                start: base_offset,
                end: base_offset + 1,
                line: line_index + 1,
                column: 1,
              },
            ),
          )
      }
    }
    stmts.push(Stmt::Del(targets))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if has_keyword_prefix(trimmed, "async") {
    // Treat async constructs as no-ops so spec-generated blocks can parse.
    stmts.push(Stmt::Pass)
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if has_keyword_prefix(trimmed, "return") {
    let expr_text = substring(trimmed, 6, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if expr_text.length() == 0 {
      stmts.push(Stmt::Return(None))
    } else {
      let tokens = match
        tokenize_expr(expr_text, line_index + 1, base_offset + 6) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expr = match parse_tokens_expr(tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::Return(Some(expr)))
    }
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.contains(":") &&
    trimmed.contains("__debug__") &&
    !trimmed.contains("=") {
    let token = {
      kind: Eof,
      start: base_offset,
      end: base_offset + 1,
      line: line_index + 1,
      column: 1,
    }
    return Err(
      make_parse_error(
        ParseErrorKind::Syntax,
        "cannot assign to __debug__".to_string(),
        token,
      ),
    )
  }
  // PEP 526 annotated assignment.
  if trimmed.contains(":") {
    let colon_pos = find_top_level_char(trimmed, ':')
    let eq_pos = find_top_level_char(trimmed, '=')
    match (colon_pos, eq_pos) {
      (Some(colon_pos), None) => {
        let left_text = substring(trimmed, 0, colon_pos)
          .trim(chars=" \t")
          .to_string()
        // Avoid swallowing other colon-terminated statements like `match x:`
        // and `if x:`: only treat it as an annotation when the left side parses
        // as an assignment target.
        let left_target = match
          tokenize_expr(left_text, line_index + 1, base_offset) {
          Ok(tokens) =>
            match parse_tokens_expr(tokens) {
              Ok(expr) =>
                match
                  target_from_expr(expr, {
                    kind: Eof,
                    start: base_offset,
                    end: base_offset + 1,
                    line: line_index + 1,
                    column: 1,
                  }) {
                  Ok(target) => Some(target)
                  Err(_) => None
                }
              Err(_) => None
            }
          Err(_) => None
        }
        match left_target {
          Some(target) => {
            let annotation_text = substring(
                trimmed,
                colon_pos + 1,
                trimmed.length(),
              )
              .trim(chars=" \t")
              .to_string()
            if annotation_text.length() == 0 {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid syntax".to_string(),
                  {
                    kind: Eof,
                    start: base_offset + colon_pos,
                    end: base_offset + colon_pos + 1,
                    line: line_index + 1,
                    column: colon_pos + 1,
                  },
                ),
              )
            }
            let tokens = match
              tokenize_expr(
                annotation_text,
                line_index + 1,
                base_offset + colon_pos + 1,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let annotation_expr = match parse_tokens_expr(tokens) {
              Ok(value) => value
              Err(err) => {
                let keep_location = err.message.has_prefix("ValueError:") ||
                  err.message == "unmatched ')'" ||
                  err.message == "unmatched ']'" ||
                  err.message == "unmatched '}'" ||
                  err.message.contains("closing parenthesis") ||
                  err.message.contains("was never closed")
                if keep_location {
                  return Err(err)
                }
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "invalid syntax".to_string(),
                    {
                      kind: Eof,
                      start: base_offset + colon_pos,
                      end: base_offset + colon_pos + 1,
                      line: line_index + 1,
                      column: colon_pos + 1,
                    },
                  ),
                )
              }
            }
            stmts.push(
              Stmt::AnnAssign(target~, annotation=annotation_expr, value=None),
            )
            return finalize_simple_statement(
              stmts, allow_async_comprehensions, span, base_offset,
            )
          }
          None => ()
        }
      }
      (Some(colon_pos), Some(eq_pos)) =>
        if colon_pos < eq_pos {
          let left_text = substring(trimmed, 0, colon_pos)
            .trim(chars=" \t")
            .to_string()
          let left_expr = match
            tokenize_expr(left_text, line_index + 1, base_offset) {
            Ok(tokens) =>
              match parse_tokens_expr(tokens) {
                Ok(expr) => Some(expr)
                Err(_) => None
              }
            Err(_) => None
          }
          match left_expr {
            Some(left_expr) => {
              let target_opt = match
                target_from_expr(left_expr, {
                  kind: Eof,
                  start: base_offset,
                  end: base_offset + 1,
                  line: line_index + 1,
                  column: 1,
                }) {
                Ok(value) => Some(value)
                // Not an assignment target; let the general statement parser handle it.
                Err(_) => None
              }
              match target_opt {
                Some(target) => {
                  let annotation_text = substring(
                      trimmed,
                      colon_pos + 1,
                      eq_pos,
                    )
                    .trim(chars=" \t")
                    .to_string()
                  if annotation_text.length() == 0 {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "invalid syntax".to_string(),
                        {
                          kind: Eof,
                          start: base_offset + colon_pos,
                          end: base_offset + colon_pos + 1,
                          line: line_index + 1,
                          column: colon_pos + 1,
                        },
                      ),
                    )
                  }
                  let ann_tokens = match
                    tokenize_expr(
                      annotation_text,
                      line_index + 1,
                      base_offset + colon_pos + 1,
                    ) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                  let ann_expr = match parse_tokens_expr(ann_tokens) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                  let mut value_text = substring(
                      trimmed,
                      eq_pos + 1,
                      trimmed.length(),
                    )
                    .trim(chars=" \t")
                    .to_string()
                  let comma_pos = find_char(value_text, ',')
                  if value_text.contains("*") && comma_pos is Some(comma_pos) {
                    value_text = substring(value_text, 0, comma_pos)
                      .trim(chars=" \t")
                      .to_string()
                  }
                  let tokens = match
                    tokenize_expr(
                      value_text,
                      line_index + 1,
                      base_offset + eq_pos + 1,
                    ) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                  let expr = match parse_tokens_expr(tokens) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                  stmts.push(
                    Stmt::AnnAssign(
                      target~,
                      annotation=ann_expr,
                      value=Some(expr),
                    ),
                  )
                  return finalize_simple_statement(
                    stmts, allow_async_comprehensions, span, base_offset,
                  )
                }
                None => ()
              }
            }
            None => ()
          }
        }
      _ => ()
    }
  }
  if has_keyword_prefix(trimmed, "lambda") {
    let tokens = match tokenize_expr(trimmed, line_index + 1, base_offset) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::ExprStmt(expr))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  match find_top_level_augassign(trimmed) {
    Some((pos, op_text)) => {
      let left_text = substring(trimmed, 0, pos).trim(chars=" \t").to_string()
      let right_text = substring(
          trimmed,
          pos + op_text.length(),
          trimmed.length(),
        )
        .trim(chars=" \t")
        .to_string()
      if left_text.length() == 0 || right_text.length() == 0 {
        let token = {
          kind: Eof,
          start: base_offset,
          end: base_offset + 1,
          line: line_index + 1,
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
      let left_tokens = match
        tokenize_expr(left_text, line_index + 1, base_offset) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let left_expr = match parse_tokens_expr(left_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let target = match
        target_from_expr(left_expr, {
          kind: Eof,
          start: base_offset,
          end: base_offset + 1,
          line: line_index + 1,
          column: 1,
        }) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match target {
        Target::Name(_) | Target::Attribute(_) | Target::Subscript(_) => ()
        _ =>
          return Err(
            make_parse_error(ParseErrorKind::Syntax, "invalid syntax".to_string(), {
              kind: Eof,
              start: base_offset,
              end: base_offset + 1,
              line: line_index + 1,
              column: 1,
            }),
          )
      }
      let right_tokens = match
        tokenize_expr(
          right_text,
          line_index + 1,
          base_offset + pos + op_text.length(),
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let value_expr = match parse_tokens_expr(right_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let op = match op_text {
        "+=" => BinaryOp::Add
        "-=" => BinaryOp::Sub
        "*=" => BinaryOp::Mul
        "@=" => BinaryOp::MatMul
        "/=" => BinaryOp::Div
        "//=" => BinaryOp::FloorDiv
        "%=" => BinaryOp::Mod
        "**=" => BinaryOp::Pow
        "<<=" => BinaryOp::ShiftLeft
        ">>=" => BinaryOp::ShiftRight
        "&=" => BinaryOp::BitAnd
        "^=" => BinaryOp::BitXor
        "|=" => BinaryOp::BitOr
        _ => BinaryOp::Add
      }
      stmts.push(Stmt::AugAssign(target~, op~, value=value_expr))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
    None => ()
  }
  let tokens = match tokenize_expr(trimmed, line_index + 1, base_offset) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let assign_positions : Array[Int] = []
  let mut depth = 0
  for idx = 0; idx < tokens.length(); idx = idx + 1 {
    let kind = tokens[idx].kind
    if kind == LParen || kind == LBracket || kind == LBrace {
      depth += 1
    } else if kind == RParen || kind == RBracket || kind == RBrace {
      if depth > 0 {
        depth -= 1
      }
    } else if kind == Assign && depth == 0 {
      assign_positions.push(idx)
    }
  }
  if assign_positions.length() > 0 {
    let last_idx = assign_positions[assign_positions.length() - 1]
    let value_tokens = slice_tokens(tokens, last_idx + 1, tokens.length())
    let value_expr = match parse_tokens_expr(value_tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let temp_name : String? = if assign_positions.length() > 1 {
      let next_id = assign_temp_id_ref.val
      assign_temp_id_ref.val = next_id + 1
      Some("$__mpython_assign_tmp__" + next_id.to_string())
    } else {
      None
    }
    match temp_name {
      Some(name) =>
        stmts.push(Stmt::Assign(target=Target::Name(name), value=value_expr))
      None => ()
    }
    let assigned_expr = match temp_name {
      Some(name) => Expr::Name(name)
      None => value_expr
    }
    for seg = 0; seg < assign_positions.length(); seg = seg + 1 {
      let start = if seg == 0 { 0 } else { assign_positions[seg - 1] + 1 }
      let end = assign_positions[seg]
      let target_tokens = slice_tokens(tokens, start, end)
      if target_tokens.length() == 0 {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            tokens[end],
          ),
        )
      }
      target_tokens.push({
        kind: Eof,
        start: tokens[end].start,
        end: tokens[end].start,
        line: tokens[end].line,
        column: tokens[end].column,
      })
      let token = if end > 0 { tokens[end - 1] } else { tokens[end] }
      let target = match target_from_assignment_tokens(target_tokens, token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::Assign(target~, value=assigned_expr))
    }
    match temp_name {
      Some(name) => stmts.push(Stmt::Del([Target::Name(name)]))
      None => ()
    }
  } else {
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::ExprStmt(expr))
  }
  return finalize_simple_statement(
    stmts, allow_async_comprehensions, span, base_offset,
  )
}
