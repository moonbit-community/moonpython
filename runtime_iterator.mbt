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
  dict.push(("pos", Value::Int(0L)))
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "iterator", bases: [], dict: [] },
    dict,
  })
}

///|
fn iter_value_to_iterator(value : Value) -> Result[Value, RuntimeError] {
  match value {
    Value::Instance(inst) =>
      if inst.class.name == "iterator" || inst.class.name == "generator" {
        Ok(Value::Instance(inst))
      } else {
        let items = match iterable_values(Value::Instance(inst)) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(make_iterator(items))
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
          Some(Value::Bool(v)) => if v { 1L } else { 0L }
          _ => 0L
        }
        if pos < items.length().to_int64() {
          let item = items[pos.to_int()]
          set_named_value(inst.dict, "pos", Value::Int(pos + 1L))
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
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not an iterator",
          ),
        )
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
) -> Result[Value, RuntimeError] {
  match iterator_value {
    Value::Instance(inst) =>
      if inst.class.name == "generator" {
        generator_send(Value::Instance(inst), sent_value)
      } else if inst.class.name == "iterator" {
        match sent_value {
          Value::None => iterator_next(Value::Instance(inst), None)
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object does not support send()",
              ),
            )
        }
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not an iterator",
          ),
        )
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
