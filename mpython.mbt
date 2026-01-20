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
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).to_char().unwrap()
  } else {
    ('a'.to_int() + (n - 10)).to_char().unwrap()
  }
}

///|
fn hex_width(codepoint : Int, width : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < width {
    let shift = 4 * (width - 1 - i)
    let digit = (codepoint >> shift) & 0xF
    buf.write_char(hex_digit(digit))
    i = i + 1
  }
  buf.to_string()
}

///|
fn ascii_escape(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text.to_array() {
    let code = ch.to_int()
    if code < 0x80 {
      buf.write_char(ch)
    } else if code <= 0xFFFF {
      buf.write_string("\\u")
      buf.write_string(hex_width(code, 4))
    } else {
      buf.write_string("\\U")
      buf.write_string(hex_width(code, 8))
    }
  }
  buf.to_string()
}

///|
fn fstring_value_to_text(
  value : Value,
  conv : Char?,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[String, RuntimeError] {
  match conv {
    None => stringify_value_with_env(value, globals, builtins, io)
    Some('s') =>
      match
        eval_builtin_call("str", [value], [], locals, globals, builtins, io) {
        Ok(Some(Value::Str(text))) => Ok(text)
        Ok(Some(other)) => Ok(value_to_string(other))
        Ok(None) => stringify_value_with_env(value, globals, builtins, io)
        Err(err) => Err(err)
      }
    Some('r') =>
      match
        eval_builtin_call("repr", [value], [], locals, globals, builtins, io) {
        Ok(Some(Value::Str(text))) => Ok(text)
        Ok(Some(other)) => Ok(value_to_string(other))
        Ok(None) => stringify_value_with_env(value, globals, builtins, io)
        Err(err) => Err(err)
      }
    Some('a') => {
      let base = match
        eval_builtin_call("repr", [value], [], locals, globals, builtins, io) {
        Ok(Some(Value::Str(text))) => text
        Ok(Some(other)) => value_to_string(other)
        Ok(None) => value_to_string(value)
        Err(err) => return Err(err)
      }
      Ok(ascii_escape(base))
    }
    Some(_) => stringify_value_with_env(value, globals, builtins, io)
  }
}

///|
fn format_string_width(
  text : String,
  spec : String,
  default_align : Char,
) -> String? {
  if spec.length() == 0 {
    return None
  }
  let chars = spec.to_array()
  let mut fill = ' '
  let mut align : Char? = None
  let mut i = 0
  if chars.length() >= 2 &&
    (chars[1] == '<' || chars[1] == '>' || chars[1] == '^') {
    fill = chars[0]
    align = Some(chars[1])
    i = 2
  } else if chars[0] == '<' || chars[0] == '>' || chars[0] == '^' {
    align = Some(chars[0])
    i = 1
  } else if is_digit(chars[0]) {
    align = Some(default_align)
    i = 0
  } else {
    return None
  }
  let start = i
  while i < chars.length() && is_digit(chars[i]) {
    i += 1
  }
  if start == i || i != chars.length() {
    return None
  }
  let width_text = substring(spec, start, i)
  let width = parse_decimal_int(width_text)
  if width <= 0 {
    return Some(text)
  }
  let len = text.length()
  if len >= width {
    return Some(text)
  }
  let pad = width - len
  let left = match align.unwrap_or(default_align) {
    '<' => 0
    '>' => pad
    '^' => pad / 2
    _ => 0
  }
  let right = pad - left
  let buf = StringBuilder::new()
  for i = 0; i < left; i = i + 1 {
    buf.write_char(fill)
  }
  buf.write_string(text)
  for i = 0; i < right; i = i + 1 {
    buf.write_char(fill)
  }
  Some(buf.to_string())
}

///|
fn parse_decimal_int(text : String) -> Int {
  let chars = text.to_array()
  let mut n = 0
  for c in chars {
    if is_digit(c) {
      n = n * 10 + (c.to_int() - 48)
    }
  }
  n
}

///|
fn fstring_int_to_base_string(
  value : @bigint.BigInt,
  base : Int,
  uppercase : Bool,
) -> String {
  if value == 0N {
    return "0"
  }
  let digits_table : Array[Char] = "0123456789abcdef".to_array()
  let upper_table : Array[Char] = "0123456789ABCDEF".to_array()
  let table = if uppercase { upper_table } else { digits_table }
  let mut n = value
  let b = @bigint.BigInt::from_int(base)
  let digits : Array[Char] = []
  while n > 0N {
    let d = (n % b).to_int()
    digits.push(table[d])
    n = n / b
  }
  let buf = StringBuilder::new()
  let mut i = digits.length()
  while i > 0 {
    i = i - 1
    buf.write_char(digits[i])
  }
  buf.to_string()
}

///|
fn format_int_with_spec(value : @bigint.BigInt, spec : String) -> String? {
  if spec.length() == 0 {
    return None
  }
  let chars = spec.to_array()
  let mut i = 0
  let mut alternate = false
  if chars[0] == '#' {
    alternate = true
    i = 1
  }
  let mut zero_pad = false
  if i < chars.length() && chars[i] == '0' {
    zero_pad = true
    i += 1
  }
  let width_start = i
  while i < chars.length() && is_digit(chars[i]) {
    i += 1
  }
  let width = if i > width_start {
    parse_decimal_int(substring(spec, width_start, i))
  } else {
    0
  }
  if i >= chars.length() {
    return None
  }
  let typ = chars[i]
  if i + 1 != chars.length() {
    return None
  }
  let neg = value < 0N
  let abs_value = if neg { -value } else { value }
  let (prefix, base, uppercase, decimal) = match typ {
    'd' => ("", 10, false, true)
    'x' => ("0x", 16, false, false)
    'X' => ("0X", 16, true, false)
    'o' => ("0o", 8, false, false)
    'b' => ("0b", 2, false, false)
    _ => return None
  }
  let digits = if decimal {
    abs_value.to_string()
  } else {
    fstring_int_to_base_string(abs_value, base, uppercase)
  }
  let sign = if neg { "-" } else { "" }
  let alt_prefix = if alternate && !decimal { prefix } else { "" }
  let mut core = sign.to_string() + alt_prefix + digits
  if width > 0 && core.length() < width {
    let pad = width - core.length()
    if zero_pad {
      let buf = StringBuilder::new()
      buf.write_string(sign)
      buf.write_string(alt_prefix)
      for i = 0; i < pad; i = i + 1 {
        buf.write_char('0')
      }
      buf.write_string(digits)
      core = buf.to_string()
    } else {
      let buf = StringBuilder::new()
      for i = 0; i < pad; i = i + 1 {
        buf.write_char(' ')
      }
      buf.write_string(core)
      core = buf.to_string()
    }
  }
  Some(core)
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
            match
              get_attr_from_value(left_val, "__add__", globals, builtins, io) {
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
            match
              get_attr_from_value(right_val, "__radd__", globals, builtins, io) {
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
    BinaryOp::Sub =>
      match (left_val, right_val) {
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
        (Value::Int(a), Value::Int(b)) => {
          if b == 0N {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::ZeroDivision,
                "integer modulo by zero".to_string(),
              ),
            )
          }
          let q0 = a / b
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
                Double::pow(
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
        let (expr_and_conv, format_spec_raw) = match
          find_top_level_format_colon(inner) {
          Some(pos) =>
            (
              substring(inner, 0, pos),
              substring(inner, pos + 1, inner.length()),
            )
          None => (inner, "".to_string())
        }
        let (expr_raw, conv) = match
          find_top_level_fstring_conversion_bang(expr_and_conv) {
          Some(pos) =>
            if pos + 1 < expr_and_conv.length() {
              let conv_char = expr_and_conv.to_array()[pos + 1]
              (substring(expr_and_conv, 0, pos), Some(conv_char))
            } else {
              (expr_and_conv, None)
            }
          None => (expr_and_conv, None)
        }
        let debug_eq = find_top_level_fstring_debug_equal(expr_raw)
        let (expr_text, debug_prefix) = match debug_eq {
          Some(pos) => {
            let mut prefix_end = pos + 1
            let chars = expr_raw.to_array()
            while prefix_end < chars.length() {
              let c = chars[prefix_end]
              if c == ' ' || c == '\t' {
                prefix_end += 1
              } else {
                break
              }
            }
            (
              substring(expr_raw, 0, pos).trim(chars=" \t").to_string(),
              Some(substring(expr_raw, 0, prefix_end)),
            )
          }
          None => (expr_raw.trim(chars=" \t").to_string(), None)
        }
        let expr = match parse_expr(expr_text) {
          Ok(value) => value
          Err(_) => return Ok(Value::Str(text))
        }
        let value = match
          eval_expr_with_env(expr, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let rendered = match
          fstring_value_to_text(value, conv, locals, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let formatted = if format_spec_raw.trim(chars=" \t").length() == 0 ||
          format_spec_raw.contains("{") ||
          format_spec_raw.contains("}") {
          rendered
        } else {
          match conv {
            Some(_) =>
              match format_string_width(rendered, format_spec_raw, '<') {
                Some(v) => v
                None => rendered
              }
            None =>
              match value {
                Value::Int(n) =>
                  match format_int_with_spec(n, format_spec_raw) {
                    Some(v) => v
                    None =>
                      match
                        format_string_width(rendered, format_spec_raw, '>') {
                        Some(v) => v
                        None => rendered
                      }
                  }
                _ =>
                  match format_string_width(rendered, format_spec_raw, '<') {
                    Some(v) => v
                    None => rendered
                  }
              }
          }
        }
        match debug_prefix {
          Some(prefix) => {
            buf.write_string(prefix)
            buf.write_string(formatted)
          }
          None => buf.write_string(formatted)
        }
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
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[(Array[String], Expr)] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].1, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push((clauses[0].0, Expr::Name(iter_name)))
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
        for name in clause.0 {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
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
      let gen_locals = clone_locals(locals)
      for clause in clauses {
        for name in clause.0 {
          if name != "_" {
            ensure_local_cell(gen_locals, name, Value::None)
          }
        }
      }
      if clauses.length() == 0 {
        let body = genexp_to_generator_body(elt, clauses, filters)
        return Ok(
          generator_new(body, gen_locals, globals, builtins, io, [], [], []),
        )
      }
      let first_iter_value = match
        eval_expr_with_env(clauses[0].1, locals, globals, builtins, io) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let first_iterator = match iter_value_to_iterator(first_iter_value) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let iter_name = fresh_genexp_local(gen_locals)
      set_local_value(gen_locals, iter_name, first_iterator)
      let adjusted_clauses : Array[(Array[String], Expr)] = []
      adjusted_clauses.push((clauses[0].0, Expr::Name(iter_name)))
      for i = 1; i < clauses.length(); i = i + 1 {
        adjusted_clauses.push(clauses[i])
      }
      let body = genexp_to_generator_body(elt, adjusted_clauses, filters)
      Ok(generator_new(body, gen_locals, globals, builtins, io, [], [], []))
    }
    Expr::SetComp(elt~, clauses~, filters~) => {
      let comp_locals = clone_locals(locals)
      let adjusted_clauses : Array[(Array[String], Expr)] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].1, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push((clauses[0].0, Expr::Name(iter_name)))
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
        for name in clause.0 {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
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
      let adjusted_clauses : Array[(Array[String], Expr)] = []
      if clauses.length() > 0 {
        let first_iter_value = match
          eval_expr_with_env(clauses[0].1, locals, globals, builtins, io) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let iter_name = fresh_genexp_local(comp_locals)
        set_local_value(comp_locals, iter_name, first_iter_value)
        adjusted_clauses.push((clauses[0].0, Expr::Name(iter_name)))
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
        for name in clause.0 {
          if name != "_" {
            ensure_local_cell(comp_locals, name, Value::None)
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
          is_async: false,
          closure: capture_cell_closure(locals),
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
        Value::Instance(_) | Value::Class(_) | Value::List(_) =>
          get_attr_from_value(target, attr, globals, builtins, io)
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
                  is_async: false,
                  closure: [],
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
                  is_async: false,
                  closure: [],
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
                Value::List(values) => {
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
            match value {
              Value::Int(v) => Ok(Value::Int(-v))
              Value::Bool(v) => Ok(Value::Int(-(if v { 1N } else { 0N })))
              _ => Ok(Value::Int(-@bigint.BigInt::from_int64(num.to_int64())))
            }
          }
        }
        UnaryOp::Pos => Ok(value)
        UnaryOp::Not => Ok(Value::Bool(!bool_from_value(value)))
        UnaryOp::Invert =>
          match value {
            Value::Int(v) => Ok(Value::Int(-(v + 1N)))
            Value::Bool(v) => Ok(Value::Int(-((if v { 1N } else { 0N }) + 1N)))
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
                match iterable_values(iter_value) {
                  Ok(values) =>
                    for v in values {
                      parts.push(value_to_string(v))
                    }
                  Err(_) =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "can only join an iterable".to_string(),
                      ),
                    )
                }
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
fn genexp_targets_to_target(targets : Array[String]) -> Target {
  if targets.length() == 1 {
    Target::Name(targets[0])
  } else {
    let out : Array[Target] = []
    for name in targets {
      out.push(Target::Name(name))
    }
    Target::Tuple(out)
  }
}

///|
fn genexp_filters_to_condition(filters : Array[Expr]) -> Expr? {
  if filters.length() == 0 {
    None
  } else if filters.length() == 1 {
    Some(filters[0])
  } else {
    Some(Expr::BoolOp(op=BoolOp::And, values=filters))
  }
}

///|
fn genexp_to_generator_body(
  elt : Expr,
  clauses : Array[(Array[String], Expr)],
  filters : Array[Expr],
) -> Array[Stmt] {
  let inner : Array[Stmt] = [Stmt::Yield(Some(elt))]
  let conditioned = match genexp_filters_to_condition(filters) {
    Some(cond) => [Stmt::If(condition=cond, body=inner, else_body=[])]
    None => inner
  }
  let mut body = conditioned
  let mut i = clauses.length()
  while i > 0 {
    i = i - 1
    let clause = clauses[i]
    body = [
      Stmt::For(
        target=genexp_targets_to_target(clause.0),
        iter=clause.1,
        body~,
        else_body=[],
      ),
    ]
  }
  body
}

///|
fn genexp_local_taken(locals : Array[(String, Value)], name : String) -> Bool {
  for pair in locals {
    if pair.0 == name {
      return true
    }
  }
  false
}

///|
fn fresh_genexp_local(locals : Array[(String, Value)]) -> String {
  let base = "__mpython_genexp_iter".to_string()
  if !genexp_local_taken(locals, base) {
    return base
  }
  let mut i = 0
  while true {
    let candidate = base + "_" + i.to_string()
    if !genexp_local_taken(locals, candidate) {
      return candidate
    }
    i = i + 1
  }
  base
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
fn append_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn collect_scope_decl_names(
  body : Array[Stmt],
) -> (Array[String], Array[String]) {
  let globals : Array[String] = []
  let nonlocals : Array[String] = []
  fn walk(stmt : Stmt) -> Unit {
    match stmt {
      Stmt::Global(ns) =>
        for n in ns {
          append_unique_name(globals, n)
        }
      Stmt::Nonlocal(ns) =>
        for n in ns {
          append_unique_name(nonlocals, n)
        }
      Stmt::If(condition~, body~, else_body~) => {
        let _ = condition
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::While(condition~, body~, else_body~) => {
        let _ = condition
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::For(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::AsyncFor(target~, iter~, body~, else_body~) => {
        let _ = target
        let _ = iter
        for s in body {
          walk(s)
        }
        for s in else_body {
          walk(s)
        }
      }
      Stmt::With(context~, target~, body~) => {
        let _ = context
        let _ = target
        for s in body {
          walk(s)
        }
      }
      Stmt::AsyncWith(context~, target~, body~) => {
        let _ = context
        let _ = target
        for s in body {
          walk(s)
        }
      }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        for s in body {
          walk(s)
        }
        for handler in handlers {
          let _ = handler.0
          let _ = handler.1
          for s in handler.2 {
            walk(s)
          }
        }
        for s in else_body {
          walk(s)
        }
        for s in finally_body {
          walk(s)
        }
      }
      Stmt::Match(subject~, cases~) => {
        let _ = subject
        for case in cases {
          let _ = case.0
          let _ = case.1
          for s in case.2 {
            walk(s)
          }
        }
      }
      Stmt::Function(..) | Stmt::Class(..) => ()
      _ => ()
    }
  }

  for stmt in body {
    walk(stmt)
  }
  (globals, nonlocals)
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
  let locals = match
    bind_function_args_with_kwargs(func, positional, keywords) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let (global_names, nonlocal_names) = collect_scope_decl_names(func.body)
  if func.is_async {
    if func.is_generator {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::NotImplemented,
          "async generators are not supported".to_string(),
        ),
      )
    }
    return Ok(
      coroutine_new(
        func.body,
        locals,
        globals,
        builtins,
        io,
        global_names,
        nonlocal_names,
        func.closure,
        Config::default(),
      ),
    )
  }
  push_closure_env(func.closure)
  push_scope_decls_with_nonlocals(global_names, nonlocal_names)
  let result = eval_block(
    func.body,
    locals,
    globals,
    builtins,
    io,
    Config::default(),
  )
  pop_scope_decls()
  pop_closure_env()
  result
}

///|
fn bind_function_args_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
) -> Result[Array[(String, Value)], RuntimeError] {
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
  Ok(locals)
}

///|
fn eval_generator_with_kwargs(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  if func.is_async {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::NotImplemented,
        "async generators are not supported".to_string(),
      ),
    )
  }
  let locals = match
    bind_function_args_with_kwargs(func, positional, keywords) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let (global_names, nonlocal_names) = collect_scope_decl_names(func.body)
  Ok(
    generator_new(
      func.body,
      locals,
      globals,
      builtins,
      io,
      global_names,
      nonlocal_names,
      func.closure,
    ),
  )
}

///|
let runtime_callbacks_ready : Ref[Bool] = { val: false }

///|
fn ensure_runtime_callbacks_ready() -> Unit {
  if runtime_callbacks_ready.val {
    return
  }
  set_eval_function_with_kwargs_callback(eval_function_with_kwargs)
  set_eval_generator_with_kwargs_callback(eval_generator_with_kwargs)
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
  let result = match
    eval_block(func.body, locals, globals, builtins, io, Config::default()) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(result)
}
