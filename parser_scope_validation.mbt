///|
// Scope declarations apply to a whole function, but cannot follow a use or
// binding of that name in the same lexical scope. Nested function/class bodies
// are deliberately not included by collect_function_local_names.
fn scope_decl_after_use_line(body : Array[Stmt]) -> Int32? {
  let seen : Set[String] = Set([])
  let globals : Set[String] = Set([])
  let nonlocals : Set[String] = Set([])
  fn record(stmt : Stmt) -> Unit {
    // Include assignment-expression bindings even inside comprehensions.
    for name in collect_function_local_names([stmt], [], [], []) {
      seen.add(name)
    }
    for
      name in collect_function_local_names(
        [stmt],
        [],
        [],
        [],
        include_reads=true,
      ) {
      seen.add(name)
    }
  }
  fn walk(stmts : Array[Stmt], line : Int32) -> Int32? {
    for stmt in stmts {
      let error = match stmt {
        Stmt::WithSpan(span~, stmt~) => walk([stmt], span.line)
        Stmt::Global(names) => {
          for name in names {
            if seen.contains(name) || nonlocals.contains(name) {
              return Some(line)
            }
            globals.add(name)
          }
          None
        }
        Stmt::Nonlocal(names) => {
          for name in names {
            if seen.contains(name) || globals.contains(name) {
              return Some(line)
            }
            nonlocals.add(name)
          }
          None
        }
        Stmt::If(condition~, body~, else_body~)
        | Stmt::While(condition~, body~, else_body~) => {
          record(Stmt::ExprStmt(condition))
          match walk(body, line) {
            Some(line) => Some(line)
            None => walk(else_body, line)
          }
        }
        Stmt::For(target~, iter~, body~, else_body~)
        | Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
          record(Stmt::Assign(target~, value=iter))
          match walk(body, line) {
            Some(line) => Some(line)
            None => walk(else_body, line)
          }
        }
        Stmt::With(context~, target~, body~)
        | Stmt::AsyncWith(context~, target~, body~) => {
          record(Stmt::ExprStmt(context))
          if target is Some(name) {
            seen.add(name)
          }
          walk(body, line)
        }
        Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
          if walk(body, line) is Some(line) {
            return Some(line)
          }
          for handler in handlers {
            if handler.exc is Some(expr) {
              record(Stmt::ExprStmt(expr))
            }
            if handler.name is Some(name) {
              seen.add(name)
            }
            if walk(handler.body, line) is Some(line) {
              return Some(line)
            }
          }
          if walk(else_body, line) is Some(line) {
            return Some(line)
          }
          walk(finally_body, line)
        }
        Stmt::Match(subject~, cases~) => {
          record(Stmt::ExprStmt(subject))
          for case in cases {
            let captures : Set[String] = Set([])
            let _ = pattern_bindings_unique(case.0, captures)
            for name in captures {
              seen.add(name)
            }
            if case.1 is Some(expr) {
              record(Stmt::ExprStmt(expr))
            }
            if walk(case.2, line) is Some(line) {
              return Some(line)
            }
          }
          None
        }
        _ => {
          record(stmt)
          None
        }
      }
      if error is Some(line) {
        return Some(line)
      }
    }
    None
  }
  walk(body, 1)
}
