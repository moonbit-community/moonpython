///|
/// Objects: classes, instances, attribute lookup, calling.

///|
fn get_named_value(dict : Array[(String, Value)], name : String) -> Value? {
  for pair in dict {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_named_value(
  dict : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < dict.length(); i = i + 1 {
    if dict[i].0 == name {
      dict[i] = (name, value)
      return
    }
  }
  dict.push((name, value))
}

///|
fn lookup_class_attr(klass : ClassValue, name : String) -> Value? {
  let direct = get_named_value(klass.dict, name)
  if direct is Some(value) {
    return Some(value)
  }
  for base in klass.bases {
    match base {
      Value::Class(base_class) => {
        let found = lookup_class_attr(base_class, name)
        if found is Some(value) {
          return Some(value)
        }
      }
      _ => ()
    }
  }
  None
}

///|
fn get_attr_from_value(
  target : Value,
  attr : String,
) -> Result[Value, RuntimeError] {
  match target {
    Value::Instance(inst) => {
      let direct = get_named_value(inst.dict, attr)
      if direct is Some(value) {
        return Ok(value)
      }
      let class_attr = lookup_class_attr(inst.class, attr)
      match class_attr {
        Some(Value::Function(func)) =>
          Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: func,
              self: Value::Instance(inst),
            }),
          )
        Some(value) => Ok(value)
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "'" + inst.class.name + "' object has no attribute '" + attr + "'",
            ),
          )
      }
    }
    Value::Class(klass) =>
      match lookup_class_attr(klass, attr) {
        Some(value) => Ok(value)
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "'" + klass.name + "' object has no attribute '" + attr + "'",
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'" +
          type_name_from_value(target) +
          "' object has no attribute '" +
          attr +
          "'",
        ),
      )
  }
}

///|
fn set_attr_on_value(
  target : Value,
  attr : String,
  value : Value,
) -> Result[Unit, RuntimeError] {
  match target {
    Value::Instance(inst) => {
      set_named_value(inst.dict, attr, value)
      Ok(())
    }
    Value::Class(klass) => {
      set_named_value(klass.dict, attr, value)
      Ok(())
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "cannot set attribute".to_string(),
        ),
      )
  }
}

///|
fn call_callable_with_env(
  callee : Value,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match callee {
    Value::Function(func) =>
      eval_function_with_kwargs(
        func, positional, keywords, globals, builtins, io,
      )
    Value::BoundMethod(method) => {
      let args : Array[Value] = [method.self]
      for item in positional {
        args.push(item)
      }
      eval_function_with_kwargs(
        method.function,
        args,
        keywords,
        globals,
        builtins,
        io,
      )
    }
    Value::Class(klass) => {
      // Minimal exception instance payload.
      if klass.name == "BaseException" ||
        klass.name == "Exception" ||
        klass.name == "RuntimeError" {
        let dict : Array[(String, Value)] = []
        if positional.length() > 0 {
          dict.push(("message", positional[0]))
        }
        return Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
      }
      let init = lookup_class_attr(klass, "__init__")
      let inst = Value::Instance(InstanceValue::{ class: klass, dict: [] })
      match init {
        Some(Value::Function(func)) => {
          let args : Array[Value] = [inst]
          for item in positional {
            args.push(item)
          }
          let _ = match
            eval_function_with_kwargs(
              func, args, keywords, globals, builtins, io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }

        }
        _ => ()
      }
      Ok(inst)
    }
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, not_callable_message(callee)),
      )
  }
}
