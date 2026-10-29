///|
fn pattern_syntax_error(line_index : Int32, base_offset : Int32) -> ParseError {
  make_parse_error(ParseErrorKind::Syntax, "invalid syntax", {
    kind: Eof,
    start: base_offset,
    end: base_offset + 1,
    line: line_index + 1,
    column: 1,
  })
}

///|
// A pattern may bind each name only once, including nested sequence patterns.
fn pattern_bindings_unique(pattern : Pattern, names : Set[String]) -> Bool {
  match pattern {
    Pattern::Name(name) | Pattern::TypeCapture(name~, ..) => {
      if name == "_" {
        return true
      }
      if names.contains(name) {
        return false
      }
      names.add(name)
      true
    }
    Pattern::Tuple(items) => {
      for item in items {
        if !pattern_bindings_unique(item, names) {
          return false
        }
      }
      true
    }
    Pattern::Wildcard | Pattern::Literal(_) => true
  }
}

///|
fn pattern_is_irrefutable(pattern : Pattern) -> Bool {
  match pattern {
    Pattern::Name(_) | Pattern::Wildcard => true
    _ => false
  }
}

///|
fn pattern_literal(expr : Expr) -> Literal? {
  match expr {
    Expr::WithSpan(expr~, ..) => pattern_literal(expr)
    Expr::Literal(value) => Some(value)
    Expr::Unary(op=UnaryOp::Neg, expr=operand) =>
      match pattern_literal(operand) {
        Some(Literal::Int(value)) => Some(Literal::Int(-value))
        Some(Literal::Float(value)) => Some(Literal::Float(-value))
        Some(Literal::Complex(real, imag)) =>
          Some(Literal::Complex(-real, -imag))
        _ => None
      }
    _ => None
  }
}
