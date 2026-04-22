///|
/// Expression tree analysis helpers.

///|
fn expr_has_await(expr : Expr) -> Bool {
  match expr {
    Expr::Await(_) => true
    Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) => {
      let mut found = false
      for item in items {
        if expr_has_await(item) {
          found = true
          break
        }
      }
      found
    }
    Expr::Dict(items) => {
      let mut found = false
      for pair in items {
        if expr_has_await(pair.0) || expr_has_await(pair.1) {
          found = true
          break
        }
      }
      found
    }
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      let mut found = expr_has_await(elt)
      if !found {
        for clause in clauses {
          if expr_has_await(clause.iter) {
            found = true
            break
          }
        }
      }
      if !found {
        for filter in filters {
          if expr_has_await(filter) {
            found = true
            break
          }
        }
      }
      found
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let mut found = expr_has_await(key) || expr_has_await(value)
      if !found {
        for clause in clauses {
          if expr_has_await(clause.iter) {
            found = true
            break
          }
        }
      }
      if !found {
        for filter in filters {
          if expr_has_await(filter) {
            found = true
            break
          }
        }
      }
      found
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_await(condition) ||
      expr_has_await(then_expr) ||
      expr_has_await(else_expr)
    Expr::NamedExpr(name~, value~) => {
      let _ = name
      expr_has_await(value)
    }
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) => expr_has_await(value)
        None => false
      }
    Expr::YieldFrom(value) => expr_has_await(value)
    Expr::Slice(start~, end~, step~) => {
      let mut found = false
      match start {
        Some(value) => found = expr_has_await(value)
        None => ()
      }
      if !found {
        match end {
          Some(value) => found = expr_has_await(value)
          None => ()
        }
      }
      if !found {
        match step {
          Some(value) => found = expr_has_await(value)
          None => ()
        }
      }
      found
    }
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_await(value)
    }
    Expr::Subscript(value~, index~) =>
      expr_has_await(value) || expr_has_await(index)
    Expr::Starred(value~) | Expr::DoubleStarred(value~) => expr_has_await(value)
    Expr::Unary(op~, expr~) => {
      let _ = op
      expr_has_await(expr)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      expr_has_await(left) || expr_has_await(right)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      let mut found = false
      for value in values {
        if expr_has_await(value) {
          found = true
          break
        }
      }
      found
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      let mut found = expr_has_await(left)
      if !found {
        for value in comparators {
          if expr_has_await(value) {
            found = true
            break
          }
        }
      }
      found
    }
    Expr::Call(callee~, args~) => {
      let mut found = expr_has_await(callee)
      if !found {
        for arg in args {
          if expr_has_await(arg) {
            found = true
            break
          }
        }
      }
      found
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      expr_has_await(value)
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
      let mut found = false
      for default_value in defaults {
        if expr_has_await(default_value) {
          found = true
          break
        }
      }
      if found {
        true
      } else {
        expr_has_await(body)
      }
    }
    Expr::WithSpan(span~, expr~) => {
      let _ = span
      expr_has_await(expr)
    }
    _ => false
  }
}
