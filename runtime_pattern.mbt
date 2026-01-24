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
        Literal::Complex(real, imag) => Value::Complex(real, imag)
        Literal::Str(v) => Value::Str(v)
        Literal::Bytes(v) => Value::Bytes(v)
      }
      if eq_value(value, lit_value) {
        Some([])
      } else {
        None
      }
    }
    Pattern::Name(name) => Some([(name, value)])
    Pattern::TypeCapture(type_name~, name~) => {
      fn value_matches_type_name(value : Value, type_name : String) -> Bool {
        fn last_qual_segment(text : String) -> String {
          let mut start = 0
          let chars = text.to_array()
          for i = 0; i < chars.length(); i = i + 1 {
            if chars[i] == '.' {
              start = i + 1
            }
          }
          substring(text, start, text.length()).to_string()
        }

        fn class_matches_name(cls : ClassValue, want : String) -> Bool {
          if cls.name == want {
            return true
          }
          for base in cls.bases {
            match base {
              Value::Class(base_cls) =>
                if class_matches_name(base_cls, want) {
                  return true
                }
              _ => ()
            }
          }
          false
        }

        let want_simple = last_qual_segment(type_name)
        match value {
          Value::Instance(inst) => class_matches_name(inst.class, want_simple)
          _ => type_name_from_value(value) == want_simple
        }
      }

      if value_matches_type_name(value, type_name) {
        if name == "_" {
          Some([])
        } else {
          Some([(name, value)])
        }
      } else {
        None
      }
    }
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
