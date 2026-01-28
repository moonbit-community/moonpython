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
fn compile_stmt(
  stmt : Stmt,
  b : BcBuilder,
  span : Span?,
  loop_stack : Ref[Array[LoopCtx]],
) -> Result[Unit, RuntimeError] {
  match stmt {
    Stmt::WithSpan(span~, stmt~) =>
      compile_stmt(stmt, b, Some(span), loop_stack)
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
        match compile_stmt(s, b, span, loop_stack) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let j_end = b.emit(BcOp::Jump(-1), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_else, else_pc)
      for s in else_body {
        match compile_stmt(s, b, span, loop_stack) {
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
      })
      for s in body {
        match compile_stmt(s, b, span, loop_stack) {
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
      })

      // Assign iteration value (TOS) to target; iterator stays below it.
      match compile_target_store(target, b, span) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      for s in body {
        match compile_stmt(s, b, span, loop_stack) {
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
        match compile_stmt(s, b, span, loop_stack) {
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
      let j = b.emit(BcOp::Jump(-1), span)
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
      let j = b.emit(BcOp::Jump(-1), span)
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
  let b = BcBuilder::new("<module>".to_string(), filename)
  let loop_stack : Ref[Array[LoopCtx]] = { val: [] }
  for stmt in program.body {
    match compile_stmt(stmt, b, None, loop_stack) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  // Modules implicitly return None.
  let none_idx = b.add_const(Value::None)
  let _ = b.emit(BcOp::LoadConst(none_idx), None)
  let _ = b.emit(BcOp::ReturnValue, None)
  Ok(b.code)
}
