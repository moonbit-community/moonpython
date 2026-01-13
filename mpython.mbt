///|
/// Implementation for the mpython interpreter.

///|
priv enum TokenKind {
  IntLit(Int64)
  FloatLit(Double)
  StrLit(String)
  BoolLit(Bool)
  Ident(String)
  LParen
  RParen
  LBracket
  RBracket
  Comma
  Colon
  Plus
  Minus
  Star
  EqEq
  NotEq
  Lt
  Lte
  Gt
  Gte
  Assign
  And
  Or
  Def
  Return
  Eof
} derive(Eq)

///|
priv struct Token {
  kind : TokenKind
  start : Int
  end : Int
  line : Int
  column : Int
}

///|
fn make_parse_error(
  kind : ParseErrorKind,
  message : String,
  token : Token,
) -> ParseError {
  ParseError::{
    kind,
    message,
    span: Span::{
      start: token.start,
      end: token.end,
      line: token.line,
      column: token.column,
    },
  }
}

///|
fn token_text(token : Token) -> String {
  match token.kind {
    TokenKind::IntLit(value) => value.to_string()
    TokenKind::FloatLit(value) => value.to_string()
    TokenKind::StrLit(value) => "\"" + value + "\""
    TokenKind::BoolLit(value) => if value { "True" } else { "False" }
    TokenKind::Ident(name) => name
    TokenKind::LParen => "("
    TokenKind::RParen => ")"
    TokenKind::LBracket => "["
    TokenKind::RBracket => "]"
    TokenKind::Comma => ","
    TokenKind::Colon => ":"
    TokenKind::Plus => "+"
    TokenKind::Minus => "-"
    TokenKind::Star => "*"
    TokenKind::EqEq => "=="
    TokenKind::NotEq => "!="
    TokenKind::Lt => "<"
    TokenKind::Lte => "<="
    TokenKind::Gt => ">"
    TokenKind::Gte => ">="
    TokenKind::Assign => "="
    TokenKind::And => "and"
    TokenKind::Or => "or"
    TokenKind::Def => "def"
    TokenKind::Return => "return"
    TokenKind::Eof => "EOF"
  }
}

///|
fn unexpected_token_error(token : Token) -> ParseError {
  make_parse_error(
    ParseErrorKind::UnexpectedToken,
    "unexpected token '" + token_text(token) + "'",
    token,
  )
}

///|
fn substring_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn substring(source : String, start : Int, end : Int) -> String {
  substring_chars(source.to_array(), start, end)
}

///|
fn find_char(source : String, target : Char) -> Int? {
  let chars = source.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == target {
      return Some(i)
    }
  }
  None
}

///|
fn find_last_char(source : String, target : Char) -> Int? {
  let chars = source.to_array()
  let mut idx = chars.length() - 1
  while idx >= 0 {
    if chars[idx] == target {
      return Some(idx)
    }
    if idx == 0 {
      break
    }
    idx -= 1
  }
  None
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn parse_int_value(text : String) -> Int64 {
  let chars = text.to_array()
  let mut value = 0L
  for c in chars {
    value = value * 10L + (c.to_int() - 48).to_int64()
  }
  value
}

///|
fn parse_float_value(text : String) -> Double {
  let chars = text.to_array()
  let mut value = 0.0
  let mut seen_dot = false
  let mut factor = 0.1
  for c in chars {
    if c == '.' {
      seen_dot = true
    } else if is_digit(c) {
      if seen_dot {
        value = value + (c.to_int() - 48).to_double() * factor
        factor = factor / 10.0
      } else {
        value = value * 10.0 + (c.to_int() - 48).to_double()
      }
    }
  }
  value
}

///|
fn slice_tokens(tokens : Array[Token], start : Int, end : Int) -> Array[Token] {
  let result : Array[Token] = []
  for i = start; i < end; i = i + 1 {
    result.push(tokens[i])
  }
  result
}

///|
fn tokenize_expr(
  source : String,
  line : Int,
  base_offset : Int,
) -> Result[Array[Token], ParseError] {
  let chars = source.to_array()
  let mut i = 0
  let tokens : Array[Token] = []
  let len = chars.length()
  while i < len {
    let c = chars[i]
    if c == ' ' || c == '\t' {
      i += 1
    } else if is_digit(c) {
      let start = i
      let mut has_dot = false
      while i < len {
        let d = chars[i]
        if d == '.' {
          if has_dot {
            break
          }
          has_dot = true
          i += 1
        } else if is_digit(d) {
          i += 1
        } else {
          break
        }
      }
      let text = substring(source, start, i)
      let kind = if has_dot {
        FloatLit(parse_float_value(text))
      } else {
        IntLit(parse_int_value(text))
      }
      tokens.push({
        kind,
        start: base_offset + start,
        end: base_offset + i,
        line,
        column: start + 1,
      })
    } else if c == '"' {
      let start = i
      i += 1
      let buf = StringBuilder::new()
      let mut closed = false
      while i < len {
        let d = chars[i]
        if d == '"' {
          closed = true
          i += 1
          break
        } else if d == '\\' {
          if i + 1 < len {
            let next = chars[i + 1]
            match next {
              'n' => buf.write_char('\n')
              't' => buf.write_char('\t')
              '"' => buf.write_char('"')
              '\\' => buf.write_char('\\')
              _ => buf.write_char(next)
            }
            i += 2
          } else {
            i += 1
          }
        } else {
          buf.write_char(d)
          i += 1
        }
      }
      if !closed {
        let token = {
          kind: Eof,
          start: base_offset + start,
          end: base_offset + len,
          line,
          column: start + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "unterminated string".to_string(),
            token,
          ),
        )
      }
      tokens.push({
        kind: StrLit(buf.to_string()),
        start: base_offset + start,
        end: base_offset + i,
        line,
        column: start + 1,
      })
    } else if is_alpha(c) || c == '_' {
      let start = i
      while i < len {
        let d = chars[i]
        if is_alnum(d) || d == '_' {
          i += 1
        } else {
          break
        }
      }
      let ident = substring(source, start, i)
      let kind = match ident {
        "True" => BoolLit(true)
        "False" => BoolLit(false)
        "and" => And
        "or" => Or
        "def" => Def
        "return" => Return
        _ => Ident(ident)
      }
      tokens.push({
        kind,
        start: base_offset + start,
        end: base_offset + i,
        line,
        column: start + 1,
      })
    } else {
      let start = i
      let (kind, consumed) = match c {
        '(' => (LParen, 1)
        ')' => (RParen, 1)
        '[' => (LBracket, 1)
        ']' => (RBracket, 1)
        ',' => (Comma, 1)
        ':' => (Colon, 1)
        '+' => (Plus, 1)
        '-' => (Minus, 1)
        '*' => (Star, 1)
        '=' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (EqEq, 2)
          } else {
            (Assign, 1)
          }
        '!' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (NotEq, 2)
          } else {
            let token = {
              kind: Eof,
              start: base_offset + start,
              end: base_offset + start + 1,
              line,
              column: start + 1,
            }
            return Err(unexpected_token_error(token))
          }
        '<' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Lte, 2)
          } else {
            (Lt, 1)
          }
        '>' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Gte, 2)
          } else {
            (Gt, 1)
          }
        _ => {
          let token = {
            kind: Eof,
            start: base_offset + start,
            end: base_offset + start + 1,
            line,
            column: start + 1,
          }
          return Err(unexpected_token_error(token))
        }
      }
      tokens.push({
        kind,
        start: base_offset + start,
        end: base_offset + start + consumed,
        line,
        column: start + 1,
      })
      i += consumed
    }
  }
  tokens.push({
    kind: Eof,
    start: base_offset + len,
    end: base_offset + len,
    line,
    column: len + 1,
  })
  Ok(tokens)
}

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
  self.parse_or()
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
    let op = match self.current().kind {
      EqEq => Some(CompareOp::Eq)
      NotEq => Some(CompareOp::NotEq)
      Lt => Some(CompareOp::Lt)
      Lte => Some(CompareOp::Lte)
      Gt => Some(CompareOp::Gt)
      Gte => Some(CompareOp::Gte)
      _ => None
    }
    match op {
      Some(op_value) => {
        let _ = self.advance()
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
    let op = match self.current().kind {
      Plus => Some(BinaryOp::Add)
      Minus => Some(BinaryOp::Sub)
      _ => None
    }
    match op {
      Some(op_value) => {
        let _ = self.advance()
        let right = match self.parse_term() {
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
fn ExprParser::parse_term(self : ExprParser) -> Result[Expr, ParseError] {
  let mut expr = match self.parse_unary() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  while self.current().kind == Star {
    let _ = self.advance()
    let right = match self.parse_unary() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    expr = Expr::Binary(op=BinaryOp::Mul, left=expr, right~)
  }
  Ok(expr)
}

///|
fn ExprParser::parse_unary(self : ExprParser) -> Result[Expr, ParseError] {
  if self.current().kind == Minus {
    let _ = self.advance()
    let expr = match self.parse_unary() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(Expr::Unary(op=UnaryOp::Neg, expr~))
  } else {
    self.parse_primary()
  }
}

///|
fn ExprParser::parse_primary(self : ExprParser) -> Result[Expr, ParseError] {
  let token = self.current()
  let expr = match token.kind {
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
    BoolLit(value) => {
      let _ = self.advance()
      Expr::Literal(Literal::Bool(value))
    }
    Ident(name) => {
      let _ = self.advance()
      Expr::Name(name)
    }
    LParen => {
      let _ = self.advance()
      let inner = match self.parse_expr() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match self.expect(RParen) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      inner
    }
    LBracket => {
      let _ = self.advance()
      let items : Array[Expr] = []
      if self.current().kind != RBracket {
        let first = match self.parse_expr() {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        items.push(first)
        while self.current().kind == Comma {
          let _ = self.advance()
          if self.current().kind == RBracket {
            break
          }
          let value = match self.parse_expr() {
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
    _ => return Err(unexpected_token_error(token))
  }
  if self.current().kind == LParen {
    let _ = self.advance()
    let args : Array[Expr] = []
    if self.current().kind != RParen {
      let first = match self.parse_expr() {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      args.push(first)
      while self.current().kind == Comma {
        let _ = self.advance()
        if self.current().kind == RParen {
          break
        }
        let value = match self.parse_expr() {
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
    Ok(Expr::Call(callee=expr, args~))
  } else {
    Ok(expr)
  }
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
    if current_indent > indent {
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
    let line_text = substring(line, current_indent, line.length())
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
      self.index += 1
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
    for idx = 0; idx < tokens.length(); idx = idx + 1 {
      if tokens[idx].kind == Assign {
        assign_index = Some(idx)
        break
      }
    }
    if assign_index is Some(idx) {
      if idx == 0 {
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
    self.index += 1
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

///|
fn bool_from_value(value : Value) -> Bool {
  match value {
    Value::None => false
    Value::Bool(v) => v
    Value::Int(v) => v != 0L
    Value::Float(v) => v != 0.0
    Value::Str(v) => v.length() > 0
    Value::List(v) => v.length() > 0
    Value::Dict(v) => v.length() > 0
    Value::Function(_) => true
  }
}

///|
fn value_to_string(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Str(v) => v
    Value::List(values) => {
      let buf = StringBuilder::new()
      buf.write_char('[')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char(']')
      buf.to_string()
    }
    Value::Dict(_) => "{}"
    Value::Function(func) => "<function " + func.name + ">"
  }
}

///|
fn eq_value(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::None, Value::None) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Int(a), Value::Int(b)) => a == b
    (Value::Float(a), Value::Float(b)) => a == b
    (Value::Str(a), Value::Str(b)) => a == b
    (Value::List(a), Value::List(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    _ => false
  }
}

///|
fn number_value(value : Value) -> Result[(Bool, Double), RuntimeError] {
  match value {
    Value::Int(v) => Ok((false, v.to_double()))
    Value::Float(v) => Ok((true, v))
    Value::Bool(v) => Ok((false, if v { 1.0 } else { 0.0 }))
    _ =>
      Err(RuntimeError::{
        kind: RuntimeErrorKind::Type,
        message: "expected number".to_string(),
        span: None,
      })
  }
}

///|
fn make_runtime_error(
  kind : RuntimeErrorKind,
  message : String,
) -> RuntimeError {
  RuntimeError::{ kind, message, span: None }
}

///|
fn get_from_env(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Value? {
  for pair in locals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in builtins {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_global_value(
  globals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < globals.length(); i = i + 1 {
    if globals[i].0 == name {
      globals[i] = (name, value)
      return
    }
  }
  globals.push((name, value))
}

///|
fn eval_expr_with_env(
  expr : Expr,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match expr {
    Expr::Literal(literal) =>
      match literal {
        Literal::None => Ok(Value::None)
        Literal::Bool(value) => Ok(Value::Bool(value))
        Literal::Int(value) => Ok(Value::Int(value))
        Literal::Float(value) => Ok(Value::Float(value))
        Literal::Str(value) => Ok(Value::Str(value))
      }
    Expr::Name(name) => {
      let value = get_from_env(name, locals, globals, builtins)
      if value is Some(value) {
        Ok(value)
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
      }
    }
    Expr::List(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        values.push(value)
      }
      Ok(Value::List(values))
    }
    Expr::Unary(op~, expr~) => {
      let value = match
        eval_expr_with_env(expr, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match op {
        UnaryOp::Neg => {
          let (is_float, num) = match number_value(value) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if is_float {
            Ok(Value::Float(-num))
          } else {
            Ok(Value::Int(-num.to_int64()))
          }
        }
        UnaryOp::Pos => Ok(value)
        UnaryOp::Not => Ok(Value::Bool(!bool_from_value(value)))
      }
    }
    Expr::Binary(op~, left~, right~) => {
      let left_val = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let right_val = match
        eval_expr_with_env(right, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match op {
        BinaryOp::Add =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
            (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
            (Value::Int(a), Value::Float(b)) =>
              Ok(Value::Float(a.to_double() + b))
            (Value::Float(a), Value::Int(b)) =>
              Ok(Value::Float(a + b.to_double()))
            (Value::Str(a), Value::Str(b)) => Ok(Value::Str(a + b))
            (Value::List(a), Value::List(b)) => {
              let merged : Array[Value] = []
              for item in a {
                merged.push(item)
              }
              for item in b {
                merged.push(item)
              }
              Ok(Value::List(merged))
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for +".to_string(),
                ),
              )
          }
        BinaryOp::Sub => {
          let (left_is_float, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (right_is_float, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let result = left_num - right_num
          if left_is_float || right_is_float {
            Ok(Value::Float(result))
          } else {
            Ok(Value::Int(result.to_int64()))
          }
        }
        BinaryOp::Mul =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a * b))
            (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a * b))
            (Value::Int(a), Value::Float(b)) =>
              Ok(Value::Float(a.to_double() * b))
            (Value::Float(a), Value::Int(b)) =>
              Ok(Value::Float(a * b.to_double()))
            (Value::Str(text), Value::Int(count)) =>
              if count <= 0L {
                Ok(Value::Str(""))
              } else {
                let buf = StringBuilder::new()
                for i = 0; i < count.to_int(); i = i + 1 {
                  buf.write_string(text)
                }
                Ok(Value::Str(buf.to_string()))
              }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for *".to_string(),
                ),
              )
          }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "operator not implemented".to_string(),
            ),
          )
      }
    }
    Expr::BoolOp(op~, values~) =>
      if values.length() == 0 {
        Ok(Value::Bool(false))
      } else {
        let mut result = match
          eval_expr_with_env(values[0], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        for i = 1; i < values.length(); i = i + 1 {
          match op {
            BoolOp::And => if !bool_from_value(result) { return Ok(result) }
            BoolOp::Or => if bool_from_value(result) { return Ok(result) }
          }
          result = match
            eval_expr_with_env(values[i], locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
        }
        Ok(result)
      }
    Expr::Compare(left~, ops~, comparators~) => {
      let mut previous = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      for i = 0; i < ops.length(); i = i + 1 {
        let current = match
          eval_expr_with_env(comparators[i], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let ok = match ops[i] {
          CompareOp::Eq => eq_value(previous, current)
          CompareOp::NotEq => !eq_value(previous, current)
          CompareOp::Lt => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num < right_num
          }
          CompareOp::Lte => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num <= right_num
          }
          CompareOp::Gt => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num > right_num
          }
          CompareOp::Gte => {
            let (_, left_num) = match number_value(previous) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (_, right_num) = match number_value(current) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            left_num >= right_num
          }
          _ => false
        }
        if !ok {
          return Ok(Value::Bool(false))
        }
        previous = current
      }
      Ok(Value::Bool(true))
    }
    Expr::Call(callee~, args~) => {
      let arg_values : Array[Value] = []
      for arg in args {
        let value = match
          eval_expr_with_env(arg, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        arg_values.push(value)
      }
      match callee {
        Expr::Name(name) =>
          match name {
            "print" => {
              let buf = StringBuilder::new()
              for i = 0; i < arg_values.length(); i = i + 1 {
                if i > 0 {
                  buf.write_string(" ")
                }
                buf.write_string(value_to_string(arg_values[i]))
              }
              buf.write_string("\n")
              io.write_stdout(buf.to_string())
              Ok(Value::None)
            }
            "input" => {
              if arg_values.length() > 0 {
                io.write_stdout(value_to_string(arg_values[0]))
              }
              let line = io.read_line()
              if line is Some(line) {
                Ok(Value::Str(line))
              } else {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "EOF when reading a line".to_string(),
                  ),
                )
              }
            }
            _ => {
              let value = get_from_env(name, locals, globals, builtins)
              if value is Some(value) {
                match value {
                  Value::Function(func) =>
                    eval_function(func, arg_values, globals, builtins, io)
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "object is not callable".to_string(),
                      ),
                    )
                }
              } else {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Name,
                    "name '" + name + "' is not defined",
                  ),
                )
              }
            }
          }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "object is not callable".to_string(),
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "expression not implemented".to_string(),
        ),
      )
  }
}

///|
fn eval_function(
  func : FunctionValue,
  args : Array[Value],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals : Array[(String, Value)] = []
  for i = 0; i < func.params.length(); i = i + 1 {
    let value = if i < args.length() { args[i] } else { Value::None }
    locals.push((func.params[i], value))
  }
  let result = match eval_block(func.body, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(result)
}

///|
fn eval_block(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let mut last = Value::None
  for stmt in body {
    match stmt {
      Stmt::ExprStmt(expr) =>
        last = match eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      Stmt::Assign(target~, value~) => {
        let eval_value = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Target::Name(name) => set_global_value(globals, name, eval_value)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::NotImplemented,
                "assignment target not supported".to_string(),
              ),
            )
        }
        last = Value::None
      }
      Stmt::Return(expr) => {
        if expr is Some(expr) {
          let value = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          return Ok(value)
        }
        return Ok(Value::None)
      }
      Stmt::Function(name~, params~, body~) => {
        let func = FunctionValue::{ name, params, body }
        set_global_value(globals, name, Value::Function(func))
        last = Value::None
      }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "statement not implemented".to_string(),
          ),
        )
    }
  }
  Ok(last)
}

///|
pub fn Config::default() -> Config {
  Config::{ max_recursion: 1000, traceback_limit: 20, track_spans: true }
}

///|
pub fn MockIO::new(stdin : Array[String]) -> MockIO {
  MockIO::{
    stdin,
    stdin_pos: { val: 0 },
    stdout: StringBuilder::new(),
    stderr: StringBuilder::new(),
  }
}

///|
pub fn MockIO::read_line(self : MockIO) -> String? {
  if self.stdin_pos.val >= self.stdin.length() {
    None
  } else {
    let line = self.stdin[self.stdin_pos.val]
    self.stdin_pos.val += 1
    Some(line)
  }
}

///|
pub fn MockIO::write_stdout(self : MockIO, text : String) -> Unit {
  self.stdout.write_string(text)
}

///|
pub fn MockIO::write_stderr(self : MockIO, text : String) -> Unit {
  self.stderr.write_string(text)
}

///|
pub fn MockIO::take_stdout(self : MockIO) -> String {
  self.stdout.to_string()
}

///|
pub fn MockIO::take_stderr(self : MockIO) -> String {
  self.stderr.to_string()
}

///|
pub fn Interpreter::new() -> Interpreter {
  Interpreter::with_io(Config::default(), MockIO::new([]))
}

///|
pub fn Interpreter::with_config(config : Config) -> Interpreter {
  Interpreter::with_io(config, MockIO::new([]))
}

///|
pub fn Interpreter::with_builtins(
  builtins : Array[(String, Value)],
  config : Config,
) -> Interpreter {
  Interpreter::{ config, globals: [], builtins, io: MockIO::new([]) }
}

///|
pub fn Interpreter::with_io(config : Config, io : MockIO) -> Interpreter {
  let builtins : Array[(String, Value)] = [
    (
      "print",
      Value::Function(FunctionValue::{ name: "print", params: [], body: [] }),
    ),
    (
      "input",
      Value::Function(FunctionValue::{ name: "input", params: [], body: [] }),
    ),
  ]
  Interpreter::{ config, globals: [], builtins, io }
}

///|
pub fn Interpreter::exec(
  self : Interpreter,
  program : Module,
) -> Result[RunResult, RuntimeError] {
  let value = match
    eval_block(program.body, [], self.globals, self.builtins, self.io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(RunResult::{
    value,
    stdout: self.io.take_stdout(),
    stderr: self.io.take_stderr(),
    globals: self.globals,
  })
}

///|
pub fn Interpreter::exec_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let program = match parse(source) {
    Ok(value) => value
    Err(err) =>
      return Err(RuntimeError::{
        kind: RuntimeErrorKind::Runtime,
        message: format_parse_error(err),
        span: None,
      })
  }
  self.exec(program)
}

///|
pub fn Interpreter::eval(
  self : Interpreter,
  expr : Expr,
) -> Result[Value, RuntimeError] {
  eval_expr_with_env(expr, [], self.globals, self.builtins, self.io)
}

///|
pub fn Interpreter::get_global(self : Interpreter, name : String) -> Value? {
  for pair in self.globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
pub fn Interpreter::set_global(
  self : Interpreter,
  name : String,
  value : Value,
) -> Unit {
  set_global_value(self.globals, name, value)
}

///|
pub fn format_parse_error(error : ParseError) -> String {
  "line " +
  error.span.line.to_string() +
  ":" +
  error.span.column.to_string() +
  " " +
  error.message
}

///|
pub fn format_runtime_error(error : RuntimeError) -> String {
  match error.kind {
    RuntimeErrorKind::ZeroDivision => "ZeroDivisionError: " + error.message
    RuntimeErrorKind::Name => "NameError: " + error.message
    RuntimeErrorKind::Type => "TypeError: " + error.message
    RuntimeErrorKind::Attribute => "AttributeError: " + error.message
    RuntimeErrorKind::Index => "IndexError: " + error.message
    RuntimeErrorKind::Key => "KeyError: " + error.message
    RuntimeErrorKind::NotImplemented => "NotImplementedError: " + error.message
    RuntimeErrorKind::Runtime => error.message
  }
}
