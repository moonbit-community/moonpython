///|
/// math module builtins.

///|
fn builtin_math_sqrt(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.sqrt", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.sqrt() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.pow(x, 0.5)))
}

///|
fn builtin_math_pow(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.pow", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.pow() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (_, a) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (_, b) = match number_value(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.pow(a, b)))
}

///|
fn builtin_math_log(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.log", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 && positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.log() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut result = @math.ln(x)
  if positional.length() == 2 {
    let (_, base) = match number_value(positional[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    result = result / @math.ln(base)
  }
  Ok(Value::Float(result))
}

///|
fn builtin_math_log2(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.log2", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.log2() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.log2(x)))
}

///|
fn builtin_math_exp(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.exp", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.exp() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.exp(x)))
}

///|
fn builtin_math_floor(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.floor", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.floor() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(@math.floor(v).to_int64())))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.floor() expects a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_math_trunc(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("math.trunc", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.trunc() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) => Ok(Value::Int(@bigint.BigInt::from_int64(v.to_int64())))
    Value::Instance(_) => {
      let trunc_fn = match
        get_attr_from_value(positional[0], "__trunc__", globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let value = match
        call_callable_with_env(trunc_fn, [], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match value {
        Value::Int(v) => Ok(Value::Int(v))
        Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__trunc__ returned non-int".to_string(),
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.trunc() expects a real number".to_string(),
        ),
      )
  }
}

///|
fn builtin_math_frexp(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("math.frexp", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.frexp() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if x == 0.0 {
    return Ok(Value::Tuple([Value::Float(0.0), Value::Int(0N)]))
  }
  if x.is_nan() || x.is_inf() {
    return Ok(Value::Tuple([Value::Float(x), Value::Int(0N)]))
  }
  let ax = if x < 0.0 { -x } else { x }
  let mut exp : Int64 = @math.floor(@math.log2(ax)).to_int64() + 1L
  let mut mant = x / @math.pow(2.0, exp.to_double())
  let mut abs_mant = if mant < 0.0 { -mant } else { mant }
  if abs_mant < 0.5 {
    mant = mant * 2.0
    exp = exp - 1L
  } else if abs_mant >= 1.0 {
    mant = mant / 2.0
    exp = exp + 1L
  }
  abs_mant = if mant < 0.0 { -mant } else { mant }
  if abs_mant < 0.5 {
    mant = mant * 2.0
    exp = exp - 1L
  } else if abs_mant >= 1.0 {
    mant = mant / 2.0
    exp = exp + 1L
  }
  Ok(
    Value::Tuple([
      Value::Float(mant),
      Value::Int(@bigint.BigInt::from_int64(exp)),
    ]),
  )
}

///|
fn builtin_math_ldexp(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("math.ldexp", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.ldexp() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let exp_i64 = match positional[1] {
    Value::Int(v) => v.to_int64()
    Value::Bool(v) => if v { 1L } else { 0L }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.ldexp() expects an integer exponent".to_string(),
        ),
      )
  }
  Ok(Value::Float(x * @math.pow(2.0, exp_i64.to_double())))
}

///|
fn builtin_math_ceil(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.ceil", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.ceil() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Float(v) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(@math.ceil(v).to_int64())))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.ceil() expects a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_math_acos(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.acos", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.acos() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.acos(x)))
}

///|
fn builtin_math_cos(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.cos", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.cos() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.cos(x)))
}

///|
fn builtin_math_sin(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.sin", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.sin() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.sin(x)))
}

///|
fn builtin_math_hypot(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.hypot", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.hypot() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (_, y) = match number_value(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(@math.hypot(x, y)))
}

///|
fn builtin_math_fabs(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.fabs", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.fabs() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let value = if x < 0.0 { -x } else { x }
  Ok(Value::Float(value))
}

///|
fn erf_approx(x : Double) -> Double {
  let p = 0.3275911
  let a1 = 0.254829592
  let a2 = -0.284496736
  let a3 = 1.421413741
  let a4 = -1.453152027
  let a5 = 1.061405429
  let sign = if x < 0.0 { -1.0 } else { 1.0 }
  let ax = if x < 0.0 { -x } else { x }
  let t = 1.0 / (1.0 + p * ax)
  let y = 1.0 -
    ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * @math.exp(-ax * ax)
  sign * y
}

///|
fn lgamma_lanczos(x : Double) -> Double {
  let c1 = 76.18009172947146
  let c2 = -86.50532032941677
  let c3 = 24.01409824083091
  let c4 = -1.231739572450155
  let c5 = 0.001208650973866179
  let c6 = -0.000005395239384953
  let mut y = x
  let mut ser = 1.000000000190015
  y = y + 1.0
  ser = ser + c1 / y
  y = y + 1.0
  ser = ser + c2 / y
  y = y + 1.0
  ser = ser + c3 / y
  y = y + 1.0
  ser = ser + c4 / y
  y = y + 1.0
  ser = ser + c5 / y
  y = y + 1.0
  ser = ser + c6 / y
  let tmp = x + 5.5
  let log_tmp = (x + 0.5) * @math.ln(tmp) - tmp
  log_tmp + @math.ln(2.5066282746310005 * ser / x)
}

///|
fn lgamma_approx(x : Double) -> Double {
  let pi = 3.141592653589793
  if x < 0.5 {
    let sinpi = @math.sin(pi * x)
    let abs_sinpi = if sinpi < 0.0 { -sinpi } else { sinpi }
    if abs_sinpi == 0.0 {
      return 1.0 / 0.0
    }
    @math.ln(pi) - @math.ln(abs_sinpi) - lgamma_lanczos(1.0 - x)
  } else {
    lgamma_lanczos(x)
  }
}

///|
fn builtin_math_erf(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.erf", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.erf() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(erf_approx(x)))
}

///|
fn builtin_math_lgamma(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.lgamma", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.lgamma() takes exactly one argument".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Float(lgamma_approx(x)))
}

///|
fn builtin_math_fsum(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("math.fsum", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.fsum() takes exactly one argument".to_string(),
      ),
    )
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut total = 0.0
  for item in items {
    let (_, value) = match number_value(item) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    total = total + value
  }
  Ok(Value::Float(total))
}

///|
fn builtin_math_sumprod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("math.sumprod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.sumprod() takes exactly two arguments".to_string(),
      ),
    )
  }
  let items_a = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items_b = match iterable_values(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if items_a.length() != items_b.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: sumprod() arguments have different lengths".to_string(),
      ),
    )
  }
  let mut total = 0.0
  for i = 0; i < items_a.length(); i = i + 1 {
    let (_, a) = match number_value(items_a[i]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let (_, b) = match number_value(items_b[i]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    total = total + a * b
  }
  Ok(Value::Float(total))
}

///|
fn builtin_math_isfinite(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.isfinite", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.isfinite() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Float(v) => Ok(Value::Bool(!v.is_nan() && !v.is_inf()))
    Value::Int(_) | Value::Bool(_) => Ok(Value::Bool(true))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.isfinite() expects a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_math_isnan(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.isnan", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.isnan() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Float(v) => Ok(Value::Bool(v.is_nan()))
    Value::Int(_) | Value::Bool(_) => Ok(Value::Bool(false))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.isnan() expects a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_math_isinf(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.isinf", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.isinf() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Float(v) => Ok(Value::Bool(v.is_inf()))
    Value::Int(_) | Value::Bool(_) => Ok(Value::Bool(false))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.isinf() expects a number".to_string(),
        ),
      )
  }
}

///|
fn builtin_math_copysign(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.copysign", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.copysign() takes exactly two arguments".to_string(),
      ),
    )
  }
  let (_, x) = match number_value(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (_, y) = match number_value(positional[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let ax = if x == 0.0 { 0.0 } else if x < 0.0 { -x } else { x }
  let neg = if y == 0.0 { 1.0 / y < 0.0 } else { y < 0.0 }
  Ok(Value::Float(if neg { -ax } else { ax }))
}

///|
fn bigint_gcd(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let mut x = if a < 0N { -a } else { a }
  let mut y = if b < 0N { -b } else { b }
  while y != 0N {
    let r = x % y
    x = y
    y = r
  }
  x
}

///|
fn builtin_math_gcd(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.gcd", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut g = 0N
  for item in positional {
    let value = match item {
      Value::Int(v) => v
      Value::Bool(v) => if v { 1N } else { 0N }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "math.gcd() expects ints".to_string(),
          ),
        )
    }
    g = bigint_gcd(g, value)
  }
  Ok(Value::Int(g))
}

///|
fn bigint_isqrt(value : @bigint.BigInt) -> @bigint.BigInt {
  if value < 2N {
    return value
  }
  let mut low = 1N
  let mut high = value
  let mut ans = 0N
  while low <= high {
    let mid = (low + high) / 2N
    let sq = mid * mid
    if sq == value {
      return mid
    }
    if sq < value {
      ans = mid
      low = mid + 1N
    } else {
      high = mid - 1N
    }
  }
  ans
}

///|
fn builtin_math_isqrt(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("math.isqrt", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "math.isqrt() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "math.isqrt() expects an int".to_string(),
        ),
      )
  }
  if value < 0N {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: isqrt() argument must be nonnegative".to_string(),
      ),
    )
  }
  Ok(Value::Int(bigint_isqrt(value)))
}
