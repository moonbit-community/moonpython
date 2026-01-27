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
          if other is Value::Instance(_) {
            match get_attr_from_value(other, "__add__", globals, builtins, io) {
              Ok(add_method) =>
                return call_callable_with_env(
                  add_method,
                  [Value::Complex(br, bi)],
                  [],
                  globals,
                  builtins,
                  io,
                )
              Err(_) => ()
            }
          }
          let (ar, ai) = match to_complex(other) {
            Ok(value) => value
            Err(err) => return Err(err)
          }
          Ok(Value::Complex(ar + br, ai + bi))
        }
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a + b))
        (Value::Float(a), Value::Float(b)) => Ok(Value::Float(a + b))
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) + (if b { 1N } else { 0N })))
        (Value::Bool(a), other) =>
          eval_binary_op_values(
            BinaryOp::Add,
            Value::Int(if a { 1N } else { 0N }),
            other,
            globals,
            builtins,
            io,
          )
        (other, Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::Add,
            other,
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
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
    BinaryOp::Sub => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__sub__", globals, builtins, io) {
          Ok(sub_method) =>
            return call_callable_with_env(
              sub_method,
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
          get_attr_from_value(right_val, "__rsub__", globals, builtins, io) {
          Ok(rsub_method) =>
            return call_callable_with_env(
              rsub_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::Mul => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__mul__", globals, builtins, io) {
          Ok(mul_method) =>
            return call_callable_with_env(
              mul_method,
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
          get_attr_from_value(right_val, "__rmul__", globals, builtins, io) {
          Ok(rmul_method) =>
            return call_callable_with_env(
              rmul_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
        (Value::Bool(a), Value::Bool(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) * (if b { 1N } else { 0N })))
        (Value::Bool(a), other) =>
          eval_binary_op_values(
            BinaryOp::Mul,
            Value::Int(if a { 1N } else { 0N }),
            other,
            globals,
            builtins,
            io,
          )
        (other, Value::Bool(b)) =>
          eval_binary_op_values(
            BinaryOp::Mul,
            other,
            Value::Int(if b { 1N } else { 0N }),
            globals,
            builtins,
            io,
          )
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
    }
    BinaryOp::Div => {
      if left_val is Value::Instance(_) {
        match
          get_attr_from_value(left_val, "__truediv__", globals, builtins, io) {
          Ok(truediv_method) =>
            return call_callable_with_env(
              truediv_method,
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
          get_attr_from_value(right_val, "__rtruediv__", globals, builtins, io) {
          Ok(rtruediv_method) =>
            return call_callable_with_env(
              rtruediv_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::FloorDiv => {
      if left_val is Value::Instance(_) {
        match
          get_attr_from_value(left_val, "__floordiv__", globals, builtins, io) {
          Ok(floordiv_method) =>
            return call_callable_with_env(
              floordiv_method,
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
          get_attr_from_value(right_val, "__rfloordiv__", globals, builtins, io) {
          Ok(rfloordiv_method) =>
            return call_callable_with_env(
              rfloordiv_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::Mod => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__mod__", globals, builtins, io) {
          Ok(mod_method) =>
            return call_callable_with_env(
              mod_method,
              [right_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
      // Don't bypass the '%' string-formatting protocol.
      if !(left_val is Value::Str(_)) && right_val is Value::Instance(_) {
        match
          get_attr_from_value(right_val, "__rmod__", globals, builtins, io) {
          Ok(rmod_method) =>
            return call_callable_with_env(
              rmod_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::Pow => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__pow__", globals, builtins, io) {
          Ok(pow_method) =>
            return call_callable_with_env(
              pow_method,
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
          get_attr_from_value(right_val, "__rpow__", globals, builtins, io) {
          Ok(rpow_method) =>
            return call_callable_with_env(
              rpow_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::MatMul => {
      if left_val is Value::Instance(_) {
        match
          get_attr_from_value(left_val, "__matmul__", globals, builtins, io) {
          Ok(matmul_method) =>
            return call_callable_with_env(
              matmul_method,
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
          get_attr_from_value(right_val, "__rmatmul__", globals, builtins, io) {
          Ok(rmatmul_method) =>
            return call_callable_with_env(
              rmatmul_method,
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
          "unsupported operand type for @".to_string(),
        ),
      )
    }
    BinaryOp::ShiftLeft => {
      if left_val is Value::Instance(_) {
        match
          get_attr_from_value(left_val, "__lshift__", globals, builtins, io) {
          Ok(lshift_method) =>
            return call_callable_with_env(
              lshift_method,
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
          get_attr_from_value(right_val, "__rlshift__", globals, builtins, io) {
          Ok(rlshift_method) =>
            return call_callable_with_env(
              rlshift_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::ShiftRight => {
      if left_val is Value::Instance(_) {
        match
          get_attr_from_value(left_val, "__rshift__", globals, builtins, io) {
          Ok(rshift_method) =>
            return call_callable_with_env(
              rshift_method,
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
          get_attr_from_value(right_val, "__rrshift__", globals, builtins, io) {
          Ok(rrshift_method) =>
            return call_callable_with_env(
              rrshift_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
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
    }
    BinaryOp::BitAnd => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__and__", globals, builtins, io) {
          Ok(and_method) =>
            return call_callable_with_env(
              and_method,
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
          get_attr_from_value(right_val, "__rand__", globals, builtins, io) {
          Ok(rand_method) =>
            return call_callable_with_env(
              rand_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a & b))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) & b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a & (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) => Ok(Value::Bool(a && b))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for &".to_string(),
            ),
          )
      }
    }
    BinaryOp::BitXor => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__xor__", globals, builtins, io) {
          Ok(xor_method) =>
            return call_callable_with_env(
              xor_method,
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
          get_attr_from_value(right_val, "__rxor__", globals, builtins, io) {
          Ok(rxor_method) =>
            return call_callable_with_env(
              rxor_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a ^ b))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) ^ b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a ^ (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) => Ok(Value::Bool(a != b))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unsupported operand type for ^".to_string(),
            ),
          )
      }
    }
    BinaryOp::BitOr => {
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, "__or__", globals, builtins, io) {
          Ok(or_method) =>
            return call_callable_with_env(
              or_method,
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
        match get_attr_from_value(right_val, "__ror__", globals, builtins, io) {
          Ok(ror_method) =>
            return call_callable_with_env(
              ror_method,
              [left_val],
              [],
              globals,
              builtins,
              io,
            )
          Err(_) => ()
        }
      }
      match (left_val, right_val) {
        (Value::Int(a), Value::Int(b)) => Ok(Value::Int(a | b))
        (Value::Bool(a), Value::Int(b)) =>
          Ok(Value::Int((if a { 1N } else { 0N }) | b))
        (Value::Int(a), Value::Bool(b)) =>
          Ok(Value::Int(a | (if b { 1N } else { 0N })))
        (Value::Bool(a), Value::Bool(b)) => Ok(Value::Bool(a || b))
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
}

///|
fn inplace_dunder_name(op : BinaryOp) -> String? {
  match op {
    BinaryOp::Add => Some("__iadd__")
    BinaryOp::Sub => Some("__isub__")
    BinaryOp::Mul => Some("__imul__")
    BinaryOp::MatMul => Some("__imatmul__")
    BinaryOp::Div => Some("__itruediv__")
    BinaryOp::FloorDiv => Some("__ifloordiv__")
    BinaryOp::Mod => Some("__imod__")
    BinaryOp::Pow => Some("__ipow__")
    BinaryOp::ShiftLeft => Some("__ilshift__")
    BinaryOp::ShiftRight => Some("__irshift__")
    BinaryOp::BitAnd => Some("__iand__")
    BinaryOp::BitXor => Some("__ixor__")
    BinaryOp::BitOr => Some("__ior__")
  }
}

///|
fn eval_augassign_op_values(
  op : BinaryOp,
  left_val : Value,
  right_val : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  // Builtin list in-place ops are observable via aliasing (`a is b`).
  match (op, left_val) {
    (BinaryOp::Add, Value::List(values)) => {
      let iterator = match
        iter_value_to_iterator(right_val, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      while true {
        match iterator_next(iterator, None, globals, builtins, io) {
          Ok(item) => values.push(item)
          Err(err) =>
            if err.exc_type == "StopIteration" {
              break
            } else {
              return Err(err)
            }
        }
      }
      return Ok(Value::List(values))
    }
    (BinaryOp::Mul, Value::List(values)) => {
      let count = match right_val {
        Value::Int(v) => v
        Value::Bool(v) => if v { 1N } else { 0N }
        _ =>
          return eval_binary_op_values(
            op,
            Value::List(values),
            right_val,
            globals,
            builtins,
            io,
          )
      }
      if count <= 0N {
        replace_array_values(values, [])
        return Ok(Value::List(values))
      }
      let count_i = match bigint_to_int_checked(count) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let original : Array[Value] = []
      for item in values {
        original.push(item)
      }
      let next : Array[Value] = []
      for _i = 0; _i < count_i; _i = _i + 1 {
        for item in original {
          next.push(item)
        }
      }
      replace_array_values(values, next)
      return Ok(Value::List(values))
    }
    _ => ()
  }

  // User-defined in-place dunders (`__iadd__`, `__imul__`, ...) take precedence.
  match inplace_dunder_name(op) {
    Some(name) =>
      if left_val is Value::Instance(_) {
        match get_attr_from_value(left_val, name, globals, builtins, io) {
          Ok(inplace_method) => {
            let out = match
              call_callable_with_env(
                inplace_method,
                [right_val],
                [],
                globals,
                builtins,
                io,
              ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            if !is_not_implemented_value(out) {
              return Ok(out)
            }
          }
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => ()
              _ => return Err(err)
            }
        }
      }
    None => ()
  }
  eval_binary_op_values(op, left_val, right_val, globals, builtins, io)
}
