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
            shadow_local_cell(comp_locals, name, Value::None)
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
            shadow_local_cell(comp_locals, name, Value::None)
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
            shadow_local_cell(comp_locals, name, Value::None)
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
            Value::Instance(inst) => {
              match get_named_value(inst.dict, list_storage_name) {
                Some(Value::List(values)) => return slice_list(values)
                _ => ()
              }
              match get_named_value(inst.dict, tuple_storage_name) {
                Some(Value::Tuple(values)) => {
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
                  return Ok(
                    Value::Tuple(slice_values_by_indices(values, indices)),
                  )
                }
                _ => ()
              }
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
              // In CPython, memoryview slices with a non-unit step are typically
              // non-contiguous. Some stdlib consumers (e.g. `binascii`) require
              // a C-contiguous buffer and raise BufferError for such views.
              let step_bigint = match step_value {
                Value::None => 1N
                Value::Int(v) => v
                Value::Bool(v) => if v { 1N } else { 0N }
                _ => 1N
              }
              let sliced = Value::MemoryView(
                slice_ints_by_indices(bytes, indices),
              )
              if step_bigint != 1N {
                let dict : Array[(String, Value)] = [
                  ("__mpython_bytes__", sliced),
                  ("__mpython_contiguous__", Value::Bool(false)),
                ]
                Ok(
                  Value::Instance(InstanceValue::{
                    class: builtin_class_from_name("memoryview", builtins),
                    dict,
                  }),
                )
              } else {
                Ok(sliced)
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
                    Value::Class(_) => [target, idx_value]
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
                    let step_bigint = match step_value {
                      Value::None => 1N
                      Value::Int(v) => v
                      Value::Bool(v) => if v { 1N } else { 0N }
                      _ => 1N
                    }
                    let sliced = Value::MemoryView(
                      slice_ints_by_indices(bytes, indices),
                    )
                    if step_bigint != 1N {
                      let dict : Array[(String, Value)] = [
                        ("__mpython_bytes__", sliced),
                        ("__mpython_contiguous__", Value::Bool(false)),
                      ]
                      Ok(
                        Value::Instance(InstanceValue::{
                          class: builtin_class_from_name("memoryview", builtins),
                          dict,
                        }),
                      )
                    } else {
                      Ok(sliced)
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
                      match get_named_value(inst.dict, tuple_storage_name) {
                        Some(Value::Tuple(values)) => {
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
                        _ =>
                          Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "subscript requires sequence".to_string(),
                            ),
                          )
                      }
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
            Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
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
            Value::Bool(v) => {
              // CPython 3.13+: `~bool` is deprecated.
              let import_value = match get_named_value(builtins, "__import__") {
                Some(v) => v
                None =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "missing builtins.__import__".to_string(),
                    ),
                  )
              }
              let warnings_module = match
                call_callable_with_env(
                  import_value,
                  [Value::Str("warnings")],
                  [],
                  globals,
                  builtins,
                  io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              let warn_fn = match
                get_attr_from_value(
                  warnings_module, "warn", globals, builtins, io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              let category = match
                get_named_value(builtins, "DeprecationWarning") {
                Some(Value::Class(k)) => Value::Class(k)
                _ => Value::None
              }
              let _ = match
                call_callable_with_env(
                  warn_fn,
                  [
                    Value::Str(
                      "Bitwise inversion on bool is deprecated".to_string(),
                    ),
                    category,
                    Value::Int(2N),
                  ],
                  [],
                  globals,
                  builtins,
                  io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              Ok(Value::Int(-((if v { 1N } else { 0N }) + 1N)))
            }
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
        let ok = match
          compare_values_with_env(
            ops[i],
            previous,
            current,
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
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
                let iterator_value = match
                  iter_value_to_iterator(iter_value, globals, builtins, io) {
                  Ok(v) => v
                  Err(_) =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "can only join an iterable".to_string(),
                      ),
                    )
                }
                let buf = StringBuilder::new()
                let mut first = true
                while true {
                  match
                    iterator_next(iterator_value, None, globals, builtins, io) {
                    Ok(item) => {
                      let part = match item {
                        Value::Str(text) => text
                        other => value_to_string(other)
                      }
                      if first {
                        first = false
                      } else {
                        buf.write_string(sep)
                      }
                      buf.write_string(part)
                    }
                    Err(err) =>
                      if err.exc_type == "StopIteration" {
                        break
                      } else {
                        return Err(err)
                      }
                  }
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
