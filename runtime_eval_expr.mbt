///|
/// Expression evaluation helpers.

///|
fn lookup_name_value(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Result[Value, RuntimeError] {
  fn read_local_cell() -> Result[Value, RuntimeError] {
    match get_local_value(locals, name) {
      Some(v) =>
        if is_cell_value(v) {
          match cell_get_value(v) {
            Some(value) => Ok(value)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "UnboundLocalError: local variable '" +
                  name +
                  "' referenced before assignment",
                ),
              )
          }
        } else {
          Ok(v)
        }
      None =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
    }
  }

  fn read_closure_cell(cell : Value) -> Result[Value, RuntimeError] {
    match cell_get_value(cell) {
      Some(value) => Ok(value)
      None =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "free variable '" +
            name +
            "' referenced before assignment in enclosing scope",
          ),
        )
    }
  }

  if scope_name_is_global(name) {
    match get_global_value(globals, name) {
      Some(v) => Ok(v)
      None =>
        match get_global_value(builtins, name) {
          Some(v) => Ok(v)
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Name,
                "name '" + name + "' is not defined",
              ),
            )
        }
    }
  } else if scope_name_is_nonlocal(name) {
    match lookup_closure_cell(name) {
      Some(cell) => read_closure_cell(cell)
      None =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
    }
  } else {
    match get_local_value(locals, name) {
      Some(_) => read_local_cell()
      None =>
        match lookup_closure_cell(name) {
          Some(cell) => read_closure_cell(cell)
          None =>
            match get_global_value(globals, name) {
              Some(v) => Ok(v)
              None =>
                match get_global_value(builtins, name) {
                  Some(v) => Ok(v)
                  None =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Name,
                        "name '" + name + "' is not defined",
                      ),
                    )
                }
            }
        }
    }
  }
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
        Literal::Complex(real, imag) => Ok(Value::Complex(real, imag))
        Literal::Str(value) => Ok(Value::Str(value))
        Literal::Bytes(value) => Ok(Value::Bytes(value))
      }
    Expr::Name(name) => lookup_name_value(name, locals, globals, builtins)
    Expr::FString(text) =>
      match eval_fstring_text(text, locals, globals, builtins, io) {
        Ok(value) => Ok(Value::Str(value))
        Err(err) => Err(err)
      }
    Expr::NamedExpr(name~, value~) => {
      let evaluated = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      set_scoped_value(locals, globals, name, evaluated)
      Ok(evaluated)
    }
    Expr::Await(expr) =>
      if !coroutine_is_active() {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'await' outside async function".to_string(),
          ),
        )
      } else {
        let awaitable = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match awaitable {
          Value::Instance(inst) =>
            if inst.class.name == "coroutine" {
              coroutine_await(awaitable)
            } else {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "'" +
                  type_name_from_value(awaitable) +
                  "' object can't be used in 'await' expression",
                ),
              )
            }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" +
                type_name_from_value(awaitable) +
                "' object can't be used in 'await' expression",
              ),
            )
        }
      }
    Expr::Yield(_) | Expr::YieldFrom(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: 'yield' outside function".to_string(),
        ),
      )
    Expr::List(items) => {
      let values : Array[Value] = []
      for item in items {
        match item {
          Expr::Starred(value~) => {
            let iter_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let items = match iterable_values(iter_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for v in items {
              values.push(v)
            }
          }
          _ => {
            let value = match
              eval_expr_with_env(item, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            values.push(value)
          }
        }
      }
      Ok(Value::List(values))
    }
    Expr::ListComp(elt~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async && !coroutine_is_active() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
        )
      }
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[CompClause] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
      }
      let clauses = if clauses.length() > 0 {
        adjusted_clauses
      } else {
        clauses
      }
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
          }
        }
      }
      let values : Array[Value] = []
      let _ = match
        eval_list_comp_walk(
          0, elt, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Ok(Value::List(values))
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      fn expr_contains_await(expr : Expr) -> Bool {
        match expr {
          Expr::Await(_) => true
          Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) =>
            for item in items {
              if expr_contains_await(item) {
                return true
              }
            } else {
              false
            }
          Expr::Dict(items) =>
            for pair in items {
              if expr_contains_await(pair.0) || expr_contains_await(pair.1) {
                return true
              }
            } else {
              false
            }
          Expr::ListComp(elt~, clauses~, filters~)
          | Expr::GenExp(elt~, clauses~, filters~)
          | Expr::SetComp(elt~, clauses~, filters~) => {
            if expr_contains_await(elt) {
              return true
            }
            for clause in clauses {
              if expr_contains_await(clause.iter) {
                return true
              }
            }
            for filter in filters {
              if expr_contains_await(filter) {
                return true
              }
            }
            false
          }
          Expr::DictComp(key~, value~, clauses~, filters~) => {
            if expr_contains_await(key) || expr_contains_await(value) {
              return true
            }
            for clause in clauses {
              if expr_contains_await(clause.iter) {
                return true
              }
            }
            for filter in filters {
              if expr_contains_await(filter) {
                return true
              }
            }
            false
          }
          Expr::IfExpr(condition~, then_expr~, else_expr~) =>
            expr_contains_await(condition) ||
            expr_contains_await(then_expr) ||
            expr_contains_await(else_expr)
          Expr::NamedExpr(name~, value~) => {
            let _ = name
            expr_contains_await(value)
          }
          Expr::Yield(expr_opt) =>
            match expr_opt {
              Some(v) => expr_contains_await(v)
              None => false
            }
          Expr::YieldFrom(value) => expr_contains_await(value)
          Expr::Slice(start~, end~, step~) => {
            match start {
              Some(v) => if expr_contains_await(v) { return true }
              None => ()
            }
            match end {
              Some(v) => if expr_contains_await(v) { return true }
              None => ()
            }
            match step {
              Some(v) => if expr_contains_await(v) { return true }
              None => ()
            }
            false
          }
          Expr::Attribute(value~, attr~) => {
            let _ = attr
            expr_contains_await(value)
          }
          Expr::Subscript(value~, index~) =>
            expr_contains_await(value) || expr_contains_await(index)
          Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
            expr_contains_await(value)
          Expr::Unary(op~, expr~) => {
            let _ = op
            expr_contains_await(expr)
          }
          Expr::Binary(op~, left~, right~) => {
            let _ = op
            expr_contains_await(left) || expr_contains_await(right)
          }
          Expr::BoolOp(op~, values~) => {
            let _ = op
            for v in values {
              if expr_contains_await(v) {
                return true
              }
            }
            false
          }
          Expr::Compare(left~, ops~, comparators~) => {
            let _ = ops
            if expr_contains_await(left) {
              return true
            }
            for v in comparators {
              if expr_contains_await(v) {
                return true
              }
            }
            false
          }
          Expr::Call(callee~, args~) =>
            if expr_contains_await(callee) {
              true
            } else {
              for arg in args {
                if expr_contains_await(arg) {
                  return true
                }
              }
              false
            }
          Expr::Keyword(name~, value~) => {
            let _ = name
            expr_contains_await(value)
          }
          Expr::Lambda(params~, defaults~, body~) => {
            let _ = params
            for d in defaults {
              if expr_contains_await(d) {
                return true
              }
            }
            expr_contains_await(body)
          }
          _ => false
        }
      }

      let gen_locals = clone_locals(locals)
      let mut has_async_clause = false
      for clause in clauses {
        if clause.is_async {
          has_async_clause = true
        }
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(gen_locals, name, Value::None)
          }
        }
      }
      let mut has_await = expr_contains_await(elt)
      if !has_await {
        for clause in clauses {
          if expr_contains_await(clause.iter) {
            has_await = true
            break
          }
        }
      }
      if !has_await {
        for filter in filters {
          if expr_contains_await(filter) {
            has_await = true
            break
          }
        }
      }
      let is_async_genexp = has_async_clause || has_await
      if is_async_genexp {
        if clauses.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: invalid async generator expression".to_string(),
            ),
          )
        }
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let first_iterator = if clauses[0].is_async {
          let aiter_value = match
            get_attr_from_value(
              first_iter_value, "__aiter__", globals, builtins, io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match
            call_callable_with_env(aiter_value, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        } else {
          match
            iter_value_to_iterator(first_iter_value, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        }
        let iter_name = fresh_genexp_local(gen_locals)
        set_local_value(gen_locals, iter_name, first_iterator)
        let adjusted_clauses : Array[CompClause] = []
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
        return Ok(
          async_genexp_new(
            elt, adjusted_clauses, filters, gen_locals, globals, builtins, io,
          ),
        )
      }
      if clauses.length() == 0 {
        let body = genexp_to_generator_body(elt, clauses, filters)
        let filename = current_traceback_filename()
        return Ok(
          generator_new(
            body,
            gen_locals,
            globals,
            builtins,
            io,
            [],
            [],
            [],
            "<genexpr>".to_string(),
            filename,
          ),
        )
      }
      let first_iter_value = match
        eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let first_iterator = match
        iter_value_to_iterator(first_iter_value, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_name = fresh_genexp_local(gen_locals)
      set_local_value(gen_locals, iter_name, first_iterator)
      let adjusted_clauses : Array[CompClause] = []
      adjusted_clauses.push(CompClause::{
        is_async: false,
        targets: clauses[0].targets,
        iter: Expr::Name(iter_name),
      })
      for i = 1; i < clauses.length(); i = i + 1 {
        adjusted_clauses.push(clauses[i])
      }
      let body = genexp_to_generator_body(elt, adjusted_clauses, filters)
      let filename = current_traceback_filename()
      Ok(
        generator_new(
          body,
          gen_locals,
          globals,
          builtins,
          io,
          [],
          [],
          [],
          "<genexpr>".to_string(),
          filename,
        ),
      )
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async && !coroutine_is_active() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
        )
      }
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[CompClause] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
      }
      let clauses = if clauses.length() > 0 {
        adjusted_clauses
      } else {
        clauses
      }
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
          }
        }
      }
      let values : Array[Value] = []
      let _ = match
        eval_list_comp_walk(
          0, elt, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let unique : Array[Value] = []
      for item in values {
        let _ = match set_add_unique(unique, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }

      }
      Ok(Value::Set(unique))
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async && !coroutine_is_active() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
        )
      }
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[CompClause] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].iter, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted_clauses.push(clauses[i])
        }
      }
      let clauses = if clauses.length() > 0 {
        adjusted_clauses
      } else {
        clauses
      }
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
          }
        }
      }
      let values : Array[(Value, Value)] = []
      let _ = match
        eval_dict_comp_walk(
          0, key, value, clauses, filters, comp_locals, globals, builtins, io, values,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      Ok(Value::Dict(values))
    }
    Expr::Dict(items) => {
      let values : Array[(Value, Value)] = []
      fn set_pair(
        pairs : Array[(Value, Value)],
        key : Value,
        value : Value,
      ) -> Result[Unit, RuntimeError] {
        match dict_set_item(pairs, key, value) {
          Ok(v) => Ok(v)
          Err(err) => Err(err)
        }
      }

      for item in items {
        match item.0 {
          Expr::DoubleStarred(value~) => {
            let mapping = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match mapping {
              Value::Dict(pairs) =>
                for pair in pairs {
                  let _ = match set_pair(values, pair.0, pair.1) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }

                }
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "dict update sequence element has wrong length".to_string(),
                  ),
                )
            }
          }
          _ => {
            let key = match
              eval_expr_with_env(item.0, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let value = match
              eval_expr_with_env(item.1, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = match set_pair(values, key, value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
        }
      }
      Ok(Value::Dict(values))
    }
    Expr::Set(items) => {
      let values : Array[Value] = []
      for item in items {
        match item {
          Expr::Starred(value~) => {
            let iter_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let items = match iterable_values(iter_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for value in items {
              let _ = match set_add_unique(values, value) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }

            }
          }
          _ => {
            let value = match
              eval_expr_with_env(item, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let _ = match set_add_unique(values, value) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }

          }
        }
      }
      Ok(Value::Set(values))
    }
    Expr::Tuple(items) => {
      let values : Array[Value] = []
      for item in items {
        match item {
          Expr::Starred(value~) => {
            let iter_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let items = match iterable_values(iter_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for v in items {
              values.push(v)
            }
          }
          _ => {
            let value = match
              eval_expr_with_env(item, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            values.push(value)
          }
        }
      }
      Ok(Value::Tuple(values))
    }
    Expr::Lambda(params~, defaults~, body~) => {
      let default_values : Array[Value] = []
      for expr in defaults {
        let value = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        default_values.push(value)
      }
      let is_generator = match body {
        Expr::Yield(_) | Expr::YieldFrom(_) => true
        _ => false
      }
      let func_body : Array[Stmt] = if is_generator {
        [Stmt::ExprStmt(body)]
      } else {
        [Stmt::Return(Some(body))]
      }
      let closure = capture_cell_closure(locals)
      let globals_marker = Value::Instance(InstanceValue::{
        class: ClassValue::{ name: "__mpython_globals__", bases: [], dict: [] },
        dict: globals,
      })
      closure.push(("$__mpython_globals__", globals_marker))
      Ok(
        Value::Function(FunctionValue::{
          name: "<lambda>",
          params,
          defaults: default_values,
          body: func_body,
          is_generator,
          is_async: false,
          closure,
        }),
      )
    }
    Expr::Attribute(value~, attr~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      get_attr_from_value(target, attr, globals, builtins, io)
    }
    Expr::Subscript(value~, index~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match index {
        Expr::Slice(start~, end~, step~) => {
          let start_value = match start {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          let end_value = match end {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          let step_value = match step {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          fn slice_list(values : Array[Value]) -> Result[Value, RuntimeError] {
            let indices = match
              slice_indices_from_values(
                values.length(),
                start_value,
                end_value,
                step_value,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            Ok(Value::List(slice_values_by_indices(values, indices)))
          }

          match target {
            Value::List(values) => slice_list(values)
            Value::Instance(inst) =>
              match get_named_value(inst.dict, list_storage_name) {
                Some(Value::List(values)) => slice_list(values)
                _ => {
                  // General Python protocol: obj.__getitem__(slice(...))
                  let slice_dict : Array[(String, Value)] = []
                  slice_dict.push(("start", start_value))
                  slice_dict.push(("stop", end_value))
                  slice_dict.push(("step", step_value))
                  let slice_obj = Value::Instance(InstanceValue::{
                    class: builtin_class_from_name("slice", builtins),
                    dict: slice_dict,
                  })
                  match
                    get_attr_from_value(
                      Value::Instance(inst),
                      "__getitem__",
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(getitem) =>
                      call_callable_with_env(
                        getitem,
                        [slice_obj],
                        [],
                        globals,
                        builtins,
                        io,
                      )
                    Err(err) =>
                      match err.kind {
                        RuntimeErrorKind::Attribute =>
                          Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "'" +
                              inst.class.name +
                              "' object is not subscriptable",
                            ),
                          )
                        _ => Err(err)
                      }
                  }
                }
              }
            Value::Tuple(values) => {
              let indices = match
                slice_indices_from_values(
                  values.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Tuple(slice_values_by_indices(values, indices)))
            }
            Value::Str(text) => {
              let chars = text.to_array()
              let indices = match
                slice_indices_from_values(
                  chars.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Str(slice_string_by_indices(chars, indices)))
            }
            Value::Bytes(bytes) => {
              let indices = match
                slice_indices_from_values(
                  bytes.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Bytes(slice_ints_by_indices(bytes, indices)))
            }
            Value::ByteArray(bytes) => {
              let indices = match
                slice_indices_from_values(
                  bytes.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::ByteArray(slice_ints_by_indices(bytes, indices)))
            }
            Value::MemoryView(bytes) => {
              let indices = match
                slice_indices_from_values(
                  bytes.length(),
                  start_value,
                  end_value,
                  step_value,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::MemoryView(slice_ints_by_indices(bytes, indices)))
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "subscript requires sequence".to_string(),
                ),
              )
          }
        }
        _ => {
          let idx_value = match
            eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match target {
            Value::Function(func) =>
              if func.body.length() == 0 &&
                is_generic_alias_origin_name(func.name) {
                let args = match idx_value {
                  Value::Tuple(values) => values
                  _ => [idx_value]
                }
                return Ok(
                  make_generic_alias(
                    Value::Class(builtin_class_from_name(func.name, builtins)),
                    args,
                  ),
                )
              }
            Value::Class(klass) =>
              if is_generic_alias_origin_name(klass.name) {
                let args = match idx_value {
                  Value::Tuple(values) => values
                  _ => [idx_value]
                }
                return Ok(make_generic_alias(Value::Class(klass), args))
              }
            _ => ()
          }
          match target {
            Value::Class(_) | Value::Function(_) =>
              match
                get_attr_from_value(
                  target, "__class_getitem__", globals, builtins, io,
                ) {
                Ok(class_getitem) => {
                  let args = match class_getitem {
                    Value::BoundMethod(_) => [idx_value]
                    Value::Function(_) => [target, idx_value]
                    _ => [idx_value]
                  }
                  return call_callable_with_env(
                    class_getitem,
                    args,
                    [],
                    globals,
                    builtins,
                    io,
                  )
                }
                Err(_) => ()
              }
            _ => ()
          }
          match idx_value {
            Value::Instance(inst) =>
              if inst.class.name == "slice" {
                let start_value = match get_named_value(inst.dict, "start") {
                  Some(v) => v
                  None => Value::None
                }
                let end_value = match get_named_value(inst.dict, "stop") {
                  Some(v) => v
                  None => Value::None
                }
                let step_value = match get_named_value(inst.dict, "step") {
                  Some(v) => v
                  None => Value::None
                }
                fn slice_list(
                  values : Array[Value],
                ) -> Result[Value, RuntimeError] {
                  let indices = match
                    slice_indices_from_values(
                      values.length(),
                      start_value,
                      end_value,
                      step_value,
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  Ok(Value::List(slice_values_by_indices(values, indices)))
                }

                return match target {
                  Value::List(values) => slice_list(values)
                  Value::Instance(list_inst) =>
                    match get_named_value(list_inst.dict, list_storage_name) {
                      Some(Value::List(values)) => slice_list(values)
                      _ =>
                        match
                          get_attr_from_value(
                            Value::Instance(list_inst),
                            "__getitem__",
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(getitem) =>
                            call_callable_with_env(
                              getitem,
                              [idx_value],
                              [],
                              globals,
                              builtins,
                              io,
                            )
                          Err(err) =>
                            match err.kind {
                              RuntimeErrorKind::Attribute =>
                                Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Type,
                                    "'" +
                                    list_inst.class.name +
                                    "' object is not subscriptable",
                                  ),
                                )
                              _ => Err(err)
                            }
                        }
                    }
                  Value::Tuple(values) => {
                    let indices = match
                      slice_indices_from_values(
                        values.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::Tuple(slice_values_by_indices(values, indices)))
                  }
                  Value::Str(text) => {
                    let chars = text.to_array()
                    let indices = match
                      slice_indices_from_values(
                        chars.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::Str(slice_string_by_indices(chars, indices)))
                  }
                  Value::Bytes(bytes) => {
                    let indices = match
                      slice_indices_from_values(
                        bytes.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::Bytes(slice_ints_by_indices(bytes, indices)))
                  }
                  Value::ByteArray(bytes) => {
                    let indices = match
                      slice_indices_from_values(
                        bytes.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::ByteArray(slice_ints_by_indices(bytes, indices)))
                  }
                  Value::MemoryView(bytes) => {
                    let indices = match
                      slice_indices_from_values(
                        bytes.length(),
                        start_value,
                        end_value,
                        step_value,
                      ) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    Ok(Value::MemoryView(slice_ints_by_indices(bytes, indices)))
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "subscript requires sequence".to_string(),
                      ),
                    )
                }
              }
            _ => ()
          }
          match target {
            // User-defined `obj[key]` should dispatch to `obj.__getitem__(key)`.
            Value::Instance(_) =>
              match
                get_attr_from_value(
                  target, "__getitem__", globals, builtins, io,
                ) {
                Ok(getitem) =>
                  return call_callable_with_env(
                    getitem,
                    [idx_value],
                    [],
                    globals,
                    builtins,
                    io,
                  )
                Err(err) =>
                  match err.kind {
                    RuntimeErrorKind::Attribute => ()
                    _ => return Err(err)
                  }
              }
            _ => ()
          }
          match target {
            Value::Dict(values) => {
              let index = match dict_find_index(values, idx_value) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              match index {
                Some(i) => Ok(values[i].1)
                None =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Key,
                      "key not found".to_string(),
                    ),
                  )
              }
            }
            _ => {
              let idx = match index_from_value(idx_value, 0) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              fn index_list(
                values : Array[Value],
                idx : Int,
              ) -> Result[Value, RuntimeError] {
                let norm = normalize_index(idx, values.length())
                if norm >= 0 && norm < values.length() {
                  Ok(values[norm])
                } else {
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Index,
                      "index out of range".to_string(),
                    ),
                  )
                }
              }

              match target {
                Value::List(values) => index_list(values, idx)
                Value::Instance(inst) =>
                  match get_named_value(inst.dict, list_storage_name) {
                    Some(Value::List(values)) => index_list(values, idx)
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "subscript requires sequence".to_string(),
                        ),
                      )
                  }
                Value::Tuple(values) => {
                  let norm = normalize_index(idx, values.length())
                  if norm >= 0 && norm < values.length() {
                    Ok(values[norm])
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                Value::Str(text) => {
                  let chars = text.to_array()
                  let norm = normalize_index(idx, chars.length())
                  if norm >= 0 && norm < chars.length() {
                    Ok(Value::Str(char_to_string(chars[norm])))
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                Value::Bytes(bytes)
                | Value::ByteArray(bytes)
                | Value::MemoryView(bytes) => {
                  let norm = normalize_index(idx, bytes.length())
                  if norm >= 0 && norm < bytes.length() {
                    Ok(Value::Int(@bigint.BigInt::from_int(bytes[norm])))
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "subscript requires sequence".to_string(),
                    ),
                  )
              }
            }
          }
        }
      }
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      let cond_value = match
        eval_expr_with_env(condition, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let ok = match
        truthy_from_value_with_env(cond_value, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if ok {
        eval_expr_with_env(then_expr, locals, globals, builtins, io)
      } else {
        eval_expr_with_env(else_expr, locals, globals, builtins, io)
      }
    }
    Expr::Unary(op~, expr~) => {
      let value = match
        eval_expr_with_env(expr, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match op {
        UnaryOp::Neg => {
          // User-defined unary operators: fall back to numeric handling only if
          // the instance doesn't implement the corresponding dunder.
          match value {
            Value::Instance(_) =>
              match
                get_attr_from_value(value, "__neg__", globals, builtins, io) {
                Ok(dunder) =>
                  return call_callable_with_env(
                    dunder,
                    [],
                    [],
                    globals,
                    builtins,
                    io,
                  )
                Err(err) =>
                  match err.kind {
                    RuntimeErrorKind::Attribute => ()
                    _ => return Err(err)
                  }
              }
            _ => ()
          }
          match value {
            Value::Complex(real, imag) =>
              return Ok(Value::Complex(-real, -imag))
            _ => ()
          }
          let (is_float, num) = match number_value(value) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if is_float {
            Ok(Value::Float(-num))
          } else {
            match value {
              Value::Int(v) => Ok(Value::Int(-v))
              Value::Bool(v) => Ok(Value::Int(-(if v { 1N } else { 0N })))
              _ => Ok(Value::Int(-@bigint.BigInt::from_int64(num.to_int64())))
            }
          }
        }
        UnaryOp::Pos =>
          match value {
            Value::Instance(_) =>
              match
                get_attr_from_value(value, "__pos__", globals, builtins, io) {
                Ok(dunder) =>
                  call_callable_with_env(dunder, [], [], globals, builtins, io)
                Err(err) =>
                  match err.kind {
                    RuntimeErrorKind::Attribute => Ok(value)
                    _ => Err(err)
                  }
              }
            _ => Ok(value)
          }
        UnaryOp::Not => {
          let ok = match
            truthy_from_value_with_env(value, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Bool(!ok))
        }
        UnaryOp::Invert => {
          match value {
            Value::Instance(_) =>
              match
                get_attr_from_value(value, "__invert__", globals, builtins, io) {
                Ok(dunder) =>
                  return call_callable_with_env(
                    dunder,
                    [],
                    [],
                    globals,
                    builtins,
                    io,
                  )
                Err(err) =>
                  match err.kind {
                    RuntimeErrorKind::Attribute => ()
                    _ => return Err(err)
                  }
              }
            _ => ()
          }
          match value {
            Value::Int(v) => Ok(Value::Int(-(v + 1N)))
            Value::Bool(v) => Ok(Value::Int(-((if v { 1N } else { 0N }) + 1N)))
            Value::Float(_) =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: 'float'".to_string(),
                ),
              )
            Value::Function(func) => {
              let type_name = if func.name == "int" ||
                func.name == "str" ||
                func.name == "bytes" ||
                func.name == "dict" {
                "type"
              } else {
                "function"
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: '" + type_name + "'",
                ),
              )
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "bad operand type for unary ~: '" +
                  type_name_from_value(value) +
                  "'",
                ),
              )
          }
        }
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
      eval_binary_op_values(op, left_val, right_val, globals, builtins, io)
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
          let ok = match
            truthy_from_value_with_env(result, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match op {
            BoolOp::And => if !ok { return Ok(result) }
            BoolOp::Or => if ok { return Ok(result) }
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
      fn compare_sequence_values(
        left : Array[Value],
        right : Array[Value],
      ) -> Result[Int, RuntimeError] {
        let min_len = if left.length() < right.length() {
          left.length()
        } else {
          right.length()
        }
        for i = 0; i < min_len; i = i + 1 {
          if eq_value(left[i], right[i]) {
            continue
          }
          fn compare_ordered(
            a : Value,
            b : Value,
          ) -> Result[Int, RuntimeError] {
            if eq_value(a, b) {
              return Ok(0)
            }
            match (a, b) {
              (Value::Str(x), Value::Str(y)) => Ok(if x < y { -1 } else { 1 })
              (Value::Tuple(xs), Value::Tuple(ys)) =>
                compare_sequence_values(xs, ys)
              (Value::List(xs), Value::List(ys)) =>
                compare_sequence_values(xs, ys)
              _ => {
                let (_, left_num) = match number_value(a) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let (_, right_num) = match number_value(b) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                Ok(if left_num < right_num { -1 } else { 1 })
              }
            }
          }

          return compare_ordered(left[i], right[i])
        }
        if left.length() == right.length() {
          Ok(0)
        } else if left.length() < right.length() {
          Ok(-1)
        } else {
          Ok(1)
        }
      }

      let mut previous = match
        eval_expr_with_env(left, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      fn is_intrinsic_default_compare(
        method_value : Value,
        name : String,
      ) -> Bool {
        match method_value {
          Value::BoundMethod(bound) =>
            bound.function.name == name && bound.function.body.length() == 0
          Value::Function(func) => func.name == name && func.body.length() == 0
          _ => false
        }
      }

      fn call_compare_method(
        target : Value,
        method_name : String,
        other : Value,
      ) -> Result[Value?, RuntimeError] {
        if !(target is Value::Instance(_)) {
          return Ok(None)
        }
        let candidate = match
          get_attr_from_value(target, method_name, globals, builtins, io) {
          Ok(v) => v
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => return Ok(None)
              _ => return Err(err)
            }
        }
        if is_intrinsic_default_compare(candidate, method_name) {
          return Ok(None)
        }
        match
          call_callable_with_env(candidate, [other], [], globals, builtins, io) {
          Ok(v) => Ok(Some(v))
          Err(err) => Err(err)
        }
      }

      fn eq_bool(left : Value, right : Value) -> Result[Bool, RuntimeError] {
        match call_compare_method(left, "__eq__", right) {
          Ok(Some(value)) => Ok(bool_from_value(value))
          Ok(None) =>
            match call_compare_method(right, "__eq__", left) {
              Ok(Some(value)) => Ok(bool_from_value(value))
              Ok(None) => Ok(eq_value(left, right))
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      }

      fn ne_bool(left : Value, right : Value) -> Result[Bool, RuntimeError] {
        match call_compare_method(left, "__ne__", right) {
          Ok(Some(value)) => Ok(bool_from_value(value))
          Ok(None) =>
            match call_compare_method(right, "__ne__", left) {
              Ok(Some(value)) => Ok(bool_from_value(value))
              Ok(None) =>
                match eq_bool(left, right) {
                  Ok(v) => Ok(!v)
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      }

      for i = 0; i < ops.length(); i = i + 1 {
        let current = match
          eval_expr_with_env(comparators[i], locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let ok = match ops[i] {
          CompareOp::Eq =>
            match eq_bool(previous, current) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
          CompareOp::NotEq =>
            match ne_bool(previous, current) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
          CompareOp::Lt =>
            match (previous, current) {
              (Value::Tuple(left), Value::Tuple(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp < 0
                  Err(err) => return Err(err)
                }
              (Value::List(left), Value::List(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp < 0
                  Err(err) => return Err(err)
                }
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in left {
                  let hit = match set_find_index(right, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok && left.length() < right.length()
              }
              (Value::Str(left), Value::Str(right)) => left < right
              _ => {
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
            }
          CompareOp::Lte =>
            match (previous, current) {
              (Value::Tuple(left), Value::Tuple(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp <= 0
                  Err(err) => return Err(err)
                }
              (Value::List(left), Value::List(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp <= 0
                  Err(err) => return Err(err)
                }
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in left {
                  let hit = match set_find_index(right, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok
              }
              (Value::Str(left), Value::Str(right)) => left <= right
              _ => {
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
            }
          CompareOp::Gt =>
            match (previous, current) {
              (Value::Tuple(left), Value::Tuple(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp > 0
                  Err(err) => return Err(err)
                }
              (Value::List(left), Value::List(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp > 0
                  Err(err) => return Err(err)
                }
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in right {
                  let hit = match set_find_index(left, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok && left.length() > right.length()
              }
              (Value::Str(left), Value::Str(right)) => left > right
              _ => {
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
            }
          CompareOp::Gte =>
            match (previous, current) {
              (Value::Tuple(left), Value::Tuple(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp >= 0
                  Err(err) => return Err(err)
                }
              (Value::List(left), Value::List(right)) =>
                match compare_sequence_values(left, right) {
                  Ok(cmp) => cmp >= 0
                  Err(err) => return Err(err)
                }
              (Value::Set(left), Value::Set(right)) => {
                let mut ok = true
                for item in right {
                  let hit = match set_find_index(left, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if hit is None {
                    ok = false
                    break
                  }
                }
                ok
              }
              (Value::Str(left), Value::Str(right)) => left >= right
              _ => {
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
            }
          CompareOp::Is =>
            match (previous, current) {
              (Value::Function(a), Value::Function(b)) => a.name == b.name
              _ => eq_value(previous, current)
            }
          CompareOp::IsNot =>
            match (previous, current) {
              (Value::Function(a), Value::Function(b)) => a.name != b.name
              _ => !eq_value(previous, current)
            }
          CompareOp::In =>
            match current {
              Value::List(values) | Value::Tuple(values) => {
                let mut found = false
                for item in values {
                  if eq_value(item, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Set(values) =>
                match set_find_index(values, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Bytes(bytes)
              | Value::ByteArray(bytes)
              | Value::MemoryView(bytes) => bytes_contains(bytes, previous)
              Value::Dict(pairs) =>
                match dict_find_index(pairs, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Str(text) =>
                match previous {
                  Value::Str(needle) => text.contains(needle)
                  _ => false
                }
              _ =>
                // 1) Prefer `__contains__` when available.
                match current {
                  Value::Instance(_) =>
                    match
                      get_attr_from_value(
                        current, "__contains__", globals, builtins, io,
                      ) {
                      Ok(contains_method) => {
                        let result = match
                          call_callable_with_env(
                            contains_method,
                            [previous],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        bool_from_value(result)
                      }
                      Err(err) =>
                        match err.kind {
                          RuntimeErrorKind::Attribute => {
                            // Fall back to iteration.
                            let iterator = match
                              iter_value_to_iterator(
                                current, globals, builtins, io,
                              ) {
                              Ok(v) => v
                              Err(e) => return Err(e)
                            }
                            let mut found = false
                            while true {
                              match
                                iterator_next(
                                  iterator,
                                  None,
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(item) =>
                                  if eq_value(item, previous) {
                                    found = true
                                    break
                                  }
                                Err(e) =>
                                  if e.exc_type == "StopIteration" {
                                    break
                                  } else {
                                    return Err(e)
                                  }
                              }
                            }
                            found
                          }
                          _ => return Err(err)
                        }
                    }
                  _ => {
                    let iterator = match
                      iter_value_to_iterator(current, globals, builtins, io) {
                      Ok(v) => v
                      Err(e) => return Err(e)
                    }
                    let mut found = false
                    while true {
                      match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(item) =>
                          if eq_value(item, previous) {
                            found = true
                            break
                          }
                        Err(e) =>
                          if e.exc_type == "StopIteration" {
                            break
                          } else {
                            return Err(e)
                          }
                      }
                    }
                    found
                  }
                }
            }
          CompareOp::NotIn =>
            !(match current {
              Value::List(values) | Value::Tuple(values) => {
                let mut found = false
                for item in values {
                  if eq_value(item, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Set(values) =>
                match set_find_index(values, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Bytes(bytes)
              | Value::ByteArray(bytes)
              | Value::MemoryView(bytes) => bytes_contains(bytes, previous)
              Value::Dict(pairs) =>
                match dict_find_index(pairs, previous) {
                  Ok(index) => index is Some(_)
                  Err(err) => return Err(err)
                }
              Value::Str(text) =>
                match previous {
                  Value::Str(needle) => text.contains(needle)
                  _ => false
                }
              _ =>
                match current {
                  Value::Instance(_) =>
                    match
                      get_attr_from_value(
                        current, "__contains__", globals, builtins, io,
                      ) {
                      Ok(contains_method) => {
                        let result = match
                          call_callable_with_env(
                            contains_method,
                            [previous],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        bool_from_value(result)
                      }
                      Err(err) =>
                        match err.kind {
                          RuntimeErrorKind::Attribute => {
                            let iterator = match
                              iter_value_to_iterator(
                                current, globals, builtins, io,
                              ) {
                              Ok(v) => v
                              Err(e) => return Err(e)
                            }
                            let mut found = false
                            while true {
                              match
                                iterator_next(
                                  iterator,
                                  None,
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(item) =>
                                  if eq_value(item, previous) {
                                    found = true
                                    break
                                  }
                                Err(e) =>
                                  if e.exc_type == "StopIteration" {
                                    break
                                  } else {
                                    return Err(e)
                                  }
                              }
                            }
                            found
                          }
                          _ => return Err(err)
                        }
                    }
                  _ => {
                    let iterator = match
                      iter_value_to_iterator(current, globals, builtins, io) {
                      Ok(v) => v
                      Err(e) => return Err(e)
                    }
                    let mut found = false
                    while true {
                      match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(item) =>
                          if eq_value(item, previous) {
                            found = true
                            break
                          }
                        Err(e) =>
                          if e.exc_type == "StopIteration" {
                            break
                          } else {
                            return Err(e)
                          }
                      }
                    }
                    found
                  }
                }
            })
        }
        if !ok {
          return Ok(Value::Bool(false))
        }
        previous = current
      }
      Ok(Value::Bool(true))
    }
    Expr::Call(callee~, args~) =>
      match callee {
        Expr::Attribute(value~, attr~) =>
          if attr == "join" {
            let sep_value = match
              eval_expr_with_env(value, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match sep_value {
              Value::Str(sep) => {
                if args.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "join() takes exactly one argument".to_string(),
                    ),
                  )
                }
                let iter_value = match
                  eval_expr_with_env(args[0], locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let parts : Array[String] = []
                match iter_value {
                  Value::List(values) =>
                    for v in values {
                      parts.push(value_to_string(v))
                    }
                  Value::Tuple(values) =>
                    for v in values {
                      parts.push(value_to_string(v))
                    }
                  Value::Set(values) =>
                    for v in values {
                      parts.push(value_to_string(v))
                    }
                  _ =>
                    match iterable_values(iter_value) {
                      Ok(values) =>
                        for v in values {
                          parts.push(value_to_string(v))
                        }
                      Err(_) =>
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Type,
                            "can only join an iterable".to_string(),
                          ),
                        )
                    }
                }
                let buf = StringBuilder::new()
                for i = 0; i < parts.length(); i = i + 1 {
                  if i > 0 {
                    buf.write_string(sep)
                  }
                  buf.write_string(parts[i])
                }
                Ok(Value::Str(buf.to_string()))
              }
              _ => {
                let callee_value = match
                  get_attr_from_value(sep_value, attr, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                let (arg_values, keywords) = match
                  eval_call_args(args, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                match callee_value {
                  Value::Function(func) =>
                    if func.body.length() == 0 {
                      match
                        eval_builtin_call(
                          func.name,
                          arg_values,
                          keywords,
                          locals,
                          globals,
                          builtins,
                          io,
                        ) {
                        Ok(Some(value)) => Ok(value)
                        Ok(None) =>
                          call_callable_with_env(
                            callee_value, arg_values, keywords, globals, builtins,
                            io,
                          )
                        Err(err) => Err(err)
                      }
                    } else {
                      call_callable_with_env(
                        callee_value, arg_values, keywords, globals, builtins, io,
                      )
                    }
                  _ =>
                    call_callable_with_env(
                      callee_value, arg_values, keywords, globals, builtins, io,
                    )
                }
              }
            }
          } else {
            let callee_value = match
              eval_expr_with_env(
                Expr::Attribute(value~, attr~),
                locals,
                globals,
                builtins,
                io,
              ) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let (arg_values, keywords) = match
              eval_call_args(args, locals, globals, builtins, io) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            match callee_value {
              Value::Function(func) =>
                if func.body.length() == 0 {
                  match
                    eval_builtin_call(
                      func.name,
                      arg_values,
                      keywords,
                      locals,
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(Some(value)) => Ok(value)
                    Ok(None) =>
                      call_callable_with_env(
                        callee_value, arg_values, keywords, globals, builtins, io,
                      )
                    Err(err) => Err(err)
                  }
                } else {
                  call_callable_with_env(
                    callee_value, arg_values, keywords, globals, builtins, io,
                  )
                }
              _ =>
                call_callable_with_env(
                  callee_value, arg_values, keywords, globals, builtins, io,
                )
            }
          }
        Expr::Name(name) => {
          let callee_value = match
            lookup_name_value(name, locals, globals, builtins) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match callee_value {
            Value::Function(func) =>
              if func.body.length() == 0 {
                let (arg_values, keywords) = match
                  eval_call_args(args, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                match
                  eval_builtin_call(
                    func.name,
                    arg_values,
                    keywords,
                    locals,
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(Some(value)) => Ok(value)
                  Ok(None) =>
                    call_callable_with_env(
                      callee_value, arg_values, keywords, globals, builtins, io,
                    )
                  Err(err) => Err(err)
                }
              } else {
                let (arg_values, keywords) = match
                  eval_call_args(args, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                call_callable_with_env(
                  callee_value, arg_values, keywords, globals, builtins, io,
                )
              }
            _ => {
              let (arg_values, keywords) = match
                eval_call_args(args, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              call_callable_with_env(
                callee_value, arg_values, keywords, globals, builtins, io,
              )
            }
          }
        }
        _ => {
          let callee_value = match
            eval_expr_with_env(callee, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (arg_values, keywords) = match
            eval_call_args(args, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          call_callable_with_env(
            callee_value, arg_values, keywords, globals, builtins, io,
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
