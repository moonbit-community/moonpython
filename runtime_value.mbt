///|
/// Core value utilities for the moonpython runtime.

///|
fn bool_from_value(value : Value) -> Bool {
  match value {
    Value::None => false
    Value::Bool(v) => v
    Value::Int(v) => v != 0N
    Value::Float(v) => v != 0.0
    Value::Complex(real, imag) => real != 0.0 || imag != 0.0
    Value::Str(v) => v.length() > 0
    Value::Bytes(v) => v.length() > 0
    Value::ByteArray(v) => v.length() > 0
    Value::MemoryView(v) => v.length() > 0
    Value::List(v) => v.length() > 0
    Value::Tuple(v) => v.length() > 0
    Value::Dict(v) => v.length() > 0
    Value::Set(v) => v.length() > 0
    Value::Function(_) => true
    Value::Class(_) => true
    Value::Instance(_) => true
    Value::BoundMethod(_) => true
  }
}

///|
fn type_name_from_value(value : Value) -> String {
  match value {
    Value::None => "NoneType"
    Value::Bool(_) => "bool"
    Value::Int(_) => "int"
    Value::Float(_) => "float"
    Value::Complex(_, _) => "complex"
    Value::Str(_) => "str"
    Value::Bytes(_) => "bytes"
    Value::ByteArray(_) => "bytearray"
    Value::MemoryView(_) => "memoryview"
    Value::List(_) => "list"
    Value::Tuple(_) => "tuple"
    Value::Dict(_) => "dict"
    Value::Set(_) => "set"
    Value::Function(_) => "function"
    Value::Class(_) => "type"
    Value::Instance(inst) => inst.class.name
    Value::BoundMethod(_) => "method"
  }
}

///|
fn not_callable_message(value : Value) -> String {
  "'" + type_name_from_value(value) + "' object is not callable"
}

///|
let object_hash_counter : Ref[@bigint.BigInt] = { val: 1N }

///|
fn fresh_object_hashvalue() -> @bigint.BigInt {
  let value = object_hash_counter.val
  object_hash_counter.val = value + 1N
  value
}

///|

///|
fn lookup_instance_field(
  dict : Array[(String, Value)],
  name : String,
) -> Value? {
  for pair in dict {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn bytes_hex_digit(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).to_char().unwrap()
  } else {
    ('a'.to_int() + (n - 10)).to_char().unwrap()
  }
}

///|
fn bytes_hex_byte(value : Int) -> String {
  let buf = StringBuilder::new()
  let hi = (value >> 4) & 0xF
  let lo = value & 0xF
  buf.write_char(bytes_hex_digit(hi))
  buf.write_char(bytes_hex_digit(lo))
  buf.to_string()
}

///|
fn bytes_repr(bytes : Array[Int]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("b'")
  for byte in bytes {
    let v = byte & 0xFF
    if v == 0x5c {
      buf.write_string("\\\\")
    } else if v == 0x27 {
      buf.write_string("\\'")
    } else if v == 0x09 {
      buf.write_string("\\t")
    } else if v == 0x0a {
      buf.write_string("\\n")
    } else if v == 0x0d {
      buf.write_string("\\r")
    } else if v >= 0x20 && v <= 0x7e {
      buf.write_char(v.to_char().unwrap())
    } else {
      buf.write_string("\\x")
      buf.write_string(bytes_hex_byte(v))
    }
  }
  buf.write_char('\'')
  buf.to_string()
}

///|
fn hash_string(text : String) -> Int64 {
  let mut h : Int64 = 0L
  for ch in text.to_array() {
    h = h * 131L + ch.to_int().to_int64()
  }
  h
}

///|
fn hash_bytes(values : Array[Int]) -> Int64 {
  let mut h : Int64 = 0L
  for value in values {
    h = h * 131L + value.to_int64()
  }
  h
}

///|
fn hash_complex(real : Double, imag : Double) -> Int64 {
  let r = real.to_int64()
  let i = imag.to_int64()
  r * 131L + i
}

///|
fn complex_to_string(real : Double, imag : Double) -> String {
  if real == 0.0 {
    if imag == 0.0 {
      "0j"
    } else {
      imag.to_string() + "j"
    }
  } else {
    let sign = if imag >= 0.0 { "+" } else { "-" }
    let imag_abs = if imag < 0.0 { -imag } else { imag }
    "(" + real.to_string() + sign + imag_abs.to_string() + "j)"
  }
}

///|
fn is_base_exception_class_value(klass : ClassValue) -> Bool {
  match class_mro(klass) {
    Ok(mro) => {
      for cls in mro {
        if cls.name == "BaseException" {
          return true
        }
      }
      false
    }
    Err(_) => false
  }
}

///|
fn value_to_string(value : Value) -> String {
  match value {
    Value::None => "None"
    Value::Bool(v) => if v { "True" } else { "False" }
    Value::Int(v) => v.to_string()
    Value::Float(v) => v.to_string()
    Value::Complex(real, imag) => complex_to_string(real, imag)
    Value::Str(v) => v
    Value::Bytes(values) => bytes_repr(values)
    Value::ByteArray(values) => "bytearray(" + bytes_repr(values) + ")"
    Value::MemoryView(values) => "memoryview(" + bytes_repr(values) + ")"
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
    Value::Dict(pairs) => {
      let buf = StringBuilder::new()
      buf.write_char('{')
      for i = 0; i < pairs.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(pairs[i].0))
        buf.write_string(": ")
        buf.write_string(value_to_string(pairs[i].1))
      }
      buf.write_char('}')
      buf.to_string()
    }
    Value::Set(values) => {
      let buf = StringBuilder::new()
      buf.write_char('{')
      for i = 0; i < values.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(value_to_string(values[i]))
      }
      buf.write_char('}')
      buf.to_string()
    }
    Value::Function(func) => "<function " + func.name + ">"
    Value::Class(klass) => "<class '" + klass.name + "'>"
    Value::Instance(inst) =>
      if is_base_exception_class_value(inst.class) {
        // Exception stringification: match CPython's BaseException.__str__ based
        // on `.args`. Keep the synthetic `message` field as a fallback for
        // runtime-generated errors that don't populate `args`.
        match lookup_instance_field(inst.dict, "args") {
          Some(Value::Tuple(args)) =>
            if args.length() == 0 {
              "".to_string()
            } else if args.length() == 1 {
              value_to_string(args[0])
            } else {
              value_to_string(Value::Tuple(args))
            }
          Some(other) => value_to_string(other)
          None =>
            match lookup_instance_field(inst.dict, "message") {
              Some(Value::Str(text)) => text
              Some(other) => value_to_string(other)
              None => "".to_string()
            }
        }
      } else if inst.class.name == "range" {
        let start = match get_named_value(inst.dict, "start") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let stop = match get_named_value(inst.dict, "stop") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let step = match get_named_value(inst.dict, "step") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 1N
        }
        if step == 1N {
          "range(" + start.to_string() + ", " + stop.to_string() + ")"
        } else {
          "range(" +
          start.to_string() +
          ", " +
          stop.to_string() +
          ", " +
          step.to_string() +
          ")"
        }
      } else {
        "<" + inst.class.name + " object>"
      }
    Value::BoundMethod(bound_method) =>
      "<bound method " + bound_method.function.name + ">"
  }
}

///|
fn find_top_level_format_colon(inner : String) -> Int? {
  let chars = inner.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == ':' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      return Some(i)
    }
  }
  None
}

///|
fn find_fstring_expr_close(after_open : String) -> Int? {
  let chars = after_open.to_array()
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace == 0 {
        return Some(i)
      }
      depth_brace -= 1
      continue
    }
  }
  None
}

///|
fn find_top_level_fstring_conversion_bang(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == '!' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      if i + 1 < chars.length() {
        let next = chars[i + 1]
        if next != '=' {
          return Some(i)
        }
      }
    }
  }
  None
}

///|
fn find_top_level_fstring_debug_equal(text : String) -> Int? {
  let chars = text.to_array()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None
  let mut escape = false
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    match quote {
      Some(q) => {
        if escape {
          escape = false
          continue
        }
        if c == '\\' {
          escape = true
          continue
        }
        if c == q {
          quote = None
        }
        continue
      }
      None => ()
    }
    if c == '\'' || c == '"' {
      quote = Some(c)
      escape = false
      continue
    }
    if c == '(' {
      depth_paren += 1
      continue
    }
    if c == ')' {
      if depth_paren > 0 {
        depth_paren -= 1
      }
      continue
    }
    if c == '[' {
      depth_bracket += 1
      continue
    }
    if c == ']' {
      if depth_bracket > 0 {
        depth_bracket -= 1
      }
      continue
    }
    if c == '{' {
      depth_brace += 1
      continue
    }
    if c == '}' {
      if depth_brace > 0 {
        depth_brace -= 1
      }
      continue
    }
    if c == '=' && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
      let prev = if i > 0 { Some(chars[i - 1]) } else { None }
      let next = if i + 1 < chars.length() { Some(chars[i + 1]) } else { None }
      let prev_is_op = match prev {
        Some('=') | Some('!') | Some('<') | Some('>') => true
        _ => false
      }
      let next_is_eq = match next {
        Some('=') => true
        _ => false
      }
      if !prev_is_op && !next_is_eq {
        return Some(i)
      }
    }
  }
  None
}

///|
fn eq_value(a : Value, b : Value) -> Bool {
  fn list_values_equal(a : Array[Value], b : Array[Value]) -> Bool {
    if a.length() != b.length() {
      return false
    }
    let mut equal = true
    for i = 0; i < a.length(); i = i + 1 {
      if !eq_value(a[i], b[i]) {
        equal = false
        break
      }
    }
    equal
  }

  fn instance_list_values(inst : InstanceValue) -> Array[Value]? {
    match get_named_value(inst.dict, list_storage_name) {
      Some(Value::List(values)) => Some(values)
      _ => None
    }
  }

  match (a, b) {
    (Value::None, Value::None) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Int(a), Value::Int(b)) => a == b
    (Value::Float(a), Value::Float(b)) => a == b
    (Value::Bool(a), Value::Int(b)) => (if a { 1N } else { 0N }) == b
    (Value::Int(a), Value::Bool(b)) => a == (if b { 1N } else { 0N })
    (Value::Bool(a), Value::Float(b)) => (if a { 1.0 } else { 0.0 }) == b
    (Value::Float(a), Value::Bool(b)) => a == (if b { 1.0 } else { 0.0 })
    (Value::Int(a), Value::Float(b)) =>
      match bigint_to_double_checked(a) {
        Ok(value) => value == b
        Err(_) => false
      }
    (Value::Float(a), Value::Int(b)) =>
      match bigint_to_double_checked(b) {
        Ok(value) => a == value
        Err(_) => false
      }
    (Value::Complex(ar, ai), Value::Complex(br, bi)) => ar == br && ai == bi
    (Value::Complex(ar, ai), Value::Float(b)) => ai == 0.0 && ar == b
    (Value::Complex(ar, ai), Value::Bool(b)) =>
      ai == 0.0 && ar == (if b { 1.0 } else { 0.0 })
    (Value::Float(a), Value::Complex(br, bi)) => bi == 0.0 && a == br
    (Value::Bool(a), Value::Complex(br, bi)) =>
      bi == 0.0 && (if a { 1.0 } else { 0.0 }) == br
    (Value::Complex(ar, ai), Value::Int(b)) =>
      if ai == 0.0 {
        match bigint_to_double_checked(b) {
          Ok(value) => ar == value
          Err(_) => false
        }
      } else {
        false
      }
    (Value::Int(a), Value::Complex(br, bi)) =>
      if bi == 0.0 {
        match bigint_to_double_checked(a) {
          Ok(value) => value == br
          Err(_) => false
        }
      } else {
        false
      }
    (Value::Str(a), Value::Str(b)) => a == b
    (Value::Bytes(a), Value::Bytes(b))
    | (Value::ByteArray(a), Value::ByteArray(b))
    | (Value::MemoryView(a), Value::MemoryView(b))
    | (Value::Bytes(a), Value::ByteArray(b))
    | (Value::Bytes(a), Value::MemoryView(b))
    | (Value::ByteArray(a), Value::Bytes(b))
    | (Value::ByteArray(a), Value::MemoryView(b))
    | (Value::MemoryView(a), Value::Bytes(b))
    | (Value::MemoryView(a), Value::ByteArray(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for i = 0; i < a.length(); i = i + 1 {
          if a[i] != b[i] {
            equal = false
            break
          }
        }
        equal
      }
    (Value::List(a), Value::List(b)) => list_values_equal(a, b)
    (Value::List(a), Value::Instance(b)) =>
      match instance_list_values(b) {
        Some(values) => list_values_equal(a, values)
        None => false
      }
    (Value::Instance(a), Value::List(b)) =>
      match instance_list_values(a) {
        Some(values) => list_values_equal(values, b)
        None => false
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
    (Value::Set(a), Value::Set(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for item in a {
          let mut found = false
          for other in b {
            if eq_value(item, other) {
              found = true
              break
            }
          }
          if !found {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Function(a), Value::Function(b)) => a.name == b.name
    (Value::BoundMethod(a), Value::BoundMethod(b)) =>
      a.function.name == b.function.name && eq_value(a.self, b.self)
    (Value::Dict(a), Value::Dict(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut equal = true
        for pair in a {
          let mut found = false
          for other in b {
            if eq_value(pair.0, other.0) && eq_value(pair.1, other.1) {
              found = true
              break
            }
          }
          if !found {
            equal = false
            break
          }
        }
        equal
      }
    (Value::Class(a), Value::Class(b)) => a.name == b.name
    (Value::Instance(a), Value::Instance(b)) =>
      if a.class.name == "weakref" && b.class.name == "weakref" {
        let av = match get_named_value(a.dict, "value") {
          Some(v) => v
          None => Value::None
        }
        let bv = match get_named_value(b.dict, "value") {
          Some(v) => v
          None => Value::None
        }
        eq_value(av, bv)
      } else {
        match (instance_list_values(a), instance_list_values(b)) {
          (Some(values_a), Some(values_b)) =>
            list_values_equal(values_a, values_b)
          (Some(_), None) | (None, Some(_)) => false
          (None, None) =>
            // Default instance equality should behave like `object`: identity
            // by default. Most instances created through `object.__new__`
            // already carry a unique `hashvalue`.
            match
              (
                get_named_value(a.dict, "hashvalue"),
                get_named_value(b.dict, "hashvalue"),
              ) {
              (Some(Value::Int(ha)), Some(Value::Int(hb))) => ha == hb
              _ => a.class.name == b.class.name
            }
        }
      }
    _ => false
  }
}

///|
fn is_value_identity(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Value::None, Value::None) => true
    (Value::Bool(a), Value::Bool(b)) => a == b
    (Value::Int(a), Value::Int(b)) => a == b
    (Value::Float(a), Value::Float(b)) => a == b
    (Value::Complex(ar, ai), Value::Complex(br, bi)) => ar == br && ai == bi
    (Value::Str(a), Value::Str(b)) => a == b
    (Value::Bytes(a), Value::Bytes(b))
    | (Value::ByteArray(a), Value::ByteArray(b))
    | (Value::MemoryView(a), Value::MemoryView(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut ok = true
        for i = 0; i < a.length(); i = i + 1 {
          if a[i] != b[i] {
            ok = false
            break
          }
        }
        ok
      }
    (Value::Tuple(a), Value::Tuple(b)) =>
      eq_value(Value::Tuple(a), Value::Tuple(b))
    (Value::List(a), Value::List(b)) => eq_value(Value::List(a), Value::List(b))
    (Value::Set(a), Value::Set(b)) => eq_value(Value::Set(a), Value::Set(b))
    (Value::Dict(a), Value::Dict(b)) => eq_value(Value::Dict(a), Value::Dict(b))
    (Value::Function(a), Value::Function(b)) => a.name == b.name
    (Value::Class(a), Value::Class(b)) => a.name == b.name
    (Value::BoundMethod(a), Value::BoundMethod(b)) =>
      a.function.name == b.function.name && is_value_identity(a.self, b.self)
    (Value::Instance(a), Value::Instance(b)) =>
      eq_value(Value::Instance(a), Value::Instance(b))
    _ => false
  }
}

///|
fn hash_value(value : Value) -> Result[@bigint.BigInt, RuntimeError] {
  match value {
    Value::None => Ok(0N)
    Value::Bool(v) => Ok(if v { 1N } else { 0N })
    Value::Int(v) => Ok(v)
    Value::Float(v) => Ok(@bigint.BigInt::from_int64(v.to_int64()))
    Value::Complex(real, imag) =>
      Ok(@bigint.BigInt::from_int64(hash_complex(real, imag)))
    Value::Str(text) => Ok(@bigint.BigInt::from_int64(hash_string(text)))
    Value::Bytes(values) => Ok(@bigint.BigInt::from_int64(hash_bytes(values)))
    Value::Tuple(values) => {
      let mut h = 0N
      for item in values {
        let value_hash = match hash_value(item) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        h = h * 131N + value_hash
      }
      Ok(h)
    }
    Value::Function(func) =>
      Ok(@bigint.BigInt::from_int64(hash_string(func.name)))
    Value::Class(klass) =>
      Ok(@bigint.BigInt::from_int64(hash_string(klass.name)))
    Value::BoundMethod(bound) =>
      Ok(@bigint.BigInt::from_int64(hash_string(bound.function.name)))
    Value::Instance(inst) =>
      match get_named_value(inst.dict, "hashvalue") {
        Some(Value::Int(v)) => Ok(v)
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unhashable type: '" +
              type_name_from_value(Value::Instance(inst)) +
              "'",
            ),
          )
      }
    other =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "unhashable type: '" + type_name_from_value(other) + "'",
        ),
      )
  }
}

///|
fn ensure_hashable(value : Value) -> Result[Unit, RuntimeError] {
  let _ = match hash_value(value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(())
}

///|
fn dict_find_index(
  pairs : Array[(Value, Value)],
  key : Value,
) -> Result[Int?, RuntimeError] {
  let _ = match ensure_hashable(key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for i = 0; i < pairs.length(); i = i + 1 {
    if eq_value(pairs[i].0, key) {
      return Ok(Some(i))
    }
  }
  Ok(None)
}

///|
fn dict_set_item(
  pairs : Array[(Value, Value)],
  key : Value,
  value : Value,
) -> Result[Unit, RuntimeError] {
  let index = match dict_find_index(pairs, key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match index {
    Some(i) => pairs[i] = (pairs[i].0, value)
    None => pairs.push((key, value))
  }
  Ok(())
}

///|
fn dict_delete_key(
  pairs : Array[(Value, Value)],
  key : Value,
) -> Result[Bool, RuntimeError] {
  let index = match dict_find_index(pairs, key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match index {
    Some(i) => {
      let _ = pairs.remove(i)
      Ok(true)
    }
    None => Ok(false)
  }
}

///|
fn set_find_index(
  values : Array[Value],
  item : Value,
) -> Result[Int?, RuntimeError] {
  let _ = match ensure_hashable(item) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for i = 0; i < values.length(); i = i + 1 {
    if eq_value(values[i], item) {
      return Ok(Some(i))
    }
  }
  Ok(None)
}

///|
fn set_add_unique(
  values : Array[Value],
  item : Value,
) -> Result[Bool, RuntimeError] {
  let index = match set_find_index(values, item) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match index {
    Some(_) => Ok(false)
    None => {
      values.push(item)
      Ok(true)
    }
  }
}

///|
fn set_remove_item(
  values : Array[Value],
  item : Value,
) -> Result[Bool, RuntimeError] {
  let index = match set_find_index(values, item) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match index {
    Some(i) => {
      let _ = values.remove(i)
      Ok(true)
    }
    None => Ok(false)
  }
}

///|
fn bigint_to_int_checked(v : @bigint.BigInt) -> Result[Int, RuntimeError] {
  let min : Int = -0x80000000
  let max : Int = 0x7fffffff
  if v.compare_int(min) < 0 || v.compare_int(max) > 0 {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OverflowError: cannot fit 'int' into an index-sized integer".to_string(),
      ),
    )
  } else {
    Ok(v.to_int())
  }
}

///|
fn bigint_to_double_checked(v : @bigint.BigInt) -> Result[Double, RuntimeError] {
  // CPython-like integer -> float conversion:
  // - exact for <= 53 bits
  // - round to nearest, ties to even
  // - overflow to inf raises OverflowError
  if v == 0N {
    return Ok(0.0)
  }
  let neg = v < 0N
  let abs = if neg { -v } else { v }
  let nbits = abs.bit_length()

  // Fast path: if it fits in 64 bits, rely on IEEE-754 hardware rounding.
  // This matches CPython's round-to-nearest, ties-to-even behavior.
  if nbits <= 64 {
    let u = abs.to_uint64()
    let d = Double::convert_uint64(u)
    return Ok(if neg { -d } else { d })
  }

  // Largest finite double is < 2^1024.
  // If abs >= 2^1024, conversion overflows.
  if nbits > 1024 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "OverflowError: int too large to convert to float".to_string(),
      ),
    )
  }

  // Extract the top 53 bits (implicit 1 + 52 mantissa bits), then round.
  let shift = nbits - 53
  let mut top53 = if shift > 0 {
    abs >> shift
  } else if shift < 0 {
    abs << -shift
  } else {
    abs
  }
  let mut exp = nbits - 1
  if shift > 0 {
    let dropped = abs - (top53 << shift)
    let half = 1N << (shift - 1)
    let round_up = if dropped > half {
      true
    } else if dropped < half {
      false
    } else {
      // tie: round to even
      (top53 & 1N) != 0N
    }
    if round_up {
      top53 = top53 + 1N
      // carry out of the 53-bit window
      if top53 == 1N << 53 {
        top53 = top53 >> 1
        exp = exp + 1
        if exp > 1023 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "OverflowError: int too large to convert to float".to_string(),
            ),
          )
        }
      }
    }
  }

  // Build IEEE-754 bits.
  let mantissa_mask = (1N << 52) - 1N
  let mantissa = (top53 & mantissa_mask).to_uint64()
  let exponent_bits : UInt64 = (exp + 1023).to_uint64()
  let sign_bits : UInt64 = if neg { 1UL << 63 } else { 0UL }
  let bits = sign_bits | (exponent_bits << 52) | mantissa
  Ok(bits.reinterpret_as_double())
}

///|
fn number_value(value : Value) -> Result[(Bool, Double), RuntimeError] {
  match value {
    Value::Int(v) =>
      match bigint_to_double_checked(v) {
        Ok(d) => Ok((false, d))
        Err(err) => Err(err)
      }
    Value::Float(v) => Ok((true, v))
    Value::Bool(v) => Ok((false, if v { 1.0 } else { 0.0 }))
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "expected number".to_string(),
        ),
      )
  }
}
