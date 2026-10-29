///|
// Direct expression children, without assigning lexical-scope meaning to them.
// Scope-sensitive validators handle lambda/comprehension boundaries themselves.
fn expression_children(expr : Expr) -> Array[Expr] {
  let out : Array[Expr] = []
  match expr {
    Expr::Literal(_) | Expr::Name(_) => ()
    Expr::FString(text) => out.append(fstring_expression_children(text))
    Expr::WithSpan(expr~, ..)
    | Expr::NamedExpr(value=expr, ..)
    | Expr::YieldFrom(expr)
    | Expr::Await(expr)
    | Expr::Unary(expr~, ..)
    | Expr::Attribute(value=expr, ..)
    | Expr::Keyword(value=expr, ..)
    | Expr::Starred(value=expr)
    | Expr::DoubleStarred(value=expr) => out.push(expr)
    Expr::Yield(expr) => if expr is Some(expr) { out.push(expr) }
    Expr::Tuple(items)
    | Expr::List(items)
    | Expr::Set(items)
    | Expr::BoolOp(values=items, ..) => out.append(items)
    Expr::Dict(items) =>
      for item in items {
        out.push(item.0)
        out.push(item.1)
      }
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~) => {
      out.push(elt)
      for clause in clauses {
        out.push(clause.iter)
        out.append(target_expressions(clause.target))
      }
      out.append(filters)
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      out.push(key)
      out.push(value)
      for clause in clauses {
        out.push(clause.iter)
        out.append(target_expressions(clause.target))
      }
      out.append(filters)
    }
    Expr::Lambda(defaults~, body~, ..) => {
      out.append(defaults)
      out.push(body)
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      out.push(condition)
      out.push(then_expr)
      out.push(else_expr)
    }
    Expr::Slice(start~, end~, step~) =>
      for expr in [start, end, step] {
        if expr is Some(expr) {
          out.push(expr)
        }
      }
    Expr::Subscript(value~, index~) => {
      out.push(value)
      out.push(index)
    }
    Expr::Call(callee~, args~) => {
      out.push(callee)
      out.append(args)
    }
    Expr::Binary(left~, right~, ..) => {
      out.push(left)
      out.push(right)
    }
    Expr::Compare(left~, comparators~, ..) => {
      out.push(left)
      out.append(comparators)
    }
  }
  out
}

///|
fn target_expressions(target : Target) -> Array[Expr] {
  match target {
    Target::Name(_) => []
    Target::Attribute(value~, ..) => [value]
    Target::Subscript(value~, index~) => [value, index]
    Target::Starred(target) => target_expressions(target)
    Target::Tuple(items) | Target::List(items) => {
      let out : Array[Expr] = []
      for item in items {
        out.append(target_expressions(item))
      }
      out
    }
  }
}

///|
// F-strings retain their source in the AST. Traverse replacement expressions and
// nested format fields using the same scanners as evaluation.
fn fstring_expression_children(text : String) -> Array[Expr] {
  let out : Array[Expr] = []
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    if (chars[i] == '{' || chars[i] == '}') &&
      i + 1 < chars.length() &&
      chars[i + 1] == chars[i] {
      i += 2
      continue
    }
    if chars[i] != '{' {
      i += 1
      continue
    }
    let close = match
      find_fstring_expr_close(substring(text, i + 1, text.length())) {
      Some(close) => i + 1 + close
      None => break
    }
    let inner = substring(text, i + 1, close)
    let (expr_and_conv, format) = match find_top_level_format_colon(inner) {
      Some(pos) =>
        (
          substring(inner, 0, pos),
          Some(substring(inner, pos + 1, inner.length())),
        )
      None => (inner, None)
    }
    let raw = match find_top_level_fstring_conversion_bang(expr_and_conv) {
      Some(pos) => substring(expr_and_conv, 0, pos)
      None => expr_and_conv
    }
    let expression = match find_top_level_fstring_debug_equal(raw) {
      Some(pos) => substring(raw, 0, pos)
      None => raw
    }
    if parse_expr(expression.trim(chars=" \t").to_owned()) is Ok(expr) {
      out.push(expr)
    }
    if format is Some(format) {
      out.append(fstring_expression_children(format))
    }
    i = close + 1
  }
  out
}
