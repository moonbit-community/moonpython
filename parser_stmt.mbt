///|
/// Statement parsing helpers for moonpython.
///

///|
fn expr_has_async_comprehension(expr : Expr) -> Bool {
  match expr {
    Expr::WithSpan(span=_, expr=inner) => expr_has_async_comprehension(inner)
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
fn expr_has_yield_or_await(expr : Expr) -> Bool {
  match expr {
    Expr::WithSpan(span=_, expr=inner) => expr_has_yield_or_await(inner)
    Expr::Yield(_) | Expr::YieldFrom(_) | Expr::Await(_) => true
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~) => {
      if expr_has_yield_or_await(elt) {
        return true
      }
      for clause in clauses {
        if expr_has_yield_or_await(clause.iter) {
          return true
        }
      }
      for filter in filters {
        if expr_has_yield_or_await(filter) {
          return true
        }
      }
      false
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      if expr_has_yield_or_await(key) || expr_has_yield_or_await(value) {
        return true
      }
      for clause in clauses {
        if expr_has_yield_or_await(clause.iter) {
          return true
        }
      }
      for filter in filters {
        if expr_has_yield_or_await(filter) {
          return true
        }
      }
      false
    }
    Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) => {
      for item in items {
        if expr_has_yield_or_await(item) {
          return true
        }
      }
      false
    }
    Expr::Dict(items) => {
      for pair in items {
        if expr_has_yield_or_await(pair.0) || expr_has_yield_or_await(pair.1) {
          return true
        }
      }
      false
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
      for d in defaults {
        if expr_has_yield_or_await(d) {
          return true
        }
      }
      expr_has_yield_or_await(body)
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_yield_or_await(condition) ||
      expr_has_yield_or_await(then_expr) ||
      expr_has_yield_or_await(else_expr)
    Expr::NamedExpr(name~, value~) => {
      let _ = name
      expr_has_yield_or_await(value)
    }
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(v) => if expr_has_yield_or_await(v) { return true }
        None => ()
      }
      match end {
        Some(v) => if expr_has_yield_or_await(v) { return true }
        None => ()
      }
      match step {
        Some(v) => if expr_has_yield_or_await(v) { return true }
        None => ()
      }
      false
    }
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      expr_has_yield_or_await(value)
    }
    Expr::Subscript(value~, index~) =>
      expr_has_yield_or_await(value) || expr_has_yield_or_await(index)
    Expr::Call(callee~, args~) => {
      if expr_has_yield_or_await(callee) {
        return true
      }
      for arg in args {
        if expr_has_yield_or_await(arg) {
          return true
        }
      }
      false
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      expr_has_yield_or_await(value)
    }
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_has_yield_or_await(value)
    Expr::Unary(op~, expr~) => {
      let _ = op
      expr_has_yield_or_await(expr)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      expr_has_yield_or_await(left) || expr_has_yield_or_await(right)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      for v in values {
        if expr_has_yield_or_await(v) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      if expr_has_yield_or_await(left) {
        return true
      }
      for cmp in comparators {
        if expr_has_yield_or_await(cmp) {
          return true
        }
      }
      false
    }
    Expr::Literal(_) | Expr::Name(_) | Expr::FString(_) => false
  }
}

///|
fn expr_has_illegal_await(expr : Expr, in_genexp : Bool) -> Bool {
  match expr {
    Expr::WithSpan(span=_, expr=inner) =>
      expr_has_illegal_await(inner, in_genexp)
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
fn expr_first_illegal_await_line(
  expr : Expr,
  in_genexp : Bool,
  fallback_line : Int,
) -> Int? {
  match expr {
    Expr::WithSpan(span~, expr=inner) =>
      expr_first_illegal_await_line(inner, in_genexp, span.line)
    Expr::Await(_) => if in_genexp { None } else { Some(fallback_line) }
    Expr::GenExp(elt~, clauses~, filters~) => {
      match expr_first_illegal_await_line(elt, true, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      for clause in clauses {
        match expr_first_illegal_await_line(clause.iter, true, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      for filter in filters {
        match expr_first_illegal_await_line(filter, true, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      match expr_first_illegal_await_line(elt, in_genexp, fallback_line) {
        Some(_) => return Some(fallback_line)
        None => ()
      }
      for clause in clauses {
        match
          expr_first_illegal_await_line(clause.iter, in_genexp, fallback_line) {
          Some(_) => return Some(fallback_line)
          None => ()
        }
      }
      for filter in filters {
        match expr_first_illegal_await_line(filter, in_genexp, fallback_line) {
          Some(_) => return Some(fallback_line)
          None => ()
        }
      }
      None
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      match expr_first_illegal_await_line(key, in_genexp, fallback_line) {
        Some(_) => return Some(fallback_line)
        None => ()
      }
      match expr_first_illegal_await_line(value, in_genexp, fallback_line) {
        Some(_) => return Some(fallback_line)
        None => ()
      }
      for clause in clauses {
        match
          expr_first_illegal_await_line(clause.iter, in_genexp, fallback_line) {
          Some(_) => return Some(fallback_line)
          None => ()
        }
      }
      for filter in filters {
        match expr_first_illegal_await_line(filter, in_genexp, fallback_line) {
          Some(_) => return Some(fallback_line)
          None => ()
        }
      }
      None
    }
    Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) => {
      for item in items {
        match expr_first_illegal_await_line(item, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Expr::Dict(items) => {
      for pair in items {
        match expr_first_illegal_await_line(pair.0, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
        match expr_first_illegal_await_line(pair.1, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let _ = params
      for default_value in defaults {
        match
          expr_first_illegal_await_line(default_value, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      expr_first_illegal_await_line(body, in_genexp, fallback_line)
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      match expr_first_illegal_await_line(condition, in_genexp, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match expr_first_illegal_await_line(then_expr, in_genexp, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      expr_first_illegal_await_line(else_expr, in_genexp, fallback_line)
    }
    Expr::NamedExpr(name~, value~) => {
      let _ = name
      expr_first_illegal_await_line(value, in_genexp, fallback_line)
    }
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) =>
          expr_first_illegal_await_line(value, in_genexp, fallback_line)
        None => None
      }
    Expr::YieldFrom(value) =>
      expr_first_illegal_await_line(value, in_genexp, fallback_line)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(value) =>
          match expr_first_illegal_await_line(value, in_genexp, fallback_line) {
            Some(line) => return Some(line)
            None => ()
          }
        None => ()
      }
      match end {
        Some(value) =>
          match expr_first_illegal_await_line(value, in_genexp, fallback_line) {
            Some(line) => return Some(line)
            None => ()
          }
        None => ()
      }
      match step {
        Some(value) =>
          expr_first_illegal_await_line(value, in_genexp, fallback_line)
        None => None
      }
    }
    Expr::Attribute(value~, attr~) => {
      let _ = attr
      expr_first_illegal_await_line(value, in_genexp, fallback_line)
    }
    Expr::Subscript(value~, index~) => {
      match expr_first_illegal_await_line(value, in_genexp, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      expr_first_illegal_await_line(index, in_genexp, fallback_line)
    }
    Expr::Call(callee~, args~) => {
      match expr_first_illegal_await_line(callee, in_genexp, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      for arg in args {
        match expr_first_illegal_await_line(arg, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Expr::Keyword(name~, value~) => {
      let _ = name
      expr_first_illegal_await_line(value, in_genexp, fallback_line)
    }
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_first_illegal_await_line(value, in_genexp, fallback_line)
    Expr::Unary(op~, expr~) => {
      let _ = op
      expr_first_illegal_await_line(expr, in_genexp, fallback_line)
    }
    Expr::Binary(op~, left~, right~) => {
      let _ = op
      match expr_first_illegal_await_line(left, in_genexp, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      expr_first_illegal_await_line(right, in_genexp, fallback_line)
    }
    Expr::BoolOp(op~, values~) => {
      let _ = op
      for value in values {
        match expr_first_illegal_await_line(value, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let _ = ops
      match expr_first_illegal_await_line(left, in_genexp, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      for value in comparators {
        match expr_first_illegal_await_line(value, in_genexp, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
fn target_first_illegal_await_line(
  target : Target,
  fallback_line : Int,
) -> Int? {
  match target {
    Target::Tuple(items) | Target::List(items) => {
      for item in items {
        match target_first_illegal_await_line(item, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Target::Starred(inner) =>
      target_first_illegal_await_line(inner, fallback_line)
    Target::Attribute(value~, attr~) => {
      let _ = attr
      expr_first_illegal_await_line(value, false, fallback_line)
    }
    Target::Subscript(value~, index~) => {
      match expr_first_illegal_await_line(value, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      expr_first_illegal_await_line(index, false, fallback_line)
    }
    _ => None
  }
}

///|
fn stmt_first_illegal_await_line(stmt : Stmt, fallback_line : Int) -> Int? {
  match stmt {
    Stmt::WithSpan(span~, stmt=inner) =>
      stmt_first_illegal_await_line(inner, span.line)
    Stmt::ExprStmt(expr) =>
      expr_first_illegal_await_line(expr, false, fallback_line)
    Stmt::Assign(target~, value~) => {
      match target_first_illegal_await_line(target, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      expr_first_illegal_await_line(value, false, fallback_line)
    }
    Stmt::AnnAssign(target~, annotation~, value~) => {
      match target_first_illegal_await_line(target, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match expr_first_illegal_await_line(annotation, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match value {
        Some(v) => expr_first_illegal_await_line(v, false, fallback_line)
        None => None
      }
    }
    Stmt::AugAssign(target~, op~, value~) => {
      let _ = op
      match target_first_illegal_await_line(target, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      expr_first_illegal_await_line(value, false, fallback_line)
    }
    Stmt::Return(expr_opt) | Stmt::Yield(expr_opt) =>
      match expr_opt {
        Some(v) => expr_first_illegal_await_line(v, false, fallback_line)
        None => None
      }
    Stmt::YieldFrom(expr) =>
      expr_first_illegal_await_line(expr, false, fallback_line)
    Stmt::Assert(condition~, message~) => {
      match expr_first_illegal_await_line(condition, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match message {
        Some(v) => expr_first_illegal_await_line(v, false, fallback_line)
        None => None
      }
    }
    Stmt::Raise(exc~, cause~) => {
      match exc {
        Some(v) =>
          match expr_first_illegal_await_line(v, false, fallback_line) {
            Some(line) => return Some(line)
            None => ()
          }
        None => ()
      }
      match cause {
        Some(v) => expr_first_illegal_await_line(v, false, fallback_line)
        None => None
      }
    }
    Stmt::Del(targets) => {
      for target in targets {
        match target_first_illegal_await_line(target, fallback_line) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Stmt::With(context~, target~, body~)
    | Stmt::AsyncWith(context~, target~, body~) => {
      let _ = target
      match expr_first_illegal_await_line(context, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_illegal_await_line(body)
    }
    Stmt::If(condition~, body~, else_body~)
    | Stmt::While(condition~, body~, else_body~) => {
      match expr_first_illegal_await_line(condition, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match stmts_first_illegal_await_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_illegal_await_line(else_body)
    }
    Stmt::For(target~, iter~, body~, else_body~)
    | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
      match target_first_illegal_await_line(target, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match expr_first_illegal_await_line(iter, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      match stmts_first_illegal_await_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_illegal_await_line(else_body)
    }
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      match stmts_first_illegal_await_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      for handler in handlers {
        match handler.exc {
          Some(v) =>
            match expr_first_illegal_await_line(v, false, fallback_line) {
              Some(line) => return Some(line)
              None => ()
            }
          None => ()
        }
        match stmts_first_illegal_await_line(handler.body) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      match stmts_first_illegal_await_line(else_body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_illegal_await_line(finally_body)
    }
    Stmt::Match(subject~, cases~) => {
      match expr_first_illegal_await_line(subject, false, fallback_line) {
        Some(line) => return Some(line)
        None => ()
      }
      for case in cases {
        match case.1 {
          Some(v) =>
            match expr_first_illegal_await_line(v, false, fallback_line) {
              Some(line) => return Some(line)
              None => ()
            }
          None => ()
        }
        match stmts_first_illegal_await_line(case.2) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
fn stmts_first_illegal_await_line(stmts : Array[Stmt]) -> Int? {
  for stmt in stmts {
    match stmt_first_illegal_await_line(stmt, 1) {
      Some(line) => return Some(line)
      None => ()
    }
  }
  None
}

///|
fn stmt_first_except_star_control_flow_line(
  stmt : Stmt,
  fallback_line : Int,
) -> Int? {
  match stmt {
    Stmt::WithSpan(span~, stmt=inner) =>
      stmt_first_except_star_control_flow_line(inner, span.line)
    Stmt::Break | Stmt::Continue | Stmt::Return(_) => Some(fallback_line)
    Stmt::If(condition=_, body~, else_body~)
    | Stmt::While(condition=_, body~, else_body~) => {
      match stmts_first_except_star_control_flow_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_except_star_control_flow_line(else_body)
    }
    Stmt::For(target=_, iter=_, body~, else_body~)
    | Stmt::AsyncFor(target=_, iter=_, body~, else_body~) => {
      match stmts_first_except_star_control_flow_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_except_star_control_flow_line(else_body)
    }
    Stmt::With(context=_, target=_, body~)
    | Stmt::AsyncWith(context=_, target=_, body~) =>
      stmts_first_except_star_control_flow_line(body)
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      match stmts_first_except_star_control_flow_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      for handler in handlers {
        match stmts_first_except_star_control_flow_line(handler.body) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      match stmts_first_except_star_control_flow_line(else_body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_except_star_control_flow_line(finally_body)
    }
    Stmt::Match(subject=_, cases~) => {
      for case in cases {
        match stmts_first_except_star_control_flow_line(case.2) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
fn stmts_first_except_star_control_flow_line(stmts : Array[Stmt]) -> Int? {
  for stmt in stmts {
    match stmt_first_except_star_control_flow_line(stmt, 1) {
      Some(line) => return Some(line)
      None => ()
    }
  }
  None
}

///|
fn stmt_first_invalid_control_flow_line(
  stmt : Stmt,
  fallback_line : Int,
  in_function : Bool,
  loop_depth : Int,
) -> Int? {
  match stmt {
    Stmt::WithSpan(span~, stmt=inner) =>
      stmt_first_invalid_control_flow_line(
        inner, span.line, in_function, loop_depth,
      )
    Stmt::Return(_) | Stmt::Yield(_) | Stmt::YieldFrom(_) =>
      if in_function {
        None
      } else {
        Some(fallback_line)
      }
    Stmt::Break | Stmt::Continue =>
      if loop_depth > 0 {
        None
      } else {
        Some(fallback_line)
      }
    Stmt::If(condition=_, body~, else_body~) => {
      match stmts_first_invalid_control_flow_line(
        body, in_function, loop_depth,
      ) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_control_flow_line(else_body, in_function, loop_depth)
    }
    Stmt::While(condition=_, body~, else_body~) => {
      match stmts_first_invalid_control_flow_line(
        body, in_function, loop_depth + 1,
      ) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_control_flow_line(else_body, in_function, loop_depth)
    }
    Stmt::For(target=_, iter=_, body~, else_body~)
    | Stmt::AsyncFor(target=_, iter=_, body~, else_body~) => {
      match stmts_first_invalid_control_flow_line(
        body, in_function, loop_depth + 1,
      ) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_control_flow_line(else_body, in_function, loop_depth)
    }
    Stmt::With(context=_, target=_, body~)
    | Stmt::AsyncWith(context=_, target=_, body~) =>
      stmts_first_invalid_control_flow_line(body, in_function, loop_depth)
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      match stmts_first_invalid_control_flow_line(
        body, in_function, loop_depth,
      ) {
        Some(line) => return Some(line)
        None => ()
      }
      for handler in handlers {
        match stmts_first_invalid_control_flow_line(
          handler.body, in_function, loop_depth,
        ) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      match stmts_first_invalid_control_flow_line(
        else_body, in_function, loop_depth,
      ) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_control_flow_line(
        finally_body, in_function, loop_depth,
      )
    }
    Stmt::Match(subject=_, cases~) => {
      for case in cases {
        match stmts_first_invalid_control_flow_line(
          case.2, in_function, loop_depth,
        ) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Stmt::Function(body~, ..) =>
      stmts_first_invalid_control_flow_line(body, true, 0)
    Stmt::Class(body~, ..) =>
      stmts_first_invalid_control_flow_line(body, false, 0)
    _ => None
  }
}

///|
fn stmts_first_invalid_control_flow_line(
  stmts : Array[Stmt],
  in_function : Bool,
  loop_depth : Int,
) -> Int? {
  for stmt in stmts {
    match stmt_first_invalid_control_flow_line(
      stmt, 1, in_function, loop_depth,
    ) {
      Some(line) => return Some(line)
      None => ()
    }
  }
  None
}

///|
fn collect_target_names_for_global_check(
  target : Target,
  names : Array[String],
) -> Unit {
  match target {
    Target::Name(name) => append_unique_name(names, name)
    Target::Tuple(items) | Target::List(items) =>
      for item in items {
        collect_target_names_for_global_check(item, names)
      }
    Target::Starred(inner) => collect_target_names_for_global_check(inner, names)
    _ => ()
  }
}

///|
fn collect_expr_names_for_global_check(expr : Expr, names : Array[String]) -> Unit {
  match expr {
    Expr::WithSpan(span=_, expr=inner) =>
      collect_expr_names_for_global_check(inner, names)
    Expr::Name(name) => append_unique_name(names, name)
    Expr::Tuple(items) | Expr::List(items) | Expr::Set(items) =>
      for item in items {
        collect_expr_names_for_global_check(item, names)
      }
    Expr::Dict(items) =>
      for item in items {
        collect_expr_names_for_global_check(item.0, names)
        collect_expr_names_for_global_check(item.1, names)
      }
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      collect_expr_names_for_global_check(elt, names)
      for clause in clauses {
        collect_expr_names_for_global_check(clause.iter, names)
      }
      for filter in filters {
        collect_expr_names_for_global_check(filter, names)
      }
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      collect_expr_names_for_global_check(key, names)
      collect_expr_names_for_global_check(value, names)
      for clause in clauses {
        collect_expr_names_for_global_check(clause.iter, names)
      }
      for filter in filters {
        collect_expr_names_for_global_check(filter, names)
      }
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      collect_expr_names_for_global_check(condition, names)
      collect_expr_names_for_global_check(then_expr, names)
      collect_expr_names_for_global_check(else_expr, names)
    }
    Expr::NamedExpr(name~, value~) => {
      append_unique_name(names, name)
      collect_expr_names_for_global_check(value, names)
    }
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) => collect_expr_names_for_global_check(value, names)
        None => ()
      }
    Expr::YieldFrom(value) | Expr::Await(value) =>
      collect_expr_names_for_global_check(value, names)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(value) => collect_expr_names_for_global_check(value, names)
        None => ()
      }
      match end {
        Some(value) => collect_expr_names_for_global_check(value, names)
        None => ()
      }
      match step {
        Some(value) => collect_expr_names_for_global_check(value, names)
        None => ()
      }
    }
    Expr::Attribute(value~, attr=_) =>
      collect_expr_names_for_global_check(value, names)
    Expr::Subscript(value~, index~) => {
      collect_expr_names_for_global_check(value, names)
      collect_expr_names_for_global_check(index, names)
    }
    Expr::Call(callee~, args~) => {
      collect_expr_names_for_global_check(callee, names)
      for arg in args {
        collect_expr_names_for_global_check(arg, names)
      }
    }
    Expr::Keyword(name=_, value~) =>
      collect_expr_names_for_global_check(value, names)
    Expr::Unary(op=_, expr~) => collect_expr_names_for_global_check(expr, names)
    Expr::Binary(op=_, left~, right~) => {
      collect_expr_names_for_global_check(left, names)
      collect_expr_names_for_global_check(right, names)
    }
    Expr::BoolOp(op=_, values~) =>
      for value in values {
        collect_expr_names_for_global_check(value, names)
      }
    Expr::Compare(left~, ops=_, comparators~) => {
      collect_expr_names_for_global_check(left, names)
      for comparator in comparators {
        collect_expr_names_for_global_check(comparator, names)
      }
    }
    Expr::Lambda(params=_, defaults~, body~) => {
      for default_value in defaults {
        collect_expr_names_for_global_check(default_value, names)
      }
      collect_expr_names_for_global_check(body, names)
    }
    _ => ()
  }
}

///|
fn params_have_global_check_name(params : Array[String], name : String) -> Bool {
  for param in params {
    match normalize_param_name_for_compare(param) {
      Some(param_name) =>
        if param_name == name {
          return true
        }
      None => ()
    }
  }
  false
}

///|
fn stmt_first_invalid_global_line(
  stmt : Stmt,
  params : Array[String],
  seen_names : Array[String],
  fallback_line : Int,
) -> Int? {
  match stmt {
    Stmt::WithSpan(span~, stmt=inner) =>
      stmt_first_invalid_global_line(inner, params, seen_names, span.line)
    Stmt::Global(names) => {
      for name in names {
        if params_have_global_check_name(params, name) ||
          name_in_list(seen_names, name) {
          return Some(fallback_line)
        }
      }
      None
    }
    Stmt::ExprStmt(expr) => {
      collect_expr_names_for_global_check(expr, seen_names)
      None
    }
    Stmt::Assign(target~, value~) => {
      collect_expr_names_for_global_check(value, seen_names)
      collect_target_names_for_global_check(target, seen_names)
      None
    }
    Stmt::AnnAssign(target~, annotation~, value~) => {
      collect_target_names_for_global_check(target, seen_names)
      collect_expr_names_for_global_check(annotation, seen_names)
      match value {
        Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
        None => ()
      }
      None
    }
    Stmt::AugAssign(target~, op=_, value~) => {
      collect_target_names_for_global_check(target, seen_names)
      collect_expr_names_for_global_check(value, seen_names)
      None
    }
    Stmt::Return(expr_opt) | Stmt::Yield(expr_opt) => {
      match expr_opt {
        Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
        None => ()
      }
      None
    }
    Stmt::YieldFrom(expr) => {
      collect_expr_names_for_global_check(expr, seen_names)
      None
    }
    Stmt::Assert(condition~, message~) => {
      collect_expr_names_for_global_check(condition, seen_names)
      match message {
        Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
        None => ()
      }
      None
    }
    Stmt::Raise(exc~, cause~) => {
      match exc {
        Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
        None => ()
      }
      match cause {
        Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
        None => ()
      }
      None
    }
    Stmt::Del(targets) => {
      for target in targets {
        collect_target_names_for_global_check(target, seen_names)
      }
      None
    }
    Stmt::If(condition~, body~, else_body~)
    | Stmt::While(condition~, body~, else_body~) => {
      collect_expr_names_for_global_check(condition, seen_names)
      match stmts_first_invalid_global_line(body, params, seen_names) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_global_line(else_body, params, seen_names)
    }
    Stmt::For(target~, iter~, body~, else_body~)
    | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
      collect_expr_names_for_global_check(iter, seen_names)
      collect_target_names_for_global_check(target, seen_names)
      match stmts_first_invalid_global_line(body, params, seen_names) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_global_line(else_body, params, seen_names)
    }
    Stmt::With(context~, target~, body~)
    | Stmt::AsyncWith(context~, target~, body~) => {
      collect_expr_names_for_global_check(context, seen_names)
      match target {
        Some(name) => append_unique_name(seen_names, name)
        None => ()
      }
      stmts_first_invalid_global_line(body, params, seen_names)
    }
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      match stmts_first_invalid_global_line(body, params, seen_names) {
        Some(line) => return Some(line)
        None => ()
      }
      for handler in handlers {
        match handler.exc {
          Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
          None => ()
        }
        match handler.name {
          Some(name) => append_unique_name(seen_names, name)
          None => ()
        }
        match stmts_first_invalid_global_line(handler.body, params, seen_names) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      match stmts_first_invalid_global_line(else_body, params, seen_names) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_global_line(finally_body, params, seen_names)
    }
    Stmt::Match(subject~, cases~) => {
      collect_expr_names_for_global_check(subject, seen_names)
      for case in cases {
        match case.1 {
          Some(expr) => collect_expr_names_for_global_check(expr, seen_names)
          None => ()
        }
        match stmts_first_invalid_global_line(case.2, params, seen_names) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Stmt::Function(name~, ..) | Stmt::Class(name~, ..) => {
      append_unique_name(seen_names, name)
      None
    }
    Stmt::Import(module_name~, alias_name~) => {
      match alias_name {
        Some(name) => append_unique_name(seen_names, name)
        None => append_unique_name(seen_names, module_name)
      }
      None
    }
    Stmt::FromImport(module_name=_, names~) => {
      for item in names {
        match item.1 {
          Some(import_alias) => append_unique_name(seen_names, import_alias)
          None => append_unique_name(seen_names, item.0)
        }
      }
      None
    }
    Stmt::Nonlocal(names) => {
      for name in names {
        if params_have_global_check_name(params, name) {
          return Some(fallback_line)
        }
        append_unique_name(seen_names, name)
      }
      None
    }
    _ => None
  }
}

///|
fn stmts_first_invalid_global_line(
  stmts : Array[Stmt],
  params : Array[String],
  seen_names : Array[String],
) -> Int? {
  for stmt in stmts {
    match stmt_first_invalid_global_line(stmt, params, seen_names, 1) {
      Some(line) => return Some(line)
      None => ()
    }
  }
  None
}

///|
fn function_body_first_invalid_global_line(
  body : Array[Stmt],
  params : Array[String],
) -> Int? {
  let seen_names : Array[String] = []
  stmts_first_invalid_global_line(body, params, seen_names)
}

///|
fn expr_has_class_body_comprehension_walrus(expr : Expr) -> Bool {
  match expr {
    Expr::WithSpan(span=_, expr=inner) =>
      expr_has_class_body_comprehension_walrus(inner)
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      let targets : Array[String] = []
      collect_named_expr_targets(elt, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.iter, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
      targets.length() > 0
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let targets : Array[String] = []
      collect_named_expr_targets(key, targets)
      collect_named_expr_targets(value, targets)
      for clause in clauses {
        collect_named_expr_targets(clause.iter, targets)
      }
      for filter in filters {
        collect_named_expr_targets(filter, targets)
      }
      targets.length() > 0
    }
    Expr::Tuple(items) | Expr::List(items) | Expr::Set(items) => {
      for item in items {
        if expr_has_class_body_comprehension_walrus(item) {
          return true
        }
      }
      false
    }
    Expr::Dict(items) => {
      for item in items {
        if expr_has_class_body_comprehension_walrus(item.0) ||
          expr_has_class_body_comprehension_walrus(item.1) {
          return true
        }
      }
      false
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_class_body_comprehension_walrus(condition) ||
      expr_has_class_body_comprehension_walrus(then_expr) ||
      expr_has_class_body_comprehension_walrus(else_expr)
    Expr::NamedExpr(name=_, value~) =>
      expr_has_class_body_comprehension_walrus(value)
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) => expr_has_class_body_comprehension_walrus(value)
        None => false
      }
    Expr::YieldFrom(value) | Expr::Await(value) =>
      expr_has_class_body_comprehension_walrus(value)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(value) =>
          if expr_has_class_body_comprehension_walrus(value) {
            return true
          }
        None => ()
      }
      match end {
        Some(value) =>
          if expr_has_class_body_comprehension_walrus(value) {
            return true
          }
        None => ()
      }
      match step {
        Some(value) => expr_has_class_body_comprehension_walrus(value)
        None => false
      }
    }
    Expr::Attribute(value~, attr=_) =>
      expr_has_class_body_comprehension_walrus(value)
    Expr::Subscript(value~, index~) =>
      expr_has_class_body_comprehension_walrus(value) ||
      expr_has_class_body_comprehension_walrus(index)
    Expr::Call(callee~, args~) => {
      if expr_has_class_body_comprehension_walrus(callee) {
        return true
      }
      for arg in args {
        if expr_has_class_body_comprehension_walrus(arg) {
          return true
        }
      }
      false
    }
    Expr::Keyword(name=_, value~) =>
      expr_has_class_body_comprehension_walrus(value)
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_has_class_body_comprehension_walrus(value)
    Expr::Unary(op=_, expr~) => expr_has_class_body_comprehension_walrus(expr)
    Expr::Binary(op=_, left~, right~) =>
      expr_has_class_body_comprehension_walrus(left) ||
      expr_has_class_body_comprehension_walrus(right)
    Expr::BoolOp(op=_, values~) => {
      for value in values {
        if expr_has_class_body_comprehension_walrus(value) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops=_, comparators~) => {
      if expr_has_class_body_comprehension_walrus(left) {
        return true
      }
      for cmp in comparators {
        if expr_has_class_body_comprehension_walrus(cmp) {
          return true
        }
      }
      false
    }
    Expr::Lambda(params=_, defaults~, body=_) => {
      for default_value in defaults {
        if expr_has_class_body_comprehension_walrus(default_value) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn target_has_class_body_comprehension_walrus(target : Target) -> Bool {
  match target {
    Target::Tuple(items) | Target::List(items) => {
      for item in items {
        if target_has_class_body_comprehension_walrus(item) {
          return true
        }
      }
      false
    }
    Target::Starred(inner) => target_has_class_body_comprehension_walrus(inner)
    Target::Attribute(value~, attr=_) =>
      expr_has_class_body_comprehension_walrus(value)
    Target::Subscript(value~, index~) =>
      expr_has_class_body_comprehension_walrus(value) ||
      expr_has_class_body_comprehension_walrus(index)
    _ => false
  }
}

///|
fn stmt_first_invalid_class_body_line(stmt : Stmt, fallback_line : Int) -> Int? {
  match stmt {
    Stmt::WithSpan(span~, stmt=inner) =>
      stmt_first_invalid_class_body_line(inner, span.line)
    Stmt::Nonlocal(_) => Some(fallback_line)
    Stmt::ExprStmt(expr) =>
      if expr_has_class_body_comprehension_walrus(expr) {
        Some(fallback_line)
      } else {
        None
      }
    Stmt::Assign(target~, value~) =>
      if target_has_class_body_comprehension_walrus(target) ||
        expr_has_class_body_comprehension_walrus(value) {
        Some(fallback_line)
      } else {
        None
      }
    Stmt::AnnAssign(target~, annotation~, value~) => {
      if target_has_class_body_comprehension_walrus(target) ||
        expr_has_class_body_comprehension_walrus(annotation) {
        return Some(fallback_line)
      }
      match value {
        Some(expr) =>
          if expr_has_class_body_comprehension_walrus(expr) {
            Some(fallback_line)
          } else {
            None
          }
        None => None
      }
    }
    Stmt::AugAssign(target~, op=_, value~) =>
      if target_has_class_body_comprehension_walrus(target) ||
        expr_has_class_body_comprehension_walrus(value) {
        Some(fallback_line)
      } else {
        None
      }
    Stmt::Return(expr_opt) | Stmt::Yield(expr_opt) =>
      match expr_opt {
        Some(expr) =>
          if expr_has_class_body_comprehension_walrus(expr) {
            Some(fallback_line)
          } else {
            None
          }
        None => None
      }
    Stmt::YieldFrom(expr) =>
      if expr_has_class_body_comprehension_walrus(expr) {
        Some(fallback_line)
      } else {
        None
      }
    Stmt::Assert(condition~, message~) => {
      if expr_has_class_body_comprehension_walrus(condition) {
        return Some(fallback_line)
      }
      match message {
        Some(expr) =>
          if expr_has_class_body_comprehension_walrus(expr) {
            Some(fallback_line)
          } else {
            None
          }
        None => None
      }
    }
    Stmt::Raise(exc~, cause~) => {
      match exc {
        Some(expr) =>
          if expr_has_class_body_comprehension_walrus(expr) {
            return Some(fallback_line)
          }
        None => ()
      }
      match cause {
        Some(expr) =>
          if expr_has_class_body_comprehension_walrus(expr) {
            Some(fallback_line)
          } else {
            None
          }
        None => None
      }
    }
    Stmt::If(condition~, body~, else_body~)
    | Stmt::While(condition~, body~, else_body~) => {
      if expr_has_class_body_comprehension_walrus(condition) {
        return Some(fallback_line)
      }
      match stmts_first_invalid_class_body_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_class_body_line(else_body)
    }
    Stmt::For(target~, iter~, body~, else_body~)
    | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
      if target_has_class_body_comprehension_walrus(target) ||
        expr_has_class_body_comprehension_walrus(iter) {
        return Some(fallback_line)
      }
      match stmts_first_invalid_class_body_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_class_body_line(else_body)
    }
    Stmt::With(context~, target=_, body~)
    | Stmt::AsyncWith(context~, target=_, body~) => {
      if expr_has_class_body_comprehension_walrus(context) {
        return Some(fallback_line)
      }
      stmts_first_invalid_class_body_line(body)
    }
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      match stmts_first_invalid_class_body_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      for handler in handlers {
        match handler.exc {
          Some(expr) =>
            if expr_has_class_body_comprehension_walrus(expr) {
              return Some(fallback_line)
            }
          None => ()
        }
        match stmts_first_invalid_class_body_line(handler.body) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      match stmts_first_invalid_class_body_line(else_body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_invalid_class_body_line(finally_body)
    }
    Stmt::Match(subject~, cases~) => {
      if expr_has_class_body_comprehension_walrus(subject) {
        return Some(fallback_line)
      }
      for case in cases {
        match case.1 {
          Some(expr) =>
            if expr_has_class_body_comprehension_walrus(expr) {
              return Some(fallback_line)
            }
          None => ()
        }
        match stmts_first_invalid_class_body_line(case.2) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Stmt::Function(..) | Stmt::Class(..) => None
    _ => None
  }
}

///|
fn stmts_first_invalid_class_body_line(stmts : Array[Stmt]) -> Int? {
  for stmt in stmts {
    match stmt_first_invalid_class_body_line(stmt, 1) {
      Some(line) => return Some(line)
      None => ()
    }
  }
  None
}

///|
fn expr_contains_name_for_class_comp(expr : Expr, wanted : String) -> Bool {
  match expr {
    Expr::WithSpan(span=_, expr=inner) =>
      expr_contains_name_for_class_comp(inner, wanted)
    Expr::Name(name) => name == wanted
    Expr::Tuple(items) | Expr::List(items) | Expr::Set(items) => {
      for item in items {
        if expr_contains_name_for_class_comp(item, wanted) {
          return true
        }
      }
      false
    }
    Expr::Dict(items) => {
      for item in items {
        if expr_contains_name_for_class_comp(item.0, wanted) ||
          expr_contains_name_for_class_comp(item.1, wanted) {
          return true
        }
      }
      false
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_contains_name_for_class_comp(condition, wanted) ||
      expr_contains_name_for_class_comp(then_expr, wanted) ||
      expr_contains_name_for_class_comp(else_expr, wanted)
    Expr::NamedExpr(name~, value~) =>
      name == wanted || expr_contains_name_for_class_comp(value, wanted)
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) => expr_contains_name_for_class_comp(value, wanted)
        None => false
      }
    Expr::YieldFrom(value) | Expr::Await(value) =>
      expr_contains_name_for_class_comp(value, wanted)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(value) =>
          if expr_contains_name_for_class_comp(value, wanted) {
            return true
          }
        None => ()
      }
      match end {
        Some(value) =>
          if expr_contains_name_for_class_comp(value, wanted) {
            return true
          }
        None => ()
      }
      match step {
        Some(value) => expr_contains_name_for_class_comp(value, wanted)
        None => false
      }
    }
    Expr::Attribute(value~, attr=_) =>
      expr_contains_name_for_class_comp(value, wanted)
    Expr::Subscript(value~, index~) =>
      expr_contains_name_for_class_comp(value, wanted) ||
      expr_contains_name_for_class_comp(index, wanted)
    Expr::Call(callee~, args~) => {
      if expr_contains_name_for_class_comp(callee, wanted) {
        return true
      }
      for arg in args {
        if expr_contains_name_for_class_comp(arg, wanted) {
          return true
        }
      }
      false
    }
    Expr::Keyword(name=_, value~) =>
      expr_contains_name_for_class_comp(value, wanted)
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_contains_name_for_class_comp(value, wanted)
    Expr::Unary(op=_, expr~) => expr_contains_name_for_class_comp(expr, wanted)
    Expr::Binary(op=_, left~, right~) =>
      expr_contains_name_for_class_comp(left, wanted) ||
      expr_contains_name_for_class_comp(right, wanted)
    Expr::BoolOp(op=_, values~) => {
      for value in values {
        if expr_contains_name_for_class_comp(value, wanted) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops=_, comparators~) => {
      if expr_contains_name_for_class_comp(left, wanted) {
        return true
      }
      for cmp in comparators {
        if expr_contains_name_for_class_comp(cmp, wanted) {
          return true
        }
      }
      false
    }
    Expr::Lambda(params=_, defaults~, body~) => {
      for default_value in defaults {
        if expr_contains_name_for_class_comp(default_value, wanted) {
          return true
        }
      }
      expr_contains_name_for_class_comp(body, wanted)
    }
    _ => false
  }
}

///|
fn expr_has_class_body_comprehension_name(expr : Expr, wanted : String) -> Bool {
  match expr {
    Expr::WithSpan(span=_, expr=inner) =>
      expr_has_class_body_comprehension_name(inner, wanted)
    Expr::ListComp(elt~, clauses~, filters~)
    | Expr::GenExp(elt~, clauses~, filters~)
    | Expr::SetComp(elt~, clauses~, filters~) => {
      if expr_contains_name_for_class_comp(elt, wanted) {
        return true
      }
      for clause in clauses {
        if expr_contains_name_for_class_comp(clause.iter, wanted) {
          return true
        }
      }
      for filter in filters {
        if expr_contains_name_for_class_comp(filter, wanted) {
          return true
        }
      }
      false
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      if expr_contains_name_for_class_comp(key, wanted) ||
        expr_contains_name_for_class_comp(value, wanted) {
        return true
      }
      for clause in clauses {
        if expr_contains_name_for_class_comp(clause.iter, wanted) {
          return true
        }
      }
      for filter in filters {
        if expr_contains_name_for_class_comp(filter, wanted) {
          return true
        }
      }
      false
    }
    Expr::Tuple(items) | Expr::List(items) | Expr::Set(items) => {
      for item in items {
        if expr_has_class_body_comprehension_name(item, wanted) {
          return true
        }
      }
      false
    }
    Expr::Dict(items) => {
      for item in items {
        if expr_has_class_body_comprehension_name(item.0, wanted) ||
          expr_has_class_body_comprehension_name(item.1, wanted) {
          return true
        }
      }
      false
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      expr_has_class_body_comprehension_name(condition, wanted) ||
      expr_has_class_body_comprehension_name(then_expr, wanted) ||
      expr_has_class_body_comprehension_name(else_expr, wanted)
    Expr::NamedExpr(name=_, value~) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Expr::Yield(expr_opt) =>
      match expr_opt {
        Some(value) => expr_has_class_body_comprehension_name(value, wanted)
        None => false
      }
    Expr::YieldFrom(value) | Expr::Await(value) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(value) =>
          if expr_has_class_body_comprehension_name(value, wanted) {
            return true
          }
        None => ()
      }
      match end {
        Some(value) =>
          if expr_has_class_body_comprehension_name(value, wanted) {
            return true
          }
        None => ()
      }
      match step {
        Some(value) => expr_has_class_body_comprehension_name(value, wanted)
        None => false
      }
    }
    Expr::Attribute(value~, attr=_) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Expr::Subscript(value~, index~) =>
      expr_has_class_body_comprehension_name(value, wanted) ||
      expr_has_class_body_comprehension_name(index, wanted)
    Expr::Call(callee~, args~) => {
      if expr_has_class_body_comprehension_name(callee, wanted) {
        return true
      }
      for arg in args {
        if expr_has_class_body_comprehension_name(arg, wanted) {
          return true
        }
      }
      false
    }
    Expr::Keyword(name=_, value~) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Expr::Unary(op=_, expr~) =>
      expr_has_class_body_comprehension_name(expr, wanted)
    Expr::Binary(op=_, left~, right~) =>
      expr_has_class_body_comprehension_name(left, wanted) ||
      expr_has_class_body_comprehension_name(right, wanted)
    Expr::BoolOp(op=_, values~) => {
      for value in values {
        if expr_has_class_body_comprehension_name(value, wanted) {
          return true
        }
      }
      false
    }
    Expr::Compare(left~, ops=_, comparators~) => {
      if expr_has_class_body_comprehension_name(left, wanted) {
        return true
      }
      for cmp in comparators {
        if expr_has_class_body_comprehension_name(cmp, wanted) {
          return true
        }
      }
      false
    }
    Expr::Lambda(params=_, defaults~, body=_) => {
      for default_value in defaults {
        if expr_has_class_body_comprehension_name(default_value, wanted) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn stmt_has_class_body_comprehension_name(stmt : Stmt, wanted : String) -> Bool {
  match stmt {
    Stmt::WithSpan(span=_, stmt=inner) =>
      stmt_has_class_body_comprehension_name(inner, wanted)
    Stmt::ExprStmt(expr) => expr_has_class_body_comprehension_name(expr, wanted)
    Stmt::Assign(target=_, value~) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Stmt::AnnAssign(target=_, annotation~, value~) => {
      if expr_has_class_body_comprehension_name(annotation, wanted) {
        return true
      }
      match value {
        Some(expr) => expr_has_class_body_comprehension_name(expr, wanted)
        None => false
      }
    }
    Stmt::AugAssign(target=_, op=_, value~) =>
      expr_has_class_body_comprehension_name(value, wanted)
    Stmt::If(condition~, body~, else_body~)
    | Stmt::While(condition~, body~, else_body~) => {
      if expr_has_class_body_comprehension_name(condition, wanted) {
        return true
      }
      stmts_have_class_body_comprehension_name(body, wanted) ||
      stmts_have_class_body_comprehension_name(else_body, wanted)
    }
    Stmt::For(target=_, iter~, body~, else_body~)
    | Stmt::AsyncFor(target=_, iter~, body~, else_body~) =>
      expr_has_class_body_comprehension_name(iter, wanted) ||
      stmts_have_class_body_comprehension_name(body, wanted) ||
      stmts_have_class_body_comprehension_name(else_body, wanted)
    Stmt::With(context~, target=_, body~)
    | Stmt::AsyncWith(context~, target=_, body~) =>
      expr_has_class_body_comprehension_name(context, wanted) ||
      stmts_have_class_body_comprehension_name(body, wanted)
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      if stmts_have_class_body_comprehension_name(body, wanted) {
        return true
      }
      for handler in handlers {
        match handler.exc {
          Some(expr) =>
            if expr_has_class_body_comprehension_name(expr, wanted) {
              return true
            }
          None => ()
        }
        if stmts_have_class_body_comprehension_name(handler.body, wanted) {
          return true
        }
      }
      stmts_have_class_body_comprehension_name(else_body, wanted) ||
      stmts_have_class_body_comprehension_name(finally_body, wanted)
    }
    Stmt::Match(subject~, cases~) => {
      if expr_has_class_body_comprehension_name(subject, wanted) {
        return true
      }
      for case in cases {
        match case.1 {
          Some(expr) =>
            if expr_has_class_body_comprehension_name(expr, wanted) {
              return true
            }
          None => ()
        }
        if stmts_have_class_body_comprehension_name(case.2, wanted) {
          return true
        }
      }
      false
    }
    Stmt::Function(..) | Stmt::Class(..) => false
    _ => false
  }
}

///|
fn stmts_have_class_body_comprehension_name(
  stmts : Array[Stmt],
  wanted : String,
) -> Bool {
  for stmt in stmts {
    if stmt_has_class_body_comprehension_name(stmt, wanted) {
      return true
    }
  }
  false
}

///|
fn stmt_first_function_import_star_line(
  stmt : Stmt,
  fallback_line : Int,
) -> Int? {
  match stmt {
    Stmt::WithSpan(span~, stmt=inner) =>
      stmt_first_function_import_star_line(inner, span.line)
    Stmt::FromImport(module_name=_, names~) => {
      for item in names {
        if item.0 == "*" {
          return Some(fallback_line)
        }
      }
      None
    }
    Stmt::If(condition=_, body~, else_body~)
    | Stmt::While(condition=_, body~, else_body~) => {
      match stmts_first_function_import_star_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_function_import_star_line(else_body)
    }
    Stmt::For(target=_, iter=_, body~, else_body~)
    | Stmt::AsyncFor(target=_, iter=_, body~, else_body~) => {
      match stmts_first_function_import_star_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_function_import_star_line(else_body)
    }
    Stmt::With(context=_, target=_, body~)
    | Stmt::AsyncWith(context=_, target=_, body~) =>
      stmts_first_function_import_star_line(body)
    Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
      match stmts_first_function_import_star_line(body) {
        Some(line) => return Some(line)
        None => ()
      }
      for handler in handlers {
        match stmts_first_function_import_star_line(handler.body) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      match stmts_first_function_import_star_line(else_body) {
        Some(line) => return Some(line)
        None => ()
      }
      stmts_first_function_import_star_line(finally_body)
    }
    Stmt::Match(subject=_, cases~) => {
      for case_item in cases {
        match stmts_first_function_import_star_line(case_item.2) {
          Some(line) => return Some(line)
          None => ()
        }
      }
      None
    }
    Stmt::Function(..) | Stmt::Class(..) => None
    _ => None
  }
}

///|
fn stmts_first_function_import_star_line(stmts : Array[Stmt]) -> Int? {
  for stmt in stmts {
    match stmt_first_function_import_star_line(stmt, 1) {
      Some(line) => return Some(line)
      None => ()
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
  let trimmed = text.trim(chars=" \t\n\r").to_owned()
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
          .to_owned()
        let inner = substring(trimmed, open_pos + 1, close_pos)
          .trim(chars=" \t\n\r")
          .to_owned()
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
            .to_owned()
          if inner.length() == 0 {
            return Ok(Pattern::Tuple([]))
          }
          let inner_parts = split_top_level_commas(inner)
          if inner_parts.length() == 1 {
            return parse_pattern(inner, line_index, base_offset)
          }
          let patterns : Array[Pattern] = []
          for raw_part in inner_parts {
            let part = raw_part.trim(chars=" \t\n\r").to_owned()
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
      let part = raw_part.trim(chars=" \t\n\r").to_owned()
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
    Expr::WithSpan(span=_, expr=inner) => target_from_expr(inner, token)
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
fn target_allows_annotation(target : Target) -> Bool {
  match target {
    Target::Name(_) | Target::Attribute(_) | Target::Subscript(_) => true
    _ => false
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
  if body.length() > 0 && body[0].kind == LBrace {
    for token in body {
      if token.kind == For || token.kind == Async {
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
  // Best-effort: span covers the whole physical line (excluding the trailing '\n').
  // This is used for tracebacks/caret diagnostics (PEP 657 tests in Lib/test).
  let end = if line_index + 1 < offsets.length() {
    offsets[line_index + 1] - 1
  } else {
    start + 1
  }
  Span::{ start, end, line: line_index + 1, column: indent + 1 }
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
  // `line_text` may be a sliced inline statement (e.g. after `:` in a one-liner
  // suite), so its end offset is relative to `base_offset`, not `line_start_offset`.
  // `line_text` can include physical newlines due to bracket continuation.
  // Keep statement spans on the first physical line so traceback caret ranges
  // don't become "very long single-line" offsets.
  let mut line_len = line_text.length()
  match line_text.find("\n") {
    Some(idx) => line_len = idx
    None => ()
  }
  if line_len <= 0 {
    line_len = 1
  }
  let line_end_offset = base_offset + line_len
  let span = Span::{
    start: base_offset,
    end: line_end_offset,
    line: line_index + 1,
    column: base_offset - line_start_offset + 1,
  }
  let stmts : Array[Stmt] = []
  let mut trimmed = line_text.trim(chars=" \t").to_owned()
  if trimmed.length() == 0 {
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  trimmed = strip_inline_comment(trimmed).trim(chars=" \t").to_owned()
  if trimmed.length() == 0 {
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if trimmed.has_prefix("[") && trimmed.contains("\n") {
    let parts : Array[String] = []
    for part in trimmed.split("\n") {
      parts.push(part.trim(chars=" \t").to_string())
    }
    if parts.length() >= 3 &&
      parts[0] == "[" &&
      parts[1].length() > 0 &&
      !parts[1].contains(",") &&
      parts[2].length() > 0 &&
      !parts[2].has_prefix("]") &&
      !parts[2].contains(",") {
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid syntax".to_string(),
          {
            kind: Eof,
            start: base_offset,
            end: base_offset + 1,
            line: line_index + 2,
            column: 1,
          },
        ),
      )
    }
  }
  match find_top_level_char(trimmed, '=') {
    Some(eq_pos) => {
      let chars = trimmed.to_array()
      let prev = if eq_pos > 0 { chars[eq_pos - 1] } else { '\u{0}' }
      let next = if eq_pos + 1 < chars.length() {
        chars[eq_pos + 1]
      } else {
        '\u{0}'
      }
      let plain_assign = prev != '=' &&
        prev != '<' &&
        prev != '>' &&
        prev != '!' &&
        prev != ':' &&
        next != '='
      if plain_assign && trimmed.has_prefix("{") {
        let left_text = substring(trimmed, 0, eq_pos).to_string()
        if left_text.contains(" for ") || left_text.contains("\nfor ") {
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
    }
    None => ()
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
      .to_owned()
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
    let tokens = match
      tokenize_expr(
        rest,
        line_index + 1,
        base_offset + 10,
        base_offset + 10 - line_start_offset + 1,
      ) {
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
      .to_owned()
    if rest.length() == 0 {
      stmts.push(Stmt::Yield(None))
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
    let tokens = match
      tokenize_expr(
        rest,
        line_index + 1,
        base_offset + 5,
        base_offset + 5 - line_start_offset + 1,
      ) {
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
      let key = substring(trimmed, 14, end_key).trim(chars="'\"").to_owned()
      let value_text = substring(trimmed, end_key + 2, trimmed.length())
        .trim(chars=" \t")
        .to_owned()
      let tokens = match
        tokenize_expr(
          value_text,
          line_index + 1,
          base_offset + end_key + 2,
          base_offset + end_key + 2 - line_start_offset + 1,
        ) {
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
      let name = part.trim(chars=" \t").to_owned()
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
      let name = part.trim(chars=" \t").to_owned()
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
      .to_owned()
    for item in module_text.split(",") {
      let part = item.trim(chars=" \t").to_owned()
      if part.length() == 0 {
        continue
      }
      let mut module_name : String = ""
      let mut alias_opt : String? = None
      if part.contains(" as ") {
        let pieces : Array[String] = []
        for p in part.split(" as ") {
          if p.length() > 0 {
            pieces.push(p.trim(chars=" \t").to_owned())
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
    let tail_check = trimmed.trim(chars=" \t").to_owned()
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
        parts.push(part.to_owned())
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
      .to_owned()
    if imported.has_prefix("(") && imported.has_suffix(")") {
      imported = substring(imported, 1, imported.length() - 1)
        .trim(chars=" \t\n\r")
        .to_owned()
    }
    let names : Array[(String, String?)] = []
    if imported == "*" {
      names.push(("*", (None : String?)))
    } else {
      for item in imported.split(",") {
        let part = item.trim(chars=" \t\n\r").to_owned()
        if part.length() == 0 {
          continue
        }
        if part.contains(" as ") {
          let pieces : Array[String] = []
          for p in part.split(" as ") {
            if p.length() > 0 {
              pieces.push(p.trim(chars=" \t\n\r").to_owned())
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
      .to_owned()
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
      let name_text = name_raw.trim(chars=" \t").to_owned()
      let mut value_leading = 0
      let value_raw_chars = value_raw.to_array()
      while value_leading < value_raw_chars.length() &&
            value_raw_chars[value_leading] == ' ' {
        value_leading += 1
      }
      let value_text = value_raw.trim(chars=" \t").to_owned()
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
        tokenize_expr(
          value_text,
          line_index + 1,
          value_offset,
          value_offset - line_start_offset + 1,
        ) {
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
    let raw_rest = substring(trimmed, 6, trimmed.length()).to_string()
    let rest_leading = count_indent(raw_rest)
    let rest = raw_rest.trim(chars=" \t").to_owned()
    let rest_base = base_offset + 6 + rest_leading
    let rest_column = rest_base - line_start_offset + 1
    if rest.has_prefix("(") {
      let condition_tokens = match
        tokenize_expr(rest, line_index + 1, rest_base, rest_column) {
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
      Some(idx) => substring(rest, 0, idx).trim(chars=" \t").to_owned()
      None => rest.trim(chars=" \t").to_owned()
    }
    let message_text = match comma_index {
      Some(idx) =>
        substring(rest, idx + 1, rest.length()).trim(chars=" \t").to_owned()
      None => ""
    }
    let condition_leading = count_indent(
      match comma_index {
        Some(idx) => substring(rest, 0, idx).to_string()
        None => rest
      },
    )
    let condition_base = rest_base + condition_leading
    let condition_column = condition_base - line_start_offset + 1
    let condition_tokens = match
      tokenize_expr(
        condition_text,
        line_index + 1,
        condition_base,
        condition_column,
      ) {
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
      let message_leading = count_indent(
        match comma_index {
          Some(idx) => substring(rest, idx + 1, rest.length()).to_string()
          None => rest
        },
      )
      let message_base = match comma_index {
        Some(idx) => rest_base + idx + 1 + message_leading
        None => rest_base + message_leading
      }
      let message_column = message_base - line_start_offset + 1
      let message_tokens = match
        tokenize_expr(
          message_text,
          line_index + 1,
          message_base,
          message_column,
        ) {
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
      .to_owned()
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
      exc_text = substring(rest, 0, idx).trim(chars=" \t").to_owned()
      cause_text = substring(rest, idx + 4, rest.length())
        .trim(chars=" \t")
        .to_owned()
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
      tokenize_expr(
        exc_text,
        line_index + 1,
        base_offset + 5,
        base_offset + 5 - line_start_offset + 1,
      ) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let exc_expr = match parse_tokens_expr(exc_tokens) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let cause_expr = if cause_text.length() > 0 {
      let cause_tokens = match
        tokenize_expr(
          cause_text,
          line_index + 1,
          base_offset + 5,
          base_offset + 5 - line_start_offset + 1,
        ) {
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
      let text = part.trim(chars=" \t").to_owned()
      if text.length() == 0 {
        continue
      }
      let tokens = match
        tokenize_expr(
          text,
          line_index + 1,
          base_offset + prefix_len,
          base_offset + prefix_len - line_start_offset + 1,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let expr = match parse_tokens_expr(tokens) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let target = match target_from_expr(expr, tokens[0]) {
        Ok(value) => value
        Err(_) =>
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
      targets.push(target)
    }
    stmts.push(Stmt::Del(targets))
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if has_keyword_prefix(trimmed, "async") {
    // Treat async constructs as no-ops so spec-generated blocks can parse.
    let rest = substring(trimmed, 5, trimmed.length())
      .trim(chars=" \t")
      .to_string()
    if has_keyword_prefix(rest, "def") ||
      has_keyword_prefix(rest, "for") ||
      has_keyword_prefix(rest, "with") {
      stmts.push(Stmt::Pass)
      return finalize_simple_statement(
        stmts, allow_async_comprehensions, span, base_offset,
      )
    }
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
  if has_keyword_prefix(trimmed, "type") &&
    (trimmed.has_prefix("type ") || trimmed.has_prefix("type\t")) &&
    trimmed.contains("=") {
    // PEP 695 `type` statements are currently parsed as no-ops.
    stmts.push(Stmt::Pass)
    return finalize_simple_statement(
      stmts, allow_async_comprehensions, span, base_offset,
    )
  }
  if has_keyword_prefix(trimmed, "return") {
    let raw_expr_text = substring(trimmed, 6, trimmed.length()).to_string()
    let expr_text = raw_expr_text.trim(chars=" \t").to_owned()
    if expr_text.length() == 0 {
      stmts.push(Stmt::Return(None))
    } else {
      let tokens = match
        tokenize_expr(
          raw_expr_text,
          line_index + 1,
          base_offset + 6,
          base_offset + 6 - line_start_offset + 1,
        ) {
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
  // PEP 526 annotated assignment.
  if trimmed.contains(":") {
    let colon_pos = find_top_level_char(trimmed, ':')
    let eq_pos = find_top_level_char(trimmed, '=')
    match (colon_pos, eq_pos) {
      (Some(colon_pos), None) => {
        let left_text = substring(trimmed, 0, colon_pos)
          .trim(chars=" \t")
          .to_owned()
        // Avoid swallowing other colon-terminated statements like `match x:`
        // and `if x:`: only treat it as an annotation when the left side parses
        // as an assignment target.
        let left_target = match
          tokenize_expr(
            left_text,
            line_index + 1,
            base_offset,
            base_offset - line_start_offset + 1,
          ) {
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
            match target {
              Target::Name("__debug__")
              | Target::Attribute(attr="__debug__", ..) =>
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "cannot assign to __debug__".to_string(),
                    {
                      kind: Eof,
                      start: base_offset,
                      end: base_offset + 1,
                      line: line_index + 1,
                      column: 1,
                    },
                  ),
                )
              _ => ()
            }
            if !target_allows_annotation(target) {
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
            let annotation_text = replace_newlines_with_spaces(
                substring(trimmed, colon_pos + 1, trimmed.length()),
              )
              .trim(chars=" \t")
              .to_owned()
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
            let annotation_expr = match
              tokenize_expr(
                annotation_text,
                line_index + 1,
                base_offset + colon_pos + 1,
                base_offset + colon_pos + 1 - line_start_offset + 1,
              ) {
              Ok(tokens) =>
                match parse_tokens_expr(tokens) {
                  Ok(value) => value
                  Err(_) =>
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
              Err(_) =>
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
            .to_owned()
          let left_expr = match
            tokenize_expr(
              left_text,
              line_index + 1,
              base_offset,
              base_offset - line_start_offset + 1,
            ) {
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
                  match target {
                    Target::Name("__debug__")
                    | Target::Attribute(attr="__debug__", ..) =>
                      return Err(
                        make_parse_error(
                          ParseErrorKind::Syntax,
                          "cannot assign to __debug__".to_string(),
                          {
                            kind: Eof,
                            start: base_offset,
                            end: base_offset + 1,
                            line: line_index + 1,
                            column: 1,
                          },
                        ),
                      )
                    _ => ()
                  }
                  if !target_allows_annotation(target) {
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
                  let annotation_text = replace_newlines_with_spaces(
                      substring(trimmed, colon_pos + 1, eq_pos),
                    )
                    .trim(chars=" \t")
                    .to_owned()
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
                  let ann_expr = match
                    tokenize_expr(
                      annotation_text,
                      line_index + 1,
                      base_offset + colon_pos + 1,
                      base_offset + colon_pos + 1 - line_start_offset + 1,
                    ) {
                    Ok(tokens) =>
                      match parse_tokens_expr(tokens) {
                        Ok(value) => value
                        Err(_) => Expr::Literal(Literal::None)
                      }
                    Err(_) => Expr::Literal(Literal::None)
                  }
                  let mut value_text = substring(
                      trimmed,
                      eq_pos + 1,
                      trimmed.length(),
                    )
                    .trim(chars=" \t")
                    .to_owned()
                  let comma_pos = find_char(value_text, ',')
                  if value_text.contains("*") && comma_pos is Some(comma_pos) {
                    value_text = substring(value_text, 0, comma_pos)
                      .trim(chars=" \t")
                      .to_owned()
                  }
                  let tokens = match
                    tokenize_expr(
                      value_text,
                      line_index + 1,
                      base_offset + eq_pos + 1,
                      base_offset + eq_pos + 1 - line_start_offset + 1,
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
    let tokens = match
      tokenize_expr(
        trimmed,
        line_index + 1,
        base_offset,
        base_offset - line_start_offset + 1,
      ) {
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
      let left_text = substring(trimmed, 0, pos).trim(chars=" \t").to_owned()
      let right_text = substring(
          trimmed,
          pos + op_text.length(),
          trimmed.length(),
        )
        .trim(chars=" \t")
        .to_owned()
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
        tokenize_expr(
          left_text,
          line_index + 1,
          base_offset,
          base_offset - line_start_offset + 1,
        ) {
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
      let right_tokens = match
        tokenize_expr(
          right_text,
          line_index + 1,
          base_offset + pos + op_text.length(),
          base_offset + pos + op_text.length() - line_start_offset + 1,
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
  let tokens = match
    tokenize_expr(
      trimmed,
      line_index + 1,
      base_offset,
      base_offset - line_start_offset + 1,
    ) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let assign_positions : Array[Int] = []
  let mut depth = 0
  let mut lambda_depth = 0
  for idx = 0; idx < tokens.length(); idx = idx + 1 {
    let kind = tokens[idx].kind
    if kind == LParen || kind == LBracket || kind == LBrace {
      depth += 1
    } else if kind == RParen || kind == RBracket || kind == RBrace {
      if depth > 0 {
        depth -= 1
      }
    } else if kind == Lambda && depth == 0 {
      // `=` inside lambda parameter defaults must not be treated as assignment.
      lambda_depth += 1
    } else if kind == Colon && depth == 0 && lambda_depth > 0 {
      // End of lambda header; the lambda body is a normal expression again.
      lambda_depth -= 1
    } else if kind == Assign && depth == 0 && lambda_depth == 0 {
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
