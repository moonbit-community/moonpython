///|
fn class_comprehension_binds(expr : Expr, in_comp~ : Bool = false) -> Bool {
  match expr {
    Expr::Lambda(defaults~, ..) =>
      defaults.any(fn(expr) { class_comprehension_binds(expr, in_comp~) })
    Expr::NamedExpr(value~, ..) => in_comp || class_comprehension_binds(value)
    Expr::ListComp(..)
    | Expr::DictComp(..)
    | Expr::SetComp(..)
    | Expr::GenExp(..) =>
      expression_children(expr).any(fn(expr) {
        class_comprehension_binds(expr, in_comp=true)
      })
    _ =>
      expression_children(expr).any(fn(expr) {
        class_comprehension_binds(expr, in_comp~)
      })
  }
}

///|
// Nonlocal must have an enclosing function scope. A comprehension cannot bind
// a name in a class scope, but a nested method/lambda has its own binding scope.
fn class_scope_error_line(
  body : Array[Stmt],
  enclosing_function : Bool,
  line~ : Int32 = 1,
) -> Int32? {
  for stmt in body {
    let expressions : Array[Expr] = []
    let children : Array[Array[Stmt]] = []
    match stmt {
      Stmt::WithSpan(span~, stmt~) =>
        if class_scope_error_line([stmt], enclosing_function, line=span.line)
          is Some(line) {
          return Some(line)
        }
      Stmt::Nonlocal(_) => if !enclosing_function { return Some(line) }
      Stmt::ExprStmt(expr)
      | Stmt::Assign(value=expr, ..)
      | Stmt::AugAssign(value=expr, ..) => expressions.push(expr)
      Stmt::AnnAssign(annotation~, value~, ..) => {
        expressions.push(annotation)
        if value is Some(value) {
          expressions.push(value)
        }
      }
      Stmt::Function(
        decorators~,
        defaults~,
        annotations~,
        return_annotation~,
        ..
      ) => {
        expressions.append(decorators)
        expressions.append(defaults)
        for annotation in annotations {
          expressions.push(annotation.1)
        }
        if return_annotation is Some(expr) {
          expressions.push(expr)
        }
      }
      Stmt::If(condition~, body~, else_body~)
      | Stmt::While(condition~, body~, else_body~) => {
        expressions.push(condition)
        children.push(body)
        children.push(else_body)
      }
      Stmt::For(iter~, body~, else_body~, ..)
      | Stmt::AsyncFor(iter~, body~, else_body~, ..) => {
        expressions.push(iter)
        children.push(body)
        children.push(else_body)
      }
      Stmt::With(context~, body~, ..) | Stmt::AsyncWith(context~, body~, ..) => {
        expressions.push(context)
        children.push(body)
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        children.push(body)
        children.push(else_body)
        children.push(finally_body)
        for handler in handlers {
          if handler.exc is Some(expr) {
            expressions.push(expr)
          }
          children.push(handler.body)
        }
      }
      Stmt::Match(subject~, cases~) => {
        expressions.push(subject)
        for case in cases {
          if case.1 is Some(expr) {
            expressions.push(expr)
          }
          children.push(case.2)
        }
      }
      Stmt::Assert(condition~, message~) => {
        expressions.push(condition)
        if message is Some(expr) {
          expressions.push(expr)
        }
      }
      Stmt::Raise(exc~, cause~) => {
        if exc is Some(expr) {
          expressions.push(expr)
        }
        if cause is Some(expr) {
          expressions.push(expr)
        }
      }
      _ => ()
    }
    if expressions.any(fn(expr) { class_comprehension_binds(expr) }) {
      return Some(line)
    }
    for child in children {
      if class_scope_error_line(child, enclosing_function, line~) is Some(line) {
        return Some(line)
      }
    }
  }
  None
}
