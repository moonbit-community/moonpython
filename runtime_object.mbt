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
fn get_attr_raw_from_value(
  target : Value,
  attr : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  fn apply_descriptor(
    class_attr : Value,
    obj : Value,
    owner : Value,
  ) -> Result[Value?, RuntimeError] {
    // Built-in descriptor: property(fget, fset, fdel, doc)
    match class_attr {
      Value::Instance(inst) =>
        if inst.class.name == "property" {
          match get_named_value(inst.dict, "fget") {
            Some(fget) =>
              match obj {
                Value::None => {
                  return Ok(Some(class_attr))
                }
                _ => {
                  if fget is Value::None {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "property has no getter".to_string(),
                      ),
                    )
                  }
                  return match call_callable_with_env(
                    fget,
                    [obj],
                    [],
                    globals,
                    builtins,
                    io,
                  ) {
                    Ok(v) => Ok(Some(v))
                    Err(err) => Err(err)
                  }
                }
              }
            None => {
              return Ok(None)
            }
          }
        }
      _ => ()
    }

    // Built-in descriptor: staticmethod(func)
    match class_attr {
      Value::Instance(inst) =>
        if inst.class.name == "staticmethod" {
          match get_named_value(inst.dict, "func") {
            Some(func) => {
              return Ok(Some(func))
            }
            None => {
              return Ok(None)
            }
          }
        }
      _ => ()
    }

    // Built-in descriptor: classmethod(func)
    match class_attr {
      Value::Instance(inst) =>
        if inst.class.name == "classmethod" {
          match get_named_value(inst.dict, "func") {
            Some(func_value) => {
              let func = match func_value {
                Value::Function(f) => f
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "classmethod() expects a function".to_string(),
                    ),
                  )
              }
              // Call with the owner class as the implicit first argument.
              return Ok(
                Some(
                  Value::BoundMethod(
                    BoundMethodValue::{ function: func, self: owner },
                  ),
                ),
              )
            }
            None => {
              return Ok(None)
            }
          }
        }
      _ => ()
    }

    let desc_class = match class_attr {
      Value::Instance(d) => Some(d.class)
      Value::Class(d) => Some(d)
      _ => None
    }
    if desc_class is None {
      return Ok(None)
    }
    let desc_class = desc_class.unwrap()
    let get_opt = match lookup_class_attr(desc_class, "__get__") {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    match get_opt {
      Some(Value::Function(get_fn)) => {
        let args : Array[Value] = [class_attr, obj, owner]
        match (eval_function_with_kwargs_ref.val)(
          get_fn,
          args,
          [],
          globals,
          builtins,
          io,
        ) {
          Ok(v) => Ok(Some(v))
          Err(err) => Err(err)
        }
      }
      _ => Ok(None)
    }
  }

  match target {
    Value::Instance(inst) => {
      let direct = get_named_value(inst.dict, attr)
      if direct is Some(value) {
        return Ok(value)
      }
      if inst.class.name == "super" {
        // super(type, obj) proxy
        let thisclass = match get_named_value(inst.dict, "__thisclass__") {
          Some(Value::Class(k)) => k
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "invalid super object".to_string(),
              ),
            )
        }
        let self_value = match get_named_value(inst.dict, "__self__") {
          Some(v) => v
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "invalid super object".to_string(),
              ),
            )
        }
        let self_class = match get_named_value(inst.dict, "__self_class__") {
          Some(Value::Class(k)) => k
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "invalid super object".to_string(),
              ),
            )
        }

        let mro = match class_mro(self_class) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let mut after = false
        for cls in mro {
          if after {
            let direct = get_named_value(cls.dict, attr)
            if direct is Some(value) {
              match value {
                Value::Function(func) => {
                  // Bind like normal instance access
                  match self_value {
                    Value::Instance(_) =>
                      return Ok(
                        Value::BoundMethod(
                          BoundMethodValue::{ function: func, self: self_value },
                        ),
                      )
                    _ => ()
                  }
                }
                _ => ()
              }
              // Apply descriptor semantics; owner is dynamic class
              let obj_for_desc = match self_value {
                Value::Instance(_) => self_value
                _ => Value::None
              }
              match apply_descriptor(value, obj_for_desc, Value::Class(self_class)) {
                Ok(Some(v)) => return Ok(v)
                Ok(None) => return Ok(value)
                Err(err) => return Err(err)
              }
            }
          }
          if cls.name == thisclass.name {
            after = true
          }
        }
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Attribute,
            "'super' object has no attribute '" + attr + "'",
          ),
        )
      }

      if inst.class.name == "generator" {
        if attr == "send" {
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "send",
                params: ["self", "value"],
                defaults: [],
                body: [],
                is_generator: false,
                is_async: false,
                closure: [],
              },
              self: Value::Instance(inst),
            }),
          )
        }
        if attr == "close" {
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "close",
                params: ["self"],
                defaults: [],
                body: [],
                is_generator: false,
                is_async: false,
                closure: [],
              },
              self: Value::Instance(inst),
            }),
          )
        }
        if attr == "throw" {
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "throw",
                params: ["self", "exc", "val", "tb"],
                defaults: [Value::None, Value::None],
                body: [],
                is_generator: false,
                is_async: false,
                closure: [],
              },
              self: Value::Instance(inst),
            }),
          )
        }
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
        Some(value) =>
          match apply_descriptor(value, Value::Instance(inst), Value::Class(inst.class)) {
            Ok(Some(v)) => Ok(v)
            Ok(None) => Ok(value)
            Err(err) => Err(err)
          }
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "'" + inst.class.name + "' object has no attribute '" + attr + "'",
            ),
          )
      }
    }
    Value::Class(klass) => {
      match lookup_class_attr(klass, attr) {
        Ok(Some(value)) =>
          match apply_descriptor(value, Value::None, Value::Class(klass)) {
            Ok(Some(v)) => Ok(v)
            Ok(None) => Ok(value)
            Err(err) => Err(err)
          }
        Ok(None) =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "'" + klass.name + "' object has no attribute '" + attr + "'",
            ),
          )
        Err(err) => Err(err)
      }
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
fn get_attr_from_value(
  target : Value,
  attr : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  // 1) If instance defines __getattribute__, use it.
  // 2) Otherwise do the default lookup.
  // 3) If default lookup fails and instance defines __getattr__, call it.
  match target {
    Value::Instance(inst) => {
      // __getattribute__ (instance hook)
      match lookup_class_attr(inst.class, "__getattribute__") {
        Ok(Some(Value::Function(f))) => {
          // Call through the normal call path so intrinsic implementations
          // (e.g. object.__getattribute__) are handled.
          let bound = Value::BoundMethod(
            BoundMethodValue::{ function: f, self: target },
          )
          let result = call_callable_with_env(
            bound,
            [Value::Str(attr)],
            [],
            globals,
            builtins,
            io,
          )
          match result {
            Ok(v) => return Ok(v)
            Err(err0) =>
              match err0.kind {
                RuntimeErrorKind::Attribute => {
                  // __getattr__ fallback only for AttributeError
                  match lookup_class_attr(inst.class, "__getattr__") {
                    Ok(Some(Value::Function(f2))) => {
                      let name_val2 = Value::Str(attr)
                      return (eval_function_with_kwargs_ref.val)(
                        f2,
                        [target, name_val2],
                        [],
                        globals,
                        builtins,
                        io,
                      )
                    }
                    Ok(Some(_)) =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "__getattr__ must be a function".to_string(),
                        ),
                      )
                    Ok(None) => return Err(err0)
                    Err(err) => return Err(err)
                  }
                }
                _ => return Err(err0)
              }
          }
        }
        Ok(Some(_)) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__ must be a function".to_string(),
            ),
          )
        Ok(None) => ()
        Err(err) => return Err(err)
      }

      // Default lookup
      let raw = get_attr_raw_from_value(target, attr, globals, builtins, io)
      match raw {
        Ok(v) => Ok(v)
        Err(err0) => {
          // __getattr__ fallback
          match lookup_class_attr(inst.class, "__getattr__") {
            Ok(Some(Value::Function(f))) => {
              let name_val = Value::Str(attr)
              (eval_function_with_kwargs_ref.val)(
                f,
                [target, name_val],
                [],
                globals,
                builtins,
                io,
              )
            }
            Ok(Some(_)) =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__getattr__ must be a function".to_string(),
                ),
              )
            Ok(None) => Err(err0)
            Err(err) => Err(err)
          }
        }
      }

    }
    _ => get_attr_raw_from_value(target, attr, globals, builtins, io)
  }
}

///|
fn set_attr_on_value(
  target : Value,
  attr : String,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  // __setattr__ (instance hook)
  match target {
    Value::Instance(inst) =>
      match lookup_class_attr(inst.class, "__setattr__") {
        Ok(Some(Value::Function(f))) => {
          let _ = match (eval_function_with_kwargs_ref.val)(
            f,
            [target, Value::Str(attr), value],
            [],
            globals,
            builtins,
            io,
          ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          return Ok(())
        }
        Ok(Some(_)) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__ must be a function".to_string(),
            ),
          )
        Ok(None) => ()
        Err(err) => return Err(err)
      }
    _ => ()
  }
  fn apply_descriptor_set(
    class_attr : Value,
    obj : Value,
    value : Value,
  ) -> Result[Bool, RuntimeError] {
    // Built-in descriptor: property(fget, fset, fdel, doc)
    match class_attr {
      Value::Instance(inst) =>
        if inst.class.name == "property" {
          match get_named_value(inst.dict, "fset") {
            Some(fset) => {
              let args : Array[Value] = [obj, value]
              let _ = match call_callable_with_env(
                fset,
                args,
                [],
                globals,
                builtins,
                io,
              ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              return Ok(true)
            }
            None =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "can't set attribute".to_string(),
                ),
              )
          }
        }
      _ => ()
    }

    let desc_class = match class_attr {
      Value::Instance(d) => Some(d.class)
      Value::Class(d) => Some(d)
      _ => None
    }
    if desc_class is None {
      return Ok(false)
    }
    let desc_class = desc_class.unwrap()
    let set_opt = match lookup_class_attr(desc_class, "__set__") {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    match set_opt {
      Some(Value::Function(set_fn)) => {
        let args : Array[Value] = [class_attr, obj, value]
        match (eval_function_with_kwargs_ref.val)(
          set_fn,
          args,
          [],
          globals,
          builtins,
          io,
        ) {
          Ok(_v) => Ok(true)
          Err(err) => Err(err)
        }
      }
      _ => Ok(false)
    }
  }

  match target {
    Value::Instance(inst) => {
      let class_attr = match lookup_class_attr(inst.class, attr) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match class_attr {
        Some(descr) => {
          let handled = match apply_descriptor_set(descr, target, value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if handled {
            return Ok(())
          }
        }
        None => ()
      }
      set_named_value(inst.dict, attr, value)
      Ok(())
    }
    Value::Class(klass) => {
      // NOTE: we don't implement metaclass descriptors yet.
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
fn delete_attr_on_value(
  target : Value,
  attr : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  // __delattr__ (instance hook)
  match target {
    Value::Instance(inst) =>
      match lookup_class_attr(inst.class, "__delattr__") {
        Ok(Some(Value::Function(f))) => {
          let _ = match (eval_function_with_kwargs_ref.val)(
            f,
            [target, Value::Str(attr)],
            [],
            globals,
            builtins,
            io,
          ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          return Ok(())
        }
        Ok(Some(_)) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__ must be a function".to_string(),
            ),
          )
        Ok(None) => ()
        Err(err) => return Err(err)
      }
    _ => ()
  }
  fn apply_descriptor_delete(
    class_attr : Value,
    obj : Value,
  ) -> Result[Bool, RuntimeError] {
    // Built-in descriptor: property(fget, fset, fdel, doc)
    match class_attr {
      Value::Instance(inst) =>
        if inst.class.name == "property" {
          match get_named_value(inst.dict, "fdel") {
            Some(fdel) => {
              let _ = match call_callable_with_env(
                fdel,
                [obj],
                [],
                globals,
                builtins,
                io,
              ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              return Ok(true)
            }
            None =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "can't delete attribute".to_string(),
                ),
              )
          }
        }
      _ => ()
    }

    let desc_class = match class_attr {
      Value::Instance(d) => Some(d.class)
      Value::Class(d) => Some(d)
      _ => None
    }
    if desc_class is None {
      return Ok(false)
    }
    let desc_class = desc_class.unwrap()
    let del_opt = match lookup_class_attr(desc_class, "__delete__") {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    match del_opt {
      Some(Value::Function(del_fn)) => {
        let args : Array[Value] = [class_attr, obj]
        match (eval_function_with_kwargs_ref.val)(
          del_fn,
          args,
          [],
          globals,
          builtins,
          io,
        ) {
          Ok(_v) => Ok(true)
          Err(err) => Err(err)
        }
      }
      _ => Ok(false)
    }
  }

  match target {
    Value::Instance(inst) => {
      let class_attr = match lookup_class_attr(inst.class, attr) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match class_attr {
        Some(descr) => {
          let handled = match apply_descriptor_delete(descr, target) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if handled {
            return Ok(())
          }
        }
        None => ()
      }
      for i = 0; i < inst.dict.length(); i = i + 1 {
        if inst.dict[i].0 == attr {
          let _ = inst.dict.remove(i)
          return Ok(())
        }
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "attribute not found".to_string(),
        ),
      )
    }
    Value::Class(klass) => {
      for i = 0; i < klass.dict.length(); i = i + 1 {
        if klass.dict[i].0 == attr {
          let _ = klass.dict.remove(i)
          return Ok(())
        }
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "attribute not found".to_string(),
        ),
      )
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "attribute not supported".to_string(),
        ),
      )
  }
}

///|
fn eval_function_with_kwargs_uninitialized(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = func
  let _ = positional
  let _ = keywords
  let _ = globals
  let _ = builtins
  let _ = io
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      "RuntimeError: internal call callback not initialized".to_string(),
    ),
  )
}

///|
let eval_function_with_kwargs_ref : Ref[
  (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
] = { val: eval_function_with_kwargs_uninitialized }

///|
fn eval_generator_with_kwargs_uninitialized(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = func
  let _ = positional
  let _ = keywords
  let _ = globals
  let _ = builtins
  let _ = io
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      "RuntimeError: internal generator callback not initialized".to_string(),
    ),
  )
}

///|
let eval_generator_with_kwargs_ref : Ref[
  (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
] = { val: eval_generator_with_kwargs_uninitialized }

///|
fn set_eval_function_with_kwargs_callback(
  callback : (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
) -> Unit {
  eval_function_with_kwargs_ref.val = callback
}

///|
fn set_eval_generator_with_kwargs_callback(
  callback : (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
) -> Unit {
  eval_generator_with_kwargs_ref.val = callback
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
      if func.is_async {
        if func.is_generator {
          Err(
            make_runtime_error(
              RuntimeErrorKind::NotImplemented,
              "async generators are not supported".to_string(),
            ),
          )
        } else {
          (eval_function_with_kwargs_ref.val)(
            func, positional, keywords, globals, builtins, io,
          )
        }
      } else if func.is_generator {
        (eval_generator_with_kwargs_ref.val)(
          func, positional, keywords, globals, builtins, io,
        )
      } else if func.name == "__getattribute__" && func.body.length() == 0 {
        // Intrinsic: object.__getattribute__(self, name)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() takes exactly two arguments".to_string(),
            ),
          )
        }
        let target = positional[0]
        let name = match positional[1] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        get_attr_raw_from_value(target, name, globals, builtins, io)
      } else {
        (eval_function_with_kwargs_ref.val)(
          func, positional, keywords, globals, builtins, io,
        )
      }
    Value::BoundMethod(method) => {
      // Intrinsic: object.__getattribute__(self, name)
      if method.function.name == "__getattribute__" &&
        method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() takes exactly one argument".to_string(),
            ),
          )
        }
        let name = match positional[0] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        return get_attr_raw_from_value(method.self, name, globals, builtins, io)
      }

      match method.self {
        Value::Instance(inst) =>
          if inst.class.name == "generator" &&
            method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match method.function.name {
              "send" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "send() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  return generator_send(method.self, positional[0])
                }
              "close" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "close() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return generator_close(method.self)
                }
              "throw" =>
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "throw() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                } else {
                  return generator_throw(method.self, positional[0])
                }
              _ => ()
            }
          }
        _ => ()
      }
      let args : Array[Value] = [method.self]
      for item in positional {
        args.push(item)
      }
      (eval_function_with_kwargs_ref.val)(
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
        klass.name == "EOFError" ||
        klass.name == "StopIteration" {
        let dict : Array[(String, Value)] = []
        dict.push(("__traceback__", Value::None))
        dict.push(("args", Value::Tuple(positional)))
        dict.push(("__cause__", Value::None))
        dict.push(("__context__", Value::None))
        dict.push(("__suppress_context__", Value::Bool(false)))
        if positional.length() > 0 {
          dict.push(("message", positional[0]))
        }
        if klass.name == "StopIteration" {
          let value = if positional.length() > 0 {
            positional[0]
          } else {
            Value::None
          }
          dict.push(("value", value))
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
            (eval_function_with_kwargs_ref.val)(
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
    Value::Instance(inst) => {
      // Callable objects: obj(...) dispatches to obj.__call__(...)
      let call_attr = match lookup_class_attr(inst.class, "__call__") {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match call_attr {
        Some(value) => {
          // Reuse the regular attribute lookup path so we also get descriptor
          // behavior and method binding.
          let bound = match get_attr_raw_from_value(callee, "__call__", globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          call_callable_with_env(bound, positional, keywords, globals, builtins, io)
        }
        None =>
          Err(
            make_runtime_error(RuntimeErrorKind::Type, not_callable_message(callee)),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, not_callable_message(callee)),
      )
  }
}
