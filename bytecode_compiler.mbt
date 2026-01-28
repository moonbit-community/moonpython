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
fn has_break_or_continue(stmts : Array[Stmt]) -> Bool {
  for stmt in stmts {
    match stmt {
      Stmt::WithSpan(span~, stmt~) => {
        let _ = span
        if has_break_or_continue([stmt]) {
          return true
        }
      }
      Stmt::Break | Stmt::Continue => return true
      Stmt::If(condition~, body~, else_body~) => {
        let _ = condition
        if has_break_or_continue(body) || has_break_or_continue(else_body) {
          return true
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        let _ = condition
        if has_break_or_continue(body) || has_break_or_continue(else_body) {
          return true
        }
      }
      Stmt::For(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        if has_break_or_continue(body) || has_break_or_continue(else_body) {
          return true
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        if has_break_or_continue(body) ||
          has_break_or_continue(else_body) ||
          has_break_or_continue(finally_body) {
          return true
        }
        for h in handlers {
          if has_break_or_continue(h.body) {
            return true
          }
        }
      }
      // Nested scopes do not affect outer control flow.
      Stmt::Function(..) | Stmt::Class(..) => ()
      _ => ()
    }
  }
  false
}

///|
fn compile_expr(
  expr : Expr,
  b : BcBuilder,
  span : Span?,
) -> Result[Unit, RuntimeError] {
  match expr {
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
      for arg in args {
        match arg {
          Expr::Keyword(_) | Expr::Starred(_) | Expr::DoubleStarred(_) =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::NotImplemented,
                "bytecode compiler: keyword/star args not implemented".to_string(),
              ),
            )
          _ => ()
        }
      }
      match compile_expr(callee, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      for arg in args {
        match compile_expr(arg, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let _ = b.emit(BcOp::CallFunction(args.length()), span)
      Ok(())
    }
    Expr::Tuple(items) => {
      for item in items {
        match compile_expr(item, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let _ = b.emit(BcOp::BuildTuple(items.length()), span)
      Ok(())
    }
    Expr::List(items) => {
      for item in items {
        match compile_expr(item, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let _ = b.emit(BcOp::BuildList(items.length()), span)
      Ok(())
    }
    Expr::Dict(items) => {
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
fn compile_try_except_else(
  body : Array[Stmt],
  handlers : Array[ExceptHandler],
  else_body : Array[Stmt],
  b : BcBuilder,
  span : Span?,
  loop_stack : Ref[Array[LoopCtx]],
  finally_depth : Int,
) -> Result[Unit, RuntimeError] {
  for handler in handlers {
    if handler.is_star {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "bytecode compiler: except* not implemented".to_string(),
        ),
      )
    }
  }
  let setup_pc = b.emit(BcOp::SetupExcept(-1), span)
  for s in body {
    match compile_stmt(s, b, span, loop_stack, finally_depth) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let _ = b.emit(BcOp::PopExcept, span)
  for s in else_body {
    match compile_stmt(s, b, span, loop_stack, finally_depth) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let j_end = b.emit(BcOp::Jump(-1), span)
  let handlers_pc = b.code.ops.length()
  bc_patch_jump(b.code, setup_pc, handlers_pc)
  let handler_done_jumps : Array[Int] = []
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
    for s in handler.body {
      match compile_stmt(s, b, span, loop_stack, finally_depth) {
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

///|
fn compile_stmt(
  stmt : Stmt,
  b : BcBuilder,
  span : Span?,
  loop_stack : Ref[Array[LoopCtx]],
  finally_depth : Int,
) -> Result[Unit, RuntimeError] {
  match stmt {
    Stmt::WithSpan(span~, stmt~) =>
      compile_stmt(stmt, b, Some(span), loop_stack, finally_depth)
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
    Stmt::If(condition~, body~, else_body~) => {
      match compile_expr(condition, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let j_else = b.emit(BcOp::JumpIfFalse(-1), span)
      for s in body {
        match compile_stmt(s, b, span, loop_stack, finally_depth) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let j_end = b.emit(BcOp::Jump(-1), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_else, else_pc)
      for s in else_body {
        match compile_stmt(s, b, span, loop_stack, finally_depth) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let end_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_end, end_pc)
      Ok(())
    }
    Stmt::While(condition~, body~, else_body~) => {
      if else_body.length() != 0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "bytecode compiler: while-else not implemented".to_string(),
          ),
        )
      }
      let loop_start = b.code.ops.length()
      match compile_expr(condition, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let j_end = b.emit(BcOp::JumpIfFalse(-1), span)
      loop_stack.val.push(LoopCtx::{
        has_iter: false,
        break_jumps: [],
        continue_jumps: [],
        finally_depth,
      })
      for s in body {
        match compile_stmt(s, b, span, loop_stack, finally_depth) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let ctx_idx = loop_stack.val.length() - 1
      let ctx = loop_stack.val[ctx_idx]
      let _ = loop_stack.val.remove(ctx_idx)
      let _ = b.emit(BcOp::Jump(loop_start), span)
      let end_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_end, end_pc)
      for pc in ctx.continue_jumps {
        bc_patch_jump(b.code, pc, loop_start)
      }
      for pc in ctx.break_jumps {
        bc_patch_jump(b.code, pc, end_pc)
      }
      Ok(())
    }
    Stmt::For(target~, iter~, body~, else_body~) => {
      match target {
        Target::Name(_) => ()
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
        match compile_stmt(s, b, span, loop_stack, finally_depth) {
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
        match compile_stmt(s, b, span, loop_stack, finally_depth) {
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
    Stmt::Try(body~, handlers~, else_body~, finally_body~) =>
      if finally_body.length() == 0 {
        compile_try_except_else(
          body, handlers, else_body, b, span, loop_stack, finally_depth,
        )
      } else {
        // `break`/`continue` in the finally-suite itself is not supported yet.
        if has_break_or_continue(finally_body) {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "bytecode compiler: break/continue in finally suite not implemented".to_string(),
            ),
          )
        }
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
          ) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
        let enter_pc = b.emit(BcOp::EnterFinally(-1), span)
        let finally_pc = b.code.ops.length()
        bc_patch_jump(b.code, setup_pc, finally_pc)
        bc_patch_jump(b.code, enter_pc, finally_pc)
        for s in finally_body {
          match compile_stmt(s, b, span, loop_stack, finally_depth) {
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
      body~,
      is_generator~,
      is_async~
    ) => {
      let _ = type_params
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
        span,
      )
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
        match compile_stmt(s, b, span, loop_stack, finally_depth + 1) {
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
        match compile_stmt(s, b, span, loop_stack, finally_depth + 1) {
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
pub fn compile_stmts_to_bc(
  body : Array[Stmt],
  name : String,
  filename : String,
) -> Result[BcCode, RuntimeError] {
  let b = BcBuilder::new(name, filename)
  let loop_stack : Ref[Array[LoopCtx]] = { val: [] }
  for stmt in body {
    match compile_stmt(stmt, b, None, loop_stack, 0) {
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
