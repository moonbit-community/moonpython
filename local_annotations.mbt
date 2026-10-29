///|
// Local variable annotations determine bindings but have no runtime effect in
// Python, with or without postponed annotations. Call only after collecting the
// function's local names, and leave nested definition bodies in their own scope.
fn local_annotation_statements(body : Array[Stmt]) -> Array[Stmt] {
  body.map(fn(stmt) {
    match stmt {
      Stmt::WithSpan(span~, stmt~) =>
        Stmt::WithSpan(span~, stmt=local_annotation_statements([stmt])[0])
      Stmt::AnnAssign(target~, value~, ..) =>
        match value {
          Some(value) => Stmt::Assign(target~, value~)
          None => Stmt::Pass
        }
      Stmt::If(condition~, body~, else_body~) =>
        Stmt::If(
          condition~,
          body=local_annotation_statements(body),
          else_body=local_annotation_statements(else_body),
        )
      Stmt::While(condition~, body~, else_body~) =>
        Stmt::While(
          condition~,
          body=local_annotation_statements(body),
          else_body=local_annotation_statements(else_body),
        )
      Stmt::For(target~, iter~, body~, else_body~) =>
        Stmt::For(
          target~,
          iter~,
          body=local_annotation_statements(body),
          else_body=local_annotation_statements(else_body),
        )
      Stmt::AsyncFor(target~, iter~, body~, else_body~) =>
        Stmt::AsyncFor(
          target~,
          iter~,
          body=local_annotation_statements(body),
          else_body=local_annotation_statements(else_body),
        )
      Stmt::With(context~, target~, body~) =>
        Stmt::With(context~, target~, body=local_annotation_statements(body))
      Stmt::AsyncWith(context~, target~, body~) =>
        Stmt::AsyncWith(
          context~,
          target~,
          body=local_annotation_statements(body),
        )
      Stmt::Match(subject~, cases~) =>
        Stmt::Match(
          subject~,
          cases=cases.map(fn(case) {
            (case.0, case.1, local_annotation_statements(case.2))
          }),
        )
      Stmt::Try(body~, handlers~, else_body~, finally_body~) =>
        Stmt::Try(
          body=local_annotation_statements(body),
          handlers=handlers.map(fn(handler) {
            ExceptHandler::{
              span: handler.span,
              is_star: handler.is_star,
              exc: handler.exc,
              name: handler.name,
              body: local_annotation_statements(handler.body),
            }
          }),
          else_body=local_annotation_statements(else_body),
          finally_body=local_annotation_statements(finally_body),
        )
      _ => stmt
    }
  })
}
