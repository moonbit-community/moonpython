///|
/// Pattern matching support for `match`.

///|
fn match_pattern(value : Value, pattern : Pattern) -> Array[(String, Value)]? {
  match pattern {
    Pattern::Wildcard => Some([])
    Pattern::Literal(lit) => {
      let lit_value = match lit {
        Literal::None => Value::None
        Literal::Bool(v) => Value::Bool(v)
        Literal::Int(v) => Value::Int(v)
        Literal::Float(v) => Value::Float(v)
        Literal::Str(v) => Value::Str(v)
      }
      if eq_value(value, lit_value) {
        Some([])
      } else {
        None
      }
    }
    Pattern::Name(name) => Some([(name, value)])
    Pattern::Tuple(patterns) =>
      match value {
        Value::Tuple(values) | Value::List(values) =>
          if values.length() != patterns.length() {
            None
          } else {
            let bindings : Array[(String, Value)] = []
            for i = 0; i < patterns.length(); i = i + 1 {
              match match_pattern(values[i], patterns[i]) {
                Some(inner) =>
                  for pair in inner {
                    bindings.push(pair)
                  }
                None => return None
              }
            }
            Some(bindings)
          }
        _ => None
      }
  }
}
