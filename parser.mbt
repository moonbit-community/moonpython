///|
/// Parser for the mpython interpreter.

///|
priv struct ExprParser {
  tokens : Array[Token]
  mut view : ArrayView[Token]
}

///|
fn ExprParser::new(tokens : Array[Token]) -> ExprParser {
  ExprParser::{ tokens, view: tokens[:] }
}

///|
fn ExprParser::view(self : ExprParser) -> ArrayView[Token] {
  self.view
}

///|
fn ExprParser::update_view(self : ExprParser, view : ArrayView[Token]) -> Unit {
  self.view = view
}

///|
fn ExprParser::index(self : ExprParser) -> Int {
  self.tokens.length() - self.view.length()
}

///|
fn ExprParser::current(self : ExprParser) -> Token {
  match self.view {
    [token, ..] => token
    [] => self.tokens[self.tokens.length() - 1]
  }
}

///|
fn ExprParser::advance(self : ExprParser) -> Token {
  match self.view {
    [token, .. rest] => {
      self.view = rest
      token
    }
    [] => self.tokens[self.tokens.length() - 1]
  }
}

///|
fn ExprParser::expect(
  self : ExprParser,
  kind : TokenKind,
) -> Result[Token, ParseError] {
  let token = self.current()
  if token.kind == kind {
    let _ = self.advance()
    Ok(token)
  } else {
    Err(unexpected_token_error(token))
  }
}

///|
fn ExprParser::parse_expr(self : ExprParser) -> Result[Expr, ParseError] {
  let expr = match self.parse_conditional() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match self.view() {
    [{ kind: Comma, .. }, ..] => {
      let items : Array[Expr] = []
      items.push(expr)
      while self.view() is [{ kind: Comma, .. }, .. rest] {
        self.update_view(rest)
        if self.view() is [{ kind: Eof, .. }, ..] {
          break
        }
        let next = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        items.push(next)
      }
      Ok(Expr::Tuple(items))
    }
    _ => Ok(expr)
  }
}

///|
fn ExprParser::parse_conditional(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_or() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if self.view() is [{ kind: ColonAssign, .. }, .. rest] {
    self.update_view(rest)
    let value = match self.parse_or() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    match expr {
      Expr::Name(name) => expr = Expr::NamedExpr(name~, value~)
      _ => return Err(unexpected_token_error(self.current()))
    }
  }
  match self.view() {
    [{ kind: If, .. }, .. rest] => {
      self.update_view(rest)
      let condition = match self.parse_or() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match self.view() {
        [{ kind: Else, .. }, .. rest2] => self.update_view(rest2)
        _ =>
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "expected 'else' after 'if' expression".to_string(),
              self.current(),
            ),
          )
      }
      let else_expr = match self.parse_conditional() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Expr::IfExpr(condition~, then_expr=expr, else_expr~))
    }
    _ => Ok(expr)
  }
}

///|
fn ExprParser::parse_or(self : ExprParser) -> Result[Expr, ParseError] {
  let values : Array[Expr] = []
  match self.parse_and() {
    Ok(first) => values.push(first)
    Err(err) => return Err(err)
  }
  while self.view() is [{ kind: Or, .. }, .. rest] {
    self.update_view(rest)
    match self.parse_and() {
      Ok(next) => values.push(next)
      Err(err) => return Err(err)
    }
  }
  if values.length() == 1 {
    Ok(values[0])
  } else {
    Ok(Expr::BoolOp(op=BoolOp::Or, values~))
  }
}

///|
fn ExprParser::parse_and(self : ExprParser) -> Result[Expr, ParseError] {
  let values : Array[Expr] = []
  match self.parse_compare() {
    Ok(first) => values.push(first)
    Err(err) => return Err(err)
  }
  while self.view() is [{ kind: And, .. }, .. rest] {
    self.update_view(rest)
    match self.parse_compare() {
      Ok(next) => values.push(next)
      Err(err) => return Err(err)
    }
  }
  if values.length() == 1 {
    Ok(values[0])
  } else {
    Ok(Expr::BoolOp(op=BoolOp::And, values~))
  }
}

///|
fn ExprParser::parse_bit_or(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_bit_xor() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while self.view() is [{ kind: BitOr, .. }, .. rest] {
    self.update_view(rest)
    let right = match self.parse_bit_xor() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    expr = Expr::Binary(op=BinaryOp::BitOr, left=expr, right~)
  }
  Ok(expr)
}

///|
fn ExprParser::parse_bit_xor(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_bit_and() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while self.view() is [{ kind: BitXor, .. }, .. rest] {
    self.update_view(rest)
    let right = match self.parse_bit_and() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    expr = Expr::Binary(op=BinaryOp::BitXor, left=expr, right~)
  }
  Ok(expr)
}

///|
fn ExprParser::parse_bit_and(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_shift() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while self.view() is [{ kind: BitAnd, .. }, .. rest] {
    self.update_view(rest)
    let right = match self.parse_shift() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    expr = Expr::Binary(op=BinaryOp::BitAnd, left=expr, right~)
  }
  Ok(expr)
}

///|
fn ExprParser::parse_shift(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_sum() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while true {
    match self.view() {
      [{ kind: ShiftLeft, .. }, .. rest] => {
        self.update_view(rest)
        let right = match self.parse_sum() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        expr = Expr::Binary(op=BinaryOp::ShiftLeft, left=expr, right~)
      }
      [{ kind: ShiftRight, .. }, .. rest] => {
        self.update_view(rest)
        let right = match self.parse_sum() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        expr = Expr::Binary(op=BinaryOp::ShiftRight, left=expr, right~)
      }
      _ => break
    }
  }
  Ok(expr)
}

///|
fn ExprParser::parse_compare(self : ExprParser) -> Result[Expr, ParseError] {
  let left = match self.parse_bit_or() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let ops : Array[CompareOp] = []
  let comparators : Array[Expr] = []
  while true {
    let op = match self.view() {
      [{ kind: EqEq, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::Eq)
      }
      [{ kind: NotEq, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::NotEq)
      }
      [{ kind: Lt, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::Lt)
      }
      [{ kind: Lte, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::Lte)
      }
      [{ kind: Gt, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::Gt)
      }
      [{ kind: Gte, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::Gte)
      }
      [{ kind: In, .. }, .. rest] => {
        self.update_view(rest)
        Some(CompareOp::In)
      }
      [{ kind: Is, .. }, .. rest] => {
        self.update_view(rest)
        match self.view() {
          [{ kind: Not, .. }, .. rest2] => {
            self.update_view(rest2)
            Some(CompareOp::IsNot)
          }
          _ => Some(CompareOp::Is)
        }
      }
      [{ kind: Not, .. }, .. rest] => {
        self.update_view(rest)
        match self.view() {
          [{ kind: In, .. }, .. rest2] => {
            self.update_view(rest2)
            Some(CompareOp::NotIn)
          }
          _ => return Err(unexpected_token_error(self.current()))
        }
      }
      _ => None
    }
    match op {
      Some(op_value) => {
        let right = match self.parse_bit_or() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        ops.push(op_value)
        comparators.push(right)
      }
      None => break
    }
  }
  if ops.length() == 0 {
    Ok(left)
  } else {
    Ok(Expr::Compare(left~, ops~, comparators~))
  }
}

///|
fn ExprParser::parse_sum(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_term() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while true {
    match self.view() {
      [{ kind: Plus, .. }, .. rest] => {
        self.update_view(rest)
        let right = match self.parse_term() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        expr = Expr::Binary(op=BinaryOp::Add, left=expr, right~)
      }
      [{ kind: Minus, .. }, .. rest] => {
        self.update_view(rest)
        let right = match self.parse_term() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        expr = Expr::Binary(op=BinaryOp::Sub, left=expr, right~)
      }
      _ => break
    }
  }
  Ok(expr)
}

///|
fn ExprParser::parse_term(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_factor() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while true {
    let op = match self.view() {
      [{ kind: Star, .. }, .. rest] => {
        self.update_view(rest)
        Some(BinaryOp::Mul)
      }
      [{ kind: At, .. }, .. rest] => {
        self.update_view(rest)
        Some(BinaryOp::MatMul)
      }
      [{ kind: Slash, .. }, .. rest] => {
        self.update_view(rest)
        Some(BinaryOp::Div)
      }
      [{ kind: SlashSlash, .. }, .. rest] => {
        self.update_view(rest)
        Some(BinaryOp::FloorDiv)
      }
      [{ kind: Percent, .. }, .. rest] => {
        self.update_view(rest)
        Some(BinaryOp::Mod)
      }
      _ => None
    }
    match op {
      Some(op_value) => {
        let right = match self.parse_factor() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        expr = Expr::Binary(op=op_value, left=expr, right~)
      }
      None => break
    }
  }
  Ok(expr)
}

///|
fn ExprParser::parse_factor(self : ExprParser) -> Result[Expr, ParseError] {
  match self.view() {
    [{ kind: Plus, .. }, .. rest] => {
      self.update_view(rest)
      let expr = match self.parse_factor() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Expr::Unary(op=UnaryOp::Pos, expr~))
    }
    [{ kind: Minus, .. }, .. rest] => {
      self.update_view(rest)
      let expr = match self.parse_factor() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Expr::Unary(op=UnaryOp::Neg, expr~))
    }
    [{ kind: Not, .. }, .. rest] => {
      self.update_view(rest)
      let expr = match self.parse_factor() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Expr::Unary(op=UnaryOp::Not, expr~))
    }
    [{ kind: Tilde, .. }, .. rest] => {
      self.update_view(rest)
      let expr = match self.parse_factor() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(Expr::Unary(op=UnaryOp::Invert, expr~))
    }
    _ => {
      let mut expr = match self.parse_primary() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if self.view() is [{ kind: StarStar, .. }, .. rest] {
        self.update_view(rest)
        let right = match self.parse_factor() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        expr = Expr::Binary(op=BinaryOp::Pow, left=expr, right~)
      }
      Ok(expr)
    }
  }
}

///|
fn ExprParser::parse_comprehension_tail(
  self : ExprParser,
  end_kind : TokenKind,
  open : Token,
) -> Result[(Array[(Array[String], Expr)], Array[Expr]), ParseError] {
  let clauses : Array[(Array[String], Expr)] = []
  let filters : Array[Expr] = []
  let walrus_targets : Array[String] = []
  let unclosed_message = if end_kind == RBracket {
    "'[' was never closed"
  } else if end_kind == RBrace {
    "'{' was never closed"
  } else {
    "'(' was never closed"
  }
  while true {
    match self.view() {
      [{ kind: For, .. }, .. rest] => {
        self.update_view(rest)
        if self.current().kind == Eof {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              unclosed_message.to_string(),
              open,
            ),
          )
        }
        let targets = match
          self.parse_comp_targets(
            open,
            unclosed_message.to_string(),
            walrus_targets,
            clauses.length() > 0,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if self.current().kind == Eof {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              unclosed_message.to_string(),
              open,
            ),
          )
        }
        match self.view() {
          [{ kind: In, .. }, .. rest2] => self.update_view(rest2)
          _ => return Err(unexpected_token_error(self.current()))
        }
        if self.current().kind == Eof {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              unclosed_message.to_string(),
              open,
            ),
          )
        }
        // In comprehensions, parse the iterable as a non-conditional expression
        // so that `for x in a if ...` treats `if` as a filter (not as `a if ...`).
        let iter = match self.parse_or() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        collect_named_expr_targets(iter, walrus_targets)
        clauses.push((targets, iter))
        continue
      }
      [{ kind: If, .. }, .. rest] => {
        self.update_view(rest)
        if self.current().kind == Eof {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              unclosed_message.to_string(),
              open,
            ),
          )
        }
        let cond = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        collect_named_expr_targets(cond, walrus_targets)
        filters.push(cond)
        continue
      }
      _ => ()
    }
    if self.current().kind == end_kind || self.current().kind == Eof {
      break
    }
    break
  }
  if clauses.length() == 0 {
    return Err(unexpected_token_error(self.current()))
  }
  Ok((clauses, filters))
}

///|
fn ExprParser::skip_comp_target_until(
  self : ExprParser,
  stop1 : TokenKind,
  stop2 : TokenKind,
  open : Token,
  unclosed_message : String,
) -> Result[Unit, ParseError] {
  let mut depth = 0
  while true {
    let token = self.current()
    if token.kind == Eof {
      return Err(
        make_parse_error(ParseErrorKind::Syntax, unclosed_message, open),
      )
    }
    if depth == 0 && (token.kind == stop1 || token.kind == stop2) {
      break
    }
    match token.kind {
      LParen | LBracket | LBrace => depth += 1
      RParen | RBracket | RBrace => if depth > 0 { depth -= 1 }
      _ => ()
    }
    let _ = self.advance()

  }
  Ok(())
}

///|
fn ExprParser::parse_comp_target_group(
  self : ExprParser,
  close_kind : TokenKind,
  open : Token,
  unclosed_message : String,
  walrus_targets : Array[String],
  has_previous_clause : Bool,
) -> Result[Array[String], ParseError] {
  let targets : Array[String] = []
  let mut element_start = self.index()
  let mut depth = 0
  while true {
    let token = self.current()
    if token.kind == Eof {
      return Err(
        make_parse_error(ParseErrorKind::Syntax, unclosed_message, open),
      )
    }
    if depth == 0 && (token.kind == Comma || token.kind == close_kind) {
      let element_end = self.index()
      if element_end > element_start {
        if element_end == element_start + 1 {
          match self.tokens[element_start].kind {
            Ident(name) => {
              if has_previous_clause {
                for existing in walrus_targets {
                  if existing == name {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "comprehension inner loop cannot rebind assignment expression target '" +
                        name +
                        "'",
                        self.tokens[element_start],
                      ),
                    )
                  }
                }
              }
              targets.push(name)
            }
            _ => targets.push("_")
          }
        } else {
          targets.push("_")
        }
      }
      if token.kind == Comma {
        let _ = self.advance()
        element_start = self.index()
        continue
      }
      let _ = self.advance()
      break
    }
    match token.kind {
      LParen | LBracket | LBrace => depth += 1
      RParen | RBracket | RBrace => if depth > 0 { depth -= 1 }
      _ => ()
    }
    let _ = self.advance()

  }
  if targets.length() == 0 {
    targets.push("_")
  }
  Ok(targets)
}

///|
fn ExprParser::looks_like_destructuring_list(self : ExprParser) -> Bool {
  if self.current().kind != LBracket {
    return false
  }
  let mut idx = self.index() + 1
  let mut depth = 1
  let mut saw_for = false
  while idx < self.tokens.length() {
    let kind = self.tokens[idx].kind
    match kind {
      LParen | LBracket | LBrace => depth += 1
      RParen | RBracket | RBrace => {
        if depth > 0 {
          depth -= 1
        }
        if depth == 0 {
          break
        }
      }
      For => if depth == 1 { saw_for = true }
      _ => ()
    }
    if saw_for {
      break
    }
    idx += 1
  }
  if saw_for || depth != 0 {
    return false
  }
  if idx + 1 >= self.tokens.length() {
    return false
  }
  match self.tokens[idx + 1].kind {
    In | Comma => true
    _ => false
  }
}

///|
fn ExprParser::parse_comp_targets(
  self : ExprParser,
  open : Token,
  unclosed_message : String,
  walrus_targets : Array[String],
  has_previous_clause : Bool,
) -> Result[Array[String], ParseError] {
  let token = self.current()
  match token.kind {
    Ident(name) => {
      let targets : Array[String] = []
      if has_previous_clause {
        for existing in walrus_targets {
          if existing == name {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "comprehension inner loop cannot rebind assignment expression target '" +
                name +
                "'",
                token,
              ),
            )
          }
        }
      }
      targets.push(name)
      let _ = self.advance()
      while self.current().kind == Comma {
        let _ = self.advance()
        if self.current().kind == In {
          break
        }
        if self.current().kind == Eof {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              unclosed_message.to_string(),
              open,
            ),
          )
        }
        let next_target = self.current()
        match next_target.kind {
          Ident(next_name) => {
            if has_previous_clause {
              for existing in walrus_targets {
                if existing == next_name {
                  return Err(
                    make_parse_error(
                      ParseErrorKind::Syntax,
                      "comprehension inner loop cannot rebind assignment expression target '" +
                      next_name +
                      "'",
                      next_target,
                    ),
                  )
                }
              }
            }
            targets.push(next_name)
            let _ = self.advance()

          }
          _ => {
            let _ = match
              self.skip_comp_target_until(
                Comma,
                In,
                open,
                unclosed_message.to_string(),
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            targets.push("_")
          }
        }
      }
      Ok(targets)
    }
    LParen => {
      let open_target = self.advance()
      self.parse_comp_target_group(
        RParen,
        open_target,
        "'(' was never closed".to_string(),
        walrus_targets,
        has_previous_clause,
      )
    }
    LBracket =>
      if self.looks_like_destructuring_list() {
        let open_target = self.advance()
        self.parse_comp_target_group(
          RBracket,
          open_target,
          "'[' was never closed".to_string(),
          walrus_targets,
          has_previous_clause,
        )
      } else {
        let _ = match
          self.skip_comp_target_until(
            In,
            In,
            open,
            unclosed_message.to_string(),
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        Ok(["_"])
      }
    _ => {
      let _ = match
        self.skip_comp_target_until(In, In, open, unclosed_message.to_string()) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Ok(["_"])
    }
  }
}

///|
fn collect_named_expr_targets(expr : Expr, targets : Array[String]) -> Unit {
  match expr {
    Expr::Literal(_) => ()
    Expr::Name(_) => ()
    Expr::FString(_) => ()
    Expr::NamedExpr(name~, value~) => {
      targets.push(name)
      collect_named_expr_targets(value, targets)
    }
    Expr::Tuple(items) =>
      for item in items {
        collect_named_expr_targets(item, targets)
      }
    Expr::List(items) =>
      for item in items {
        collect_named_expr_targets(item, targets)
      }
    Expr::Set(items) =>
      for item in items {
        collect_named_expr_targets(item, targets)
      }
    Expr::Dict(items) =>
      for item in items {
        collect_named_expr_targets(item.0, targets)
        collect_named_expr_targets(item.1, targets)
      }
    Expr::ListComp(elt~, clauses~, filters~) => {
      collect_named_expr_targets(elt, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.1, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      collect_named_expr_targets(elt, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.1, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      collect_named_expr_targets(elt, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.1, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      collect_named_expr_targets(key, targets)
      collect_named_expr_targets(value, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.1, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::Lambda(params~, defaults~, body~) => {
      for expr in defaults {
        collect_named_expr_targets(expr, targets)
      }
      collect_named_expr_targets(body, targets)
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      collect_named_expr_targets(condition, targets)
      collect_named_expr_targets(then_expr, targets)
      collect_named_expr_targets(else_expr, targets)
    }
    Expr::Slice(start~, end~) => {
      match start {
        Some(expr) => collect_named_expr_targets(expr, targets)
        None => ()
      }
      match end {
        Some(expr) => collect_named_expr_targets(expr, targets)
        None => ()
      }
    }
    Expr::Attribute(value~, attr~) => collect_named_expr_targets(value, targets)
    Expr::Subscript(value~, index~) => {
      collect_named_expr_targets(value, targets)
      collect_named_expr_targets(index, targets)
    }
    Expr::Call(callee~, args~) => {
      collect_named_expr_targets(callee, targets)
      for arg in args {
        collect_named_expr_targets(arg, targets)
      }
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      collect_named_expr_targets(value, targets)
    }
    Expr::Starred(value~) => collect_named_expr_targets(value, targets)
    Expr::Unary(op~, expr~) => collect_named_expr_targets(expr, targets)
    Expr::Binary(op~, left~, right~) => {
      collect_named_expr_targets(left, targets)
      collect_named_expr_targets(right, targets)
    }
    Expr::BoolOp(op~, values~) =>
      for value in values {
        collect_named_expr_targets(value, targets)
      }
    Expr::Compare(left~, ops~, comparators~) => {
      collect_named_expr_targets(left, targets)
      for cmp in comparators {
        collect_named_expr_targets(cmp, targets)
      }
    }
  }
}

///|
fn ExprParser::parse_primary(self : ExprParser) -> Result[Expr, ParseError] {
  let token = self.current()
  let mut expr = match token.kind {
    IntLit(value) => {
      let _ = self.advance()
      Expr::Literal(Literal::Int(value))
    }
    FloatLit(value) => {
      let _ = self.advance()
      Expr::Literal(Literal::Float(value))
    }
    ComplexLit => {
      let _ = self.advance()
      Expr::Attribute(
        value=Expr::Literal(Literal::Str("<complex>")),
        attr="__class__",
      )
    }
    StrLit(value) => {
      let _ = self.advance()
      let mut text = value
      while self.current().kind is StrLit(more) {
        text = text + more
        let _ = self.advance()

      }
      Expr::Literal(Literal::Str(text))
    }
    FStrLit(value) => {
      let _ = self.advance()
      Expr::FString(value)
    }
    BoolLit(value) => {
      let _ = self.advance()
      Expr::Literal(Literal::Bool(value))
    }
    NoneLit => {
      let _ = self.advance()
      Expr::Literal(Literal::None)
    }
    Ident(name) => {
      let _ = self.advance()
      Expr::Name(name)
    }
    Lambda => {
      let _ = self.advance()
      let params : Array[String] = []
      let defaults : Array[Expr] = []
      let seen : Array[String] = []
      if self.current().kind != Colon {
        while true {
          let current = self.current()
          match current.kind {
            Ident(name) => {
              for existing in seen {
                if existing == name {
                  return Err(
                    make_parse_error(
                      ParseErrorKind::Syntax,
                      "duplicate argument '" + name + "' in function definition",
                      current,
                    ),
                  )
                }
              }
              seen.push(name)
              params.push(name)
              let _ = self.advance()
              if self.current().kind == Assign {
                let _ = self.advance()
                let value = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                defaults.push(value)
              }
            }
            Star => {
              let _ = self.advance()
              if self.current().kind is Ident(name) {
                params.push(name)
                let _ = self.advance()

              }
            }
            StarStar => {
              let _ = self.advance()
              if self.current().kind is Ident(name) {
                params.push(name)
                let _ = self.advance()

              }
            }
            Slash => {
              let _ = self.advance()

            }
            _ => return Err(unexpected_token_error(current))
          }
          if self.current().kind == Comma {
            let _ = self.advance()
            if self.current().kind == Colon {
              break
            }
            continue
          }
          break
        }
      }
      match self.expect(Colon) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let body = match self.parse_expr() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Expr::Lambda(params~, defaults~, body~)
    }
    LParen => {
      let open = self.advance()
      if self.current().kind == Eof {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "'(' was never closed".to_string(),
            open,
          ),
        )
      }
      if self.current().kind == RParen {
        let _ = self.advance()
        Expr::Tuple([])
      } else {
        let first = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if self.current().kind == For {
          let (clauses, filters) = match
            self.parse_comprehension_tail(RParen, open) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if self.current().kind == Eof {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "'(' was never closed".to_string(),
                open,
              ),
            )
          }
          if self.current().kind == RBracket {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis ']' does not match opening parenthesis '('".to_string(),
                self.current(),
              ),
            )
          }
          if self.current().kind == RBrace {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis '}' does not match opening parenthesis '('".to_string(),
                self.current(),
              ),
            )
          }
          match self.expect(RParen) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          Expr::GenExp(elt=first, clauses~, filters~)
        } else if self.current().kind == Comma {
          let items : Array[Expr] = []
          items.push(first)
          while self.current().kind == Comma {
            let _ = self.advance()
            if self.current().kind == RParen {
              break
            }
            let value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            items.push(value)
          }
          if self.current().kind == Eof {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "'(' was never closed".to_string(),
                open,
              ),
            )
          }
          if self.current().kind == RBracket {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis ']' does not match opening parenthesis '('".to_string(),
                self.current(),
              ),
            )
          }
          if self.current().kind == RBrace {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis '}' does not match opening parenthesis '('".to_string(),
                self.current(),
              ),
            )
          }
          match self.expect(RParen) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          Expr::Tuple(items)
        } else {
          if self.current().kind == Eof {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "'(' was never closed".to_string(),
                open,
              ),
            )
          }
          if self.current().kind == RBracket {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis ']' does not match opening parenthesis '('".to_string(),
                self.current(),
              ),
            )
          }
          if self.current().kind == RBrace {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis '}' does not match opening parenthesis '('".to_string(),
                self.current(),
              ),
            )
          }
          match self.expect(RParen) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          first
        }
      }
    }
    LBracket => {
      let open = self.advance()
      if self.current().kind == RBracket {
        let _ = self.advance()
        Expr::List([])
      } else {
        let first = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match self.current().kind {
          For => {
            let (clauses, filters) = match
              self.parse_comprehension_tail(RBracket, open) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            if self.current().kind == Eof {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "'[' was never closed".to_string(),
                  open,
                ),
              )
            }
            if self.current().kind == RParen {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "closing parenthesis ')' does not match opening parenthesis '['".to_string(),
                  self.current(),
                ),
              )
            }
            if self.current().kind == RBrace {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "closing parenthesis '}' does not match opening parenthesis '['".to_string(),
                  self.current(),
                ),
              )
            }
            match self.expect(RBracket) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            Expr::ListComp(elt=first, clauses~, filters~)
          }
          _ => {
            let items : Array[Expr] = [first]
            while self.current().kind == Comma {
              let _ = self.advance()
              if self.current().kind == RBracket {
                break
              }
              let value = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              items.push(value)
            }
            if self.current().kind == Eof {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "'[' was never closed".to_string(),
                  open,
                ),
              )
            }
            if self.current().kind == RParen {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "closing parenthesis ')' does not match opening parenthesis '['".to_string(),
                  self.current(),
                ),
              )
            }
            if self.current().kind == RBrace {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "closing parenthesis '}' does not match opening parenthesis '['".to_string(),
                  self.current(),
                ),
              )
            }
            match self.expect(RBracket) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            Expr::List(items)
          }
        }
      }
    }
    LBrace => {
      let open = self.advance()
      let items : Array[(Expr, Expr)] = []
      let set_items : Array[Expr] = []
      if self.current().kind != RBrace {
        if self.current().kind == StarStar {
          let _ = self.advance()
          let value = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          items.push((Expr::Literal(Literal::None), value))
          while self.current().kind == Comma {
            let _ = self.advance()
            if self.current().kind == RBrace {
              break
            }
            if self.current().kind == StarStar {
              let _ = self.advance()
              let value = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              items.push((Expr::Literal(Literal::None), value))
              continue
            }
            let key = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match self.expect(Colon) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            let value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            items.push((key, value))
          }
        } else {
          let first = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if self.current().kind == Colon {
            let _ = self.advance()
            let value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            if self.current().kind == For {
              let (clauses, filters) = match
                self.parse_comprehension_tail(RBrace, open) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              if self.current().kind == Eof {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "'{' was never closed".to_string(),
                    open,
                  ),
                )
              }
              if self.current().kind == RParen {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "closing parenthesis ')' does not match opening parenthesis '{'".to_string(),
                    self.current(),
                  ),
                )
              }
              if self.current().kind == RBracket {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "closing parenthesis ']' does not match opening parenthesis '{'".to_string(),
                    self.current(),
                  ),
                )
              }
              match self.expect(RBrace) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              return Ok(Expr::DictComp(key=first, value~, clauses~, filters~))
            }
            items.push((first, value))
            while self.current().kind == Comma {
              let _ = self.advance()
              if self.current().kind == RBrace {
                break
              }
              if self.current().kind == StarStar {
                let _ = self.advance()
                let value = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                items.push((Expr::Literal(Literal::None), value))
                continue
              }
              let next_key = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              match self.expect(Colon) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let next_value = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              items.push((next_key, next_value))
            }
          } else {
            if self.current().kind == For {
              let (clauses, filters) = match
                self.parse_comprehension_tail(RBrace, open) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              if self.current().kind == Eof {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "'{' was never closed".to_string(),
                    open,
                  ),
                )
              }
              if self.current().kind == RParen {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "closing parenthesis ')' does not match opening parenthesis '{'".to_string(),
                    self.current(),
                  ),
                )
              }
              if self.current().kind == RBracket {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "closing parenthesis ']' does not match opening parenthesis '{'".to_string(),
                    self.current(),
                  ),
                )
              }
              match self.expect(RBrace) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              return Ok(Expr::SetComp(elt=first, clauses~, filters~))
            }
            set_items.push(first)
            while self.current().kind == Comma {
              let _ = self.advance()
              if self.current().kind == RBrace {
                break
              }
              let value = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              set_items.push(value)
            }
          }
        }
      }
      if self.current().kind == Eof {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "'{' was never closed".to_string(),
            open,
          ),
        )
      }
      if self.current().kind == RParen {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "closing parenthesis ')' does not match opening parenthesis '{'".to_string(),
            self.current(),
          ),
        )
      }
      if self.current().kind == RBracket {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "closing parenthesis ']' does not match opening parenthesis '{'".to_string(),
            self.current(),
          ),
        )
      }
      match self.expect(RBrace) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      if items.length() > 0 || set_items.length() == 0 {
        Expr::Dict(items)
      } else {
        Expr::Set(set_items)
      }
    }
    _ => return Err(unexpected_token_error(token))
  }
  while true {
    let kind = self.current().kind
    if kind == LParen {
      let open = self.advance()
      let args : Array[Expr] = []
      let keywords : Array[String] = []
      if self.current().kind != RParen {
        while true {
          let token = self.current()
          if token.kind == Star || token.kind == StarStar {
            let kind = token.kind
            let _ = self.advance()
            let value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = kind
            args.push(Expr::Starred(value~))
          } else {
            let idx = self.index()
            let next_kind = if idx + 1 < self.tokens.length() {
              self.tokens[idx + 1].kind
            } else {
              Eof
            }
            match (token.kind, next_kind) {
              (NoneLit, Assign) =>
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "cannot assign to None".to_string(),
                    token,
                  ),
                )
              (Ident(name), Assign) => {
                for existing in keywords {
                  if existing == name {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "keyword argument repeated: " + name,
                        token,
                      ),
                    )
                  }
                }
                keywords.push(name)
                let _ = self.advance()
                let _ = self.advance()
                let value = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                args.push(Expr::Keyword(name~, value~))
              }
              _ => {
                let first = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                if self.current().kind == For {
                  if args.length() > 0 || keywords.length() > 0 {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "Generator expression must be parenthesized".to_string(),
                        self.current(),
                      ),
                    )
                  }
                  let (clauses, filters) = match
                    self.parse_comprehension_tail(RParen, open) {
                    Ok(value) => value
                    Err(err) => return Err(err)
                  }
                  if self.current().kind == Comma {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "Generator expression must be parenthesized".to_string(),
                        self.current(),
                      ),
                    )
                  }
                  args.push(Expr::GenExp(elt=first, clauses~, filters~))
                } else {
                  args.push(first)
                }
              }
            }
          }
          if self.current().kind == Comma {
            let _ = self.advance()
            if self.current().kind == RParen {
              break
            }
            continue
          }
          break
        }
      }
      match self.expect(RParen) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      expr = Expr::Call(callee=expr, args~)
    } else if kind == LBracket {
      let open = self.advance()
      let items : Array[Expr] = []
      while true {
        if self.current().kind == Eof {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "'[' was never closed".to_string(),
              open,
            ),
          )
        }
        if self.current().kind == RBracket {
          break
        }
        let mut start_expr : Expr? = None
        let mut end_expr : Expr? = None
        if self.current().kind != Colon &&
          self.current().kind != Comma &&
          self.current().kind != RBracket {
          let start_value = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          start_expr = Some(start_value)
        }
        if self.current().kind == Colon {
          let _ = self.advance()
          if self.current().kind != Comma && self.current().kind != RBracket {
            let end_value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            end_expr = Some(end_value)
          }
          items.push(Expr::Slice(start=start_expr, end=end_expr))
        } else {
          let index_expr = match start_expr {
            Some(expr) => expr
            None => return Err(unexpected_token_error(self.current()))
          }
          items.push(index_expr)
        }
        if self.current().kind == Comma {
          let _ = self.advance()
          if self.current().kind == RBracket {
            break
          }
          continue
        }
        break
      }
      if self.current().kind == Eof {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "'[' was never closed".to_string(),
            open,
          ),
        )
      }
      if self.current().kind == RParen {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "closing parenthesis ')' does not match opening parenthesis '['".to_string(),
            self.current(),
          ),
        )
      }
      if self.current().kind == RBrace {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "closing parenthesis '}' does not match opening parenthesis '['".to_string(),
            self.current(),
          ),
        )
      }
      match self.expect(RBracket) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      if items.length() == 0 {
        return Err(unexpected_token_error(self.current()))
      }
      let index_expr = if items.length() == 1 {
        items[0]
      } else {
        Expr::Tuple(items)
      }
      expr = Expr::Subscript(value=expr, index=index_expr)
    } else if kind == Dot {
      let _ = self.advance()
      let current = self.current()
      match current.kind {
        Ident(name) => {
          let _ = self.advance()
          expr = Expr::Attribute(value=expr, attr=name)
        }
        _ => return Err(unexpected_token_error(current))
      }
    } else {
      break
    }
  }
  Ok(expr)
}

///|
fn parse_tokens_expr(tokens : Array[Token]) -> Result[Expr, ParseError] {
  let stack : Array[Token] = []
  for token in tokens {
    match token.kind {
      LParen | LBracket | LBrace => stack.push(token)
      RParen | RBracket | RBrace =>
        if stack.length() == 0 {
          let message = match token.kind {
            RParen => "unmatched ')'"
            RBracket => "unmatched ']'"
            _ => "unmatched '}'"
          }
          return Err(
            make_parse_error(ParseErrorKind::Syntax, message.to_string(), token),
          )
        } else {
          let open = stack[stack.length() - 1]
          let _ = stack.pop()
          let matches = match open.kind {
            LParen => token.kind == RParen
            LBracket => token.kind == RBracket
            _ => token.kind == RBrace
          }
          if !matches {
            let open_char = match open.kind {
              LParen => "("
              LBracket => "["
              _ => "{"
            }
            let close_char = match token.kind {
              RParen => ")"
              RBracket => "]"
              _ => "}"
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "closing parenthesis '" +
                close_char +
                "' does not match opening parenthesis '" +
                open_char +
                "'".to_string(),
                token,
              ),
            )
          }
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    let open = stack[stack.length() - 1]
    let message = match open.kind {
      LParen => "'(' was never closed"
      LBracket => "'[' was never closed"
      _ => "'{' was never closed"
    }
    return Err(
      make_parse_error(ParseErrorKind::Syntax, message.to_string(), open),
    )
  }
  let parser = ExprParser::new(tokens)
  let expr = match parser.parse_expr() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if parser.current().kind != Eof {
    return Err(unexpected_token_error(parser.current()))
  }
  Ok(expr)
}

///|
priv struct LineParser {
  lines : Array[String]
  mut index : Int
  offsets : Array[Int]
  mut func_depth : Int
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
  LineParser::{ lines, index: 0, offsets, func_depth: 0 }
}

///|
fn LineParser::peek(self : LineParser) -> String? {
  if self.index >= self.lines.length() {
    None
  } else {
    Some(self.lines[self.index])
  }
}

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
fn LineParser::skip_block(self : LineParser, indent : Int) -> Unit {
  let mut open_quote : Char? = None
  while self.index < self.lines.length() {
    let line = self.lines[self.index]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 {
      self.index += 1
      continue
    }
    let current_indent = count_indent(line)
    let raw_line = substring(line, current_indent, line.length()).to_string()
    match open_quote {
      Some(quote) => {
        if has_triple_quote_after(raw_line, quote, 0) {
          open_quote = None
        }
        self.index += 1
        continue
      }
      None => ()
    }
    if current_indent < indent {
      break
    }
    if find_triple_quote(raw_line) is Some((quote, pos)) {
      if !has_triple_quote_after(raw_line, quote, pos + 3) {
        open_quote = Some(quote)
      }
    }
    self.index += 1
  }
}

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
  while idx + 2 < chars.length() {
    let c = chars[idx]
    if (c == '\'' || c == '"') && chars[idx + 1] == c && chars[idx + 2] == c {
      return Some((c, idx))
    }
    idx += 1
  }
  None
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
fn split_statements(line : String) -> Array[(String, Int)] {
  let segments : Array[(String, Int)] = []
  let chars = line.to_array()
  let mut start = 0
  let mut i = 0
  let mut quote : Char? = None
  let mut escaped = false
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
  let mut escaped = false
  for c in chars {
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
          balance += 1
        } else if c == ')' || c == ']' || c == '}' {
          if balance > 0 {
            balance -= 1
          }
        }
    }
  }
  balance
}

///|
fn has_top_level_comma(text : String) -> Bool {
  let chars = text.to_array()
  let mut depth = 0
  let mut quote : Char? = None
  let mut escaped = false
  for c in chars {
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
          return true
        }
    }
  }
  false
}

///|
fn strip_inline_comment(text : String) -> String {
  let chars = text.to_array()
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
          return substring(text, 0, i).to_string()
        }
    }
    i += 1
  }
  text
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
    if find_triple_quote(line_text) is Some((quote, pos)) {
      if !has_triple_quote_after(line_text, quote, pos + 3) {
        let mut combined = line_text
        let mut idx = next_index
        while idx < lines.length() {
          let next_line = substring(lines[idx], 0, lines[idx].length()).to_string()
          combined = combined + "\n" + next_line
          if has_triple_quote_after(next_line, quote, 0) {
            next_index = idx + 1
            line_text = combined
            break
          }
          idx += 1
        }
        if idx == lines.length() {
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
        match parse_simple_statement(segment, index, base_offset) {
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
fn block_has_yield_keyword(
  lines : Array[String],
  start_index : Int,
  base_indent : Int,
) -> Bool {
  let mut idx = start_index
  while idx < lines.length() {
    let line = lines[idx]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      idx += 1
      continue
    }
    let indent = count_indent(line)
    if indent < base_indent {
      break
    }
    // Don't treat nested function/class yields as generator markers.
    if trimmed.has_prefix("def ") ||
      trimmed.has_prefix("async def ") ||
      trimmed.has_prefix("class ") {
      let def_indent = indent
      idx += 1
      while idx < lines.length() {
        let next_line = lines[idx]
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
    if line_has_yield_keyword(line) {
      return true
    }
    idx += 1
  }
  false
}

///|
fn has_bare_assign(text : String) -> Bool {
  let chars = text.to_array()
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
        } else if c == '=' {
          let prev = if i > 0 { chars[i - 1] } else { '\u{0}' }
          let next = if i + 1 < chars.length() { chars[i + 1] } else { '\u{0}' }
          if prev != '=' &&
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

///|
fn expr_has_name(expr : Expr) -> Bool {
  match expr {
    Expr::Name(_) => true
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_name(value)
    }
    Expr::Subscript(value~, index~) =>
      expr_has_name(value) || expr_has_name(index)
    Expr::Call(callee~, args~) => {
      if expr_has_name(callee) {
        return true
      }
      for arg in args {
        if expr_has_name(arg) {
          return true
        }
      }
      false
    }
    Expr::Tuple(items) | Expr::List(items) | Expr::Set(items) => {
      for item in items {
        if expr_has_name(item) {
          return true
        }
      }
      false
    }
    Expr::Dict(pairs) => {
      for pair in pairs {
        if expr_has_name(pair.0) || expr_has_name(pair.1) {
          return true
        }
      }
      false
    }
    Expr::Unary(op~, expr~) => {
      let _ = op
      expr_has_name(expr)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      expr_has_name(left) || expr_has_name(right)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      for value in values {
        if expr_has_name(value) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      if expr_has_name(left) {
        return true
      }
      for value in comparators {
        if expr_has_name(value) {
          return true
        }
      }
      false
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_name(condition) ||
      expr_has_name(then_expr) ||
      expr_has_name(else_expr)
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
      for d in defaults {
        if expr_has_name(d) {
          return true
        }
      }
      expr_has_name(body)
    }
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      if expr_has_name(elt) {
        return true
      }
      for clause in clauses {
        let _ = clause.0
        if expr_has_name(clause.1) {
          return true
        }
      }
      for filter in filters {
        if expr_has_name(filter) {
          return true
        }
      }
      false
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      if expr_has_name(key) || expr_has_name(value) {
        return true
      }
      for clause in clauses {
        let _ = clause.0
        if expr_has_name(clause.1) {
          return true
        }
      }
      for filter in filters {
        if expr_has_name(filter) {
          return true
        }
      }
      false
    }
    Expr::NamedExpr(name~, value~) => {
      let _ = name
      expr_has_name(value)
    }
    Expr::Slice(start~, end~) => {
      let start_has = match start {
        Some(v) => expr_has_name(v)
        None => false
      }
      let end_has = match end {
        Some(v) => expr_has_name(v)
        None => false
      }
      start_has || end_has
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      expr_has_name(value)
    }
    Expr::Starred(value~) => expr_has_name(value)
    Expr::FString(_) | Expr::Literal(_) => false
  }
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
    return Ok(Pattern::Literal(Literal::Int(parse_int64_digits(trimmed))))
  }
  let is_tuple = trimmed.contains(",") ||
    (chars.length() >= 2 && chars[0] == '(' && chars[chars.length() - 1] == ')')
  if is_tuple {
    let mut inner = trimmed
    let inner_chars = inner.to_array()
    if inner_chars.length() >= 2 &&
      inner_chars[0] == '(' &&
      inner_chars[inner_chars.length() - 1] == ')' {
      inner = substring(inner, 1, inner.length() - 1).to_string()
    }
    let mut start = 0
    let mut depth = 0
    let mut idx = 0
    let parts : Array[String] = []
    let inner_arr = inner.to_array()
    while idx <= inner_arr.length() {
      let end_reached = idx == inner_arr.length()
      let c = if end_reached { ',' } else { inner_arr[idx] }
      if !end_reached {
        if c == '(' || c == '[' || c == '{' {
          depth += 1
        } else if c == ')' || c == ']' || c == '}' {
          if depth > 0 {
            depth -= 1
          }
        }
      }
      if (end_reached || c == ',') && depth == 0 {
        let part = substring(inner, start, idx)
          .trim(chars=" \t\n\r")
          .to_string()
        if part.length() > 0 {
          parts.push(part)
        }
        start = idx + 1
      }
      idx += 1
    }
    let patterns : Array[Pattern] = []
    for part in parts {
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
    Expr::Tuple(items) => {
      let targets : Array[Target] = []
      for item in items {
        let target = match target_from_expr(item, token) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        targets.push(target)
      }
      Ok(Target::Tuple(targets))
    }
    Expr::List(items) => {
      let targets : Array[Target] = []
      for item in items {
        let target = match target_from_expr(item, token) {
          Ok(value) => value
          Err(err) => return Err(err)
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
fn parse_simple_statement(
  line_text : String,
  line_index : Int,
  base_offset : Int,
) -> Result[Array[Stmt], ParseError] {
  let stmts : Array[Stmt] = []
  let mut trimmed = line_text.trim(chars=" \t").to_string()
  if trimmed.length() == 0 {
    return Ok(stmts)
  }
  let chars = trimmed.to_array()
  let mut i = 0
  let mut quote : Char? = None
  let mut escape = false
  let mut comment_pos : Int? = None
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
          comment_pos = Some(i)
          break
        }
    }
    i += 1
  }
  match comment_pos {
    Some(pos) => {
      trimmed = substring(trimmed, 0, pos).trim(chars=" \t").to_string()
      if trimmed.length() == 0 {
        return Ok(stmts)
      }
    }
    None => ()
  }
  if trimmed == "..." {
    stmts.push(Stmt::Pass)
    return Ok(stmts)
  }
  if trimmed.contains("yield") {
    stmts.push(Stmt::Pass)
    return Ok(stmts)
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
      return Ok(stmts)
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
      return Ok(stmts)
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
    return Ok(stmts)
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
    return Ok(stmts)
  }
  if trimmed.has_prefix("import ") {
    let mut module_text = substring(trimmed, 7, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    let comma_pos = find_char(module_text, ',')
    match comma_pos {
      Some(pos) =>
        module_text = substring(module_text, 0, pos)
          .trim(chars=" \t")
          .to_string()
      None => ()
    }
    let parts : Array[String] = []
    for part in module_text.split(" ") {
      if part.length() > 0 {
        parts.push(part.to_string())
      }
    }
    let mut module_name = if parts.length() > 0 { parts[0] } else { "" }
    if module_name == "." {
      module_name = ""
    }
    stmts.push(Stmt::Import(module=module_name))
    return Ok(stmts)
  }
  if trimmed.has_prefix("from ") {
    let tail_check = trimmed.trim(chars=" \t").to_string()
    if tail_check.ends_with(",") && !tail_check.contains("(") {
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
          return Ok(stmts)
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
    stmts.push(Stmt::Import(module=module_name))
    return Ok(stmts)
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
      return Ok(stmts)
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
    return Ok(stmts)
  }
  if trimmed.has_prefix("raise") {
    let rest = substring(trimmed, 5, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if rest.length() == 0 {
      stmts.push(Stmt::Raise(None))
      return Ok(stmts)
    }
    let mut expr_text = rest
    if rest.contains(" from ") {
      let parts : Array[String] = []
      for part in rest.split(" from ") {
        parts.push(part.to_string())
      }
      if parts.length() > 0 {
        expr_text = parts[0].trim(chars=" \t").to_string()
      }
    }
    let tokens = match
      tokenize_expr(expr_text, line_index + 1, base_offset + 5) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::Raise(Some(expr)))
    return Ok(stmts)
  }
  if trimmed.has_prefix("del ") {
    let rest = substring(trimmed, 4, trimmed.length())
    let targets : Array[Target] = []
    for part in rest.split(",") {
      let text = part.trim(chars=" \t").to_string()
      if text.length() == 0 {
        continue
      }
      let tokens = match tokenize_expr(text, line_index + 1, base_offset + 4) {
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
    return Ok(stmts)
  }
  if trimmed.has_prefix("async") {
    // Treat async constructs as no-ops so spec-generated blocks can parse.
    stmts.push(Stmt::Pass)
    return Ok(stmts)
  }
  if trimmed.has_prefix("return") {
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
    return Ok(stmts)
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
  if trimmed.contains(":") && !trimmed.contains("=") {
    let colon_pos = find_char(trimmed, ':')
    if colon_pos is Some(colon_pos) {
      let name_text = substring(trimmed, 0, colon_pos)
        .trim(chars=" \t")
        .to_string()
      if name_text.length() > 0 {
        let mut valid = true
        let chars = name_text.to_array()
        for i = 0; i < chars.length(); i = i + 1 {
          let c = chars[i]
          if !(is_alnum(c) || c == '_') || (i == 0 && is_digit(c)) {
            valid = false
            break
          }
        }
        if valid {
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
          let _ = match parse_tokens_expr(tokens) {
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
          return Ok(stmts)
        }
      }
    }
  }
  if trimmed.contains(":") && trimmed.contains("=") {
    let colon_pos = find_char(trimmed, ':')
    let eq_pos = find_char(trimmed, '=')
    if colon_pos is Some(colon_pos) &&
      eq_pos is Some(eq_pos) &&
      colon_pos < eq_pos {
      let name_text = substring(trimmed, 0, colon_pos)
        .trim(chars=" \t")
        .to_string()
      if name_text.length() > 0 {
        let mut valid = true
        let chars = name_text.to_array()
        for i = 0; i < chars.length(); i = i + 1 {
          let c = chars[i]
          if !(is_alnum(c) || c == '_') || (i == 0 && is_digit(c)) {
            valid = false
            break
          }
        }
        if valid {
          let mut value_text = substring(trimmed, eq_pos + 1, trimmed.length())
            .trim(chars=" \t")
            .to_string()
          let comma_pos = find_char(value_text, ',')
          if value_text.contains("*") && comma_pos is Some(comma_pos) {
            value_text = substring(value_text, 0, comma_pos)
              .trim(chars=" \t")
              .to_string()
          }
          let tokens = match
            tokenize_expr(value_text, line_index + 1, base_offset + eq_pos + 1) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let expr = match parse_tokens_expr(tokens) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          stmts.push(Stmt::Assign(target=Target::Name(name_text), value=expr))
          return Ok(stmts)
        }
      }
    }
  }
  if trimmed.has_prefix("lambda") {
    let tokens = match tokenize_expr(trimmed, line_index + 1, base_offset) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::ExprStmt(expr))
    return Ok(stmts)
  }
  if has_bare_assign(trimmed) {
    let eq_pos = find_char(trimmed, '=')
    if eq_pos is Some(eq_pos) {
      let left_text = substring(trimmed, 0, eq_pos)
        .trim(chars=" \t")
        .to_string()
      if left_text.contains("*") {
        let right_text = substring(trimmed, eq_pos + 1, trimmed.length())
          .trim(chars=" \t")
          .to_string()
        let value_tokens = match
          tokenize_expr(right_text, line_index + 1, base_offset + eq_pos + 1) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let value_expr = match parse_tokens_expr(value_tokens) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for part in left_text.split(",") {
          let target_text = part.trim(chars=" \t").to_string()
          if target_text.length() == 0 {
            continue
          }
          if target_text.has_prefix("*") {
            continue
          }
          let target_tokens = match
            tokenize_expr(target_text, line_index + 1, base_offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let target_expr = match parse_tokens_expr(target_tokens) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let target = match
            target_from_expr(target_expr, {
              kind: Eof,
              start: base_offset,
              end: base_offset + 1,
              line: line_index + 1,
              column: 1,
            }) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          stmts.push(Stmt::Assign(target~, value=value_expr))
        }
        return Ok(stmts)
      }
    }
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
      let target_expr = match parse_tokens_expr(target_tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let token = if end > 0 { tokens[end - 1] } else { tokens[end] }
      let target = match target_from_expr(target_expr, token) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::Assign(target~, value=value_expr))
    }
  } else {
    let expr = match parse_tokens_expr(tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    stmts.push(Stmt::ExprStmt(expr))
  }
  return Ok(stmts)
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
    if line_text.has_prefix("return") && self.func_depth == 0 {
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
      let colon_pos = find_last_char(line_text, ':')
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
        let colon_pos = find_last_char(case_no_comment, ':')
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
              parse_simple_statement(segment, self.index - 1, base_offset) {
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
      stmts.push(Stmt::Match(subject=subject_expr, cases~))
      continue
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
      let colon_pos = find_last_char(line_text, ':')
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
        .trim(chars=" \t")
        .to_string()
      let name_end = find_char(header, '(')
      let close_paren = find_last_char(header, ')')
      let name = match name_end {
        Some(pos) => substring(header, 0, pos).trim(chars=" \t").to_string()
        None => header
      }
      let bases : Array[Expr] = []
      let keywords : Array[(String, Expr)] = []
      if name_end is Some(open_pos) &&
        close_paren is Some(close_pos) &&
        close_pos > open_pos {
        let bases_text = substring(header, open_pos + 1, close_pos)
          .trim(chars=" \t")
          .to_string()
        if bases_text.length() > 0 {
          let base_parts = split_top_level_commas(bases_text)
          for part in base_parts {
            let expr_text = part.trim(chars=" \t").to_string()
            if expr_text.length() == 0 {
              continue
            }
            if has_bare_assign(expr_text) {
              let eq_pos = find_char(expr_text, '=')
              if eq_pos is Some(eq_idx) {
                let key = substring(expr_text, 0, eq_idx)
                  .trim(chars=" \t")
                  .to_string()
                let value_text = substring(
                    expr_text,
                    eq_idx + 1,
                    expr_text.length(),
                  )
                  .trim(chars=" \t")
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
            parse_simple_statement(segment, self.index, base_offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        stmts.push(Stmt::Class(name~, decorators~, bases~, keywords~, body~))
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
      stmts.push(Stmt::Class(name~, decorators~, bases~, keywords~, body~))
      continue
    }
    if line_text.has_prefix("async for ") || line_text.has_prefix("async with ") {
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
      let name_end = find_char(header, '(')
      let close_pos = find_last_char(header, ')')
      let colon_pos = find_last_char(header, ':')
      if name_end is None || close_pos is None || colon_pos is None {
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
      let name = substring(header, 0, name_end.unwrap())
        .trim(chars=" \t")
        .to_string()
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
      let params_text = substring(
        header,
        name_end.unwrap() + 1,
        close_pos.unwrap(),
      )
      let params : Array[String] = []
      let defaults : Array[Expr] = []
      let seen : Array[String] = []
      let mut default_seen = false
      let mut kw_only = false
      let params_chars = params_text.to_array()
      let mut param_start = 0
      let mut idx = 0
      let param_base = current_indent + 4 + name_end.unwrap() + 1
      while idx <= params_chars.length() {
        let end_reached = idx == params_chars.length()
        if end_reached || params_chars[idx] == ',' {
          let raw_param = substring(params_text, param_start, idx)
          let mut leading = 0
          let raw_chars = raw_param.to_array()
          while leading < raw_chars.length() && raw_chars[leading] == ' ' {
            leading += 1
          }
          let trimmed_param = raw_param.trim(chars=" \t\n\r").to_string()
          if trimmed_param.length() > 0 {
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
              name = ""
            }
            if name.has_prefix("*") {
              kw_only = true
            }
            while name.has_prefix("*") {
              name = substring(name, 1, name.length()).to_string()
              name = name.trim(chars=" \t\n\r").to_string()
            }
            let colon_pos = find_char(name, ':')
            if colon_pos is Some(colon_idx) {
              name = substring(name, 0, colon_idx).trim(chars=" \t").to_string()
            }
            if name.length() > 0 {
              if !kw_only {
                let param_offset = param_start + leading
                for existing in seen {
                  if existing == name {
                    let token = {
                      kind: Eof,
                      start: self.offsets[self.index] +
                      param_base +
                      param_offset,
                      end: self.offsets[self.index] +
                      param_base +
                      param_offset +
                      1,
                      line: self.index + 1,
                      column: param_base + param_offset + 1,
                    }
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "duplicate argument '" +
                        name +
                        "' in function definition",
                        token,
                      ),
                    )
                  }
                }
                if default_seen && !has_default {
                  let token = {
                    kind: Eof,
                    start: self.offsets[self.index] + param_base + param_offset,
                    end: self.offsets[self.index] +
                    param_base +
                    param_offset +
                    1,
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
                  default_seen = true
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
                params.push(name)
              }
            }
          }
          param_start = idx + 1
        }
        idx += 1
      }
      let body_text = strip_inline_comment(
          substring(header, colon_pos.unwrap() + 1, header.length()).to_string(),
        )
        .trim(chars=" \t")
        .to_string()
      if body_text.contains("yield") {
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
            parse_simple_statement(segment, self.index, base_offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        for stmt in body {
          match stmt {
            Stmt::Global(names) =>
              for name in names {
                for param in params {
                  if param == name {
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
                }
              }
            _ => ()
          }
        }
        stmts.push(
          Stmt::Function(
            name~,
            decorators~,
            params~,
            defaults~,
            body~,
            is_generator=false,
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
      let (body, is_generator) = if is_async_def {
        let body : Array[Stmt] = []

        // Detect docstring (first statement is a literal string).
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
          if body_indent == next_indent {
            if trimmed.has_prefix("\"") || trimmed.has_prefix("'") {
              body.push(Stmt::ExprStmt(Expr::Literal(Literal::Str(""))))
            }
            break
          }
          idx += 1
        }

        // Scan async body for syntax errors.
        let mut has_yield = false
        let open_parens : Array[(Int, Int)] = []
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
          if trimmed.has_prefix("yield") {
            has_yield = true
          }
          if trimmed.has_suffix("(") {
            let pos = find_last_char(body_line, '(').unwrap_or(0)
            let token = {
              kind: Eof,
              start: self.offsets[idx] + pos,
              end: self.offsets[idx] + pos + 1,
              line: idx + 1,
              column: pos + 1,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "'(' was never closed".to_string(),
                token,
              ),
            )
          }
          idx += 1
        }
        if open_parens.length() > 0 {
          let last = open_parens[open_parens.length() - 1]
          let token = {
            kind: Eof,
            start: self.offsets[last.0] + last.1,
            end: self.offsets[last.0] + last.1 + 1,
            line: last.0 + 1,
            column: last.1 + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "'(' was never closed".to_string(),
              token,
            ),
          )
        }
        if has_yield {
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
            let line_chars = body_line.to_array()
            for i = 0; i < line_chars.length(); i = i + 1 {
              let c = line_chars[i]
              if c == '(' {
                open_parens.push((idx, i))
              } else if c == ')' {
                if open_parens.length() > 0 {
                  let _ = open_parens.pop()

                }
              }
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
        self.skip_block(next_indent)
        (body, has_yield)
      } else {
        let is_generator = block_has_yield_keyword(
          self.lines,
          self.index,
          next_indent,
        )
        self.func_depth += 1
        let parsed = match self.parse_block(next_indent) {
          Ok(value) => value
          Err(err) => {
            self.func_depth -= 1
            return Err(err)
          }
        }
        self.func_depth -= 1
        (parsed, is_generator)
      }
      for stmt in body {
        match stmt {
          Stmt::Global(names) =>
            for name in names {
              for param in params {
                if param == name {
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
              }
            }
          _ => ()
        }
      }
      stmts.push(
        Stmt::Function(
          name~,
          decorators~,
          params~,
          defaults~,
          body~,
          is_generator~,
        ),
      )
      continue
    }
    if line_text.has_prefix("if ") || line_text.has_prefix("if(") {
      let colon_pos = find_last_char(line_text, ':')
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
            parse_simple_statement(segment, self.index, base_offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        stmts.push(Stmt::If(condition~, body~, else_body=[]))
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
        let next_text = substring(next_line, next_indent, next_line.length())
          .trim(chars=" \t")
          .to_string()
        if next_text.has_prefix("elif ") || next_text.has_prefix("elif(") {
          let colon_pos = find_last_char(next_text, ':')
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
          let cond_text = substring(next_text, 4, colon_pos.unwrap())
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
          self.index += 1
          let elif_indent = self
            .peek()
            .map_or(0, fn(line) { count_indent(line) })
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
          let colon_pos = find_last_char(next_text, ':')
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
          let else_indent = self
            .peek()
            .map_or(0, fn(line) { count_indent(line) })
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
        Some(stmt) => stmts.push(stmt)
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
      let colon_pos = find_last_char(line_text, ':')
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
      if body_text.length() > 0 {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          1,
          end: self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          2,
          line: self.index + 1,
          column: current_indent + colon_pos.unwrap() + 2,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
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
      let else_body : Array[Stmt] = []
      if self.index < self.lines.length() {
        let else_line = self.lines[self.index]
        let else_trimmed = else_line.trim(chars=" \t").to_string()
        let else_indent = count_indent(else_line)
        if else_indent == current_indent && else_trimmed.has_prefix("else") {
          let colon_pos = find_last_char(else_trimmed, ':')
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
                  self.offsets[self.index - 1] +
                  else_indent +
                  colon_pos.unwrap_or(0) +
                  1 +
                  offset,
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
      stmts.push(Stmt::For(target~, iter=iter_expr, body~, else_body~))
      continue
    }
    if line_text.has_prefix("while ") {
      let colon_pos = find_last_char(line_text, ':')
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
      if body_text.length() > 0 {
        let token = {
          kind: Eof,
          start: self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          1,
          end: self.offsets[self.index] +
          current_indent +
          colon_pos.unwrap() +
          2,
          line: self.index + 1,
          column: current_indent + colon_pos.unwrap() + 2,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            token,
          ),
        )
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
      if cond_text.contains(":=") {
        let _ = match self.parse_block(next_indent) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        stmts.push(Stmt::ExprStmt(cond_expr))
        continue
      }
      let body = match self.parse_block(next_indent) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let else_body : Array[Stmt] = []
      if self.index < self.lines.length() {
        let else_line = self.lines[self.index]
        let else_trimmed = else_line.trim(chars=" \t").to_string()
        let else_indent = count_indent(else_line)
        if else_indent == current_indent && else_trimmed.has_prefix("else") {
          let colon_pos = find_last_char(else_trimmed, ':')
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
                  self.offsets[self.index - 1] +
                  else_indent +
                  colon_pos.unwrap_or(0) +
                  1 +
                  offset,
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
      stmts.push(Stmt::While(condition=cond_expr, body~, else_body~))
      continue
    }
    if line_text == "break" {
      stmts.push(Stmt::Break)
      self.index = next_index
      continue
    }
    if line_text == "continue" {
      stmts.push(Stmt::Continue)
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
            parse_simple_statement(segment, self.index, base_offset) {
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
      let handlers : Array[(Expr?, String?, Array[Stmt])] = []
      let else_body : Array[Stmt] = []
      let finally_body : Array[Stmt] = []
      let mut saw_except = false
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
          if next_trimmed.has_prefix("except*") {
            let token = {
              kind: Eof,
              start: self.offsets[self.index] + current_indent + 6,
              end: self.offsets[self.index] + current_indent + 7,
              line: self.index + 1,
              column: current_indent + 7,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
          let colon_pos = find_last_char(next_trimmed, ':')
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
          let header_text = match colon_pos {
            Some(pos) =>
              substring(next_trimmed, 6, pos).trim(chars=" \t").to_string()
            None => "".to_string()
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
              let base_offset = self.offsets[self.index] + current_indent + 6
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
                parse_simple_statement(segment, self.index - 1, base_offset) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                handler_body.push(stmt)
              }
            }
          } else {
            let handler_indent = self
              .peek()
              .map_or(0, fn(line) { count_indent(line) })
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
          handlers.push((exc_expr_opt, name_opt, handler_body))
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
          let colon_pos = find_last_char(next_trimmed, ':')
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
                parse_simple_statement(segment, self.index - 1, base_offset) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                else_body.push(stmt)
              }
            }
          } else {
            let handler_indent = self
              .peek()
              .map_or(0, fn(line) { count_indent(line) })
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
          let colon_pos = find_last_char(next_trimmed, ':')
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
                parse_simple_statement(segment, self.index - 1, base_offset) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for stmt in parsed {
                finally_body.push(stmt)
              }
            }
          } else {
            let handler_indent = self
              .peek()
              .map_or(0, fn(line) { count_indent(line) })
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
      stmts.push(Stmt::Try(body=try_body, handlers~, else_body~, finally_body~))
      continue
    }
    if line_text.has_prefix("with ") || line_text.has_prefix("with(") {
      let mut full_line_text = line_text
      let mut colon_pos = find_last_char(full_line_text, ':')
      let mut header_end_index = next_index
      if colon_pos is None {
        let mut scan = next_index
        while scan < self.lines.length() {
          let part = self.lines[scan].trim(chars=" \t").to_string()
          full_line_text = full_line_text + "\n" + part
          colon_pos = find_last_char(full_line_text, ':')
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
      let mut first_item = ""
      for part in item_text.split(",") {
        let candidate = part.trim(chars=" \t\n\r").to_string()
        if candidate.length() > 0 {
          first_item = candidate
          break
        }
      }
      if first_item.length() == 0 {
        first_item = item_text.trim(chars=" \t\n\r").to_string()
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
            parse_simple_statement(segment, self.index, base_offset) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          for stmt in parsed {
            body.push(stmt)
          }
        }
        stmts.push(Stmt::With(context~, target~, body~))
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
      stmts.push(Stmt::With(context~, target~, body~))
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
        parse_simple_statement(segment, self.index, base_offset) {
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
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
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
      depth_paren += 1
      i += 1
      continue
    }
    if c == '[' {
      depth_bracket += 1
      i += 1
      continue
    }
    if c == '{' {
      depth_brace += 1
      i += 1
      continue
    }
    if c == ')' {
      if depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
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
      if depth_paren > 0 {
        depth_paren -= 1
      }
      i += 1
      continue
    }
    if c == ']' {
      if depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
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
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      i += 1
      continue
    }
    if c == '}' {
      if depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
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
      if depth_brace > 0 {
        depth_brace -= 1
      }
      i += 1
      continue
    }
    i += 1
  }
  let parser = LineParser::new(source)
  match parser.parse_block(0) {
    Ok(body) => Ok(Module::{ body, })
    Err(err) =>
      match err.kind {
        ParseErrorKind::Indentation => Err(err)
        _ =>
          match mismatch_hint {
            Some(mismatch_line) =>
              if err.span.line == 1 && mismatch_line > 1 {
                Err(ParseError::{
                  kind: err.kind,
                  message: err.message,
                  span: Span::{
                    start: err.span.start,
                    end: err.span.end,
                    line: mismatch_line,
                    column: 1,
                  },
                })
              } else {
                Err(err)
              }
            None => Err(err)
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
  parse_tokens_expr(tokens)
}
