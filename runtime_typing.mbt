///|
/// Typing helpers for generic aliases and unions.

///|
fn is_generic_alias_origin_name(name : String) -> Bool {
  match name {
    "list" | "dict" | "tuple" | "set" | "frozenset" | "type" => true
    _ => false
  }
}

///|
fn union_args_from_value(
  value : Value,
  builtins : Array[(String, Value)],
) -> Array[Value]? {
  match value {
    Value::Class(_) => Some([value])
    Value::Function(func) =>
      if func.body.length() == 0 && is_builtin_class_name(func.name) {
        Some([Value::Class(builtin_class_from_name(func.name, builtins))])
      } else {
        None
      }
    Value::Instance(inst) =>
      if inst.class.name == "UnionType" {
        match get_named_value(inst.dict, "__args__") {
          Some(Value::Tuple(values)) => Some(values)
          _ => Some([value])
        }
      } else if inst.class.name == "GenericAlias" {
        Some([value])
      } else {
        None
      }
    Value::None =>
      Some([Value::Class(ClassValue::{ name: "NoneType", bases: [], dict: [] })])
    _ => None
  }
}
