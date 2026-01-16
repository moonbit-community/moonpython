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
fn clone_class_list(list : Array[ClassValue]) -> Array[ClassValue] {
  let result : Array[ClassValue] = []
  for item in list {
    result.push(item)
  }
  result
}

///|
fn class_name_in_list(
  list : Array[ClassValue],
  name : String,
  start : Int,
) -> Bool {
  for i = start; i < list.length(); i = i + 1 {
    if list[i].name == name {
      return true
    }
  }
  false
}

///|
fn class_mro_merge(
  seqs_in : Array[Array[ClassValue]],
) -> Result[Array[ClassValue], RuntimeError] {
  let seqs : Array[Array[ClassValue]] = []
  for seq in seqs_in {
    seqs.push(clone_class_list(seq))
  }
  let out : Array[ClassValue] = []
  while true {
    let mut all_empty = true
    for seq in seqs {
      if seq.length() > 0 {
        all_empty = false
        break
      }
    }
    if all_empty {
      return Ok(out)
    }
    let mut candidate : ClassValue? = None
    for seq in seqs {
      if seq.length() == 0 {
        continue
      }
      let head = seq[0]
      let mut blocked = false
      for other in seqs {
        if class_name_in_list(other, head.name, 1) {
          blocked = true
          break
        }
      }
      if !blocked {
        candidate = Some(head)
        break
      }
    }
    if candidate is None {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "cannot create a consistent method resolution order".to_string(),
        ),
      )
    }
    let pick = candidate.unwrap()
    out.push(pick)
    for seq in seqs {
      if seq.length() > 0 && seq[0].name == pick.name {
        let _ = seq.remove(0)

      }
    }
  }
  Ok(out)
}

///|
fn class_mro_with_seen(
  klass : ClassValue,
  seen : Array[String],
) -> Result[Array[ClassValue], RuntimeError] {
  for name in seen {
    if name == klass.name {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "cannot create a consistent method resolution order".to_string(),
        ),
      )
    }
  }
  let next_seen : Array[String] = []
  for name in seen {
    next_seen.push(name)
  }
  next_seen.push(klass.name)
  let seqs : Array[Array[ClassValue]] = []
  let direct_bases : Array[ClassValue] = []
  for base in klass.bases {
    match base {
      Value::Class(base_class) => {
        direct_bases.push(base_class)
        let base_mro = match class_mro_with_seen(base_class, next_seen) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        seqs.push(base_mro)
      }
      _ => ()
    }
  }
  seqs.push(direct_bases)
  let tail = match class_mro_merge(seqs) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let mro : Array[ClassValue] = [klass]
  for item in tail {
    mro.push(item)
  }
  Ok(mro)
}

///|
fn class_mro(klass : ClassValue) -> Result[Array[ClassValue], RuntimeError] {
  class_mro_with_seen(klass, [])
}

///|
fn lookup_class_attr(
  klass : ClassValue,
  name : String,
) -> Result[Value?, RuntimeError] {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for cls in mro {
    let direct = get_named_value(cls.dict, name)
    if direct is Some(value) {
      return Ok(Some(value))
    }
  }
  Ok(None)
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
      let class_attr = match lookup_class_attr(inst.class, attr) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
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
        Ok(Some(value)) => Ok(value)
        Ok(None) =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "'" + klass.name + "' object has no attribute '" + attr + "'",
            ),
          )
        Err(err) => Err(err)
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
        klass.name == "RuntimeError" ||
        klass.name == "NameError" ||
        klass.name == "TypeError" ||
        klass.name == "AttributeError" ||
        klass.name == "IndexError" ||
        klass.name == "KeyError" ||
        klass.name == "NotImplementedError" ||
        klass.name == "ZeroDivisionError" ||
        klass.name == "ValueError" ||
        klass.name == "ImportError" ||
        klass.name == "AssertionError" ||
        klass.name == "SyntaxError" ||
        klass.name == "IndentationError" ||
        klass.name == "EOFError" {
        let dict : Array[(String, Value)] = []
        if positional.length() > 0 {
          dict.push(("message", positional[0]))
        }
        return Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
      }
      let init = match lookup_class_attr(klass, "__init__") {
        Ok(value) => value
        Err(err) => return Err(err)
      }
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
