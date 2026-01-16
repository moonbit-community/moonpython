///|
/// Expression evaluation for the mpython runtime.
///
/// Most runtime utilities are split into dedicated files:
/// - runtime_value.mbt
/// - runtime_error.mbt
/// - runtime_env.mbt
/// - runtime_assign.mbt
/// - runtime_comprehension.mbt
/// - runtime_pattern.mbt
/// - runtime_block.mbt
/// - interpreter_api.mbt

///|
fn stringify_value_with_env(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  match value {
    Value::Instance(inst) => {
      let instance = Value::Instance(inst)
      match get_attr_from_value(instance, "__str__") {
        Ok(method) =>
          match call_callable_with_env(method, [], [], globals, builtins, io) {
            Ok(Value::Str(text)) => Ok(text)
            Ok(other) => Ok(value_to_string(other))
            Err(_) => Ok(value_to_string(instance))
          }
        Err(_) => Ok(value_to_string(instance))
      }
    }
    _ => Ok(value_to_string(value))
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
        Literal::Str(value) => Ok(Value::Str(value))
      }
    Expr::Name(name) => {
      let value = get_from_env(name, locals, globals, builtins)
      if value is Some(value) {
        Ok(value)
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Name,
            "name '" + name + "' is not defined",
          ),
        )
      }
    }
    Expr::FString(text) => {
      let buf = StringBuilder::new()
      let mut rest = text
      while true {
        let open = find_char(rest, '{')
        if open is None {
          buf.write_string(rest)
          break
        }
        let open = open.unwrap()
        buf.write_string(substring(rest, 0, open))
        let after_open = substring(rest, open + 1, rest.length())
        let close = find_fstring_expr_close(after_open)
        if close is None {
          return Ok(Value::Str(text))
        }
        let close = close.unwrap()
        let inner = substring(after_open, 0, close)
        let remaining = substring(after_open, close + 1, after_open.length())
        let expr = match parse_expr(inner) {
          Ok(value) => value
          Err(_) =>
            match find_top_level_format_colon(inner) {
              Some(pos) => {
                let expr_text = substring(inner, 0, pos)
                match parse_expr(expr_text) {
                  Ok(value) => value
                  Err(_) => return Ok(Value::Str(text))
                }
              }
              None => return Ok(Value::Str(text))
            }
        }
        let value = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let text = match
          stringify_value_with_env(value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        buf.write_string(text)
        rest = remaining
      }
      Ok(Value::Str(buf.to_string()))
    }
    Expr::NamedExpr(name~, value~) => {
      let evaluated = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      set_global_value(globals, name, evaluated)
      Ok(evaluated)
    }
    Expr::List(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        values.push(value)
      }
      Ok(Value::List(values))
    }
    Expr::ListComp(elt~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
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
      let _ = elt
      let _ = filters
      if clauses.length() > 0 {
        let iter_value = match
          eval_expr_with_env(clauses[0].1, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let _ = match iterable_values(iter_value) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }

      }
      Ok(
        Value::Function(FunctionValue::{
          name: "<genexpr>",
          params: [],
          body: [],
        }),
      )
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
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
        let mut exists = false
        for existing in unique {
          if eq_value(existing, item) {
            exists = true
            break
          }
        }
        if !exists {
          unique.push(item)
        }
      }
      Ok(Value::Set(unique))
    }
    Expr::DictComp(key~, value~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
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
      for item in items {
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
        values.push((key, value))
      }
      Ok(Value::Dict(values))
    }
    Expr::Set(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let mut exists = false
        for existing in values {
          if eq_value(existing, value) {
            exists = true
            break
          }
        }
        if !exists {
          values.push(value)
        }
      }
      Ok(Value::Set(values))
    }
    Expr::Tuple(items) => {
      let values : Array[Value] = []
      for item in items {
        let value = match
          eval_expr_with_env(item, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        values.push(value)
      }
      Ok(Value::Tuple(values))
    }
    Expr::Lambda(params~, defaults~, body~) => {
      for expr in defaults {
        let _ = match eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }

      }
      let func_body : Array[Stmt] = [Stmt::Return(Some(body))]
      Ok(
        Value::Function(FunctionValue::{
          name: "<lambda>",
          params,
          body: func_body,
        }),
      )
    }
    Expr::Attribute(value~, attr~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if attr == "__class__" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "ValueError: unsupported value".to_string(),
          ),
        )
      }
      match target {
        Value::Instance(_) | Value::Class(_) =>
          get_attr_from_value(target, attr)
        _ =>
          match (target, attr) {
            (Value::Str(text), "upper") => Ok(Value::Str(text.to_upper()))
            (Value::Int(_), "__hash__") =>
              Ok(
                Value::Function(FunctionValue::{
                  name: "__hash__",
                  params: [],
                  body: [],
                }),
              )
            (Value::Function(_), "__hash__") =>
              Ok(
                Value::Function(FunctionValue::{
                  name: "__hash__",
                  params: [],
                  body: [],
                }),
              )
            (Value::Function(func), "__doc__") =>
              if func.body.length() > 0 {
                match func.body[0] {
                  Stmt::ExprStmt(Expr::Literal(Literal::Str(text))) =>
                    Ok(Value::Str(text))
                  _ => Ok(Value::None)
                }
              } else {
                Ok(Value::None)
              }
            (Value::Function(func), "__name__") => Ok(Value::Str(func.name))
            (Value::Function(func), "__qualname__") => Ok(Value::Str(func.name))
            (Value::Function(_), "__code__") => Ok(Value::Str("<code>"))
            _ => {
              let type_name = match target {
                Value::Str(text) =>
                  if text == "<code>" {
                    "code"
                  } else {
                    "str"
                  }
                _ => type_name_from_value(target)
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "'" + type_name + "' object has no attribute '" + attr + "'",
                ),
              )
            }
          }
      }
    }
    Expr::Subscript(value~, index~) => {
      let target = match
        eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match index {
        Expr::Slice(start~, end~) => {
          let start_index = match start {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::Int(0L)
          }
          let end_index = match end {
            Some(expr) =>
              match eval_expr_with_env(expr, locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
            None => Value::None
          }
          let start = match index_from_value(start_index, 0) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match target {
            Value::List(values) => {
              let end = match index_from_value(end_index, values.length()) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::List(slice_values(values, start, end)))
            }
            Value::Tuple(values) => {
              let end = match index_from_value(end_index, values.length()) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::Tuple(slice_values(values, start, end)))
            }
            Value::Str(text) => {
              let chars = text.to_array()
              let end = match index_from_value(end_index, chars.length()) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::Str(slice_string(chars, start, end)))
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
            Value::Dict(values) => {
              for pair in values {
                if eq_value(pair.0, idx_value) {
                  return Ok(pair.1)
                }
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Key,
                  "key not found".to_string(),
                ),
              )
            }
            _ => {
              let idx = match index_from_value(idx_value, 0) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              match target {
                Value::List(values) =>
                  if idx >= 0 && idx < values.length() {
                    Ok(values[idx])
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                Value::Tuple(values) =>
                  if idx >= 0 && idx < values.length() {
                    Ok(values[idx])
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "index out of range".to_string(),
                      ),
                    )
                  }
                Value::Str(text) => {
                  let chars = text.to_array()
                  if idx >= 0 && idx < chars.length() {
                    Ok(Value::Str(char_to_string(chars[idx])))
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
      if bool_from_value(cond_value) {
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
          let (is_float, num) = match number_value(value) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if is_float {
            Ok(Value::Float(-num))
          } else {
            Ok(Value::Int(-num.to_int64()))
          }
        }
        UnaryOp::Pos => Ok(value)
        UnaryOp::Not => Ok(Value::Bool(!bool_from_value(value)))
        UnaryOp::Invert =>
          match value {
            Value::Int(v) => Ok(Value::Int(-(v + 1L)))
            Value::Bool(v) => Ok(Value::Int(-((if v { 1L } else { 0L }) + 1L)))
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
      match op {
        BinaryOp::Add =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
            (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
            (Value::Int(a), Value::Float(b)) =>
              Ok(Value::Float(a.to_double() + b))
            (Value::Float(a), Value::Int(b)) =>
              Ok(Value::Float(a + b.to_double()))
            (Value::Str(a), Value::Str(b)) => Ok(Value::Str(a + b))
            (Value::List(a), Value::List(b)) => {
              let merged : Array[Value] = []
              for item in a {
                merged.push(item)
              }
              for item in b {
                merged.push(item)
              }
              Ok(Value::List(merged))
            }
            _ => {
              if left_val is Value::Instance(_) {
                match get_attr_from_value(left_val, "__add__") {
                  Ok(method) =>
                    return call_callable_with_env(
                      method,
                      [right_val],
                      [],
                      globals,
                      builtins,
                      io,
                    )
                  Err(_) => ()
                }
              }
              if right_val is Value::Instance(_) {
                match get_attr_from_value(right_val, "__radd__") {
                  Ok(method) =>
                    return call_callable_with_env(
                      method,
                      [left_val],
                      [],
                      globals,
                      builtins,
                      io,
                    )
                  Err(_) => ()
                }
              }
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for +".to_string(),
                ),
              )
            }
          }
        BinaryOp::Sub => {
          let (left_is_float, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (right_is_float, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let result = left_num - right_num
          if left_is_float || right_is_float {
            Ok(Value::Float(result))
          } else {
            Ok(Value::Int(result.to_int64()))
          }
        }
        BinaryOp::Mul =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a * b))
            (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a * b))
            (Value::Int(a), Value::Float(b)) =>
              Ok(Value::Float(a.to_double() * b))
            (Value::Float(a), Value::Int(b)) =>
              Ok(Value::Float(a * b.to_double()))
            (Value::Str(text), Value::Int(count))
            | (Value::Int(count), Value::Str(text)) =>
              if count <= 0L {
                Ok(Value::Str(""))
              } else {
                let buf = StringBuilder::new()
                for i = 0; i < count.to_int(); i = i + 1 {
                  buf.write_string(text)
                }
                Ok(Value::Str(buf.to_string()))
              }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for *".to_string(),
                ),
              )
          }
        BinaryOp::Div => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Float(left_num / right_num))
        }
        BinaryOp::FloorDiv => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Int((left_num / right_num).floor().to_int64()))
        }
        BinaryOp::Mod => {
          let (_, left_num) = match number_value(left_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let (_, right_num) = match number_value(right_val) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Float(left_num % right_num))
        }
        BinaryOp::Pow =>
          match (left_val, right_val) {
            (Value::Int(left), Value::Int(right)) =>
              if right < 0L {
                Ok(
                  Value::Float(Double::pow(left.to_double(), right.to_double())),
                )
              } else {
                let mut result = 1L
                for i = 0; i < right.to_int(); i = i + 1 {
                  result = result * left
                }
                Ok(Value::Int(result))
              }
            _ => {
              let (_, left_num) = match number_value(left_val) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              let (_, right_num) = match number_value(right_val) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              Ok(Value::Float(Double::pow(left_num, right_num)))
            }
          }
        BinaryOp::MatMul =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for @".to_string(),
            ),
          )
        BinaryOp::ShiftLeft =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a << b.to_int()))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) << b.to_int()))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a << (if b { 1 } else { 0 })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int((if a { 1L } else { 0L }) << (if b { 1 } else { 0 })),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for <<".to_string(),
                ),
              )
          }
        BinaryOp::ShiftRight =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a >> b.to_int()))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) >> b.to_int()))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a >> (if b { 1 } else { 0 })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int((if a { 1L } else { 0L }) >> (if b { 1 } else { 0 })),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for >>".to_string(),
                ),
              )
          }
        BinaryOp::BitAnd =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a & b))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) & b))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a & (if b { 1L } else { 0L })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int(
                  (if a { 1L } else { 0L }) & (if b { 1L } else { 0L }),
                ),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for &".to_string(),
                ),
              )
          }
        BinaryOp::BitXor =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a ^ b))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) ^ b))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a ^ (if b { 1L } else { 0L })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int(
                  (if a { 1L } else { 0L }) ^ (if b { 1L } else { 0L }),
                ),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for ^".to_string(),
                ),
              )
          }
        BinaryOp::BitOr =>
          match (left_val, right_val) {
            (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a | b))
            (Value::Bool(a), Value::Int(b)) =>
              Ok(Value::Int((if a { 1L } else { 0L }) | b))
            (Value::Int(a), Value::Bool(b)) =>
              Ok(Value::Int(a | (if b { 1L } else { 0L })))
            (Value::Bool(a), Value::Bool(b)) =>
              Ok(
                Value::Int(
                  (if a { 1L } else { 0L }) | (if b { 1L } else { 0L }),
                ),
              )
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for |".to_string(),
                ),
              )
          }
      }
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
          match op {
            BoolOp::And => if !bool_from_value(result) { return Ok(result) }
            BoolOp::Or => if bool_from_value(result) { return Ok(result) }
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
        let ok = match ops[i] {
          CompareOp::Eq => eq_value(previous, current)
          CompareOp::NotEq => !eq_value(previous, current)
          CompareOp::Lt => {
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
          CompareOp::Lte => {
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
          CompareOp::Gt => {
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
          CompareOp::Gte => {
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
              Value::List(values) | Value::Tuple(values) | Value::Set(values) => {
                let mut found = false
                for item in values {
                  if eq_value(item, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Dict(pairs) => {
                let mut found = false
                for pair in pairs {
                  if eq_value(pair.0, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Str(text) =>
                match previous {
                  Value::Str(needle) => text.contains(needle)
                  _ => false
                }
              _ => false
            }
          CompareOp::NotIn =>
            !(match current {
              Value::List(values) | Value::Tuple(values) | Value::Set(values) => {
                let mut found = false
                for item in values {
                  if eq_value(item, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Dict(pairs) => {
                let mut found = false
                for pair in pairs {
                  if eq_value(pair.0, previous) {
                    found = true
                    break
                  }
                }
                found
              }
              Value::Str(text) =>
                match previous {
                  Value::Str(needle) => text.contains(needle)
                  _ => false
                }
              _ => false
            })
          _ => false
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
            let sep = match sep_value {
              Value::Str(text) => text
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "join separator must be str".to_string(),
                  ),
                )
            }
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
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "can only join an iterable".to_string(),
                  ),
                )
            }
            let buf = StringBuilder::new()
            for i = 0; i < parts.length(); i = i + 1 {
              if i > 0 {
                buf.write_string(sep)
              }
              buf.write_string(parts[i])
            }
            Ok(Value::Str(buf.to_string()))
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
            call_callable_with_env(
              callee_value, arg_values, keywords, globals, builtins, io,
            )
          }
        Expr::Name(name) =>
          match name {
            "print" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              let buf = StringBuilder::new()
              for i = 0; i < arg_values.length(); i = i + 1 {
                if i > 0 {
                  buf.write_string(" ")
                }
                let text = match
                  stringify_value_with_env(arg_values[i], globals, builtins, io) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                buf.write_string(text)
              }
              buf.write_string("\n")
              io.write_stdout(buf.to_string())
              Ok(Value::None)
            }
            "len" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() != 1 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "len() takes exactly one argument".to_string(),
                  ),
                )
              }
              match arg_values[0] {
                Value::Str(text) => Ok(Value::Int(text.length().to_int64()))
                Value::List(values) =>
                  Ok(Value::Int(values.length().to_int64()))
                Value::Tuple(values) =>
                  Ok(Value::Int(values.length().to_int64()))
                Value::Dict(pairs) => Ok(Value::Int(pairs.length().to_int64()))
                Value::Set(values) => Ok(Value::Int(values.length().to_int64()))
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "object has no len()".to_string(),
                    ),
                  )
              }
            }
            "range" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              fn to_int(value : Value) -> Result[Int64, RuntimeError] {
                match value {
                  Value::Int(v) => Ok(v)
                  Value::Bool(v) => Ok(if v { 1L } else { 0L })
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "range() integer argument expected".to_string(),
                      ),
                    )
                }
              }

              if arg_values.length() == 0 || arg_values.length() > 3 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "range() takes 1 to 3 arguments".to_string(),
                  ),
                )
              }
              let mut start = 0L
              let mut stop = 0L
              let mut step = 1L
              if arg_values.length() == 1 {
                stop = match to_int(arg_values[0]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
              } else if arg_values.length() == 2 {
                start = match to_int(arg_values[0]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                stop = match to_int(arg_values[1]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
              } else {
                start = match to_int(arg_values[0]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                stop = match to_int(arg_values[1]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                step = match to_int(arg_values[2]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
              }
              if step == 0L {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "range() arg 3 must not be zero".to_string(),
                  ),
                )
              }
              let items : Array[Value] = []
              let mut i = start
              if step > 0L {
                while i < stop {
                  items.push(Value::Int(i))
                  i = i + step
                }
              } else {
                while i > stop {
                  items.push(Value::Int(i))
                  i = i + step
                }
              }
              Ok(Value::List(items))
            }
            "sum" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 || arg_values.length() > 2 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "sum() takes 1 or 2 arguments".to_string(),
                  ),
                )
              }
              let items = match iterable_values(arg_values[0]) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              let mut is_float = false
              let mut total = 0.0
              if arg_values.length() == 2 {
                let (start_is_float, start_num) = match
                  number_value(arg_values[1]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                is_float = start_is_float
                total = start_num
              }
              for item in items {
                let (item_is_float, item_num) = match number_value(item) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if item_is_float {
                  is_float = true
                }
                total = total + item_num
              }
              if is_float {
                Ok(Value::Float(total))
              } else {
                Ok(Value::Int(total.to_int64()))
              }
            }
            "input" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() > 0 {
                io.write_stdout(value_to_string(arg_values[0]))
              }
              let line = io.read_line()
              if line is Some(line) {
                Ok(Value::Str(line))
              } else {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "EOF when reading a line".to_string(),
                  ),
                )
              }
            }
            "str" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Str(""))
              } else {
                let text = match
                  stringify_value_with_env(arg_values[0], globals, builtins, io) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                Ok(Value::Str(text))
              }
            }
            "int" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Int(0L))
              } else {
                match arg_values[0] {
                  Value::Int(v) => Ok(Value::Int(v))
                  Value::Bool(v) => Ok(Value::Int(if v { 1L } else { 0L }))
                  Value::Float(v) => Ok(Value::Int(v.to_int64()))
                  Value::Str(text) => {
                    let parsed = @strconv.parse_int(text) catch {
                      _ =>
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "ValueError: invalid literal for int()".to_string(),
                          ),
                        )
                    }
                    Ok(Value::Int(parsed.to_int64()))
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "int() argument must be a string or a number".to_string(),
                      ),
                    )
                }
              }
            }
            "float" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Float(0.0))
              } else {
                match arg_values[0] {
                  Value::Float(v) => Ok(Value::Float(v))
                  Value::Int(v) => Ok(Value::Float(v.to_double()))
                  Value::Bool(v) => Ok(Value::Float(if v { 1.0 } else { 0.0 }))
                  Value::Str(text) => {
                    let parsed = @strconv.parse_double(text) catch {
                      _ =>
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "ValueError: could not convert string to float".to_string(),
                          ),
                        )
                    }
                    Ok(Value::Float(parsed))
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "float() argument must be a string or a number".to_string(),
                      ),
                    )
                }
              }
            }
            "list" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::List([]))
              } else {
                let items = match iterable_values(arg_values[0]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                Ok(Value::List(items))
              }
            }
            "tuple" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Tuple([]))
              } else {
                let items = match iterable_values(arg_values[0]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                Ok(Value::Tuple(items))
              }
            }
            "set" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Set([]))
              } else {
                let items = match iterable_values(arg_values[0]) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let unique : Array[Value] = []
                for item in items {
                  let mut exists = false
                  for existing in unique {
                    if eq_value(existing, item) {
                      exists = true
                      break
                    }
                  }
                  if !exists {
                    unique.push(item)
                  }
                }
                Ok(Value::Set(unique))
              }
            }
            "dict" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              if arg_values.length() == 0 {
                Ok(Value::Dict([]))
              } else {
                match arg_values[0] {
                  Value::Dict(pairs) => Ok(Value::Dict(pairs))
                  Value::List(items) | Value::Tuple(items) => {
                    let pairs : Array[(Value, Value)] = []
                    for item in items {
                      match item {
                        Value::Tuple(values) | Value::List(values) =>
                          if values.length() == 2 {
                            pairs.push((values[0], values[1]))
                          } else {
                            return Err(
                              make_runtime_error(
                                RuntimeErrorKind::Runtime,
                                "ValueError: dictionary update sequence element has wrong length".to_string(),
                              ),
                            )
                          }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "cannot convert to dict".to_string(),
                            ),
                          )
                      }
                    }
                    Ok(Value::Dict(pairs))
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "cannot convert to dict".to_string(),
                      ),
                    )
                }
              }
            }
            "len" => {
              if args.length() != 1 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "len() takes exactly one argument".to_string(),
                  ),
                )
              }
              let value = match
                eval_expr_with_env(args[0], locals, globals, builtins, io) {
                Ok(value) => value
                Err(err) => return Err(err)
              }
              let length = match value {
                Value::Str(v) => v.length()
                Value::List(v) => v.length()
                Value::Tuple(v) => v.length()
                Value::Dict(v) => v.length()
                Value::Set(v) => v.length()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "object of type has no len()".to_string(),
                    ),
                  )
              }
              Ok(Value::Int(length.to_int64()))
            }
            "range" => {
              let arg_values : Array[Value] = []
              for arg in args {
                let value = match
                  eval_expr_with_env(arg, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                arg_values.push(value)
              }
              let (start, stop, step) = if arg_values.length() == 1 {
                (Value::Int(0L), arg_values[0], Value::Int(1L))
              } else if arg_values.length() == 2 {
                (arg_values[0], arg_values[1], Value::Int(1L))
              } else if arg_values.length() == 3 {
                (arg_values[0], arg_values[1], arg_values[2])
              } else {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "range() takes 1 to 3 arguments".to_string(),
                  ),
                )
              }
              let start_i = match start {
                Value::Int(v) => v.to_int()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "range() integer arguments expected".to_string(),
                    ),
                  )
              }
              let stop_i = match stop {
                Value::Int(v) => v.to_int()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "range() integer arguments expected".to_string(),
                    ),
                  )
              }
              let step_i = match step {
                Value::Int(v) => v.to_int()
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "range() integer arguments expected".to_string(),
                    ),
                  )
              }
              if step_i == 0 {
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: range() arg 3 must not be zero".to_string(),
                  ),
                )
              }
              let values : Array[Value] = []
              let mut i = start_i
              if step_i > 0 {
                while i < stop_i {
                  values.push(Value::Int(i.to_int64()))
                  i += step_i
                }
              } else {
                while i > stop_i {
                  values.push(Value::Int(i.to_int64()))
                  i += step_i
                }
              }
              Ok(Value::List(values))
            }
            _ => {
              let value = get_from_env(name, locals, globals, builtins)
              if value is Some(value) {
                let (arg_values, keywords) = match
                  eval_call_args(args, locals, globals, builtins, io) {
                  Ok(value) => value
                  Err(err) => return Err(err)
                }
                call_callable_with_env(
                  value, arg_values, keywords, globals, builtins, io,
                )
              } else {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Name,
                    "name '" + name + "' is not defined",
                  ),
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

///|
fn eval_call_args(
  args : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[(Array[Value], Array[(String, Value)]), RuntimeError] {
  let positional : Array[Value] = []
  let keywords : Array[(String, Value)] = []
  for arg in args {
    match arg {
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
        for item in items {
          positional.push(item)
        }
      }
      Expr::Keyword(name~, value~) => {
        let eval_value = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        keywords.push((name, eval_value))
      }
      _ => {
        let eval_value = match
          eval_expr_with_env(arg, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        positional.push(eval_value)
      }
    }
  }
  Ok((positional, keywords))
}

///|
fn eval_function_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals : Array[(String, Value)] = []
  let assigned : Array[Bool] = []
  for param in func.params {
    locals.push((param, Value::None))
    assigned.push(false)
  }
  for i = 0; i < positional.length() && i < func.params.length(); i = i + 1 {
    locals[i] = (func.params[i], positional[i])
    assigned[i] = true
  }
  for pair in keywords {
    let name = pair.0
    let value = pair.1
    for i = 0; i < func.params.length(); i = i + 1 {
      if func.params[i] == name {
        if assigned[i] {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              func.name + "() got multiple values for argument '" + name + "'",
            ),
          )
        }
        locals[i] = (name, value)
        assigned[i] = true
        break
      }
    }
  }
  let result = match eval_block(func.body, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(result)
}

///|
fn eval_function(
  func : FunctionValue,
  args : Array[Value],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let locals : Array[(String, Value)] = []
  for i = 0; i < func.params.length(); i = i + 1 {
    let value = if i < args.length() { args[i] } else { Value::None }
    locals.push((func.params[i], value))
  }
  let result = match eval_block(func.body, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(result)
}
