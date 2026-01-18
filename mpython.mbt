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
  let _ = globals
  let _ = builtins
  let _ = io
  Ok(value_to_string(value))
}

///|
fn eval_binary_op_values(
  op : BinaryOp,
  left_val : Value,
  right_val : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match op {
    BinaryOp::Add =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
        (Value::Int(a), Value::Float(b)) => Ok(Value::Float(a.to_double() + b))
        (Value::Float(a), Value::Int(b)) => Ok(Value::Float(a + b.to_double()))
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
        (Value::Int(a), Value::Float(b)) => Ok(Value::Float(a.to_double() * b))
        (Value::Float(a), Value::Int(b)) => Ok(Value::Float(a * b.to_double()))
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
      if right_num == 0.0 {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::ZeroDivision,
            "division by zero".to_string(),
          ),
        )
      }
      Ok(Value::Float(left_num / right_num))
    }
    BinaryOp::FloorDiv => {
      let (left_is_float, left_num) = match number_value(left_val) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let (right_is_float, right_num) = match number_value(right_val) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if right_num == 0.0 {
        let msg = if left_is_float || right_is_float {
          "float floor division by zero".to_string()
        } else {
          "integer division or modulo by zero".to_string()
        }
        return Err(make_runtime_error(RuntimeErrorKind::ZeroDivision, msg))
      }
      Ok(Value::Int((left_num / right_num).floor().to_int64()))
    }
    BinaryOp::Mod => {
      let (left_is_float, left_num) = match number_value(left_val) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let (right_is_float, right_num) = match number_value(right_val) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      if right_num == 0.0 {
        let msg = if left_is_float || right_is_float {
          "float modulo".to_string()
        } else {
          "integer modulo by zero".to_string()
        }
        return Err(make_runtime_error(RuntimeErrorKind::ZeroDivision, msg))
      }
      Ok(Value::Float(left_num % right_num))
    }
    BinaryOp::Pow =>
      match (left_val, right_val) {
        (Value::Int(left), Value::Int(right)) =>
          if right < 0L {
            Ok(Value::Float(Double::pow(left.to_double(), right.to_double())))
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
          Ok(Value::Int((if a { 1L } else { 0L }) << (if b { 1 } else { 0 })))
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
          Ok(Value::Int((if a { 1L } else { 0L }) >> (if b { 1 } else { 0 })))
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
          Ok(Value::Int((if a { 1L } else { 0L }) & (if b { 1L } else { 0L })))
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
          Ok(Value::Int((if a { 1L } else { 0L }) ^ (if b { 1L } else { 0L })))
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
          Ok(Value::Int((if a { 1L } else { 0L }) | (if b { 1L } else { 0L })))
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
          defaults: [],
          body: [],
          is_generator: false,
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
      fn set_pair(
        pairs : Array[(Value, Value)],
        key : Value,
        value : Value,
      ) -> Unit {
        for i = 0; i < pairs.length(); i = i + 1 {
          if eq_value(pairs[i].0, key) {
            pairs[i] = (key, value)
            return
          }
        }
        pairs.push((key, value))
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
                  set_pair(values, pair.0, pair.1)
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
            set_pair(values, key, value)
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
          }
          _ => {
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
      let func_body : Array[Stmt] = [Stmt::Return(Some(body))]
      Ok(
        Value::Function(FunctionValue::{
          name: "<lambda>",
          params,
          defaults: default_values,
          body: func_body,
          is_generator: false,
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
                  defaults: [],
                  body: [],
                  is_generator: false,
                }),
              )
            (Value::Function(_), "__hash__") =>
              Ok(
                Value::Function(FunctionValue::{
                  name: "__hash__",
                  params: [],
                  defaults: [],
                  body: [],
                  is_generator: false,
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
          match target {
            Value::List(values) => {
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
        Expr::Name(name) => {
          let callee_value = get_from_env(name, locals, globals, builtins)
          if callee_value is Some(callee_value) {
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
                      name, arg_values, keywords, locals, globals, builtins, io,
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
          } else {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Name,
                "name '" + name + "' is not defined",
              ),
            )
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
      Expr::DoubleStarred(value~) => {
        let mapping = match
          eval_expr_with_env(value, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match mapping {
          Value::Dict(pairs) =>
            for pair in pairs {
              match pair.0 {
                Value::Str(name) => keywords.push((name, pair.1))
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "keywords must be strings".to_string(),
                    ),
                  )
              }
            }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "keywords must be strings".to_string(),
              ),
            )
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
  if positional.length() > func.params.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        func.name +
        "() takes " +
        func.params.length().to_string() +
        " positional arguments but " +
        positional.length().to_string() +
        " were given",
      ),
    )
  }
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
    let mut found = false
    for i = 0; i < func.params.length(); i = i + 1 {
      if func.params[i] == name {
        found = true
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
    if !found {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          func.name + "() got an unexpected keyword argument '" + name + "'",
        ),
      )
    }
  }
  if func.defaults.length() > func.params.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "RuntimeError: bad function defaults".to_string(),
      ),
    )
  }
  let required_count = func.params.length() - func.defaults.length()
  for i = required_count; i < func.params.length(); i = i + 1 {
    if !assigned[i] {
      locals[i] = (func.params[i], func.defaults[i - required_count])
      assigned[i] = true
    }
  }
  let missing : Array[String] = []
  for i = 0; i < required_count; i = i + 1 {
    if !assigned[i] {
      missing.push(func.params[i])
    }
  }
  if missing.length() > 0 {
    let buf = StringBuilder::new()
    buf.write_string(func.name)
    buf.write_string("() missing ")
    buf.write_string(missing.length().to_string())
    buf.write_string(" required positional argument")
    if missing.length() != 1 {
      buf.write_string("s")
    }
    buf.write_string(": ")
    for i = 0; i < missing.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string("'")
      buf.write_string(missing[i])
      buf.write_string("'")
    }
    return Err(make_runtime_error(RuntimeErrorKind::Type, buf.to_string()))
  }
  let result = match eval_block(func.body, locals, globals, builtins, io) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(result)
}

///|
let runtime_callbacks_ready : Ref[Bool] = { val: false }

///|
fn ensure_runtime_callbacks_ready() -> Unit {
  if runtime_callbacks_ready.val {
    return
  }
  set_eval_function_with_kwargs_callback(eval_function_with_kwargs)
  runtime_callbacks_ready.val = true
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
