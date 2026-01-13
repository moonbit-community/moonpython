///|
/// Parser for the mpython interpreter.

///|
priv struct ExprParser {
  tokens : Array[Token]
  mut index : Int
}

///|
fn ExprParser::current(self : ExprParser) -> Token {
  self.tokens[self.index]
}

///|
fn ExprParser::advance(self : ExprParser) -> Token {
  let token = self.tokens[self.index]
  self.index += 1
  token
}

///|
fn ExprParser::expect(
  self : ExprParser,
  kind : TokenKind,
) -> Result[Token, ParseError] {
  let token = self.current()
  if token.kind == kind {
    self.index += 1
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
  if self.current().kind == Comma {
    let items : Array[Expr] = []
    items.push(expr)
    while self.current().kind == Comma {
      let _ = self.advance()
      if self.current().kind == Eof {
        break
      }
      let next = match self.parse_conditional() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      items.push(next)
    }
    Ok(Expr::Tuple(items))
  } else {
    Ok(expr)
  }
}

///|
fn ExprParser::parse_conditional(self : ExprParser) -> Result[Expr, ParseError] {
  let expr = match self.parse_or() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if self.current().kind == If {
    let _ = self.advance()
    let condition = match self.parse_or() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if self.current().kind != Else {
      return Err(unexpected_token_error(self.current()))
    }
    let _ = self.advance()
    let else_expr = match self.parse_conditional() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(Expr::IfExpr(condition=condition, then_expr=expr, else_expr=else_expr))
  } else {
    Ok(expr)
  }
}

///|
fn ExprParser::parse_or(self : ExprParser) -> Result[Expr, ParseError] {
  let values : Array[Expr] = []
  match self.parse_and() {
    Ok(first) => values.push(first)
    Err(err) => return Err(err)
  }
  while self.current().kind == Or {
    let _ = self.advance()
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
  while self.current().kind == And {
    let _ = self.advance()
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
fn ExprParser::parse_compare(self : ExprParser) -> Result[Expr, ParseError] {
  let left = match self.parse_sum() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let ops : Array[CompareOp] = []
  let comparators : Array[Expr] = []
  while true {
    let mut op : CompareOp? = None
    let kind = self.current().kind
    if kind == EqEq {
      op = Some(CompareOp::Eq)
      let _ = self.advance()

    } else if kind == NotEq {
      op = Some(CompareOp::NotEq)
      let _ = self.advance()

    } else if kind == Lt {
      op = Some(CompareOp::Lt)
      let _ = self.advance()

    } else if kind == Lte {
      op = Some(CompareOp::Lte)
      let _ = self.advance()

    } else if kind == Gt {
      op = Some(CompareOp::Gt)
      let _ = self.advance()

    } else if kind == Gte {
      op = Some(CompareOp::Gte)
      let _ = self.advance()

    } else if kind == In {
      op = Some(CompareOp::In)
      let _ = self.advance()

    } else if kind == Is {
      let _ = self.advance()
      if self.current().kind == Not {
        let _ = self.advance()
        op = Some(CompareOp::IsNot)
      } else {
        op = Some(CompareOp::Is)
      }
    } else if kind == Not {
      let _ = self.advance()
      if self.current().kind == In {
        let _ = self.advance()
        op = Some(CompareOp::NotIn)
      } else {
        return Err(unexpected_token_error(self.current()))
      }
    }
    match op {
      Some(op_value) => {
        let right = match self.parse_sum() {
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
    let kind = self.current().kind
    if kind == Plus || kind == Minus {
      let op = if kind == Plus { BinaryOp::Add } else { BinaryOp::Sub }
      let _ = self.advance()
      let right = match self.parse_term() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      expr = Expr::Binary(op~, left=expr, right=right)
    } else {
      break
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
    let kind = self.current().kind
    if kind == Star || kind == Slash || kind == SlashSlash || kind == Percent {
      let op = if kind == Star {
        BinaryOp::Mul
      } else if kind == Slash {
        BinaryOp::Div
      } else if kind == SlashSlash {
        BinaryOp::FloorDiv
      } else {
        BinaryOp::Mod
      }
      let _ = self.advance()
      let right = match self.parse_factor() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      expr = Expr::Binary(op~, left=expr, right=right)
    } else {
      break
    }
  }
  Ok(expr)
}

///|
fn ExprParser::parse_factor(self : ExprParser) -> Result[Expr, ParseError] {
  let kind = self.current().kind
  if kind == Plus || kind == Minus || kind == Not || kind == Tilde {
    let op = if kind == Plus {
      UnaryOp::Pos
    } else if kind == Minus {
      UnaryOp::Neg
    } else if kind == Not {
      UnaryOp::Not
    } else {
      UnaryOp::Invert
    }
    let _ = self.advance()
    let expr = match self.parse_factor() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(Expr::Unary(op~, expr~))
  } else {
    self.parse_primary()
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
    StrLit(value) => {
      let _ = self.advance()
      Expr::Literal(Literal::Str(value))
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
      if self.current().kind != Colon {
        while true {
          let current = self.current()
          match current.kind {
            Ident(name) => {
              let _ = self.advance()
              params.push(name)
            }
            _ => return Err(unexpected_token_error(current))
          }
          if self.current().kind == Comma {
            let _ = self.advance()
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
      Expr::Lambda(params~, body~)
    }
    LParen => {
      let _ = self.advance()
      if self.current().kind == RParen {
        let _ = self.advance()
        Expr::Tuple([])
      } else {
        let first = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        if self.current().kind == Comma {
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
          match self.expect(RParen) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          Expr::Tuple(items)
        } else {
          match self.expect(RParen) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          first
        }
      }
    }
    LBracket => {
      let _ = self.advance()
      let items : Array[Expr] = []
      if self.current().kind != RBracket {
        let first = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        items.push(first)
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
      }
      match self.expect(RBracket) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Expr::List(items)
    }
    LBrace => {
      let _ = self.advance()
      let items : Array[(Expr, Expr)] = []
      if self.current().kind != RBrace {
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
        while self.current().kind == Comma {
          let _ = self.advance()
          if self.current().kind == RBrace {
            break
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
      }
      match self.expect(RBrace) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Expr::Dict(items)
    }
    _ => return Err(unexpected_token_error(token))
  }
  while true {
    let kind = self.current().kind
    if kind == LParen {
      let _ = self.advance()
      let args : Array[Expr] = []
      if self.current().kind != RParen {
        let first = match self.parse_conditional() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        args.push(first)
        while self.current().kind == Comma {
          let _ = self.advance()
          if self.current().kind == RParen {
            break
          }
          let value = match self.parse_conditional() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          args.push(value)
        }
      }
      match self.expect(RParen) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      expr = Expr::Call(callee=expr, args~)
    } else if kind == LBracket {
      let _ = self.advance()
      let mut start_expr : Expr? = None
      let mut end_expr : Expr? = None
      if self.current().kind != Colon && self.current().kind != RBracket {
        let start_value = match self.parse_expr() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        start_expr = Some(start_value)
      }
      if self.current().kind == Colon {
        let _ = self.advance()
        if self.current().kind != RBracket {
          let end_value = match self.parse_expr() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          end_expr = Some(end_value)
        }
        match self.expect(RBracket) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        expr = Expr::Subscript(
          value=expr,
          index=Expr::Slice(start=start_expr, end=end_expr),
        )
      } else {
        match self.expect(RBracket) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let index_expr = if start_expr is Some(start_expr) {
          start_expr
        } else {
          return Err(unexpected_token_error(self.current()))
        }
        expr = Expr::Subscript(value=expr, index=index_expr)
      }
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
priv struct LineParser {
  lines : Array[String]
  mut index : Int
  offsets : Array[Int]
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
  LineParser::{ lines, index: 0, offsets }
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
fn count_indent(line : String) -> Int {
  let chars = line.to_array()
  let mut count = 0
  for c in chars {
    if c == ' ' {
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
    if chars[idx] == quote &&
      chars[idx + 1] == quote &&
      chars[idx + 2] == quote {
      return true
    }
    idx += 1
  }
  false
}

///|
fn LineParser::parse_block(
  self : LineParser,
  indent : Int,
) -> Result[Array[Stmt], ParseError] {
  let stmts : Array[Stmt] = []
  while self.index < self.lines.length() {
    let line = self.lines[self.index]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 {
      self.index += 1
      continue
    }
    let current_indent = count_indent(line)
    if current_indent < indent {
      break
    }
    if current_indent > indent && indent > 0 {
      let token = {
        kind: Eof,
        start: self.offsets[self.index] + current_indent,
        end: self.offsets[self.index] + current_indent,
        line: self.index + 1,
        column: current_indent + 1,
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
    let mut next_index = self.index + 1
    if line_text.has_prefix("'''") || line_text.has_prefix("\"\"\"") {
      let quote = if line_text.has_prefix("'''") { '\'' } else { '"' }
      if !has_triple_quote_after(raw_line, quote, 3) {
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
    if line_text.has_prefix("def ") {
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
      let params_text = substring(
        header,
        name_end.unwrap() + 1,
        close_pos.unwrap(),
      )
      let params : Array[String] = []
      let params_trimmed = params_text.trim(chars=" \t").to_string()
      if params_trimmed.length() > 0 {
        for param in params_text.split(",") {
          params.push(param.trim(chars=" \t").to_string())
        }
      }
      self.index += 1
      let next_indent = self.peek().map_or(0, fn(line) { count_indent(line) })
      if next_indent <= current_indent {
        let token = {
          kind: Eof,
          start: self.offsets[self.index - 1],
          end: self.offsets[self.index - 1] + line.length(),
          line: self.index,
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
      stmts.push(Stmt::Function(name~, params~, body~))
      continue
    }
    if line_text == "return" || line_text.has_prefix("return ") {
      let expr_text = substring(line_text, 6, line_text.length())
        .trim(chars=" \t")
        .to_string()
      if expr_text.length() == 0 {
        stmts.push(Stmt::Return(None))
      } else {
        let tokens = match
          tokenize_expr(
            expr_text,
            self.index + 1,
            self.offsets[self.index] + current_indent + 6,
          ) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let parser = ExprParser::{ tokens, index: 0 }
        let expr = match parser.parse_expr() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        stmts.push(Stmt::Return(Some(expr)))
      }
      self.index = next_index
      continue
    }
    let tokens = match
      tokenize_expr(
        line_text,
        self.index + 1,
        self.offsets[self.index] + current_indent,
      ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let mut assign_index : Int? = None
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
        assign_index = Some(idx)
        break
      }
    }
    if assign_index is Some(idx) {
      if idx != 1 {
        let token = tokens[0]
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid assignment".to_string(),
            token,
          ),
        )
      }
      match tokens[0].kind {
        Ident(name) => {
          let expr_tokens = slice_tokens(tokens, idx + 1, tokens.length())
          let parser = ExprParser::{ tokens: expr_tokens, index: 0 }
          let expr = match parser.parse_expr() {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          stmts.push(Stmt::Assign(target=Target::Name(name), value=expr))
        }
        _ => {
          let token = tokens[0]
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid assignment".to_string(),
              token,
            ),
          )
        }
      }
    } else {
      let parser = ExprParser::{ tokens, index: 0 }
      let expr = match parser.parse_expr() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      stmts.push(Stmt::ExprStmt(expr))
    }
    self.index = next_index
  }
  Ok(stmts)
}

///|
pub fn parse(source : String) -> Result[Module, ParseError] {
  let parser = LineParser::new(source)
  let body = match parser.parse_block(0) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(Module::{ body, })
}

///|
pub fn parse_expr(source : String) -> Result[Expr, ParseError] {
  let tokens = match tokenize_expr(source, 1, 0) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let parser = ExprParser::{ tokens, index: 0 }
  parser.parse_expr()
}
