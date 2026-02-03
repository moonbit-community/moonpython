///|
/// AST -> bytecode compiler.
///
/// This starts as a minimal compiler and is extended feature-by-feature until
/// it covers the full surface area that the old AST-walking evaluator supports.

///|
fn literal_to_value(lit : Literal) -> Value {
  match lit {
    Literal::None => Value::None
    Literal::Bool(v) => Value::Bool(v)
    Literal::Int(v) => Value::Int(v)
    Literal::Float(v) => Value::Float(v)
    Literal::Complex(r, i) => Value::Complex(r, i)
    Literal::Str(v) => Value::Str(v)
    Literal::Bytes(v) => Value::Bytes(v)
  }
}

///|
priv struct LoopCtx {
  has_iter : Bool
  break_jumps : Array[Int]
  continue_jumps : Array[Int]
  finally_depth : Int
}

///|
fn compile_expr(
  expr : Expr,
  b : BcBuilder,
  span : Span?,
) -> Result[Unit, RuntimeError] {
  match expr {
    Expr::WithSpan(span=new_span, expr=inner) =>
      // Prefer the expression's own span when available.
      compile_expr(inner, b, Some(new_span))
    Expr::Literal(lit) => {
      let idx = b.add_const(literal_to_value(lit))
      let _ = b.emit(BcOp::LoadConst(idx), span)
      Ok(())
    }
    Expr::Name(name) => {
      let idx = b.intern_name(name)
      let _ = b.emit(BcOp::LoadName(idx), span)
      Ok(())
    }
    Expr::FString(text) => {
      let idx = b.add_const(Value::Str(text))
      let _ = b.emit(BcOp::LoadConst(idx), span)
      let _ = b.emit(BcOp::EvalFString, span)
      Ok(())
    }
    Expr::NamedExpr(name~, value~) => {
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::DupTop, span)
      let name_idx = b.intern_name(name)
      let _ = b.emit(BcOp::StoreName(name_idx), span)
      Ok(())
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) => {
      match compile_expr(condition, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let j_else = b.emit(BcOp::JumpIfFalse(-1), span)
      match compile_expr(then_expr, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let j_end = b.emit(BcOp::Jump(-1), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_else, else_pc)
      match compile_expr(else_expr, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let end_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_end, end_pc)
      Ok(())
    }
    Expr::Unary(op~, expr~) => {
      match compile_expr(expr, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::Unary(op), span)
      Ok(())
    }
    Expr::Binary(op~, left~, right~) => {
      match compile_expr(left, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match compile_expr(right, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::Binary(op), span)
      Ok(())
    }
    Expr::BoolOp(op~, values~) => {
      if values.length() == 0 {
        let idx = b.add_const(Value::Bool(true))
        let _ = b.emit(BcOp::LoadConst(idx), span)
        return Ok(())
      }
      match compile_expr(values[0], b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let jumps : Array[Int] = []
      for i = 1; i < values.length(); i = i + 1 {
        let j = match op {
          BoolOp::And => b.emit(BcOp::JumpIfFalseOrPop(-1), span)
          BoolOp::Or => b.emit(BcOp::JumpIfTrueOrPop(-1), span)
        }
        jumps.push(j)
        match compile_expr(values[i], b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let end_pc = b.code.ops.length()
      for pc in jumps {
        bc_patch_jump(b.code, pc, end_pc)
      }
      Ok(())
    }
    Expr::Lambda(params~, defaults~, body~) => {
      // Keep evaluation order aligned with CPython: defaults are evaluated left-to-right
      // at lambda creation time.
      for def_expr in defaults {
        match compile_expr(def_expr, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
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
      let template = FunctionValue::{
        name: "<lambda>".to_string(),
        params,
        defaults: [],
        body: func_body,
        is_generator,
        is_async: false,
        closure: [],
      }
      let template_idx = b.add_const(Value::Function(template))
      let _ = b.emit(
        BcOp::MakeFunction(template_idx, defaults.length(), 0),
        span,
      )
      Ok(())
    }
    Expr::Compare(left~, ops~, comparators~) => {
      if ops.length() != comparators.length() {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "bytecode compiler: invalid compare node".to_string(),
          ),
        )
      }
      if ops.length() == 0 {
        let idx = b.add_const(Value::Bool(true))
        let _ = b.emit(BcOp::LoadConst(idx), span)
        return Ok(())
      }
      match compile_expr(left, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match compile_expr(comparators[0], b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      if ops.length() == 1 {
        let _ = b.emit(BcOp::Compare(ops[0]), span)
        return Ok(())
      }
      let fail_jumps : Array[Int] = []
      for i = 0; i < ops.length(); i = i + 1 {
        let op = ops[i]
        if i < ops.length() - 1 {
          // Stack: [prev, cur]
          // -> duplicate cur and rotate so we can compare prev/cur while keeping cur:
          //    [prev, cur] -> [prev, cur, cur] -> [cur, prev, cur]
          let _ = b.emit(BcOp::DupTop, span)
          let _ = b.emit(BcOp::RotThree, span)
          let _ = b.emit(BcOp::Compare(op), span)
          // On failure: JumpIfFalse consumes the bool and jumps, leaving [cur] on the stack.
          let j_fail = b.emit(BcOp::JumpIfFalse(-1), span)
          fail_jumps.push(j_fail)
          match compile_expr(comparators[i + 1], b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        } else {
          let _ = b.emit(BcOp::Compare(op), span)

        }
      }
      let j_done = b.emit(BcOp::Jump(-1), span)
      let fail_pc = b.code.ops.length()
      for pc in fail_jumps {
        bc_patch_jump(b.code, pc, fail_pc)
      }
      let _ = b.emit(BcOp::PopTop, span)
      let false_idx = b.add_const(Value::Bool(false))
      let _ = b.emit(BcOp::LoadConst(false_idx), span)
      let done_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_done, done_pc)
      Ok(())
    }
    Expr::Call(callee~, args~) => {
      let mut has_star = false
      for arg in args {
        match arg {
          Expr::Starred(_) | Expr::DoubleStarred(_) => {
            has_star = true
            break
          }
          _ => ()
        }
      }
      if !has_star {
        let pos_args : Array[Expr] = []
        let kw_names : Array[String] = []
        let kw_values : Array[Expr] = []
        for arg in args {
          match arg {
            Expr::Keyword(name~, value~) => {
              kw_names.push(name)
              kw_values.push(value)
            }
            Expr::Starred(_) | Expr::DoubleStarred(_) => ()
            _ => pos_args.push(arg)
          }
        }
        match compile_expr(callee, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        for arg in pos_args {
          match compile_expr(arg, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        for value in kw_values {
          match compile_expr(value, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        if kw_names.length() == 0 {
          let _ = b.emit(BcOp::CallFunction(pos_args.length()), span)

        } else {
          let name_values : Array[Value] = []
          for name in kw_names {
            name_values.push(Value::Str(name))
          }
          let kw_tuple_idx = b.add_const(Value::Tuple(name_values))
          let _ = b.emit(BcOp::LoadConst(kw_tuple_idx), span)
          let _ = b.emit(BcOp::CallFunctionKw(pos_args.length()), span)

        }
        Ok(())
      } else {
        // Fallback to MicroPython-style "CALL_FUNCTION_EX"-like path:
        // build expanded positional list + keyword-pair list, then call.
        match compile_expr(callee, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let _ = b.emit(BcOp::BuildList(0), span) // positional
        let _ = b.emit(BcOp::BuildList(0), span) // keyword pairs (name,value tuples)
        for arg in args {
          match arg {
            Expr::Keyword(name~, value~) => {
              let name_idx = b.add_const(Value::Str(name))
              let _ = b.emit(BcOp::LoadConst(name_idx), span)
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::BuildTuple(2), span)
              let _ = b.emit(BcOp::ListAppend, span)

            }
            Expr::DoubleStarred(value~) => {
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::KwListExtendFromDict, span)

            }
            Expr::Starred(value~) => {
              // Swap keyword list / positional list to make positional list the target.
              let _ = b.emit(BcOp::RotTwo, span)
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::ListExtend, span)
              let _ = b.emit(BcOp::RotTwo, span)

            }
            _ => {
              let _ = b.emit(BcOp::RotTwo, span)
              match compile_expr(arg, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::ListAppend, span)
              let _ = b.emit(BcOp::RotTwo, span)

            }
          }
        }
        let _ = b.emit(BcOp::CallFunctionVar, span)
        Ok(())
      }
    }
    Expr::Tuple(items) => {
      let mut has_star = false
      for item in items {
        match item {
          Expr::Starred(_) => {
            has_star = true
            break
          }
          _ => ()
        }
      }
      if !has_star {
        for item in items {
          match compile_expr(item, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        let _ = b.emit(BcOp::BuildTuple(items.length()), span)
        Ok(())
      } else {
        let _ = b.emit(BcOp::BuildList(0), span)
        for item in items {
          match item {
            Expr::Starred(value~) => {
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::ListExtend, span)

            }
            _ => {
              match compile_expr(item, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::ListAppend, span)

            }
          }
        }
        let _ = b.emit(BcOp::ListToTuple, span)
        Ok(())
      }
    }
    Expr::ListComp(elt~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async {
        let _ = b.emit(
          BcOp::CheckInCoroutineScope(
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
          span,
        )

      }
      let res_name = "__mpy_comp_res$" + b.code.ops.length().to_string()
      let res_init = Stmt::Assign(
        target=Target::Name(res_name),
        value=Expr::List([]),
      )

      // Build the innermost statement: res.append(elt)
      let append_stmt = Stmt::ExprStmt(
        Expr::Call(
          callee=Expr::Attribute(value=Expr::Name(res_name), attr="append"),
          args=[elt],
        ),
      )
      let mut inner : Array[Stmt] = [append_stmt]
      // Filters apply at the innermost level.
      for i = filters.length() - 1; i >= 0; i = i - 1 {
        inner = [Stmt::If(condition=filters[i], body=inner, else_body=[])]
        if i == 0 {
          break
        }
      }

      // Wrap nested `for` clauses from inside-out.
      fn make_unpack_assign_stmt(
        tmp : String,
        targets : Array[String],
      ) -> Stmt? {
        if targets.length() == 1 && targets[0] == "_" {
          return None
        }
        let items : Array[Target] = []
        for t in targets {
          if t == "_" {
            // '_' is treated as a wildcard in MoonPython's comprehension semantics.
            items.push(Target::Name("__mpy_comp_ignored$" + tmp))
          } else {
            items.push(Target::Name(t))
          }
        }
        let target = if items.length() == 1 {
          items[0]
        } else {
          Target::Tuple(items)
        }
        let assign = Stmt::Assign(target~, value=Expr::Name(tmp))
        if items.length() == 1 {
          Some(assign)
        } else {
          let handler_span = match span {
            Some(s) => s
            None => Span::{ start: 0, end: 1, line: 1, column: 1 }
          }
          let handler = ExceptHandler::{
            span: handler_span,
            is_star: false,
            exc: None,
            name: None,
            body: [
              Stmt::Raise(
                exc=Some(
                  Expr::Call(callee=Expr::Name("TypeError"), args=[
                    Expr::Literal(Literal::Str("cannot unpack")),
                  ]),
                ),
                cause=None,
              ),
            ],
          }
          Some(
            Stmt::Try(body=[assign], handlers=[handler], else_body=[], finally_body=[]),
          )
        }
      }

      for i = clauses.length() - 1; i >= 0; i = i - 1 {
        let clause = clauses[i]
        // When targets are "_" or unpacking, bind into a temp and then assign.
        let direct = clause.targets.length() == 1 && clause.targets[0] != "_"
        let loop_target : Target = if direct {
          Target::Name(clause.targets[0])
        } else {
          Target::Name(
            "__mpy_comp_it$" +
            b.code.ops.length().to_string() +
            "$" +
            i.to_string(),
          )
        }
        let body : Array[Stmt] = []
        if !direct {
          let tmp = match loop_target {
            Target::Name(n) => n
            _ => "__mpy_comp_it$".to_string()
          }
          match make_unpack_assign_stmt(tmp, clause.targets) {
            Some(assign_stmt) => body.push(assign_stmt)
            None => ()
          }
        }
        for s in inner {
          body.push(s)
        }
        inner = [
          if clause.is_async {
            Stmt::AsyncFor(target=loop_target, iter=clause.iter, body~, else_body=[])
          } else {
            Stmt::For(target=loop_target, iter=clause.iter, body~, else_body=[])
          },
        ]
        if i == 0 {
          break
        }
      }
      let func_body : Array[Stmt] = [res_init]
      for s in inner {
        func_body.push(s)
      }
      func_body.push(Stmt::Return(Some(Expr::Name(res_name))))
      let template = FunctionValue::{
        name: "<listcomp>".to_string(),
        params: [],
        defaults: [],
        body: func_body,
        is_generator: false,
        is_async: false,
        closure: [],
      }
      let template_idx = b.add_const(Value::Function(template))
      let _ = b.emit(BcOp::MakeFunction(template_idx, 0, 0), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      Ok(())
    }
    Expr::GenExp(elt~, clauses~, filters~) => {
      fn contains_await(expr : Expr) -> Bool {
        match expr {
          Expr::Await(_) => true
          Expr::List(items) | Expr::Tuple(items) | Expr::Set(items) =>
            for item in items {
              if contains_await(item) {
                return true
              }
            } else {
              false
            }
          Expr::Dict(items) =>
            for pair in items {
              if contains_await(pair.0) || contains_await(pair.1) {
                return true
              }
            } else {
              false
            }
          Expr::ListComp(elt~, clauses~, filters~)
          | Expr::GenExp(elt~, clauses~, filters~)
          | Expr::SetComp(elt~, clauses~, filters~) => {
            if contains_await(elt) {
              return true
            }
            for clause in clauses {
              if contains_await(clause.iter) {
                return true
              }
            }
            for filter in filters {
              if contains_await(filter) {
                return true
              }
            }
            false
          }
          Expr::DictComp(key~, value~, clauses~, filters~) => {
            if contains_await(key) || contains_await(value) {
              return true
            }
            for clause in clauses {
              if contains_await(clause.iter) {
                return true
              }
            }
            for filter in filters {
              if contains_await(filter) {
                return true
              }
            }
            false
          }
          Expr::IfExpr(condition~, then_expr~, else_expr~) =>
            contains_await(condition) ||
            contains_await(then_expr) ||
            contains_await(else_expr)
          Expr::NamedExpr(name~, value~) => {
            let _ = name
            contains_await(value)
          }
          Expr::Yield(expr_opt) =>
            match expr_opt {
              Some(v) => contains_await(v)
              None => false
            }
          Expr::YieldFrom(value) => contains_await(value)
          Expr::Slice(start~, end~, step~) => {
            match start {
              Some(v) => if contains_await(v) { return true }
              None => ()
            }
            match end {
              Some(v) => if contains_await(v) { return true }
              None => ()
            }
            match step {
              Some(v) => if contains_await(v) { return true }
              None => ()
            }
            false
          }
          Expr::Attribute(value~, attr~) => {
            let _ = attr
            contains_await(value)
          }
          Expr::Subscript(value~, index~) =>
            contains_await(value) || contains_await(index)
          Expr::Starred(value~) | Expr::DoubleStarred(value~) =>
            contains_await(value)
          Expr::Unary(op~, expr~) => {
            let _ = op
            contains_await(expr)
          }
          Expr::Binary(op~, left~, right~) => {
            let _ = op
            contains_await(left) || contains_await(right)
          }
          Expr::BoolOp(op~, values~) => {
            let _ = op
            for v in values {
              if contains_await(v) {
                return true
              }
            }
            false
          }
          Expr::Compare(left~, ops~, comparators~) => {
            let _ = ops
            if contains_await(left) {
              return true
            }
            for v in comparators {
              if contains_await(v) {
                return true
              }
            }
            false
          }
          Expr::Call(callee~, args~) =>
            if contains_await(callee) {
              true
            } else {
              for arg in args {
                if contains_await(arg) {
                  return true
                }
              }
              false
            }
          Expr::Keyword(name~, value~) => {
            let _ = name
            contains_await(value)
          }
          Expr::Lambda(params~, defaults~, body~) => {
            let _ = params
            for d in defaults {
              if contains_await(d) {
                return true
              }
            }
            contains_await(body)
          }
          _ => false
        }
      }

      let mut has_async_clause = false
      for clause in clauses {
        if clause.is_async {
          has_async_clause = true
          break
        }
      }
      let mut has_await = contains_await(elt)
      if !has_await {
        for clause in clauses {
          if contains_await(clause.iter) {
            has_await = true
            break
          }
        }
      }
      if !has_await {
        for f in filters {
          if contains_await(f) {
            has_await = true
            break
          }
        }
      }
      let is_async_genexp = has_async_clause || has_await
      if is_async_genexp && clauses.length() == 0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: invalid async generator expression".to_string(),
          ),
        )
      }
      let target_names : Array[Value] = []
      for clause in clauses {
        for name in clause.targets {
          if name != "_" {
            target_names.push(Value::Str(name))
          }
        }
      }
      let target_names_idx = b.add_const(Value::Tuple(target_names))
      if clauses.length() == 0 {
        // Synchronous genexp with no clauses is effectively a one-shot generator.
        let body = genexp_to_generator_body(elt, clauses, filters)
        let template = FunctionValue::{
          name: "<genexpr>".to_string(),
          params: [],
          defaults: [],
          body,
          is_generator: true,
          is_async: false,
          closure: [],
        }
        let template_idx = b.add_const(Value::Function(template))
        let _ = b.emit(
          BcOp::GenExpNew(template_idx, -1, target_names_idx),
          span,
        )
        Ok(())
      } else {
        // Evaluate the first iterator at generator-expression creation time.
        match compile_expr(clauses[0].iter, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        if clauses[0].is_async {
          let aiter_idx = b.intern_name("__aiter__")
          let _ = b.emit(BcOp::LoadAttr(aiter_idx), span)
          let _ = b.emit(BcOp::CallFunction(0), span)

        } else {
          let _ = b.emit(BcOp::GetIter, span)

        }
        let iter_name = "__mpy_genexp_iter$" + b.code.ops.length().to_string()
        let iter_name_idx = b.intern_name(iter_name)
        let adjusted : Array[CompClause] = []
        adjusted.push(CompClause::{
          is_async: clauses[0].is_async,
          targets: clauses[0].targets,
          iter: Expr::Name(iter_name),
        })
        for i = 1; i < clauses.length(); i = i + 1 {
          adjusted.push(clauses[i])
        }
        if is_async_genexp {
          let spec_idx = b.add_genexp(GenExpSpec::{
            elt,
            clauses: adjusted,
            filters,
          })
          let _ = b.emit(
            BcOp::AsyncGenExpNew(spec_idx, iter_name_idx, target_names_idx),
            span,
          )

        } else {
          let body = genexp_to_generator_body(elt, adjusted, filters)
          let template = FunctionValue::{
            name: "<genexpr>".to_string(),
            params: [],
            defaults: [],
            body,
            is_generator: true,
            is_async: false,
            closure: [],
          }
          let template_idx = b.add_const(Value::Function(template))
          let _ = b.emit(
            BcOp::GenExpNew(template_idx, iter_name_idx, target_names_idx),
            span,
          )

        }
        Ok(())
      }
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async {
        let _ = b.emit(
          BcOp::CheckInCoroutineScope(
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
          span,
        )

      }
      let res_name = "__mpy_comp_res$" + b.code.ops.length().to_string()
      // set comprehensions use a dedicated set object, independent of any `set` binding.
      // MoonPython's runtime does not have a literal empty-set node, so use `set()`.
      let res_init = Stmt::Assign(
        target=Target::Name(res_name),
        value=Expr::Call(callee=Expr::Name("set"), args=[]),
      )
      let add_stmt = Stmt::ExprStmt(
        Expr::Call(
          callee=Expr::Attribute(value=Expr::Name(res_name), attr="add"),
          args=[elt],
        ),
      )
      let mut inner : Array[Stmt] = [add_stmt]
      for i = filters.length() - 1; i >= 0; i = i - 1 {
        inner = [Stmt::If(condition=filters[i], body=inner, else_body=[])]
        if i == 0 {
          break
        }
      }
      fn make_unpack_assign_stmt(
        tmp : String,
        targets : Array[String],
      ) -> Stmt? {
        if targets.length() == 1 && targets[0] == "_" {
          return None
        }
        let items : Array[Target] = []
        for t in targets {
          if t == "_" {
            items.push(Target::Name("__mpy_comp_ignored$" + tmp))
          } else {
            items.push(Target::Name(t))
          }
        }
        let target = if items.length() == 1 {
          items[0]
        } else {
          Target::Tuple(items)
        }
        let assign = Stmt::Assign(target~, value=Expr::Name(tmp))
        if items.length() == 1 {
          Some(assign)
        } else {
          let handler_span = match span {
            Some(s) => s
            None => Span::{ start: 0, end: 1, line: 1, column: 1 }
          }
          let handler = ExceptHandler::{
            span: handler_span,
            is_star: false,
            exc: None,
            name: None,
            body: [
              Stmt::Raise(
                exc=Some(
                  Expr::Call(callee=Expr::Name("TypeError"), args=[
                    Expr::Literal(Literal::Str("cannot unpack")),
                  ]),
                ),
                cause=None,
              ),
            ],
          }
          Some(
            Stmt::Try(body=[assign], handlers=[handler], else_body=[], finally_body=[]),
          )
        }
      }

      for i = clauses.length() - 1; i >= 0; i = i - 1 {
        let clause = clauses[i]
        let direct = clause.targets.length() == 1 && clause.targets[0] != "_"
        let loop_target : Target = if direct {
          Target::Name(clause.targets[0])
        } else {
          Target::Name(
            "__mpy_comp_it$" +
            b.code.ops.length().to_string() +
            "$" +
            i.to_string(),
          )
        }
        let body : Array[Stmt] = []
        if !direct {
          let tmp = match loop_target {
            Target::Name(n) => n
            _ => "__mpy_comp_it$".to_string()
          }
          match make_unpack_assign_stmt(tmp, clause.targets) {
            Some(assign_stmt) => body.push(assign_stmt)
            None => ()
          }
        }
        for s in inner {
          body.push(s)
        }
        inner = [
          if clause.is_async {
            Stmt::AsyncFor(target=loop_target, iter=clause.iter, body~, else_body=[])
          } else {
            Stmt::For(target=loop_target, iter=clause.iter, body~, else_body=[])
          },
        ]
        if i == 0 {
          break
        }
      }
      let func_body : Array[Stmt] = [res_init]
      for s in inner {
        func_body.push(s)
      }
      func_body.push(Stmt::Return(Some(Expr::Name(res_name))))
      let template = FunctionValue::{
        name: "<setcomp>".to_string(),
        params: [],
        defaults: [],
        body: func_body,
        is_generator: false,
        is_async: false,
        closure: [],
      }
      let template_idx = b.add_const(Value::Function(template))
      let _ = b.emit(BcOp::MakeFunction(template_idx, 0, 0), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      Ok(())
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let mut has_async = false
      for clause in clauses {
        if clause.is_async {
          has_async = true
          break
        }
      }
      if has_async {
        let _ = b.emit(
          BcOp::CheckInCoroutineScope(
            "SyntaxError: 'async for' outside async function".to_string(),
          ),
          span,
        )

      }
      let res_name = "__mpy_comp_res$" + b.code.ops.length().to_string()
      let res_init = Stmt::Assign(
        target=Target::Name(res_name),
        value=Expr::Dict([]),
      )
      let set_stmt = Stmt::Assign(
        target=Target::Subscript(value=Expr::Name(res_name), index=key),
        value~,
      )
      let mut inner : Array[Stmt] = [set_stmt]
      for i = filters.length() - 1; i >= 0; i = i - 1 {
        inner = [Stmt::If(condition=filters[i], body=inner, else_body=[])]
        if i == 0 {
          break
        }
      }
      fn make_unpack_assign_stmt(
        tmp : String,
        targets : Array[String],
      ) -> Stmt? {
        if targets.length() == 1 && targets[0] == "_" {
          return None
        }
        let items : Array[Target] = []
        for t in targets {
          if t == "_" {
            items.push(Target::Name("__mpy_comp_ignored$" + tmp))
          } else {
            items.push(Target::Name(t))
          }
        }
        let target = if items.length() == 1 {
          items[0]
        } else {
          Target::Tuple(items)
        }
        let assign = Stmt::Assign(target~, value=Expr::Name(tmp))
        if items.length() == 1 {
          Some(assign)
        } else {
          let handler_span = match span {
            Some(s) => s
            None => Span::{ start: 0, end: 1, line: 1, column: 1 }
          }
          let handler = ExceptHandler::{
            span: handler_span,
            is_star: false,
            exc: None,
            name: None,
            body: [
              Stmt::Raise(
                exc=Some(
                  Expr::Call(callee=Expr::Name("TypeError"), args=[
                    Expr::Literal(Literal::Str("cannot unpack")),
                  ]),
                ),
                cause=None,
              ),
            ],
          }
          Some(
            Stmt::Try(body=[assign], handlers=[handler], else_body=[], finally_body=[]),
          )
        }
      }

      for i = clauses.length() - 1; i >= 0; i = i - 1 {
        let clause = clauses[i]
        let direct = clause.targets.length() == 1 && clause.targets[0] != "_"
        let loop_target : Target = if direct {
          Target::Name(clause.targets[0])
        } else {
          Target::Name(
            "__mpy_comp_it$" +
            b.code.ops.length().to_string() +
            "$" +
            i.to_string(),
          )
        }
        let body : Array[Stmt] = []
        if !direct {
          let tmp = match loop_target {
            Target::Name(n) => n
            _ => "__mpy_comp_it$".to_string()
          }
          match make_unpack_assign_stmt(tmp, clause.targets) {
            Some(assign_stmt) => body.push(assign_stmt)
            None => ()
          }
        }
        for s in inner {
          body.push(s)
        }
        inner = [
          if clause.is_async {
            Stmt::AsyncFor(target=loop_target, iter=clause.iter, body~, else_body=[])
          } else {
            Stmt::For(target=loop_target, iter=clause.iter, body~, else_body=[])
          },
        ]
        if i == 0 {
          break
        }
      }
      let func_body : Array[Stmt] = [res_init]
      for s in inner {
        func_body.push(s)
      }
      func_body.push(Stmt::Return(Some(Expr::Name(res_name))))
      let template = FunctionValue::{
        name: "<dictcomp>".to_string(),
        params: [],
        defaults: [],
        body: func_body,
        is_generator: false,
        is_async: false,
        closure: [],
      }
      let template_idx = b.add_const(Value::Function(template))
      let _ = b.emit(BcOp::MakeFunction(template_idx, 0, 0), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      Ok(())
    }
    Expr::List(items) => {
      let mut has_star = false
      for item in items {
        match item {
          Expr::Starred(_) => {
            has_star = true
            break
          }
          _ => ()
        }
      }
      if !has_star {
        for item in items {
          match compile_expr(item, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        let _ = b.emit(BcOp::BuildList(items.length()), span)
        Ok(())
      } else {
        let _ = b.emit(BcOp::BuildList(0), span)
        for item in items {
          match item {
            Expr::Starred(value~) => {
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::ListExtend, span)

            }
            _ => {
              match compile_expr(item, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::ListAppend, span)

            }
          }
        }
        Ok(())
      }
    }
    Expr::Dict(items) => {
      let mut has_double_star = false
      for pair in items {
        match pair.0 {
          Expr::DoubleStarred(_) => {
            has_double_star = true
            break
          }
          _ => ()
        }
      }
      if !has_double_star {
        for pair in items {
          match compile_expr(pair.0, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match compile_expr(pair.1, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        let _ = b.emit(BcOp::BuildMap(items.length()), span)
        Ok(())
      } else {
        // Build and update a dict to support `{**m, k: v}`.
        let _ = b.emit(BcOp::BuildMap(0), span)
        for pair in items {
          match pair.0 {
            Expr::DoubleStarred(value~) => {
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::DictUpdate, span)

            }
            _ => {
              match compile_expr(pair.0, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              match compile_expr(pair.1, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::DictSetItem, span)

            }
          }
        }
        Ok(())
      }
    }
    Expr::Set(items) => {
      let mut has_star = false
      for item in items {
        match item {
          Expr::Starred(_) => {
            has_star = true
            break
          }
          _ => ()
        }
      }
      if !has_star {
        for item in items {
          match compile_expr(item, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        let _ = b.emit(BcOp::BuildSet(items.length()), span)
        Ok(())
      } else {
        let _ = b.emit(BcOp::BuildSet(0), span)
        for item in items {
          match item {
            Expr::Starred(value~) => {
              match compile_expr(value, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::SetUpdate, span)

            }
            _ => {
              match compile_expr(item, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::SetAdd, span)

            }
          }
        }
        Ok(())
      }
    }
    Expr::Attribute(value~, attr~) => {
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let idx = b.intern_name(attr)
      let _ = b.emit(BcOp::LoadAttr(idx), span)
      Ok(())
    }
    Expr::Subscript(value~, index~) => {
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match compile_expr(index, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::LoadSubscr, span)
      Ok(())
    }
    Expr::Await(expr) => {
      match compile_expr(expr, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::Await, span)
      Ok(())
    }
    Expr::Slice(start~, end~, step~) => {
      match start {
        Some(expr) =>
          match compile_expr(expr, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => {
          let idx = b.add_const(Value::None)
          let _ = b.emit(BcOp::LoadConst(idx), span)

        }
      }
      match end {
        Some(expr) =>
          match compile_expr(expr, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => {
          let idx = b.add_const(Value::None)
          let _ = b.emit(BcOp::LoadConst(idx), span)

        }
      }
      match step {
        Some(expr) =>
          match compile_expr(expr, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => {
          let idx = b.add_const(Value::None)
          let _ = b.emit(BcOp::LoadConst(idx), span)

        }
      }
      let _ = b.emit(BcOp::BuildSlice, span)
      Ok(())
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "bytecode compiler: expr not implemented".to_string(),
        ),
      )
  }
}

///|
fn compile_target_store(
  target : Target,
  b : BcBuilder,
  span : Span?,
) -> Result[Unit, RuntimeError] {
  match target {
    Target::Name(name) => {
      let idx = b.intern_name(name)
      let _ = b.emit(BcOp::StoreName(idx), span)
      Ok(())
    }
    Target::Attribute(value~, attr~) => {
      // Assignment target where the assigned value is already on the stack.
      // Emit:
      //   <value> <obj> -> <obj> <value> -> STORE_ATTR
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::RotTwo, span)
      let idx = b.intern_name(attr)
      let _ = b.emit(BcOp::StoreAttr(idx), span)
      Ok(())
    }
    Target::Subscript(value~, index~) => {
      // Assignment target where the assigned value is already on the stack.
      // Emit:
      //   <value> <obj> <idx> -> <obj> <idx> <value> -> STORE_SUBSCR
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match compile_expr(index, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::RotThree, span)
      let _ = b.emit(BcOp::RotThree, span)
      let _ = b.emit(BcOp::StoreSubscr, span)
      Ok(())
    }
    Target::Tuple(items) | Target::List(items) => {
      let mut star_idx : Int? = None
      for i = 0; i < items.length(); i = i + 1 {
        match items[i] {
          Target::Starred(_) =>
            match star_idx {
              Some(_) =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "SyntaxError: two starred expressions in assignment".to_string(),
                  ),
                )
              None => star_idx = Some(i)
            }
          _ => ()
        }
      }
      match star_idx {
        Some(si) => {
          let before = si
          let after = items.length() - si - 1
          let _ = b.emit(BcOp::UnpackEx(before, after), span)
          for item in items {
            match item {
              Target::Starred(inner) =>
                match compile_target_store(inner, b, span) {
                  Ok(_) => ()
                  Err(err) => return Err(err)
                }
              _ =>
                match compile_target_store(item, b, span) {
                  Ok(_) => ()
                  Err(err) => return Err(err)
                }
            }
          }
          Ok(())
        }
        None => {
          let _ = b.emit(BcOp::UnpackSequence(items.length()), span)
          for item in items {
            match compile_target_store(item, b, span) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
          }
          Ok(())
        }
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "bytecode compiler: complex assignment target not implemented".to_string(),
        ),
      )
  }
}

///|
fn compile_target_delete(
  target : Target,
  b : BcBuilder,
  span : Span?,
) -> Result[Unit, RuntimeError] {
  match target {
    Target::Name(name) => {
      let idx = b.intern_name(name)
      let _ = b.emit(BcOp::DeleteName(idx), span)
      Ok(())
    }
    Target::Starred(_) =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "SyntaxError: can't use starred expression here".to_string(),
        ),
      )
    Target::Tuple(items) | Target::List(items) => {
      for item in items {
        match compile_target_delete(item, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(())
    }
    Target::Attribute(value~, attr~) => {
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let idx = b.intern_name(attr)
      let _ = b.emit(BcOp::DeleteAttr(idx), span)
      Ok(())
    }
    Target::Subscript(value~, index~) => {
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match compile_expr(index, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::DeleteSubscr, span)
      Ok(())
    }
  }
}

///|
fn compile_try_except_else(
  body : Array[Stmt],
  handlers : Array[ExceptHandler],
  else_body : Array[Stmt],
  b : BcBuilder,
  span : Span?,
  loop_stack : Ref[Array[LoopCtx]],
  finally_depth : Int,
  future_annotations : Bool,
) -> Result[Unit, RuntimeError] {
  fn caretless_span(span : Span?) -> Span? {
    match span {
      Some(s) =>
        // Suppress PEP 657 caret rendering for internal exception-dispatch spans.
        // We still keep the correct line/column, but force end_column == 0 by
        // making the span width exceed the caret cutoff.
        Some(Span::{
          start: s.start,
          end: s.start + 1024,
          line: s.line,
          column: s.column,
        })
      None => None
    }
  }

  fn validate_except_star_body(
    body : Array[Stmt],
    loop_depth : Int,
    in_nested_def : Bool,
  ) -> Result[Unit, RuntimeError] {
    for stmt in body {
      match stmt {
        Stmt::WithSpan(span=_, stmt=inner) =>
          match validate_except_star_body([inner], loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        Stmt::Break | Stmt::Continue =>
          if !in_nested_def && loop_depth == 0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "SyntaxError: 'break', 'continue' and 'return' cannot appear in an except* block".to_string(),
              ),
            )
          }
        Stmt::Return(_) =>
          if !in_nested_def {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "SyntaxError: 'break', 'continue' and 'return' cannot appear in an except* block".to_string(),
              ),
            )
          }
        Stmt::Function(
          name=_,
          decorators=_,
          type_params=_,
          params=_,
          defaults=_,
          annotations=_,
          return_annotation=_,
          body=nested_body,
          is_generator=_,
          is_async=_
        ) =>
          // Nested function bodies are allowed to use return/break/continue.
          match validate_except_star_body(nested_body, 0, true) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        Stmt::Class(
          name=_,
          decorators=_,
          type_params=_,
          bases=_,
          keywords=_,
          body=nested_body
        ) =>
          // Nested class bodies are allowed to contain nested defs/loops.
          match validate_except_star_body(nested_body, 0, true) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        Stmt::If(condition=_, body=if_body, else_body~) => {
          match validate_except_star_body(if_body, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match
            validate_except_star_body(else_body, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        Stmt::While(condition=_, body=while_body, else_body=while_else) => {
          match
            validate_except_star_body(while_body, loop_depth + 1, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match
            validate_except_star_body(while_else, loop_depth + 1, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        Stmt::For(target=_, iter=_, body=for_body, else_body=for_else) => {
          match
            validate_except_star_body(for_body, loop_depth + 1, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match
            validate_except_star_body(for_else, loop_depth + 1, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        Stmt::AsyncFor(target=_, iter=_, body=for_body, else_body=for_else) => {
          match
            validate_except_star_body(for_body, loop_depth + 1, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match
            validate_except_star_body(for_else, loop_depth + 1, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        Stmt::With(context=_, target=_, body=with_body) =>
          match
            validate_except_star_body(with_body, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        Stmt::AsyncWith(context=_, target=_, body=with_body) =>
          match
            validate_except_star_body(with_body, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        Stmt::Try(
          body=try_body,
          handlers=try_handlers,
          else_body=try_else,
          finally_body=try_finally
        ) => {
          match validate_except_star_body(try_body, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          for handler in try_handlers {
            match
              validate_except_star_body(handler.body, loop_depth, in_nested_def) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
          }
          match validate_except_star_body(try_else, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match
            validate_except_star_body(try_finally, loop_depth, in_nested_def) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        Stmt::Match(subject=_, cases=match_cases) =>
          for case in match_cases {
            let case_body = case.2
            match
              validate_except_star_body(case_body, loop_depth, in_nested_def) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
          }
        _ => ()
      }
    }
    Ok(())
  }

  let mut has_star = false
  let mut first_star_span : Span? = None
  for handler in handlers {
    if handler.is_star {
      has_star = true
      if first_star_span is None {
        first_star_span = Some(handler.span)
      }
    }
  }
  if has_star {
    // PEP 654: a try block cannot mix `except` and `except*` clauses.
    for handler in handlers {
      if !handler.is_star {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "SyntaxError: cannot have both 'except' and 'except*' on the same 'try'".to_string(),
          ),
        )
      }
      // `except*:` is invalid: every handler must have a type expression.
      match handler.exc {
        None =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: invalid except* clause".to_string(),
            ),
          )
        Some(_) => ()
      }
      match validate_except_star_body(handler.body, 0, false) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
  }
  let setup_pc = b.emit(BcOp::SetupExcept(-1), span)
  for s in body {
    match
      compile_stmt(s, b, span, loop_stack, finally_depth, future_annotations) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let _ = b.emit(BcOp::PopExcept, span)
  for s in else_body {
    match
      compile_stmt(s, b, span, loop_stack, finally_depth, future_annotations) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let j_end = b.emit(BcOp::Jump(-1), span)
  let handlers_pc = b.code.ops.length()
  bc_patch_jump(b.code, setup_pc, handlers_pc)
  if has_star {
    let star_span = match first_star_span {
      Some(s) => Some(s)
      None => span
    }
    let star_span = caretless_span(star_span)
    let _ = b.emit(BcOp::EnsureExceptionGroup, star_span)
    let _ = b.emit(BcOp::ExceptStarInit, star_span)

  }
  let handler_done_jumps : Array[Int] = []
  if has_star {
    let star_done_jumps : Array[Int] = []
    for i = 0; i < handlers.length(); i = i + 1 {
      let handler = handlers[i]
      let handler_span = caretless_span(Some(handler.span))
      // Handler type expression is guaranteed to exist (validated above).
      let exc_expr = match handler.exc {
        Some(v) => v
        None =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: invalid except* clause".to_string(),
            ),
          )
      }
      match compile_expr(exc_expr, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::ExceptStarMatch, handler_span)
      let next_handler_jump = b.emit(BcOp::JumpIfFalse(-1), handler_span)
      match handler.name {
        Some(name) => {
          let name_idx = b.intern_name(name)
          let _ = b.emit(BcOp::LoadException, handler_span)
          let _ = b.emit(BcOp::StoreName(name_idx), handler_span)
          ()
        }
        None => ()
      }
      // See non-star handler comment: clear pending unwind exception once a
      // handler starts executing.
      let _ = b.emit(BcOp::ClearPendingException, handler_span)
      for s in handler.body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let _ = b.emit(BcOp::ExceptStarEndHandler, handler_span)
      // If no remaining exceptions exist, the exception is fully handled.
      star_done_jumps.push(b.emit(BcOp::JumpIfFalse(-1), handler_span))
      let next_pc = b.code.ops.length()
      bc_patch_jump(b.code, next_handler_jump, next_pc)
    }
    let _ = b.emit(BcOp::ExceptStarRaiseRemaining, span)
    let handled_pc = b.code.ops.length()
    for pc in star_done_jumps {
      bc_patch_jump(b.code, pc, handled_pc)
    }
    let _ = b.emit(BcOp::EndExcept, span)
    let handled_jump = b.emit(BcOp::Jump(-1), span)
    let end_pc = b.code.ops.length()
    bc_patch_jump(b.code, j_end, end_pc)
    bc_patch_jump(b.code, handled_jump, end_pc)
    Ok(())
  } else {
    for i = 0; i < handlers.length(); i = i + 1 {
      let handler = handlers[i]
      let next_handler_jump : Int? = match handler.exc {
        None => (None : Int?)
        Some(exc_expr) => {
          match compile_expr(exc_expr, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let _ = b.emit(BcOp::CheckExceptionMatch, span)
          Some(b.emit(BcOp::JumpIfFalse(-1), span))
        }
      }
      match handler.name {
        Some(name) => {
          let name_idx = b.intern_name(name)
          let _ = b.emit(BcOp::LoadException, span)
          let _ = b.emit(BcOp::StoreName(name_idx), span)
          ()
        }
        None => ()
      }
      // Once we're executing a handler, the exception is no longer "pending"
      // for unwind through nested finally/with blocks. Keep it available via
      // `active_exception_stack` (for sys.exc_info / bare raise), but clear the
      // VM's unwind flag so normal finally blocks don't re-raise it.
      let _ = b.emit(BcOp::ClearPendingException, span)
      for s in handler.body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let _ = b.emit(BcOp::EndExcept, span)
      handler_done_jumps.push(b.emit(BcOp::Jump(-1), span))
      match next_handler_jump {
        Some(pc) => {
          let next_pc = b.code.ops.length()
          bc_patch_jump(b.code, pc, next_pc)
          ()
        }
        None => ()
      }
    }
    let _ = b.emit(BcOp::Reraise, span)
    let end_pc = b.code.ops.length()
    bc_patch_jump(b.code, j_end, end_pc)
    for pc in handler_done_jumps {
      bc_patch_jump(b.code, pc, end_pc)
    }
    Ok(())
  }
}

///|
fn compile_stmt(
  stmt : Stmt,
  b : BcBuilder,
  span : Span?,
  loop_stack : Ref[Array[LoopCtx]],
  finally_depth : Int,
  future_annotations : Bool,
) -> Result[Unit, RuntimeError] {
  match stmt {
    Stmt::WithSpan(span~, stmt~) =>
      compile_stmt(
        stmt,
        b,
        Some(span),
        loop_stack,
        finally_depth,
        future_annotations,
      )
    Stmt::Pass => Ok(())
    Stmt::ExprStmt(expr) => {
      match compile_expr(expr, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::PopTop, span)
      Ok(())
    }
    Stmt::Assign(target~, value~) => {
      // Match CPython/MicroPython evaluation order:
      // - For attribute/subscript targets, evaluate the target object (and index)
      //   before evaluating the RHS.
      let rhs = value
      match target {
        Target::Name(_) => {
          match compile_expr(rhs, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          compile_target_store(target, b, span)
        }
        Target::Tuple(_) | Target::List(_) => {
          match compile_expr(rhs, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          compile_target_store(target, b, span)
        }
        Target::Attribute(value~, attr~) => {
          match compile_expr(value, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match compile_expr(rhs, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let idx = b.intern_name(attr)
          let _ = b.emit(BcOp::StoreAttr(idx), span)
          Ok(())
        }
        Target::Subscript(value~, index~) => {
          match compile_expr(value, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match compile_expr(index, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match compile_expr(rhs, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let _ = b.emit(BcOp::StoreSubscr, span)
          Ok(())
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "bytecode compiler: complex assignment target not implemented".to_string(),
            ),
          )
      }
    }
    Stmt::AnnAssign(target~, annotation~, value~) => {
      match target {
        Target::Name(name) => {
          match compile_expr(annotation, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let name_idx = b.intern_name(name)
          let _ = b.emit(BcOp::StoreAnnotation(name_idx), span)

        }
        _ => ()
      }
      match value {
        Some(expr) =>
          match
            compile_stmt(
              Stmt::Assign(target~, value=expr),
              b,
              span,
              loop_stack,
              finally_depth,
              future_annotations,
            ) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => ()
      }
      Ok(())
    }
    Stmt::TypeAlias(name~, type_params~, value~) => {
      let _ = type_params
      let _ = value
      let idx = b.add_const(Value::None)
      let _ = b.emit(BcOp::LoadConst(idx), span)
      let name_idx = b.intern_name(name)
      let _ = b.emit(BcOp::StoreName(name_idx), span)
      Ok(())
    }
    Stmt::AugAssign(target~, op~, value~) => {
      match compile_expr(value, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      match target {
        Target::Name(name) => {
          let name_idx = b.intern_name(name)
          let _ = b.emit(BcOp::AugAssignName(name_idx, op), span)
          Ok(())
        }
        Target::Attribute(value~, attr~) => {
          match compile_expr(value, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let attr_idx = b.intern_name(attr)
          let _ = b.emit(BcOp::AugAssignAttr(attr_idx, op), span)
          Ok(())
        }
        Target::Subscript(value~, index~) => {
          match compile_expr(value, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match compile_expr(index, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let _ = b.emit(BcOp::AugAssignSubscr(op), span)
          Ok(())
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "bytecode compiler: augmented assignment target not implemented".to_string(),
            ),
          )
      }
    }
    Stmt::If(condition~, body~, else_body~) => {
      match compile_expr(condition, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let j_else = b.emit(BcOp::JumpIfFalse(-1), span)
      for s in body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let j_end = b.emit(BcOp::Jump(-1), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_else, else_pc)
      for s in else_body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let end_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_end, end_pc)
      Ok(())
    }
    Stmt::While(condition~, body~, else_body~) => {
      let loop_start = b.code.ops.length()
      match compile_expr(condition, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      // If the condition is false, jump to the `else` suite (or loop end when absent).
      let j_else = b.emit(BcOp::JumpIfFalse(-1), span)
      loop_stack.val.push(LoopCtx::{
        has_iter: false,
        break_jumps: [],
        continue_jumps: [],
        finally_depth,
      })
      for s in body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let ctx_idx = loop_stack.val.length() - 1
      let ctx = loop_stack.val[ctx_idx]
      let _ = loop_stack.val.remove(ctx_idx)
      let _ = b.emit(BcOp::Jump(loop_start), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_else, else_pc)
      for pc in ctx.continue_jumps {
        bc_patch_jump(b.code, pc, loop_start)
      }

      // `while ... else`: run else_body only when loop terminates normally (i.e. not broken).
      for s in else_body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let end_pc = b.code.ops.length()
      for pc in ctx.break_jumps {
        bc_patch_jump(b.code, pc, end_pc)
      }
      Ok(())
    }
    Stmt::For(target~, iter~, body~, else_body~) => {
      match target {
        Target::Name(_) | Target::Tuple(_) | Target::List(_) => ()
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "bytecode compiler: for target not implemented".to_string(),
            ),
          )
      }
      match compile_expr(iter, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let _ = b.emit(BcOp::GetIter, span)
      let loop_start = b.code.ops.length()
      let for_iter_pc = b.emit(BcOp::ForIter(-1), span)
      loop_stack.val.push(LoopCtx::{
        has_iter: true,
        break_jumps: [],
        continue_jumps: [],
        finally_depth,
      })

      // Assign iteration value (TOS) to target; iterator stays below it.
      match compile_target_store(target, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      for s in body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let ctx_idx = loop_stack.val.length() - 1
      let ctx = loop_stack.val[ctx_idx]
      let _ = loop_stack.val.remove(ctx_idx)
      let _ = b.emit(BcOp::Jump(loop_start), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, for_iter_pc, else_pc)
      for pc in ctx.continue_jumps {
        bc_patch_jump(b.code, pc, loop_start)
      }

      // `for ... else`: run else_body only when loop is exhausted (i.e. not broken).
      for s in else_body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let end_pc = b.code.ops.length()
      for pc in ctx.break_jumps {
        bc_patch_jump(b.code, pc, end_pc)
      }
      Ok(())
    }
    Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
      match target {
        Target::Name(_) | Target::Tuple(_) | Target::List(_) => ()
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "bytecode compiler: async for target not implemented".to_string(),
            ),
          )
      }
      let _ = b.emit(
        BcOp::CheckInCoroutineScope(
          "SyntaxError: 'async for' outside async function".to_string(),
        ),
        span,
      )

      // it = (ITER).__aiter__()
      match compile_expr(iter, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let aiter_idx = b.intern_name("__aiter__")
      let _ = b.emit(BcOp::LoadAttr(aiter_idx), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      let it_name = "__mpy_asyncfor_it$" + b.code.ops.length().to_string()
      let it_name_idx = b.intern_name(it_name)
      let _ = b.emit(BcOp::StoreName(it_name_idx), span)
      let loop_start = b.code.ops.length()
      // try:
      //   value = await it.__anext__()
      // except StopAsyncIteration:
      //   break
      let setup_pc = b.emit(BcOp::SetupExcept(-1), span)
      let anext_idx = b.intern_name("__anext__")
      let _ = b.emit(BcOp::LoadName(it_name_idx), span)
      let _ = b.emit(BcOp::LoadAttr(anext_idx), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      let _ = b.emit(BcOp::Await, span)
      let _ = b.emit(BcOp::PopExcept, span)
      loop_stack.val.push(LoopCtx::{
        has_iter: false,
        break_jumps: [],
        continue_jumps: [],
        finally_depth,
      })
      match compile_target_store(target, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      for s in body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let ctx_idx = loop_stack.val.length() - 1
      let ctx = loop_stack.val[ctx_idx]
      let _ = loop_stack.val.remove(ctx_idx)
      let _ = b.emit(BcOp::Jump(loop_start), span)

      // Handler block (catch StopAsyncIteration; otherwise reraise).
      let handler_pc = b.code.ops.length()
      bc_patch_jump(b.code, setup_pc, handler_pc)
      let stop_idx = b.intern_name("StopAsyncIteration")
      let _ = b.emit(BcOp::LoadName(stop_idx), span)
      let _ = b.emit(BcOp::CheckExceptionMatch, span)
      let j_not_stop = b.emit(BcOp::JumpIfFalse(-1), span)
      let _ = b.emit(BcOp::EndExcept, span)
      let j_to_else = b.emit(BcOp::Jump(-1), span)
      let reraise_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_not_stop, reraise_pc)
      let _ = b.emit(BcOp::Reraise, span)

      // Loop exhausted => else suite.
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_to_else, else_pc)
      for pc in ctx.continue_jumps {
        bc_patch_jump(b.code, pc, loop_start)
      }
      for s in else_body {
        match
          compile_stmt(
            s, b, span, loop_stack, finally_depth, future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let end_pc = b.code.ops.length()
      for pc in ctx.break_jumps {
        bc_patch_jump(b.code, pc, end_pc)
      }
      let _ = b.emit(BcOp::DeleteName(it_name_idx), span)
      Ok(())
    }
    Stmt::Break => {
      if loop_stack.val.length() == 0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "bytecode compiler: break not in loop".to_string(),
          ),
        )
      }
      let idx = loop_stack.val.length() - 1
      let ctx = loop_stack.val[idx]
      if ctx.has_iter {
        let _ = b.emit(BcOp::PopTop, span)
        // pop iterator
      }
      let unwind = finally_depth - ctx.finally_depth
      let j = if unwind > 0 {
        b.emit(BcOp::UnwindJump(-1, unwind), span)
      } else {
        b.emit(BcOp::Jump(-1), span)
      }
      ctx.break_jumps.push(j)
      loop_stack.val[idx] = ctx
      Ok(())
    }
    Stmt::Continue => {
      if loop_stack.val.length() == 0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "bytecode compiler: continue not in loop".to_string(),
          ),
        )
      }
      let idx = loop_stack.val.length() - 1
      let ctx = loop_stack.val[idx]
      let unwind = finally_depth - ctx.finally_depth
      let j = if unwind > 0 {
        b.emit(BcOp::UnwindJump(-1, unwind), span)
      } else {
        b.emit(BcOp::Jump(-1), span)
      }
      ctx.continue_jumps.push(j)
      loop_stack.val[idx] = ctx
      Ok(())
    }
    Stmt::Match(subject~, cases~) => {
      match compile_expr(subject, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let subj_name = "__mpy_match_subj$" + b.code.ops.length().to_string()
      let subj_idx = b.intern_name(subj_name)
      let _ = b.emit(BcOp::StoreName(subj_idx), span)
      let end_jumps : Array[Int] = []
      for case in cases {
        let pattern = case.0
        let guard_opt = case.1
        let case_body = case.2
        let _ = b.emit(BcOp::LoadName(subj_idx), span)
        let pat_idx = b.add_pattern(pattern)
        let _ = b.emit(BcOp::MatchPattern(pat_idx), span)
        // If match_pattern returns None, skip this case.
        let _ = b.emit(BcOp::DupTop, span)
        let none_idx = b.add_const(Value::None)
        let _ = b.emit(BcOp::LoadConst(none_idx), span)
        let _ = b.emit(BcOp::Compare(CompareOp::Eq), span)
        let j_no_match = b.emit(BcOp::JumpIfTrue(-1), span)

        // Match: bind names and evaluate optional guard.
        let _ = b.emit(BcOp::MatchBind, span)
        let mut j_guard_fail : Int? = None
        match guard_opt {
          Some(guard_expr) => {
            match compile_expr(guard_expr, b, span) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            j_guard_fail = Some(b.emit(BcOp::JumpIfFalse(-1), span))
          }
          None => ()
        }
        for s in case_body {
          match
            compile_stmt(
              s, b, span, loop_stack, finally_depth, future_annotations,
            ) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        // Matched: drop restore token and finish.
        let _ = b.emit(BcOp::PopTop, span)
        end_jumps.push(b.emit(BcOp::Jump(-1), span))

        // Guard failed: restore bindings and continue.
        match j_guard_fail {
          Some(j) => {
            let guard_fail_pc = b.code.ops.length()
            bc_patch_jump(b.code, j, guard_fail_pc)
            let _ = b.emit(BcOp::MatchRestore, span)
            let j_to_next = b.emit(BcOp::Jump(-1), span)

            // No-match label: pop the None result and continue to next case.
            let no_match_pc = b.code.ops.length()
            bc_patch_jump(b.code, j_no_match, no_match_pc)
            let _ = b.emit(BcOp::PopTop, span)
            let next_case_pc = b.code.ops.length()
            bc_patch_jump(b.code, j_to_next, next_case_pc)
          }
          None => {
            let no_match_pc = b.code.ops.length()
            bc_patch_jump(b.code, j_no_match, no_match_pc)
            let _ = b.emit(BcOp::PopTop, span)

          }
        }
      }
      let end_pc = b.code.ops.length()
      for pc in end_jumps {
        bc_patch_jump(b.code, pc, end_pc)
      }
      let _ = b.emit(BcOp::DeleteName(subj_idx), span)
      Ok(())
    }
    Stmt::Global(_) => Ok(())
    Stmt::Nonlocal(_) => {
      let _ = b.emit(
        BcOp::CheckInFunctionScope(
          "SyntaxError: nonlocal declaration not allowed at module level".to_string(),
        ),
        span,
      )
      Ok(())
    }
    Stmt::Assert(condition~, message~) => {
      let assert_span : Span? = match expr_span(condition) {
        Some(s) => Some(s)
        None => span
      }
      match compile_expr(condition, b, assert_span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let j_ok = b.emit(BcOp::JumpIfTrue(-1), assert_span)
      match message {
        Some(expr) => {
          let msg_span : Span? = match expr_span(expr) {
            Some(s) => Some(s)
            None => span
          }
          match compile_expr(expr, b, msg_span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          let _ = b.emit(BcOp::AssertFail, assert_span)

        }
        None => {
          let _ = b.emit(BcOp::AssertFailNone, assert_span)

        }
      }
      let ok_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_ok, ok_pc)
      Ok(())
    }
    Stmt::Return(expr_opt) => {
      match expr_opt {
        Some(expr) =>
          match compile_expr(expr, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        None => {
          let idx = b.add_const(Value::None)
          let _ = b.emit(BcOp::LoadConst(idx), span)

        }
      }
      let _ = b.emit(BcOp::ReturnValue, span)
      Ok(())
    }
    Stmt::Raise(exc~, cause~) =>
      match exc {
        None => {
          let _ = b.emit(BcOp::Reraise, span)
          Ok(())
        }
        Some(expr) => {
          match compile_expr(expr, b, span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          match cause {
            None => {
              let _ = b.emit(BcOp::Raise, span)
              Ok(())
            }
            Some(cause_expr) => {
              match compile_expr(cause_expr, b, span) {
                Ok(_) => ()
                Err(err) => return Err(err)
              }
              let _ = b.emit(BcOp::RaiseFrom, span)
              Ok(())
            }
          }
        }
      }
    Stmt::Del(targets) => {
      for target in targets {
        match compile_target_delete(target, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      Ok(())
    }
    Stmt::Import(module_name~, alias_name~) => {
      let mod_idx = b.add_const(Value::Str(module_name))
      let alias_idx = match alias_name {
        Some(name) => b.intern_name(name)
        None => -1
      }
      let _ = b.emit(BcOp::ImportName(mod_idx, alias_idx), span)
      Ok(())
    }
    Stmt::FromImport(module_name~, names~) => {
      let mod_idx = b.add_const(Value::Str(module_name))
      let import_names : Array[Value] = []
      let import_aliases : Array[Value] = []
      for item in names {
        import_names.push(Value::Str(item.0))
        match item.1 {
          Some(alias_name) => import_aliases.push(Value::Str(alias_name))
          None => import_aliases.push(Value::None)
        }
      }
      let names_idx = b.add_const(Value::Tuple(import_names))
      let aliases_idx = b.add_const(Value::Tuple(import_aliases))
      let _ = b.emit(BcOp::FromImport(mod_idx, names_idx, aliases_idx), span)
      Ok(())
    }
    Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~) => {
      let _ = type_params
      // Keep evaluation order aligned with CPython:
      // decorator expressions first, then base/keyword expressions, then class creation.
      for dec_expr in decorators {
        match compile_expr(dec_expr, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      for base in bases {
        match base {
          Expr::Starred(value~) => {
            let flag_idx = b.add_const(Value::Bool(true))
            let _ = b.emit(BcOp::LoadConst(flag_idx), span)
            match compile_expr(value, b, span) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            let _ = b.emit(BcOp::BuildTuple(2), span)

          }
          _ => {
            let flag_idx = b.add_const(Value::Bool(false))
            let _ = b.emit(BcOp::LoadConst(flag_idx), span)
            match compile_expr(base, b, span) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            let _ = b.emit(BcOp::BuildTuple(2), span)

          }
        }
      }
      let _ = b.emit(BcOp::BuildList(bases.length()), span)
      for kw in keywords {
        let key_idx = b.add_const(Value::Str(kw.0))
        let _ = b.emit(BcOp::LoadConst(key_idx), span)
        match compile_expr(kw.1, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let _ = b.emit(BcOp::BuildTuple(2), span)

      }
      let _ = b.emit(BcOp::BuildList(keywords.length()), span)
      let template = FunctionValue::{
        name: "<class>".to_string(),
        params: [],
        defaults: [],
        body,
        is_generator: false,
        is_async: false,
        closure: [],
      }
      let template_idx = b.add_const(Value::Function(template))
      let name_idx = b.intern_name(name)
      // Decorator application happens inside `MakeClass`. Use the outermost
      // decorator's span so failures report the correct `@decorator` line.
      let apply_span = if decorators.length() > 0 {
        match decorators[0] {
          Expr::WithSpan(span=dec_span, expr=_) => Some(dec_span)
          _ => span
        }
      } else {
        span
      }
      let _ = b.emit(
        BcOp::MakeClass(template_idx, name_idx, decorators.length()),
        apply_span,
      )
      let _ = b.emit(BcOp::StoreName(name_idx), span)
      Ok(())
    }
    Stmt::Try(body~, handlers~, else_body~, finally_body~) =>
      if finally_body.length() == 0 {
        compile_try_except_else(
          body, handlers, else_body, b, span, loop_stack, finally_depth, future_annotations,
        )
      } else {
        let setup_pc = b.emit(BcOp::SetupFinally(-1), span)
        match
          compile_try_except_else(
            body,
            handlers,
            else_body,
            b,
            span,
            loop_stack,
            finally_depth + 1,
            future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let enter_pc = b.emit(BcOp::EnterFinally(-1), span)
        let finally_pc = b.code.ops.length()
        bc_patch_jump(b.code, setup_pc, finally_pc)
        bc_patch_jump(b.code, enter_pc, finally_pc)
        for s in finally_body {
          match
            compile_stmt(
              s,
              b,
              span,
              loop_stack,
              finally_depth + 1,
              future_annotations,
            ) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
        }
        let _ = b.emit(BcOp::EndFinally, span)
        Ok(())
      }
    Stmt::Function(
      name~,
      decorators~,
      type_params~,
      params~,
      defaults~,
      annotations~,
      return_annotation~,
      body~,
      is_generator~,
      is_async~
    ) => {
      // PEP 695 type parameters introduce implicit bindings that are visible to
      // annotations. MoonPython does not yet model those runtime bindings, so
      // avoid eagerly evaluating annotations for generic functions (typing.py
      // uses `def override[F](...) -> F:` patterns).
      // Keep evaluation order aligned with CPython:
      // decorator expressions first, then default expressions, then function creation.
      for dec_expr in decorators {
        match compile_expr(dec_expr, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      for def_expr in defaults {
        match compile_expr(def_expr, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let mut ann_tmp_idx : Int? = None
      let has_annotations = annotations.length() > 0 ||
        return_annotation is Some(_)
      let eval_annotations = has_annotations &&
        !future_annotations &&
        type_params.length() == 0
      if eval_annotations {
        let tmp_name = "$__mpy_fn_annotations$" +
          b.code.ops.length().to_string()
        let tmp_idx = b.intern_name(tmp_name)
        ann_tmp_idx = Some(tmp_idx)
        let mut pairs = 0
        for pair in annotations {
          let key = pair.0
          let expr = pair.1
          let key_idx = b.add_const(Value::Str(key))
          let _ = b.emit(BcOp::LoadConst(key_idx), span)
          let ann_span : Span? = match expr_span(expr) {
            Some(s) => Some(s)
            None => span
          }
          match compile_expr(expr, b, ann_span) {
            Ok(_) => ()
            Err(err) => return Err(err)
          }
          pairs = pairs + 1
        }
        match return_annotation {
          Some(expr) => {
            let key_idx = b.add_const(Value::Str("return".to_string()))
            let _ = b.emit(BcOp::LoadConst(key_idx), span)
            let ann_span : Span? = match expr_span(expr) {
              Some(s) => Some(s)
              None => span
            }
            match compile_expr(expr, b, ann_span) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
            pairs = pairs + 1
          }
          None => ()
        }
        let _ = b.emit(BcOp::BuildMap(pairs), span)
        let _ = b.emit(BcOp::StoreName(tmp_idx), span)

      }
      let template = FunctionValue::{
        name,
        params,
        defaults: [],
        body,
        is_generator,
        is_async,
        closure: [],
      }
      let template_idx = b.add_const(Value::Function(template))
      let _ = b.emit(
        BcOp::MakeFunction(template_idx, defaults.length(), decorators.length()),
        // Decorator application happens inside `MakeFunction`. Use the outermost
        // decorator's span so failures report the correct `@decorator` line.
        if decorators.length() > 0 {
          match decorators[0] {
            Expr::WithSpan(span=dec_span, expr=_) => Some(dec_span)
            _ => span
          }
        } else {
          span
        },
      )
      match ann_tmp_idx {
        Some(tmp_idx) => {
          let ann_attr_idx = b.intern_name("__annotations__")
          let _ = b.emit(BcOp::DupTop, span)
          let _ = b.emit(BcOp::LoadName(tmp_idx), span)
          let _ = b.emit(BcOp::StoreAttr(ann_attr_idx), span)
          let _ = b.emit(BcOp::DeleteName(tmp_idx), span)

        }
        None => ()
      }
      let name_idx = b.intern_name(name)
      let _ = b.emit(BcOp::StoreName(name_idx), span)
      Ok(())
    }
    Stmt::With(context~, target~, body~) => {
      match compile_expr(context, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let exit_idx = b.intern_name("__exit__")
      let enter_idx = b.intern_name("__enter__")
      let exit_name = "__mpy_with_exit$" + b.code.ops.length().to_string()
      let exit_name_idx = b.intern_name(exit_name)
      let _ = b.emit(BcOp::DupTop, span)
      let _ = b.emit(BcOp::LoadAttr(exit_idx), span)
      let _ = b.emit(BcOp::StoreName(exit_name_idx), span)
      let _ = b.emit(BcOp::LoadAttr(enter_idx), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      match target {
        Some(name) => {
          let name_idx = b.intern_name(name)
          let _ = b.emit(BcOp::StoreName(name_idx), span)
          ()
        }
        None => {
          let _ = b.emit(BcOp::PopTop, span)
          ()
        }
      }
      let setup_pc = b.emit(BcOp::SetupFinally(-1), span)
      for s in body {
        match
          compile_stmt(
            s,
            b,
            span,
            loop_stack,
            finally_depth + 1,
            future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let enter_pc = b.emit(BcOp::EnterFinally(-1), span)

      // Handler (runs on normal exit, return, and exception unwind).
      let handler_pc = b.code.ops.length()
      bc_patch_jump(b.code, setup_pc, handler_pc)
      bc_patch_jump(b.code, enter_pc, handler_pc)
      let _ = b.emit(BcOp::HasPendingException, span)
      let j_normal = b.emit(BcOp::JumpIfFalse(-1), span)

      // Exception path: __exit__(exc_type, exc, tb); if truthy -> suppress.
      let _ = b.emit(BcOp::LoadName(exit_name_idx), span)
      let _ = b.emit(BcOp::LoadExceptionType, span)
      let _ = b.emit(BcOp::LoadException, span)
      let _ = b.emit(BcOp::LoadExceptionTraceback, span)
      let _ = b.emit(BcOp::CallFunction(3), span)
      let j_no_suppress = b.emit(BcOp::JumpIfFalse(-1), span)
      let _ = b.emit(BcOp::ClearPendingException, span)
      let j_tail = b.emit(BcOp::Jump(-1), span)

      // Normal/return path: __exit__(None, None, None)
      let normal_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_normal, normal_pc)
      let none_idx = b.add_const(Value::None)
      let _ = b.emit(BcOp::LoadName(exit_name_idx), span)
      let _ = b.emit(BcOp::LoadConst(none_idx), span)
      let _ = b.emit(BcOp::LoadConst(none_idx), span)
      let _ = b.emit(BcOp::LoadConst(none_idx), span)
      let _ = b.emit(BcOp::CallFunction(3), span)
      let _ = b.emit(BcOp::PopTop, span)

      // Tail: delete hidden exit and let EndFinally continue unwind.
      let tail_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_no_suppress, tail_pc)
      bc_patch_jump(b.code, j_tail, tail_pc)
      let _ = b.emit(BcOp::DeleteName(exit_name_idx), span)
      let _ = b.emit(BcOp::EndFinally, span)
      Ok(())
    }
    Stmt::AsyncWith(context~, target~, body~) => {
      match compile_expr(context, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let aexit_idx = b.intern_name("__aexit__")
      let aenter_idx = b.intern_name("__aenter__")
      let exit_name = "__mpy_async_with_exit$" + b.code.ops.length().to_string()
      let exit_name_idx = b.intern_name(exit_name)
      let _ = b.emit(BcOp::DupTop, span)
      let _ = b.emit(BcOp::LoadAttr(aexit_idx), span)
      let _ = b.emit(BcOp::StoreName(exit_name_idx), span)
      let _ = b.emit(BcOp::LoadAttr(aenter_idx), span)
      let _ = b.emit(BcOp::CallFunction(0), span)
      let _ = b.emit(BcOp::Await, span)
      match target {
        Some(name) => {
          let name_idx = b.intern_name(name)
          let _ = b.emit(BcOp::StoreName(name_idx), span)
          ()
        }
        None => {
          let _ = b.emit(BcOp::PopTop, span)
          ()
        }
      }
      let setup_pc = b.emit(BcOp::SetupFinally(-1), span)
      for s in body {
        match
          compile_stmt(
            s,
            b,
            span,
            loop_stack,
            finally_depth + 1,
            future_annotations,
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let enter_pc = b.emit(BcOp::EnterFinally(-1), span)

      // Handler (runs on normal exit, return, and exception unwind).
      let handler_pc = b.code.ops.length()
      bc_patch_jump(b.code, setup_pc, handler_pc)
      bc_patch_jump(b.code, enter_pc, handler_pc)
      let _ = b.emit(BcOp::HasPendingException, span)
      let j_normal = b.emit(BcOp::JumpIfFalse(-1), span)

      // Exception path: await __aexit__(exc_type_name, exc, tb); if truthy -> suppress.
      let _ = b.emit(BcOp::LoadName(exit_name_idx), span)
      let _ = b.emit(BcOp::LoadExceptionTypeName, span)
      let _ = b.emit(BcOp::LoadException, span)
      let _ = b.emit(BcOp::LoadExceptionTraceback, span)
      let _ = b.emit(BcOp::CallFunction(3), span)
      let _ = b.emit(BcOp::Await, span)
      let j_no_suppress = b.emit(BcOp::JumpIfFalse(-1), span)
      let _ = b.emit(BcOp::ClearPendingException, span)
      let j_tail = b.emit(BcOp::Jump(-1), span)

      // Normal/return path: await __aexit__(None, None, None)
      let normal_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_normal, normal_pc)
      let none_idx = b.add_const(Value::None)
      let _ = b.emit(BcOp::LoadName(exit_name_idx), span)
      let _ = b.emit(BcOp::LoadConst(none_idx), span)
      let _ = b.emit(BcOp::LoadConst(none_idx), span)
      let _ = b.emit(BcOp::LoadConst(none_idx), span)
      let _ = b.emit(BcOp::CallFunction(3), span)
      let _ = b.emit(BcOp::Await, span)
      let _ = b.emit(BcOp::PopTop, span)

      // Tail: delete hidden exit and let EndFinally continue unwind.
      let tail_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_no_suppress, tail_pc)
      bc_patch_jump(b.code, j_tail, tail_pc)
      let _ = b.emit(BcOp::DeleteName(exit_name_idx), span)
      let _ = b.emit(BcOp::EndFinally, span)
      Ok(())
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "bytecode compiler: stmt not implemented".to_string(),
        ),
      )
  }
}

///|
pub fn compile_module_to_bc(
  program : Module,
  filename : String,
) -> Result[BcCode, RuntimeError] {
  compile_stmts_to_bc(program.body, "<module>".to_string(), filename)
}

///|
fn stmts_have_future_annotations(body : Array[Stmt]) -> Bool {
  for stmt in body {
    match stmt {
      Stmt::WithSpan(span=_, stmt=inner) =>
        if stmts_have_future_annotations([inner]) {
          return true
        }
      Stmt::FromImport(module_name~, names~) =>
        if module_name == "__future__" {
          for item in names {
            if item.0 == "annotations" {
              return true
            }
          }
        }
      _ => ()
    }
  }
  false
}

///|
pub fn compile_stmts_to_bc_with_future(
  body : Array[Stmt],
  name : String,
  filename : String,
  future_annotations : Bool,
) -> Result[BcCode, RuntimeError] {
  let b = BcBuilder::new(name, filename)
  let loop_stack : Ref[Array[LoopCtx]] = { val: [] }
  for stmt in body {
    match compile_stmt(stmt, b, None, loop_stack, 0, future_annotations) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  // Falling off the end returns None.
  let none_idx = b.add_const(Value::None)
  let _ = b.emit(BcOp::LoadConst(none_idx), None)
  let _ = b.emit(BcOp::ReturnValue, None)
  Ok(b.code)
}

///|
pub fn compile_stmts_to_bc(
  body : Array[Stmt],
  name : String,
  filename : String,
) -> Result[BcCode, RuntimeError] {
  let future = stmts_have_future_annotations(body)
  compile_stmts_to_bc_with_future(body, name, filename, future)
}
