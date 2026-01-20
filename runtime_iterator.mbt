///|
/// Iterator protocol helpers (internal).

///|
fn make_iterator(items_in : Array[Value]) -> Value {
  let items : Array[Value] = []
  for item in items_in {
    items.push(item)
  }
  let dict : Array[(String, Value)] = []
  dict.push(("items", Value::List(items)))
  dict.push(("pos", Value::Int(0N)))
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "iterator", bases: [], dict: [] },
    dict,
  })
}

///|
fn iter_value_to_iterator(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match value {
    Value::Instance(inst) =>
      if inst.class.name == "iterator" || inst.class.name == "generator" {
        Ok(Value::Instance(inst))
      } else {
        // Try the Python protocol first: obj.__iter__() -> iterator
        match
          get_attr_from_value(
            Value::Instance(inst),
            "__iter__",
            globals,
            builtins,
            io,
          ) {
          Ok(iter_method) =>
            call_callable_with_env(iter_method, [], [], globals, builtins, io)
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => {
                // Fallback to the internal materialization path (builtins + our
                // internal iterator/generator types).
                let items = match iterable_values(Value::Instance(inst)) {
                  Ok(v) => v
                  Err(e) => return Err(e)
                }
                Ok(make_iterator(items))
              }
              _ => Err(err)
            }
        }
      }
    other => {
      let items = match iterable_values(other) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(make_iterator(items))
    }
  }
}

///|
fn iterator_next(
  iterator_value : Value,
  default_value : Value?,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match iterator_value {
    Value::Instance(inst) =>
      if inst.class.name == "iterator" {
        let items_value = get_named_value(inst.dict, "items")
        let pos_value = get_named_value(inst.dict, "pos")
        let items = match items_value {
          Some(Value::List(items)) => items
          _ => []
        }
        let pos = match pos_value {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        if pos < @bigint.BigInt::from_int(items.length()) {
          let idx = match bigint_to_int_checked(pos) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let item = items[idx]
          set_named_value(inst.dict, "pos", Value::Int(pos + 1N))
          Ok(item)
        } else {
          match default_value {
            Some(v) => Ok(v)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "StopIteration".to_string(),
                ),
              )
          }
        }
      } else if inst.class.name == "generator" {
        generator_next(Value::Instance(inst), default_value)
      } else {
        let next_method = match
          get_attr_from_value(
            Value::Instance(inst),
            "__next__",
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(_) =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object is not an iterator",
              ),
            )
        }
        match
          call_callable_with_env(next_method, [], [], globals, builtins, io) {
          Ok(v) => Ok(v)
          Err(err) =>
            if err.exc_type == "StopIteration" {
              match default_value {
                Some(v) => Ok(v)
                None => Err(err)
              }
            } else {
              Err(err)
            }
        }
      }
    other =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" + type_name_from_value(other) + "' object is not an iterator",
        ),
      )
  }
}

///|
fn iterator_send(
  iterator_value : Value,
  sent_value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match iterator_value {
    Value::Instance(inst) =>
      if inst.class.name == "generator" {
        generator_send(Value::Instance(inst), sent_value)
      } else if inst.class.name == "iterator" {
        match sent_value {
          Value::None =>
            iterator_next(Value::Instance(inst), None, globals, builtins, io)
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object does not support send()",
              ),
            )
        }
      } else {
        match sent_value {
          Value::None =>
            iterator_next(Value::Instance(inst), None, globals, builtins, io)
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object does not support send()",
              ),
            )
        }
      }
    other =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" + type_name_from_value(other) + "' object is not an iterator",
        ),
      )
  }
}
