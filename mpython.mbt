///|
/// Implementation for the mpython interpreter runtime.

///|
fn bool_from_value(value : Value) -> Bool {
  match value {
    Value::None => false
    Value::Bool(v) => v
    Value::Int(v) => v != 0L
    Value::Float(v) => v != 0.0
    Value::Str(v) => v.length() > 0
    Value::List(v) => v.length() > 0
    Value::Tuple(v) => v.length() > 0
    Value::Dict(v) => v.length() > 0
    Value::Function(_) => true
  }
}

///|
fn value_to_string(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Str(v) => v
    Value::List(values) => {
      let buf = StringBuilder::new()
      buf.write_char('[')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char(']')
      buf.to_string()
    }
    Value::Tuple(values) => {
      let buf = StringBuilder::new()
      buf.write_char('(')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      if values.length() == 1 {
        buf.write_string(",")
      }
      buf.write_char(')')
      buf.to_string()
    }
    Value::Dict(_) => "{}"
    Value::Function(func) => "<function " + func.name + ">"
  }
}

///|
fn eq_value(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::None, Value::None) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Int(a), Value::Int(b)) => a == b
    (Value::Float(a), Value::Float(b)) => a == b
    (Value::Str(a), Value::Str(b)) => a == b
    (Value::List(a), Value::List(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Tuple(a), Value::Tuple(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if !eq_value(a[i], b[i]) {
            equal = false
            break
          }
        }
        equal
      }
    _ => false
  }
}

///|
fn number_value(value : Value) -> Result[(Bool, Double), RuntimeError] {
  match value {
    Value::Int(v) => Ok((false, v.to_double()))
    Value::Float(v) => Ok((true, v))
    Value::Bool(v) => Ok((false, if v { 1.0 } else { 0.0 }))
    _ =>
      Err(RuntimeError::{
        kind: RuntimeErrorKind::Type,
        message: "expected number".to_string(),
        span: None,
      })
  }
}

///|
fn make_runtime_error(
  kind : RuntimeErrorKind,
  message : String,
) -> RuntimeError {
  RuntimeError::{ kind, message, span: None }
}

///|
fn normalize_index(index : Int, length : Int) -> Int {
  if index < 0 {
    length + index
  } else {
    index
  }
}

///|
fn index_from_value(value : Value, default : Int) -> Result[Int, RuntimeError] {
  match value {
    Value::None => Ok(default)
    Value::Int(v) => Ok(v.to_int())
    Value::Bool(v) => Ok(if v { 1 } else { 0 })
    Value::Float(v) => Ok(v.to_int())
    _ => Err(make_runtime_error(RuntimeErrorKind::Type, "invalid index".to_string()))
  }
}

///|
fn slice_values(values : Array[Value], start : Int, end : Int) -> Array[Value] {
  let result : Array[Value] = []
  let len = values.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 { s = 0 }
  if e < 0 { e = 0 }
  if s > len { s = len }
  if e > len { e = len }
  for i = s; i < e; i = i + 1 {
    result.push(values[i])
  }
  result
}

///|
fn slice_string(chars : Array[Char], start : Int, end : Int) -> String {
  let len = chars.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 { s = 0 }
  if e < 0 { e = 0 }
  if s > len { s = len }
  if e > len { e = len }
  let buf = StringBuilder::new()
  for i = s; i < e; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn get_from_env(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Value? {
  for pair in locals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in builtins {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_global_value(
  globals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < globals.length(); i = i + 1 {
    if globals[i].0 == name {
      globals[i] = (name, value)
      return
    }
  }
  globals.push((name, value))
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
      let open = find_char(text, '{')
      let close = find_last_char(text, '}')
      if open is Some(open) && close is Some(close) && close > open {
        let prefix = substring(text, 0, open)
        let inner = substring(text, open + 1, close)
        let suffix = substring(text, close + 1, text.length())
        let expr = match parse_expr(inner) {
          Ok(value) => value
          Err(_) => return Ok(Value::Str(text))
        }
        let value = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        Ok(Value::Str(prefix + value_to_string(value) + suffix))
      } else {
        Ok(Value::Str(text))
      }
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
    Expr::Lambda(params~, body~) => {
      let func_body : Array[Stmt] = [Stmt::Return(Some(body))]
      Ok(Value::Function(FunctionValue::{ name: "<lambda>", params, body: func_body }))
    }
    Expr::Attribute(value~, attr~) => {
      let target = match eval_expr_with_env(value, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match (target, attr) {
        (Value::Str(text), "upper") => Ok(Value::Str(text.to_upper()))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "attribute not supported".to_string(),
            ),
          )
      }
    }
    Expr::Subscript(value~, index~) => {
      let target = match eval_expr_with_env(value, locals, globals, builtins, io) {
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
          let idx_value = match eval_expr_with_env(index, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let idx = match index_from_value(idx_value, 0) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          match target {
            Value::List(values) =>
              if idx >= 0 && idx < values.length() {
                Ok(values[idx])
              } else {
                Err(make_runtime_error(RuntimeErrorKind::Index, "index out of range".to_string()))
              }
            Value::Tuple(values) =>
              if idx >= 0 && idx < values.length() {
                Ok(values[idx])
              } else {
                Err(make_runtime_error(RuntimeErrorKind::Index, "index out of range".to_string()))
              }
            Value::Str(text) => {
              let chars = text.to_array()
              if idx >= 0 && idx < chars.length() {
                Ok(Value::Str(char_to_string(chars[idx])))
              } else {
                Err(make_runtime_error(RuntimeErrorKind::Index, "index out of range".to_string()))
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
        UnaryOp::Invert => {
          let (is_float, num) = match number_value(value) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          if is_float {
            Ok(Value::Int((-(num + 1.0)).to_int64()))
          } else {
            Ok(Value::Int((-(num + 1.0)).to_int64()))
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
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "unsupported operand type for +".to_string(),
                ),
              )
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
            (Value::Str(text), Value::Int(count)) =>
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
        BinaryOp::Pow => {
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
          _ => false
        }
        if !ok {
          return Ok(Value::Bool(false))
        }
        previous = current
      }
      Ok(Value::Bool(true))
    }
    Expr::Call(callee~, args~) => {
      let arg_values : Array[Value] = []
      for arg in args {
        let value = match
          eval_expr_with_env(arg, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        arg_values.push(value)
      }
      match callee {
        Expr::Name(name) =>
          match name {
            "print" => {
              let buf = StringBuilder::new()
              for i = 0; i < arg_values.length(); i = i + 1 {
                if i > 0 {
                  buf.write_string(" ")
                }
                buf.write_string(value_to_string(arg_values[i]))
              }
              buf.write_string("\n")
              io.write_stdout(buf.to_string())
              Ok(Value::None)
            }
            "input" => {
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
            "str" =>
              if arg_values.length() == 0 {
                Ok(Value::Str(""))
              } else {
                Ok(Value::Str(value_to_string(arg_values[0])))
              }
            _ => {
              let value = get_from_env(name, locals, globals, builtins)
              if value is Some(value) {
                match value {
                  Value::Function(func) =>
                    eval_function(func, arg_values, globals, builtins, io)
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "object is not callable".to_string(),
                      ),
                    )
                }
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
          match callee_value {
            Value::Function(func) =>
              eval_function(func, arg_values, globals, builtins, io)
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "object is not callable".to_string(),
                ),
              )
          }
        }
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

///|
fn eval_block(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let mut last = Value::None
  for stmt in body {
    match stmt {
      Stmt::ExprStmt(expr) =>
        last = match eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      Stmt::Assign(target~, value~) => {
        let eval_value = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        match target {
          Target::Name(name) => set_global_value(globals, name, eval_value)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::NotImplemented,
                "assignment target not supported".to_string(),
              ),
            )
        }
        last = Value::None
      }
      Stmt::Return(expr) => {
        if expr is Some(expr) {
          let value = match
            eval_expr_with_env(expr, locals, globals, builtins, io) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          return Ok(value)
        }
        return Ok(Value::None)
      }
      Stmt::Function(name~, params~, body~) => {
        let func = FunctionValue::{ name, params, body }
        set_global_value(globals, name, Value::Function(func))
        last = Value::None
      }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::NotImplemented,
            "statement not implemented".to_string(),
          ),
        )
    }
  }
  Ok(last)
}

///|
pub fn Config::default() -> Config {
  Config::{ max_recursion: 1000, traceback_limit: 20, track_spans: true }
}

///|
pub fn MockIO::new(stdin : Array[String]) -> MockIO {
  MockIO::{
    stdin,
    stdin_pos: { val: 0 },
    stdout: StringBuilder::new(),
    stderr: StringBuilder::new(),
  }
}

///|
pub fn MockIO::read_line(self : MockIO) -> String? {
  if self.stdin_pos.val >= self.stdin.length() {
    None
  } else {
    let line = self.stdin[self.stdin_pos.val]
    self.stdin_pos.val += 1
    Some(line)
  }
}

///|
pub fn MockIO::write_stdout(self : MockIO, text : String) -> Unit {
  self.stdout.write_string(text)
}

///|
pub fn MockIO::write_stderr(self : MockIO, text : String) -> Unit {
  self.stderr.write_string(text)
}

///|
pub fn MockIO::take_stdout(self : MockIO) -> String {
  self.stdout.to_string()
}

///|
pub fn MockIO::take_stderr(self : MockIO) -> String {
  self.stderr.to_string()
}

///|
pub fn Interpreter::new() -> Interpreter {
  Interpreter::with_io(Config::default(), MockIO::new([]))
}

///|
pub fn Interpreter::with_config(config : Config) -> Interpreter {
  Interpreter::with_io(config, MockIO::new([]))
}

///|
pub fn Interpreter::with_builtins(
  builtins : Array[(String, Value)],
  config : Config,
) -> Interpreter {
  Interpreter::{ config, globals: [], builtins, io: MockIO::new([]) }
}

///|
pub fn Interpreter::with_io(config : Config, io : MockIO) -> Interpreter {
  let builtins : Array[(String, Value)] = [
    (
      "print",
      Value::Function(FunctionValue::{ name: "print", params: [], body: [] }),
    ),
    (
      "input",
      Value::Function(FunctionValue::{ name: "input", params: [], body: [] }),
    ),
  ]
  Interpreter::{ config, globals: [], builtins, io }
}

///|
pub fn Interpreter::exec(
  self : Interpreter,
  program : Module,
) -> Result[RunResult, RuntimeError] {
  let value = match
    eval_block(program.body, [], self.globals, self.builtins, self.io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(RunResult::{
    value,
    stdout: self.io.take_stdout(),
    stderr: self.io.take_stderr(),
    globals: self.globals,
  })
}

///|
pub fn Interpreter::exec_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  let program = match parse(source) {
    Ok(value) => value
    Err(err) =>
      return Err(RuntimeError::{
        kind: RuntimeErrorKind::Runtime,
        message: format_parse_error(err),
        span: None,
      })
  }
  self.exec(program)
}

///|
pub fn Interpreter::eval(
  self : Interpreter,
  expr : Expr,
) -> Result[Value, RuntimeError] {
  eval_expr_with_env(expr, [], self.globals, self.builtins, self.io)
}

///|
pub fn Interpreter::get_global(self : Interpreter, name : String) -> Value? {
  for pair in self.globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
pub fn Interpreter::set_global(
  self : Interpreter,
  name : String,
  value : Value,
) -> Unit {
  set_global_value(self.globals, name, value)
}

///|
pub fn format_parse_error(error : ParseError) -> String {
  "line " +
  error.span.line.to_string() +
  ":" +
  error.span.column.to_string() +
  " " +
  error.message
}

///|
pub fn format_runtime_error(error : RuntimeError) -> String {
  match error.kind {
    RuntimeErrorKind::ZeroDivision => "ZeroDivisionError: " + error.message
    RuntimeErrorKind::Name => "NameError: " + error.message
    RuntimeErrorKind::Type => "TypeError: " + error.message
    RuntimeErrorKind::Attribute => "AttributeError: " + error.message
    RuntimeErrorKind::Index => "IndexError: " + error.message
    RuntimeErrorKind::Key => "KeyError: " + error.message
    RuntimeErrorKind::NotImplemented => "NotImplementedError: " + error.message
    RuntimeErrorKind::Runtime => error.message
  }
}
