///|
/// Scope and parameter analysis helpers.

///|
fn append_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn collect_scope_decl_names(
  body : Array[Stmt],
) -> (Array[String], Array[String]) {
  let globals : Array[String] = []
  let nonlocals : Array[String] = []
  fn walk(stmt : Stmt) -> Unit {
    match stmt {
      Stmt::WithSpan(span=_, stmt=inner) => walk(inner)
      Stmt::Global(ns) =>
        for n in ns {
          append_unique_name(globals, n)
        }
      Stmt::Nonlocal(ns) =>
        for n in ns {
          append_unique_name(nonlocals, n)
        }
      Stmt::If(condition~, body~, else_body~) => {
        let _ = condition
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        let _ = condition
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::For(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::With(context~, target~, body~) => {
        let _ = context
        let _ = target
        for s in body {
          walk(s)
        }
      }
      Stmt::AsyncWith(context~, target~, body~) => {
        let _ = context
        let _ = target
        for s in body {
          walk(s)
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        for s in body {
          walk(s)
        }
        for handler in handlers {
          let _ = handler.exc
          let _ = handler.name
          for s in handler.body {
            walk(s)
          }
        }
        for s in else_body {
          walk(s)
        }
        for s in finally_body {
          walk(s)
        }
      }
      Stmt::Match(subject~, cases~) => {
        let _ = subject
        for case in cases {
          let _ = case.0
          let _ = case.1
          for s in case.2 {
            walk(s)
          }
        }
      }
      Stmt::Function(..) | Stmt::Class(..) | Stmt::TypeAlias(..) => ()
      _ => ()
    }
  }

  for stmt in body {
    walk(stmt)
  }
  (globals, nonlocals)
}

///|
fn name_in_list(names : Array[String], name : String) -> Bool {
  for n in names {
    if n == name {
      return true
    }
  }
  false
}

///|
fn param_has_default_marker(param : String) -> Bool {
  if param == "*" || param == "/" {
    return false
  }
  if param.has_prefix("*") {
    return false
  }
  param.has_suffix("=")
}

///|
fn normalize_param_name(param : String) -> String? {
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
fn param_list_has_name(params : Array[String], name : String) -> Bool {
  for param in params {
    match normalize_param_name(param) {
      Some(param_name) => if param_name == name { return true }
      None => ()
    }
  }
  false
}

///|
fn param_is_kw_only_marker(param : String) -> Bool {
  param == "*"
}

///|
fn param_is_posonly_marker(param : String) -> Bool {
  param == "/"
}

///|
fn param_is_vararg(param : String) -> Bool {
  param.has_prefix("*") && !param.has_prefix("**") && param != "*"
}

///|
fn param_is_kwarg(param : String) -> Bool {
  param.has_prefix("**")
}

///|
let globals_capture_name = "$__mpython_globals__"

///|
fn resolve_function_globals(
  func : FunctionValue,
  fallback : Array[(String, Value)],
) -> Array[(String, Value)] {
  for pair in func.closure {
    if pair.0 == globals_capture_name {
      match pair.1 {
        Value::Instance(inst) => return inst.dict
        _ => ()
      }
    }
  }
  fallback
}

///|
fn check_scope_decl_conflicts(
  params : Array[String],
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Result[Unit, RuntimeError] {
  for name in global_names {
    if name_in_list(nonlocal_names, name) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: name '" + name + "' is nonlocal and global",
        ),
      )
    }
    if param_list_has_name(params, name) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: name '" + name + "' is parameter and global",
        ),
      )
    }
  }
  for name in nonlocal_names {
    if param_list_has_name(params, name) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: name '" + name + "' is parameter and nonlocal",
        ),
      )
    }
  }
  Ok(())
}

///|
fn collect_function_local_names(
  body : Array[Stmt],
  params : Array[String],
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Array[String] {
  let locals : Array[String] = []
  fn add_local(name : String) -> Unit {
    if name_in_list(global_names, name) || name_in_list(nonlocal_names, name) {
      return
    }
    append_unique_name(locals, name)
  }

  fn add_target(target : Target) -> Unit {
    match target {
      Target::Name(name) => add_local(name)
      Target::Tuple(items) | Target::List(items) =>
        for item in items {
          add_target(item)
        }
      Target::Starred(inner) => add_target(inner)
      _ => ()
    }
  }

  fn add_pattern(pat : Pattern) -> Unit {
    match pat {
      Pattern::Name(name) => add_local(name)
      Pattern::Tuple(items) =>
        for item in items {
          add_pattern(item)
        }
      _ => ()
    }
  }

  fn walk_expr(expr : Expr) -> Unit {
    match expr {
      Expr::NamedExpr(name~, value~) => {
        add_local(name)
        walk_expr(value)
      }
      Expr::Lambda(params~, defaults~, body~) => {
        let _ = params
        for d in defaults {
          walk_expr(d)
        }
        let _ = body

      }
      Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) =>
        for item in items {
          walk_expr(item)
        }
      Expr::ListComp(elt~, clauses~, filters~)
      | Expr::GenExp(elt~, clauses~, filters~)
      | Expr::SetComp(elt~, clauses~, filters~) => {
        for clause in clauses {
          let _ = clause.targets
          walk_expr(clause.iter)
        }
        for filter in filters {
          walk_expr(filter)
        }
        walk_expr(elt)
      }
      Expr::Dict(items) =>
        for pair in items {
          walk_expr(pair.0)
          walk_expr(pair.1)
        }
      Expr::DictComp(key~, value~, clauses~, filters~) => {
        for clause in clauses {
          let _ = clause.targets
          walk_expr(clause.iter)
        }
        for filter in filters {
          walk_expr(filter)
        }
        walk_expr(key)
        walk_expr(value)
      }
      Expr::IfExpr(condition~, then_expr~, else_expr~) => {
        walk_expr(condition)
        walk_expr(then_expr)
        walk_expr(else_expr)
      }
      Expr::Yield(value) =>
        match value {
          Some(v) => walk_expr(v)
          None => ()
        }
      Expr::YieldFrom(value) | Expr::Await(value) => walk_expr(value)
      Expr::Slice(start~, end~, step~) => {
        match start {
          Some(v) => walk_expr(v)
          None => ()
        }
        match end {
          Some(v) => walk_expr(v)
          None => ()
        }
        match step {
          Some(v) => walk_expr(v)
          None => ()
        }
      }
      Expr::Attribute(value~, attr~) => {
        let _ = attr
        walk_expr(value)
      }
      Expr::Subscript(value~, index~) => {
        walk_expr(value)
        walk_expr(index)
      }
      Expr::Call(callee~, args~) => {
        walk_expr(callee)
        for arg in args {
          walk_expr(arg)
        }
      }
      Expr::Keyword(name~, value~) => {
        let _ = name
        walk_expr(value)
      }
      Expr::Starred(value~) | Expr::DoubleStarred(value~) => walk_expr(value)
      Expr::Unary(op~, expr~) => {
        let _ = op
        walk_expr(expr)
      }
      Expr::Binary(op~, left~, right~) => {
        let _ = op
        walk_expr(left)
        walk_expr(right)
      }
      Expr::BoolOp(op~, values~) => {
        let _ = op
        for v in values {
          walk_expr(v)
        }
      }
      Expr::Compare(left~, ops~, comparators~) => {
        let _ = ops
        walk_expr(left)
        for v in comparators {
          walk_expr(v)
        }
      }
      _ => ()
    }
  }

  fn walk_stmt(stmt : Stmt) -> Unit {
    match stmt {
      Stmt::WithSpan(span=_, stmt=inner) => walk_stmt(inner)
      Stmt::Assign(target~, value~) => {
        add_target(target)
        walk_expr(value)
      }
      Stmt::AnnAssign(target~, annotation~, value~) => {
        add_target(target)
        walk_expr(annotation)
        match value {
          Some(v) => walk_expr(v)
          None => ()
        }
      }
      Stmt::AugAssign(target~, op~, value~) => {
        let _ = op
        add_target(target)
        walk_expr(value)
      }
      Stmt::TypeAlias(name~, type_params~, value~) => {
        let _ = type_params
        add_local(name)
        walk_expr(value)
      }
      Stmt::Del(targets) =>
        for t in targets {
          add_target(t)
        }
      Stmt::ExprStmt(expr) => walk_expr(expr)
      Stmt::Return(expr) =>
        match expr {
          Some(v) => walk_expr(v)
          None => ()
        }
      Stmt::If(condition~, body~, else_body~) => {
        walk_expr(condition)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        walk_expr(condition)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::For(target~, iter~, body~, else_body~) => {
        add_target(target)
        walk_expr(iter)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        add_target(target)
        walk_expr(iter)
        for s in body {
          walk_stmt(s)
        }
        for s in else_body {
          walk_stmt(s)
        }
      }
      Stmt::With(context~, target~, body~)
      | Stmt::AsyncWith(context~, target~, body~) => {
        walk_expr(context)
        match target {
          Some(name) => add_local(name)
          None => ()
        }
        for s in body {
          walk_stmt(s)
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        for s in body {
          walk_stmt(s)
        }
        for handler in handlers {
          let _ = handler.exc
          match handler.name {
            Some(name) => add_local(name)
            None => ()
          }
          for s in handler.body {
            walk_stmt(s)
          }
        }
        for s in else_body {
          walk_stmt(s)
        }
        for s in finally_body {
          walk_stmt(s)
        }
      }
      Stmt::Match(subject~, cases~) => {
        walk_expr(subject)
        for case in cases {
          add_pattern(case.0)
          match case.1 {
            Some(v) => walk_expr(v)
            None => ()
          }
          for s in case.2 {
            walk_stmt(s)
          }
        }
      }
      Stmt::Import(module_name~, alias_name~) => {
        let binding = match alias_name {
          Some(name) => name
          None => module_name
        }
        add_local(binding)
      }
      Stmt::FromImport(module_name~, names~) => {
        let _ = module_name
        for item in names {
          let name = item.0
          let alias_opt = item.1
          if name != "*" {
            add_local(
              match alias_opt {
                Some(alias_name) => alias_name
                None => name
              },
            )
          }
        }
      }
      Stmt::Function(
        name~,
        decorators~,
        type_params~,
        params~,
        defaults~,
        body~,
        is_generator~,
        is_async~
      ) => {
        add_local(name)
        for dec in decorators {
          walk_expr(dec)
        }
        for d in defaults {
          walk_expr(d)
        }
        let _ = type_params
        let _ = params
        let _ = body
        let _ = is_generator
        let _ = is_async

      }
      Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~) => {
        add_local(name)
        for dec in decorators {
          walk_expr(dec)
        }
        for b in bases {
          walk_expr(b)
        }
        for kw in keywords {
          let _ = kw.0
          walk_expr(kw.1)
        }
        let _ = type_params
        let _ = body

      }
      _ => ()
    }
  }

  for p in params {
    match normalize_param_name(p) {
      Some(name) => add_local(name)
      None => ()
    }
  }
  for stmt in body {
    walk_stmt(stmt)
  }
  locals
}
