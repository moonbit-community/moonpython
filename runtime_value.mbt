///|
/// Core value utilities for the mpython runtime.

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
    Value::Str(_) => "str"
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
fn is_exception_class_name(name : String) -> Bool {
  name == "BaseException" ||
  name == "Exception" ||
  name == "RuntimeError" ||
  name == "NameError" ||
  name == "TypeError" ||
  name == "AttributeError" ||
  name == "IndexError" ||
  name == "KeyError" ||
  name == "NotImplementedError" ||
  name == "ZeroDivisionError" ||
  name == "ValueError" ||
  name == "ImportError" ||
  name == "AssertionError" ||
  name == "SyntaxError" ||
  name == "IndentationError" ||
  name == "EOFError" ||
  name == "StopIteration"
}

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
      if is_exception_class_name(inst.class.name) {
        match lookup_instance_field(inst.dict, "message") {
          Some(Value::Str(text)) => text
          Some(other) => value_to_string(other)
          None => "".to_string()
        }
      } else {
        "<" + inst.class.name + " object>"
      }
    Value::BoundMethod(method) => "<bound method " + method.function.name + ">"
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
    (Value::Instance(a), Value::Instance(b)) => a.class.name == b.class.name
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
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "expected number".to_string(),
        ),
      )
  }
}
