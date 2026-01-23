///|
/// Binary operator evaluation helpers.

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
        (Value::Complex(ar, ai), Value::Complex(br, bi)) =>
          Ok(Value::Complex(ar + br, ai + bi))
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar + br, ai + bi))
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar + br, ai + bi))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
        (Value::Int(a), Value::Float(b)) => {
          let aa = match bigint_to_double_checked(a) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(aa + b))
        }
        (Value::Float(a), Value::Int(b)) => {
          let bb = match bigint_to_double_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(a + bb))
        }
        (Value::Str(a), Value::Str(b)) => Ok(Value::Str(a + b))
        (Value::Bytes(a), Value::Bytes(b)) => {
          let merged : Array[Int] = []
          for item in a {
            merged.push(item)
          }
          for item in b {
            merged.push(item)
          }
          Ok(Value::Bytes(merged))
        }
        (Value::ByteArray(a), Value::ByteArray(b)) => {
          let merged : Array[Int] = []
          for item in a {
            merged.push(item)
          }
          for item in b {
            merged.push(item)
          }
          Ok(Value::ByteArray(merged))
        }
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
        (Value::Tuple(a), Value::Tuple(b)) => {
          let merged : Array[Value] = []
          for item in a {
            merged.push(item)
          }
          for item in b {
            merged.push(item)
          }
          Ok(Value::Tuple(merged))
        }
        _ => {
          if left_val is Value::Instance(_) {
            match
              get_attr_from_value(left_val, "__add__", globals, builtins, io) {
              Ok(add_method) =>
                return call_callable_with_env(
                  add_method,
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
            match
              get_attr_from_value(right_val, "__radd__", globals, builtins, io) {
              Ok(radd_method) =>
                return call_callable_with_env(
                  radd_method,
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
    BinaryOp::Sub =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) =>
          Ok(Value::Complex(ar - br, ai - bi))
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar - br, ai - bi))
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar - br, ai - bi))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a - b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a - b))
        (Value::Int(a), Value::Float(b)) => {
          let aa = match bigint_to_double_checked(a) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(aa - b))
        }
        (Value::Float(a), Value::Int(b)) => {
          let bb = match bigint_to_double_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(a - bb))
        }
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) - (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) - b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a - (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Float(b)) =>
          Ok(Value::Float((if a { 1.0 } else { 0.0 }) - b))
        (Value::Float(a), Value::Bool(b)) =>
          Ok(Value::Float(a - (if b { 1.0 } else { 0.0 })))
        (Value::Set(left), Value::Set(right)) => {
          let out : Array[Value] = []
          for item in left {
            let idx = match set_find_index(right, item) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            if idx is None {
              out.push(item)
            }
          }
          Ok(Value::Set(out))
        }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for -".to_string(),
            ),
          )
      }
    BinaryOp::Mul =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) =>
          Ok(Value::Complex(ar * br - ai * bi, ar * bi + ai * br))
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar * br - ai * bi, ar * bi + ai * br))
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar * br - ai * bi, ar * bi + ai * br))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a * b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a * b))
        (Value::Int(a), Value::Float(b)) => {
          let aa = match bigint_to_double_checked(a) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(aa * b))
        }
        (Value::Float(a), Value::Int(b)) => {
          let bb = match bigint_to_double_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Float(a * bb))
        }
        (Value::Str(text), Value::Int(count))
        | (Value::Int(count), Value::Str(text)) =>
          if count <= 0N {
            Ok(Value::Str(""))
          } else {
            let buf = StringBuilder::new()
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for i = 0; i < count_i; i = i + 1 {
              buf.write_string(text)
            }
            Ok(Value::Str(buf.to_string()))
          }
        (Value::Bytes(bytes), Value::Int(count))
        | (Value::Int(count), Value::Bytes(bytes)) =>
          if count <= 0N {
            Ok(Value::Bytes([]))
          } else {
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let out : Array[Int] = []
            for i = 0; i < count_i; i = i + 1 {
              for byte in bytes {
                out.push(byte)
              }
            }
            Ok(Value::Bytes(out))
          }
        (Value::ByteArray(bytes), Value::Int(count))
        | (Value::Int(count), Value::ByteArray(bytes)) =>
          if count <= 0N {
            Ok(Value::ByteArray([]))
          } else {
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let out : Array[Int] = []
            for i = 0; i < count_i; i = i + 1 {
              for byte in bytes {
                out.push(byte)
              }
            }
            Ok(Value::ByteArray(out))
          }
        (Value::List(values), Value::Int(count))
        | (Value::Int(count), Value::List(values)) =>
          if count <= 0N {
            Ok(Value::List([]))
          } else {
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let out : Array[Value] = []
            for i = 0; i < count_i; i = i + 1 {
              for item in values {
                out.push(item)
              }
            }
            Ok(Value::List(out))
          }
        (Value::Tuple(values), Value::Int(count))
        | (Value::Int(count), Value::Tuple(values)) =>
          if count <= 0N {
            Ok(Value::Tuple([]))
          } else {
            let count_i = match bigint_to_int_checked(count) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let out : Array[Value] = []
            for i = 0; i < count_i; i = i + 1 {
              for item in values {
                out.push(item)
              }
            }
            Ok(Value::Tuple(out))
          }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for *".to_string(),
            ),
          )
      }
    BinaryOp::Div =>
      match (left_val, right_val) {
        (Value::Complex(ar, ai), Value::Complex(br, bi)) => {
          let denom = br * br + bi * bi
          if denom == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(
            Value::Complex(
              (ar * br + ai * bi) / denom,
              (ai * br - ar * bi) / denom,
            ),
          )
        }
        (Value::Complex(ar, ai), other) => {
          let (br, bi) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let denom = br * br + bi * bi
          if denom == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(
            Value::Complex(
              (ar * br + ai * bi) / denom,
              (ai * br - ar * bi) / denom,
            ),
          )
        }
        (other, Value::Complex(br, bi)) => {
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          let denom = br * br + bi * bi
          if denom == 0.0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "division by zero".to_string(),
              ),
            )
          }
          Ok(
            Value::Complex(
              (ar * br + ai * bi) / denom,
              (ai * br - ar * bi) / denom,
            ),
          )
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
      }
    BinaryOp::FloorDiv =>
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => {
          if b == 0N {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "integer division or modulo by zero".to_string(),
              ),
            )
          }
          let q0 = a / b
          let r0 = a % b
          let q = if r0 != 0N && (r0 < 0N) != (b < 0N) { q0 - 1N } else { q0 }
          Ok(Value::Int(q))
        }
        (Value::Bool(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::FloorDiv,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        (Value::Bool(a), Value::Int(b)) =>
          eval_binary_op_values(
            BinaryOp::FloorDiv,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(b),
            globals,
            builtins,
            io,
          )
        (Value::Int(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::FloorDiv,
            Value::Int(a),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        _ => {
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
          Ok(Value::Float((left_num / right_num).floor()))
        }
      }
    BinaryOp::Mod =>
      match (left_val, right_val) {
        (Value::Str(format), value) => {
          let formatted = match format_percent_string(format, value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Str(formatted))
        }
        (Value::Int(a), Value::Int(b)) => {
          if b == 0N {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "integer modulo by zero".to_string(),
              ),
            )
          }
          let r0 = a % b
          let needs_adjust = r0 != 0N && (r0 < 0N) != (b < 0N)
          let r = if needs_adjust { r0 + b } else { r0 }
          Ok(Value::Int(r))
        }
        (Value::Bool(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::Mod,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        (Value::Bool(a), Value::Int(b)) =>
          eval_binary_op_values(
            BinaryOp::Mod,
            Value::Int(if a { 1N } else { 0N }),
            Value::Int(b),
            globals,
            builtins,
            io,
          )
        (Value::Int(a), Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::Mod,
            Value::Int(a),
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
        _ => {
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
      }
    BinaryOp::Pow =>
      match (left_val, right_val) {
        (Value::Int(left), Value::Int(right)) =>
          if right < 0N {
            Ok(
              Value::Float(
                @math.pow(
                  match bigint_to_double_checked(left) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  },
                  match bigint_to_double_checked(right) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  },
                ),
              ),
            )
          } else {
            Ok(Value::Int(left.pow(right)))
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
          Ok(Value::Float(@math.pow(left_num, right_num)))
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
        (Value::Int(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int(a << bb))
        }
        (Value::Bool(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int((if a { 1N } else { 0N }) << bb))
        }
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a << (if b { 1 } else { 0 })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) << (if b { 1 } else { 0 })))
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
        (Value::Int(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int(a >> bb))
        }
        (Value::Bool(a), Value::Int(b)) => {
          let bb = match bigint_to_int_checked(b) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int((if a { 1N } else { 0N }) >> bb))
        }
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a >> (if b { 1 } else { 0 })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) >> (if b { 1 } else { 0 })))
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
          Ok(Value::Int((if a { 1N } else { 0N }) & b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a & (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) & (if b { 1N } else { 0N })))
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
          Ok(Value::Int((if a { 1N } else { 0N }) ^ b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a ^ (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) ^ (if b { 1N } else { 0N })))
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
          Ok(Value::Int((if a { 1N } else { 0N }) | b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a | (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) | (if b { 1N } else { 0N })))
        (Value::Set(left), Value::Set(right)) => {
          let values : Array[Value] = []
          for item in left {
            let _ = match set_add_unique(values, item) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          for item in right {
            let _ = match set_add_unique(values, item) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          Ok(Value::Set(values))
        }
        (Value::Dict(left), Value::Dict(right)) => {
          // PEP 584: dict union.
          let out : Array[(Value, Value)] = []
          for pair in left {
            out.push(pair)
          }
          for pair in right {
            let _ = match dict_set_item(out, pair.0, pair.1) {
              Ok(v) => v
              Err(err) => return Err(err)
            }

          }
          Ok(Value::Dict(out))
        }
        _ => {
          let left_args = union_args_from_value(left_val, builtins)
          let right_args = union_args_from_value(right_val, builtins)
          match (left_args, right_args) {
            (Some(left), Some(right)) => {
              let args : Array[Value] = []
              for value in left {
                args.push(value)
              }
              for value in right {
                args.push(value)
              }
              Ok(make_union_type(args))
            }
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
  }
}
