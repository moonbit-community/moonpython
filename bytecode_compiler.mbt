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
) -> Result[Unit, RuntimeError] {
  match stmt {
    Stmt::WithSpan(span~, stmt~) => compile_stmt(stmt, b, Some(span))
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
        match compile_stmt(s, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let j_end = b.emit(BcOp::Jump(-1), span)
      let else_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_else, else_pc)
      for s in else_body {
        match compile_stmt(s, b, span) {
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
      for s in body {
        match compile_stmt(s, b, span) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
      let _ = b.emit(BcOp::Jump(loop_start), span)
      let end_pc = b.code.ops.length()
      bc_patch_jump(b.code, j_end, end_pc)
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
  for stmt in program.body {
    match compile_stmt(stmt, b, None) {
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
