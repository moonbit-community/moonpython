///|
/// Expression parser for moonpython.
///

///|
priv struct ExprParser {
  tokens : Array[Token]
  mut view : ArrayView[Token]
}

///|
let assign_temp_id_ref : Ref[Int] = { val: 0 }

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
fn normalize_param_name_for_compare(param : String) -> String? {
  if param == "*" || param == "/" {
    return None
  }
  let mut name = param
  if name.has_suffix("=") {
    name = substring(name, 0, name.length() - 1)
  }
  if name.has_prefix("**") {
    name = substring(name, 2, name.length())
  } else if name.has_prefix("*") {
    name = substring(name, 1, name.length())
  }
  if name.length() == 0 {
    None
  } else {
    Some(name)
  }
}

///|
fn has_keyword_prefix(text : String, keyword : String) -> Bool {
  if !text.has_prefix(keyword) {
    return false
  }
  if text.length() == keyword.length() {
    return true
  }
  let chars = text.to_array()
  let next = chars[keyword.length()]
  !(is_alnum(next) || next == '_')
}

///|
fn ExprParser::parse_expr(self : ExprParser) -> Result[Expr, ParseError] {
  if self.view() is [{ kind: Yield, .. }, .. rest] {
    self.update_view(rest)
    if self.view() is [{ kind: From, .. }, .. rest2] {
      self.update_view(rest2)
      let inner = match self.parse_conditional() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      return Ok(Expr::YieldFrom(inner))
    }
    match self.view() {
      [{ kind: Eof | Comma | RParen | RBracket | RBrace, .. }, ..] =>
        return Ok(Expr::Yield(None))
      _ => ()
    }
    let first = match self.parse_conditional() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    return match self.view() {
      [{ kind: Comma, .. }, ..] => {
        let items : Array[Expr] = []
        items.push(first)
        while self.view() is [{ kind: Comma, .. }, .. rest3] {
          self.update_view(rest3)
          if self.view() is [{ kind: Eof, .. }, ..] {
            break
          }
          let next = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          items.push(next)
        }
        Ok(Expr::Yield(Some(Expr::Tuple(items))))
      }
      _ => Ok(Expr::Yield(Some(first)))
    }
  }
  let expr = if self.current().kind == Star {
    let star = self.advance()
    let value = match self.parse_conditional() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    // Starred expressions must participate in a tuple/list display (or call
    // args). Without a comma, treat `*expr` as invalid syntax.
    if self.current().kind != Comma {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          star,
        ),
      )
    }
    Expr::Starred(value~)
  } else {
    match self.parse_conditional() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
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
        let next = if self.current().kind == Star {
          let _ = self.advance()
          let value = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Expr::Starred(value~)
        } else {
          match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
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
  if self.view() is [{ kind: Yield, .. }, .. rest] {
    self.update_view(rest)
    if self.view() is [{ kind: From, .. }, .. rest2] {
      self.update_view(rest2)
      let inner = match self.parse_conditional() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      return Ok(Expr::YieldFrom(inner))
    }
    match self.view() {
      [{ kind: Eof | Comma | RParen | RBracket | RBrace, .. }, ..] =>
        return Ok(Expr::Yield(None))
      _ => ()
    }
    let inner = match self.parse_conditional() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    return Ok(Expr::Yield(Some(inner)))
  }
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
  match self.parse_not() {
    Ok(first) => values.push(first)
    Err(err) => return Err(err)
  }
  while self.view() is [{ kind: And, .. }, .. rest] {
    self.update_view(rest)
    match self.parse_not() {
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
fn ExprParser::parse_not(self : ExprParser) -> Result[Expr, ParseError] {
  // `not` has lower precedence than comparisons in Python, but higher than
  // `and`/`or`. Parse it here (not as a factor-level unary op) so expressions
  // like `not x in y` behave like `not (x in y)`.
  if self.view() is [{ kind: Not, .. }, .. rest] {
    self.update_view(rest)
    let expr = match self.parse_not() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(Expr::Unary(op=UnaryOp::Not, expr~))
  } else {
    self.parse_compare()
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
) -> Result[(Array[CompClause], Array[Expr]), ParseError] {
  let clauses : Array[CompClause] = []
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
      [{ kind: Async, .. }, { kind: For, .. }, .. rest] => {
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
        let iter = match self.parse_or() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        // PEP 572: forbid assignment expressions in comprehension iterables.
        let iter_walrus_targets : Array[String] = []
        collect_named_expr_targets(iter, iter_walrus_targets)
        if iter_walrus_targets.length() > 0 {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              open,
            ),
          )
        }
        clauses.push(CompClause::{ is_async: true, targets, iter })
        continue
      }
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
        // PEP 572: forbid assignment expressions in comprehension iterables.
        let iter_walrus_targets : Array[String] = []
        collect_named_expr_targets(iter, iter_walrus_targets)
        if iter_walrus_targets.length() > 0 {
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid syntax".to_string(),
              open,
            ),
          )
        }
        clauses.push(CompClause::{ is_async: false, targets, iter })
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
        // In comprehensions, parse `if` filters as a non-conditional expression.
        // This matches CPython's grammar (`if` filter expects an `or_test`) and
        // allows multiple `if` clauses without the next `if` being consumed as a
        // ternary operator.
        let cond = match self.parse_or() {
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
        } else if element_end == element_start + 2 &&
          self.tokens[element_start].kind == Star &&
          self.tokens[element_start + 1].kind is Ident(name) {
          if has_previous_clause {
            for existing in walrus_targets {
              if existing == name {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "comprehension inner loop cannot rebind assignment expression target '" +
                    name +
                    "'",
                    self.tokens[element_start + 1],
                  ),
                )
              }
            }
          }
          targets.push(name)
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
      if self.current().kind != Comma && self.current().kind != In {
        // Comprehension targets can be general assignment targets (e.g. `x[0]`),
        // but moonpython currently only tracks bound names. Skip unsupported
        // target shapes and use a placeholder binding.
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
        return Ok(["_"])
      }
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
          LParen => {
            let open_target = self.advance()
            let group_targets = match
              self.parse_comp_target_group(
                RParen,
                open_target,
                "'(' was never closed".to_string(),
                walrus_targets,
                has_previous_clause,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            for t in group_targets {
              targets.push(t)
            }
          }
          LBracket =>
            if self.looks_like_destructuring_list() {
              let open_target = self.advance()
              let group_targets = match
                self.parse_comp_target_group(
                  RBracket,
                  open_target,
                  "'[' was never closed".to_string(),
                  walrus_targets,
                  has_previous_clause,
                ) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              for t in group_targets {
                targets.push(t)
              }
            } else {
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
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) => collect_named_expr_targets(value, targets)
        None => ()
      }
    Expr::YieldFrom(value) => collect_named_expr_targets(value, targets)
    Expr::Await(value) => collect_named_expr_targets(value, targets)
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
        collect_named_expr_targets(clause.iter, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      collect_named_expr_targets(elt, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.iter, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      collect_named_expr_targets(elt, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.iter, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      collect_named_expr_targets(key, targets)
      collect_named_expr_targets(value, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.iter, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
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
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(expr) => collect_named_expr_targets(expr, targets)
        None => ()
      }
      match end {
        Some(expr) => collect_named_expr_targets(expr, targets)
        None => ()
      }
      match step {
        Some(expr) => collect_named_expr_targets(expr, targets)
        None => ()
      }
    }
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      collect_named_expr_targets(value, targets)
    }
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
    Expr::DoubleStarred(value~) => collect_named_expr_targets(value, targets)
    Expr::Unary(op~, expr~) => {
      let _ = op
      collect_named_expr_targets(expr, targets)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      collect_named_expr_targets(left, targets)
      collect_named_expr_targets(right, targets)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      for value in values {
        collect_named_expr_targets(value, targets)
      }
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      collect_named_expr_targets(left, targets)
      for cmp in comparators {
        collect_named_expr_targets(cmp, targets)
      }
    }
  }
}

///|
fn collect_comprehension_bound_names(
  clauses : Array[CompClause],
  out : Array[String],
) -> Unit {
  for clause in clauses {
    for name in clause.targets {
      if name == "_" {
        continue
      }
      let mut seen = false
      for existing in out {
        if existing == name {
          seen = true
          break
        }
      }
      if !seen {
        out.push(name)
      }
    }
  }
}

///|
fn validate_comprehension_walrus(
  open : Token,
  clauses : Array[CompClause],
  exprs : Array[Expr],
) -> Result[Unit, ParseError] {
  let bound : Array[String] = []
  collect_comprehension_bound_names(clauses, bound)
  if bound.length() == 0 {
    return Ok(())
  }
  let walrus_targets : Array[String] = []
  for expr in exprs {
    collect_named_expr_targets(expr, walrus_targets)
  }
  for name in walrus_targets {
    for b in bound {
      if name == b {
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid syntax".to_string(),
            open,
          ),
        )
      }
    }
  }
  Ok(())
}

///|
fn bytes_from_string_literal(
  value : String,
  token : Token,
) -> Result[Array[Int], ParseError] {
  let out : Array[Int] = []
  for ch in value.to_array() {
    let code = ch.to_int()
    if code > 255 {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "bytes can only contain ASCII literal characters".to_string(),
          token,
        ),
      )
    }
    out.push(code)
  }
  Ok(out)
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
    ComplexLit(value) => {
      let _ = self.advance()
      Expr::Literal(Literal::Complex(0.0, value))
    }
    StrLit(value) => {
      let _ = self.advance()
      let pieces : Array[Expr] = [Expr::Literal(Literal::Str(value))]
      while true {
        match self.current().kind {
          StrLit(text) => {
            let _ = self.advance()
            pieces.push(Expr::Literal(Literal::Str(text)))
          }
          FStrLit(text) => {
            let _ = self.advance()
            pieces.push(Expr::FString(text))
          }
          BytesLit(_) =>
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "cannot mix bytes and nonbytes literals".to_string(),
                self.current(),
              ),
            )
          _ => break
        }
      }
      if pieces.length() == 1 {
        pieces[0]
      } else {
        // Merge adjacent literal pieces to avoid deep trees for plain strings.
        let simplified : Array[Expr] = []
        for piece in pieces {
          match piece {
            Expr::Literal(Literal::Str(text)) =>
              if simplified.length() > 0 {
                let last_idx = simplified.length() - 1
                match simplified[last_idx] {
                  Expr::Literal(Literal::Str(prev)) =>
                    simplified[last_idx] = Expr::Literal(
                      Literal::Str(prev + text),
                    )
                  _ => simplified.push(piece)
                }
              } else {
                simplified.push(piece)
              }
            _ => simplified.push(piece)
          }
        }
        let mut expr = simplified[0]
        for i = 1; i < simplified.length(); i = i + 1 {
          expr = Expr::Binary(op=BinaryOp::Add, left=expr, right=simplified[i])
        }
        expr
      }
    }
    BytesLit(value) => {
      let token = self.current()
      let _ = self.advance()
      let merged : Array[Int] = []
      let first = match bytes_from_string_literal(value, token) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for item in first {
        merged.push(item)
      }
      while true {
        match self.current().kind {
          BytesLit(text) => {
            let token = self.current()
            let _ = self.advance()
            let more = match bytes_from_string_literal(text, token) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for item in more {
              merged.push(item)
            }
          }
          StrLit(_) | FStrLit(_) =>
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "cannot mix bytes and nonbytes literals".to_string(),
                self.current(),
              ),
            )
          _ => break
        }
      }
      Expr::Literal(Literal::Bytes(merged))
    }
    FStrLit(value) => {
      let _ = self.advance()
      let pieces : Array[Expr] = [Expr::FString(value)]
      while true {
        match self.current().kind {
          StrLit(text) => {
            let _ = self.advance()
            pieces.push(Expr::Literal(Literal::Str(text)))
          }
          FStrLit(text) => {
            let _ = self.advance()
            pieces.push(Expr::FString(text))
          }
          BytesLit(_) =>
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "cannot mix bytes and nonbytes literals".to_string(),
                self.current(),
              ),
            )
          _ => break
        }
      }
      if pieces.length() == 1 {
        pieces[0]
      } else {
        let mut expr = pieces[0]
        for i = 1; i < pieces.length(); i = i + 1 {
          expr = Expr::Binary(op=BinaryOp::Add, left=expr, right=pieces[i])
        }
        expr
      }
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
    Await => {
      let _ = self.advance()
      let expr = match self.parse_primary() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      Expr::Await(expr)
    }
    Lambda => {
      let _ = self.advance()
      let params : Array[String] = []
      let defaults : Array[Expr] = []
      let seen : Array[String] = []
      let mut default_seen = false
      let mut kw_only = false
      let mut saw_slash = false
      if self.current().kind != Colon {
        while true {
          let current = self.current()
          match current.kind {
            Ident(name) => {
              let mut encoded = name
              let _ = self.advance()
              if self.current().kind == Assign {
                let _ = self.advance()
                let value = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                defaults.push(value)
                encoded = name + "="
                if !kw_only {
                  default_seen = true
                }
              } else if !kw_only && default_seen {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "non-default argument follows default argument".to_string(),
                    current,
                  ),
                )
              }
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
              params.push(encoded)
            }
            Star => {
              let _ = self.advance()
              let mut has_name = false
              if self.current().kind is Ident(name) {
                has_name = true
                for existing in seen {
                  if existing == name {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "duplicate argument '" +
                        name +
                        "' in function definition",
                        current,
                      ),
                    )
                  }
                }
                seen.push(name)
                params.push("*" + name)
                let _ = self.advance()
                if self.current().kind == Assign {
                  return Err(
                    make_parse_error(
                      ParseErrorKind::Syntax,
                      "invalid syntax".to_string(),
                      self.current(),
                    ),
                  )
                }
              }
              if !has_name {
                params.push("*")
              }
              kw_only = true
            }
            StarStar => {
              let _ = self.advance()
              if self.current().kind is Ident(name) {
                for existing in seen {
                  if existing == name {
                    return Err(
                      make_parse_error(
                        ParseErrorKind::Syntax,
                        "duplicate argument '" +
                        name +
                        "' in function definition",
                        current,
                      ),
                    )
                  }
                }
                seen.push(name)
                params.push("**" + name)
                let _ = self.advance()
                if self.current().kind == Assign {
                  return Err(
                    make_parse_error(
                      ParseErrorKind::Syntax,
                      "invalid syntax".to_string(),
                      self.current(),
                    ),
                  )
                }
              }
              kw_only = true
            }
            Slash => {
              if saw_slash || kw_only || params.length() == 0 {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "invalid syntax".to_string(),
                    current,
                  ),
                )
              }
              saw_slash = true
              params.push("/")
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
      let body_started_paren = self.current().kind == LParen
      let body = match self.parse_conditional() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match body {
        Expr::NamedExpr(..) =>
          if !body_started_paren {
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid syntax".to_string(),
                token,
              ),
            )
          }
        _ => ()
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
        let first = if self.current().kind == Star {
          let _ = self.advance()
          let value = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Expr::Starred(value~)
        } else {
          match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        if self.current().kind == For || self.current().kind == Async {
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
          let exprs : Array[Expr] = [first]
          for f in filters {
            exprs.push(f)
          }
          match validate_comprehension_walrus(open, clauses, exprs) {
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
            let value = if self.current().kind == Star {
              let _ = self.advance()
              let value = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Expr::Starred(value~)
            } else {
              match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
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
        let first = if self.current().kind == Star {
          let _ = self.advance()
          let value = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Expr::Starred(value~)
        } else {
          match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        match self.current().kind {
          For | Async => {
            if first is Expr::Starred(_) {
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid syntax".to_string(),
                  open,
                ),
              )
            }
            match first {
              _ => ()
            }
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
            let exprs : Array[Expr] = [first]
            for f in filters {
              exprs.push(f)
            }
            match validate_comprehension_walrus(open, clauses, exprs) {
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
              let value = if self.current().kind == Star {
                let _ = self.advance()
                let value = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                Expr::Starred(value~)
              } else {
                match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
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
          items.push(
            (Expr::DoubleStarred(value~), Expr::Literal(Literal::None)),
          )
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
              items.push(
                (Expr::DoubleStarred(value~), Expr::Literal(Literal::None)),
              )
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
          let first = if self.current().kind == Star {
            let _ = self.advance()
            let value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            Expr::Starred(value~)
          } else {
            match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
          }
          if self.current().kind == Colon {
            let _ = self.advance()
            let value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            if self.current().kind == For || self.current().kind == Async {
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
              let exprs : Array[Expr] = [first, value]
              for f in filters {
                exprs.push(f)
              }
              match validate_comprehension_walrus(open, clauses, exprs) {
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
                items.push(
                  (Expr::DoubleStarred(value~), Expr::Literal(Literal::None)),
                )
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
            if self.current().kind == For || self.current().kind == Async {
              if first is Expr::Starred(_) {
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "invalid syntax".to_string(),
                    open,
                  ),
                )
              }
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
              let exprs : Array[Expr] = [first]
              for f in filters {
                exprs.push(f)
              }
              match validate_comprehension_walrus(open, clauses, exprs) {
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
              let value = if self.current().kind == Star {
                let _ = self.advance()
                let value = match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                Expr::Starred(value~)
              } else {
                match self.parse_conditional() {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
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
            match kind {
              Star => args.push(Expr::Starred(value~))
              StarStar => args.push(Expr::DoubleStarred(value~))
              _ => args.push(Expr::Starred(value~))
            }
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
                if self.current().kind == For || self.current().kind == Async {
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
                  let exprs : Array[Expr] = [first]
                  for f in filters {
                    exprs.push(f)
                  }
                  match validate_comprehension_walrus(open, clauses, exprs) {
                    Ok(_) => ()
                    Err(err) => return Err(err)
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
          if self.current().kind == Star {
            let _ = self.advance()
            let start_value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            start_expr = Some(Expr::Starred(value=start_value))
          } else {
            let start_value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            start_expr = Some(start_value)
          }
        }
        if self.current().kind == Colon {
          let _ = self.advance()
          if self.current().kind != Colon &&
            self.current().kind != Comma &&
            self.current().kind != RBracket {
            let end_value = match self.parse_conditional() {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            end_expr = Some(end_value)
          }
          let mut step_expr : Expr? = None
          if self.current().kind == Colon {
            let _ = self.advance()
            if self.current().kind != Comma && self.current().kind != RBracket {
              let step_value = match self.parse_conditional() {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              step_expr = Some(step_value)
            }
          }
          items.push(
            Expr::Slice(start=start_expr, end=end_expr, step=step_expr),
          )
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
