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
let function_dict_name = "$__mpython_func_dict__"

///|
fn function_attr_dict(func : FunctionValue) -> Array[(Value, Value)] {
  for pair in func.closure {
    if pair.0 == function_dict_name {
      match pair.1 {
        Value::Dict(pairs) => return pairs
        _ => break
      }
    }
  }
  let pairs : Array[(Value, Value)] = []
  func.closure.push((function_dict_name, Value::Dict(pairs)))
  pairs
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
fn class_includes_list(klass : ClassValue) -> Bool {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(_) => return false
  }
  for cls in mro {
    if cls.name == "list" {
      return true
    }
  }
  false
}

///|
fn class_includes_dict(klass : ClassValue) -> Bool {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(_) => return false
  }
  for cls in mro {
    if cls.name == "dict" {
      return true
    }
  }
  false
}

///|
fn is_ascii_alpha(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int())
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  let code = c.to_int()
  code >= '0'.to_int() && code <= '9'.to_int()
}

///|
fn is_ascii_alnum(c : Char) -> Bool {
  is_ascii_alpha(c) || is_ascii_digit(c)
}

///|
fn is_ascii_whitespace(c : Char) -> Bool {
  let code = c.to_int()
  code == ' '.to_int() ||
  code == '\t'.to_int() ||
  code == '\n'.to_int() ||
  code == '\r'.to_int() ||
  code == 0x0b ||
  code == 0x0c
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
                Value::None => return Ok(Some(class_attr))
                _ => {
                  if fget is Value::None {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "property has no getter".to_string(),
                      ),
                    )
                  }
                  return match
                    call_callable_with_env(
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
            None => return Ok(None)
          }
        }
      _ => ()
    }

    // Built-in descriptor: staticmethod(func)
    match class_attr {
      Value::Instance(inst) =>
        if inst.class.name == "staticmethod" {
          match get_named_value(inst.dict, "func") {
            Some(func) => return Ok(Some(func))
            None => return Ok(None)
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
                  Value::BoundMethod(BoundMethodValue::{
                    function: func,
                    self: owner,
                  }),
                ),
              )
            }
            None => return Ok(None)
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
        match
          (eval_function_with_kwargs_ref.val)(
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
      if inst.class.name == "classmethod" || inst.class.name == "staticmethod" {
        if attr == "__func__" {
          match get_named_value(inst.dict, "func") {
            Some(value) => return Ok(value)
            None =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "'" + inst.class.name + "' object has no attribute '__func__'",
                ),
              )
          }
        }
      }
      if inst.class.name == "code" && attr == "replace" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "code.replace",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if inst.class.name == "coroutine" && attr == "close" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "coroutine.close",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
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
                Value::Function(func) =>
                  // Bind like normal instance access
                  match self_value {
                    Value::Instance(_) =>
                      return Ok(
                        Value::BoundMethod(BoundMethodValue::{
                          function: func,
                          self: self_value,
                        }),
                      )
                    _ => ()
                  }
                _ => ()
              }
              // Apply descriptor semantics; owner is dynamic class
              let obj_for_desc = match self_value {
                Value::Instance(_) => self_value
                _ => Value::None
              }
              match
                apply_descriptor(value, obj_for_desc, Value::Class(self_class)) {
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
      if inst.class.name == "async_generator" {
        let has_gen_id = match get_named_value(inst.dict, "gen_id") {
          Some(_) => true
          None => false
        }
        if attr == "__aiter__" {
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "__aiter__",
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
        if attr == "__anext__" {
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "__anext__",
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
        if has_gen_id {
          if attr == "asend" {
            return Ok(
              Value::BoundMethod(BoundMethodValue::{
                function: FunctionValue::{
                  name: "asend",
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
          if attr == "athrow" {
            return Ok(
              Value::BoundMethod(BoundMethodValue::{
                function: FunctionValue::{
                  name: "athrow",
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
          if attr == "aclose" {
            return Ok(
              Value::BoundMethod(BoundMethodValue::{
                function: FunctionValue::{
                  name: "aclose",
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
          match
            apply_descriptor(
              value,
              Value::Instance(inst),
              Value::Class(inst.class),
            ) {
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
    Value::Tuple(_) => {
      if attr == "index" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "index",
              params: ["self", "value", "start", "end"],
              defaults: [Value::None, Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'" + type_name_from_value(target) + "' object has no attribute '" +
          attr +
          "'",
        ),
      )
    }
    Value::Str(_) => {
      if attr == "startswith" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "startswith",
              params: ["self", "prefix", "start", "end"],
              defaults: [Value::None, Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "isascii" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "isascii",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "isdigit" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "isdigit",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "partition" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "partition",
              params: ["self", "sep"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "endswith" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "endswith",
              params: ["self", "suffix", "start", "end"],
              defaults: [Value::None, Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "isidentifier" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "isidentifier",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "upper" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "upper",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "replace" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "replace",
              params: ["self", "old", "new", "count"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "split" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "split",
              params: ["self", "sep", "maxsplit"],
              defaults: [Value::None, Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'str' object has no attribute '" + attr + "'",
        ),
      )
    }
    Value::List(_) => {
      if attr == "append" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "append",
              params: ["self", "object"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "extend" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "extend",
              params: ["self", "iterable"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "insert" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "insert",
              params: ["self", "index", "object"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "remove" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "remove",
              params: ["self", "value"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "clear" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "clear",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "pop" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "pop",
              params: ["self", "index"],
              defaults: [Value::Int(@bigint.BigInt::from_int(-1))],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'list' object has no attribute '" + attr + "'",
        ),
      )
    }
    Value::Dict(_) => {
      if attr == "get" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "get",
              params: ["self", "key", "default"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "pop" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "pop",
              params: ["self", "key", "default"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "setdefault" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "setdefault",
              params: ["self", "key", "default"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "keys" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "keys",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "values" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "values",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "items" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "items",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "update" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "update",
              params: ["self", "other"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "clear" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "clear",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__getitem__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__getitem__",
              params: ["self", "key"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__setitem__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__setitem__",
              params: ["self", "key", "value"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__delitem__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__delitem__",
              params: ["self", "key"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__iter__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__iter__",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__len__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__len__",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__contains__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__contains__",
              params: ["self", "key"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'dict' object has no attribute '" + attr + "'",
        ),
      )
    }
    Value::Set(_) => {
      if attr == "add" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "add",
              params: ["self", "value"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "remove" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "remove",
              params: ["self", "value"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "discard" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "discard",
              params: ["self", "value"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "pop" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "pop",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "clear" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "clear",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "update" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "update",
              params: ["self", "iterable"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "issuperset" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "issuperset",
              params: ["self", "other"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "issubset" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "issubset",
              params: ["self", "other"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__contains__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__contains__",
              params: ["self", "item"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__iter__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__iter__",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__len__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__len__",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'set' object has no attribute '" + attr + "'",
        ),
      )
    }
    Value::Function(func) =>
      if attr == "__dict__" {
        if func.body.length() == 0 && is_builtin_class_name(func.name) {
          let klass = builtin_class_from_name(func.name, builtins)
          let pairs : Array[(Value, Value)] = []
          for item in klass.dict {
            pairs.push((Value::Str(item.0), item.1))
          }
          Ok(Value::Dict(pairs))
        } else {
          Ok(Value::Dict(function_attr_dict(func)))
        }
      } else {
        let pairs = function_attr_dict(func)
        let index = match dict_find_index(pairs, Value::Str(attr)) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if index is Some(i) {
          return Ok(pairs[i].1)
        }
        if attr == "__code__" {
          Ok(make_code_instance(0N))
        } else if attr == "__closure__" {
          let cells : Array[Value] = []
          for pair in func.closure {
            if is_cell_value(pair.1) {
              cells.push(pair.1)
            }
          }
          if cells.length() == 0 {
            Ok(Value::None)
          } else {
            Ok(Value::Tuple(cells))
          }
        } else if attr == "__globals__" {
          let mut env = globals
          for pair in func.closure {
            if pair.0 == globals_capture_name {
              match pair.1 {
                Value::Instance(inst) => env = inst.dict
                _ => ()
              }
              break
            }
          }
          let pairs : Array[(Value, Value)] = []
          for item in env {
            pairs.push((Value::Str(item.0), item.1))
          }
          Ok(Value::Dict(pairs))
        } else if attr == "__module__" {
          let mut env = globals
          for pair in func.closure {
            if pair.0 == globals_capture_name {
              match pair.1 {
                Value::Instance(inst) => env = inst.dict
                _ => ()
              }
              break
            }
          }
          let module_name = match get_named_value(env, "__name__") {
            Some(Value::Str(name)) => name
            _ =>
              if func.body.length() == 0 {
                "builtins".to_string()
              } else {
                "__main__".to_string()
              }
          }
          Ok(Value::Str(module_name))
        } else if attr == "__doc__" {
          Ok(Value::None)
        } else if attr == "__qualname__" {
          Ok(Value::Str(func.name))
        } else if attr == "__name__" {
          Ok(Value::Str(func.name))
        } else if func.body.length() == 0 && is_builtin_class_name(func.name) {
          get_attr_raw_from_value(
            Value::Class(builtin_class_from_name(func.name, builtins)),
            attr,
            globals,
            builtins,
            io,
          )
        } else {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "'function' object has no attribute '" + attr + "'",
            ),
          )
        }
      }
    Value::Class(klass) =>
      if attr == "__name__" {
        Ok(Value::Str(klass.name))
      } else if attr == "__qualname__" {
        Ok(Value::Str(klass.name))
      } else if attr == "__doc__" {
        Ok(Value::None)
      } else if attr == "__dict__" {
        let pairs : Array[(Value, Value)] = []
        for item in klass.dict {
          pairs.push((Value::Str(item.0), item.1))
        }
        Ok(Value::Dict(pairs))
      } else if attr == "__mro__" {
        let mro = match class_mro(klass) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
        let values : Array[Value] = []
        for item in mro {
          values.push(Value::Class(item))
        }
        Ok(Value::Tuple(values))
      } else if klass.name == "int" && attr == "from_bytes" {
        Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "int.from_bytes",
              params: ["cls", "bytes", "byteorder", "signed"],
              defaults: [Value::Bool(false)],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: Value::Class(klass),
          }),
        )
      } else if attr == "__code__" && klass.name == "function" {
        Ok(make_code_instance(0N))
      } else if attr == "__closure__" && klass.name == "function" {
        Ok(Value::None)
      } else if attr == "__globals__" && klass.name == "function" {
        Ok(
          Value::Instance(InstanceValue::{
            class: builtin_class_from_name("member_descriptor", builtins),
            dict: [],
          }),
        )
      } else {
        match lookup_class_attr(klass, attr) {
          Ok(Some(value)) =>
            match apply_descriptor(value, Value::None, Value::Class(klass)) {
              Ok(Some(v)) => Ok(v)
              Ok(None) => Ok(value)
              Err(err) => Err(err)
            }
          Ok(None) =>
            if attr == "register" {
              Ok(
                Value::BoundMethod(BoundMethodValue::{
                  function: FunctionValue::{
                    name: "register",
                    params: ["cls", "subclass"],
                    defaults: [],
                    body: [],
                    is_generator: false,
                    is_async: false,
                    closure: [],
                  },
                  self: Value::Class(klass),
                }),
              )
            } else {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Attribute,
                  "'" + klass.name + "' object has no attribute '" + attr + "'",
                ),
              )
            }
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
          let bound = Value::BoundMethod(BoundMethodValue::{
            function: f,
            self: target,
          })
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
                RuntimeErrorKind::Attribute =>
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
        Err(err0) =>
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
    _ => get_attr_raw_from_value(target, attr, globals, builtins, io)
  }
}

///|
fn set_attr_raw_on_value(
  target : Value,
  attr : String,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
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
              let _ = match
                call_callable_with_env(fset, args, [], globals, builtins, io) {
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
        match
          (eval_function_with_kwargs_ref.val)(
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
    Value::Function(func) => {
      let pairs = function_attr_dict(func)
      let _ = match dict_set_item(pairs, Value::Str(attr), value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
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
          let bound = Value::BoundMethod(BoundMethodValue::{
            function: f,
            self: target,
          })
          let _ = match
            call_callable_with_env(
              bound,
              [Value::Str(attr), value],
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
  set_attr_raw_on_value(target, attr, value, globals, builtins, io)
}

///|
fn delete_attr_raw_on_value(
  target : Value,
  attr : String,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
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
              let _ = match
                call_callable_with_env(fdel, [obj], [], globals, builtins, io) {
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
        match
          (eval_function_with_kwargs_ref.val)(
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
          let bound = Value::BoundMethod(BoundMethodValue::{
            function: f,
            self: target,
          })
          let _ = match
            call_callable_with_env(
              bound,
              [Value::Str(attr)],
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
  delete_attr_raw_on_value(target, attr, globals, builtins, io)
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
fn make_dict_view_class(name : String) -> ClassValue {
  let dict : Array[(String, Value)] = []
  dict.push(
    (
      "__iter__",
      Value::Function(FunctionValue::{
        name: "__iter__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  dict.push(
    (
      "__len__",
      Value::Function(FunctionValue::{
        name: "__len__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  dict.push(
    (
      "__contains__",
      Value::Function(FunctionValue::{
        name: "__contains__",
        params: ["self", "item"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  ClassValue::{ name, bases: [], dict }
}

///|
fn make_dict_view_instance(view_name : String, dict_value : Value) -> Value {
  Value::Instance(InstanceValue::{
    class: make_dict_view_class(view_name),
    dict: [("dict", dict_value)],
  })
}

///|
fn make_code_instance(flags : @bigint.BigInt) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "code", bases: [], dict: [] },
    dict: [("co_flags", Value::Int(flags))],
  })
}

///|
fn make_generic_alias(origin : Value, args : Array[Value]) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "GenericAlias", bases: [], dict: [] },
    dict: [("__origin__", origin), ("__args__", Value::Tuple(args))],
  })
}

///|
fn make_union_type(args : Array[Value]) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "UnionType", bases: [], dict: [] },
    dict: [("__args__", Value::Tuple(args))],
  })
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
          (eval_generator_with_kwargs_ref.val)(
            func, positional, keywords, globals, builtins, io,
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
      } else if func.name == "__setattr__" && func.body.length() == 0 {
        // Intrinsic: object.__setattr__(self, name, value)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 3 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() takes exactly three arguments".to_string(),
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
        let value = positional[2]
        let _ = match
          set_attr_raw_on_value(target, name, value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::None)
      } else if func.name == "__delattr__" && func.body.length() == 0 {
        // Intrinsic: object.__delattr__(self, name)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() takes exactly two arguments".to_string(),
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
        let _ = match
          delete_attr_raw_on_value(target, name, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::None)
      } else if func.name == "__new__" && func.body.length() == 0 {
        // Intrinsic: object.__new__(cls)
        if positional.length() < 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__new__() expects a type".to_string(),
            ),
          )
        }
        let cls_value = positional[0]
        match cls_value {
          Value::Class(klass) => {
            let inst_dict : Array[(String, Value)] = []
            if class_includes_list(klass) {
              inst_dict.push((list_storage_name, Value::List([])))
            }
            if class_includes_dict(klass) {
              inst_dict.push((dict_storage_name, Value::Dict([])))
            }
            Ok(Value::Instance(InstanceValue::{ class: klass, dict: inst_dict }))
          }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "__new__() expects a type".to_string(),
              ),
            )
        }
      } else if func.name == "__eq__" && func.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__eq__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__eq__() takes exactly two arguments".to_string(),
            ),
          )
        }
        Ok(Value::Bool(eq_value(positional[0], positional[1])))
      } else if func.name == "__ne__" && func.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__ne__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__ne__() takes exactly two arguments".to_string(),
            ),
          )
        }
        Ok(Value::Bool(!eq_value(positional[0], positional[1])))
      } else if func.body.length() == 0 {
        match
          eval_builtin_call(
            func.name,
            positional,
            keywords,
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(Some(value)) => Ok(value)
          Ok(None) =>
            (eval_function_with_kwargs_ref.val)(
              func, positional, keywords, globals, builtins, io,
            )
          Err(err) => Err(err)
        }
      } else {
        (eval_function_with_kwargs_ref.val)(
          func, positional, keywords, globals, builtins, io,
        )
      }
    Value::BoundMethod(bound_method) => {
      // Intrinsic: object.__getattribute__(self, name)
      if bound_method.function.name == "__getattribute__" &&
        bound_method.function.body.length() == 0 {
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
        return get_attr_raw_from_value(
          bound_method.self,
          name,
          globals,
          builtins,
          io,
        )
      }

      // Intrinsic: object.__setattr__(self, name, value)
      if bound_method.function.name == "__setattr__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() takes exactly two arguments".to_string(),
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
        let value = positional[1]
        let _ = match
          set_attr_raw_on_value(
            bound_method.self,
            name,
            value,
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        return Ok(Value::None)
      }

      // Intrinsic: object.__delattr__(self, name)
      if bound_method.function.name == "__delattr__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() takes exactly one argument".to_string(),
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
        let _ = match
          delete_attr_raw_on_value(
            bound_method.self,
            name,
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        return Ok(Value::None)
      }
      match bound_method.self {
        Value::Instance(inst) =>
          if (
              inst.class.name == "dict_keys" ||
              inst.class.name == "dict_values" ||
              inst.class.name == "dict_items"
            ) &&
            bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            let dict_value = match get_named_value(inst.dict, "dict") {
              Some(v) => v
              None =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "RuntimeError: bad dict view".to_string(),
                  ),
                )
            }
            let pairs = match dict_value {
              Value::Dict(pairs) => pairs
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "dict view expects a dict".to_string(),
                  ),
                )
            }
            match bound_method.function.name {
              "__len__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__len__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(
                    Value::Int(@bigint.BigInt::from_int(pairs.length())),
                  )
                }
              "__iter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__iter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let items : Array[Value] = []
                  if inst.class.name == "dict_keys" {
                    for pair in pairs {
                      items.push(pair.0)
                    }
                  } else if inst.class.name == "dict_values" {
                    for pair in pairs {
                      items.push(pair.1)
                    }
                  } else {
                    for pair in pairs {
                      items.push(Value::Tuple([pair.0, pair.1]))
                    }
                  }
                  return Ok(make_iterator(items))
                }
              "__contains__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__contains__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let item = positional[0]
                  if inst.class.name == "dict_keys" {
                    let index = match dict_find_index(pairs, item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    return Ok(Value::Bool(index is Some(_)))
                  } else if inst.class.name == "dict_values" {
                    for pair in pairs {
                      if eq_value(pair.1, item) {
                        return Ok(Value::Bool(true))
                      }
                    }
                    return Ok(Value::Bool(false))
                  } else {
                    let _ = match ensure_hashable(item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    match item {
                      Value::Tuple(values) | Value::List(values) =>
                        if values.length() != 2 {
                          return Ok(Value::Bool(false))
                        } else {
                          for pair in pairs {
                            if eq_value(pair.0, values[0]) &&
                              eq_value(pair.1, values[1]) {
                              return Ok(Value::Bool(true))
                            }
                          }
                          return Ok(Value::Bool(false))
                        }
                      _ => return Ok(Value::Bool(false))
                    }
                  }
                }
              _ => ()
            }
          } else if inst.class.name == "generator" &&
            bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "send" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "send() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  return generator_send(bound_method.self, positional[0])
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
                  return generator_close(bound_method.self)
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
                  return generator_throw(bound_method.self, positional[0])
                }
              _ => ()
            }
          } else if inst.class.name == "async_generator" &&
            bound_method.function.body.length() == 0 {
            let has_gen_id = match get_named_value(inst.dict, "gen_id") {
              Some(_) => true
              None => false
            }
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "__aiter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__aiter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(bound_method.self)
                }
              "__anext__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__anext__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if has_gen_id {
                    return Ok(
                      async_generator_make_anext_coroutine(
                        bound_method.self,
                        globals,
                        builtins,
                        io,
                      ),
                    )
                  }
                  return Ok(
                    async_genexp_make_anext_coroutine(
                      bound_method.self,
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              "asend" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "asend() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  if !has_gen_id {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "'async_generator' object has no attribute 'asend'",
                      ),
                    )
                  }
                  return Ok(
                    async_generator_make_asend_coroutine(
                      bound_method.self,
                      positional[0],
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              "athrow" =>
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "athrow() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                } else {
                  if !has_gen_id {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "'async_generator' object has no attribute 'athrow'",
                      ),
                    )
                  }
                  return Ok(
                    async_generator_make_athrow_coroutine(
                      bound_method.self,
                      positional[0],
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              "aclose" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "aclose() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if !has_gen_id {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "'async_generator' object has no attribute 'aclose'",
                      ),
                    )
                  }
                  return Ok(
                    async_generator_make_aclose_coroutine(
                      bound_method.self,
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              _ => ()
            }
          }
        Value::Str(text) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 &&
              bound_method.function.name != "split" {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "startswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "startswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let prefix = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "startswith() expects a str prefix".to_string(),
                      ),
                    )
                }
                let start = match index_from_value(
                  if positional.length() >= 2 { positional[1] } else { Value::None },
                  0,
                ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match index_from_value(
                  if positional.length() == 3 { positional[2] } else { Value::None },
                  text.length(),
                ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let segment = substring(text, start_idx, end_idx)
                return Ok(Value::Bool(segment.has_prefix(prefix)))
              }
              "endswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "endswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let suffix = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "endswith() expects a str suffix".to_string(),
                      ),
                    )
                }
                let start = match index_from_value(
                  if positional.length() >= 2 { positional[1] } else { Value::None },
                  0,
                ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match index_from_value(
                  if positional.length() == 3 { positional[2] } else { Value::None },
                  text.length(),
                ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let segment = substring(text, start_idx, end_idx)
                return Ok(Value::Bool(segment.has_suffix(suffix)))
              }
              "isascii" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isascii() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  for c in text.to_array() {
                    if c > '\u007f' {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "isdigit" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isdigit() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_ascii_digit(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "partition" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "partition() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let sep = match positional[0] {
                    Value::Str(value) => value
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "partition() expects a str separator".to_string(),
                        ),
                      )
                  }
                  if sep.length() == 0 {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "ValueError: empty separator".to_string(),
                      ),
                    )
                  }
                  match text.find(sep) {
                    Some(pos) => {
                      let head = substring(text, 0, pos)
                      let tail = substring(text, pos + sep.length(), text.length())
                      return Ok(Value::Tuple([Value::Str(head), Value::Str(sep), Value::Str(tail)]))
                    }
                    None =>
                      return Ok(
                        Value::Tuple([Value::Str(text), Value::Str(""), Value::Str("")]),
                      )
                  }
                }
              "isidentifier" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isidentifier() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  let first = chars[0]
                  if !(is_ascii_alpha(first) || first == '_') {
                    return Ok(Value::Bool(false))
                  }
                  for i = 1; i < chars.length(); i = i + 1 {
                    let c = chars[i]
                    if !(is_ascii_alnum(c) || c == '_') {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "upper" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "upper() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Str(text.to_upper()))
                }
              "replace" => {
                if positional.length() < 2 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "replace() takes 2 or 3 arguments".to_string(),
                    ),
                  )
                }
                let old = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "replace() expects a str pattern".to_string(),
                      ),
                    )
                }
                let new_value = match positional[1] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "replace() expects a str replacement".to_string(),
                      ),
                    )
                }
                let count = if positional.length() == 3 {
                  match index_from_value(positional[2], -1) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                } else {
                  -1
                }
                if count == 0 {
                  return Ok(Value::Str(text))
                }
                if old.length() == 0 {
                  let chars = text.to_array()
                  let total = chars.length() + 1
                  let limit = if count < 0 || count > total { total } else { count }
                  let builder = StringBuilder::new()
                  let mut inserted = 0
                  for i = 0; i < chars.length(); i = i + 1 {
                    if inserted < limit {
                      builder.write_string(new_value)
                      inserted += 1
                    }
                    builder.write_char(chars[i])
                  }
                  if inserted < limit {
                    builder.write_string(new_value)
                  }
                  return Ok(Value::Str(builder.to_string()))
                }
                let builder = StringBuilder::new()
                let mut first = true
                let mut replaced = 0
                for part in text.split(old) {
                  if first {
                    builder.write_string(part.to_string())
                    first = false
                    continue
                  }
                  if count < 0 || replaced < count {
                    builder.write_string(new_value)
                    replaced += 1
                  } else {
                    builder.write_string(old)
                  }
                  builder.write_string(part.to_string())
                }
                return Ok(Value::Str(builder.to_string()))
              }
              "split" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "split() takes at most 2 arguments".to_string(),
                    ),
                  )
                }
                let mut sep_kw : Value? = None
                let mut maxsplit_kw : Value? = None
                for item in keywords {
                  if item.0 == "sep" {
                    sep_kw = Some(item.1)
                  } else if item.0 == "maxsplit" {
                    maxsplit_kw = Some(item.1)
                  } else {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "split() got unexpected keyword arguments".to_string(),
                      ),
                    )
                  }
                }
                if positional.length() >= 1 && sep_kw is Some(_) {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "split() got multiple values for argument 'sep'".to_string(),
                    ),
                  )
                }
                if positional.length() == 2 && maxsplit_kw is Some(_) {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "split() got multiple values for argument 'maxsplit'".to_string(),
                    ),
                  )
                }
                let sep_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  match sep_kw {
                    Some(v) => v
                    None => Value::None
                  }
                }
                let maxsplit_value = if positional.length() == 2 {
                  positional[1]
                } else {
                  match maxsplit_kw {
                    Some(v) => v
                    None => Value::Int(@bigint.BigInt::from_int(-1))
                  }
                }
                let maxsplit = match index_from_value(maxsplit_value, -1) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                match sep_value {
                  Value::None => {
                    let chars = text.to_array()
                    let len = chars.length()
                    let mut i = 0
                    while i < len && is_ascii_whitespace(chars[i]) {
                      i += 1
                    }
                    if i >= len {
                      return Ok(Value::List([]))
                    }
                    if maxsplit == 0 {
                      let mut end = len
                      while end > i && is_ascii_whitespace(chars[end - 1]) {
                        end -= 1
                      }
                      return Ok(Value::List([Value::Str(substring(text, i, end))]))
                    }
                    let parts : Array[Value] = []
                    let mut splits = 0
                    let mut start = i
                    while i < len {
                      if is_ascii_whitespace(chars[i]) {
                        let end = i
                        parts.push(Value::Str(substring(text, start, end)))
                        splits += 1
                        while i < len && is_ascii_whitespace(chars[i]) {
                          i += 1
                        }
                        if maxsplit >= 0 && splits >= maxsplit {
                          let mut tail_end = len
                          while tail_end > i && is_ascii_whitespace(chars[tail_end - 1]) {
                            tail_end -= 1
                          }
                          if tail_end > i {
                            parts.push(Value::Str(substring(text, i, tail_end)))
                          }
                          return Ok(Value::List(parts))
                        }
                        start = i
                        continue
                      }
                      i += 1
                    }
                    if i > start {
                      parts.push(Value::Str(substring(text, start, i)))
                    }
                    return Ok(Value::List(parts))
                  }
                  Value::Str(sep) => {
                    if sep.length() == 0 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "ValueError: empty separator".to_string(),
                        ),
                      )
                    }
                    let raw_parts : Array[String] = []
                    for part in text.split(sep) {
                      raw_parts.push(part.to_string())
                    }
                    if maxsplit < 0 || raw_parts.length() <= maxsplit + 1 {
                      let parts : Array[Value] = []
                      for part in raw_parts {
                        parts.push(Value::Str(part))
                      }
                      return Ok(Value::List(parts))
                    }
                    let parts : Array[Value] = []
                    for i = 0; i <= maxsplit; i = i + 1 {
                      parts.push(Value::Str(raw_parts[i]))
                    }
                    let builder = StringBuilder::new()
                    let mut first_tail = true
                    for i = maxsplit + 1; i < raw_parts.length(); i = i + 1 {
                      if !first_tail {
                        builder.write_string(sep)
                      }
                      builder.write_string(raw_parts[i])
                      first_tail = false
                    }
                    parts.push(Value::Str(builder.to_string()))
                    return Ok(Value::List(parts))
                  }
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "split() separator must be str or None".to_string(),
                      ),
                    )
                }
              }
              _ => ()
            }
          }
        Value::List(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "append" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "append() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  values.push(positional[0])
                  return Ok(Value::None)
                }
              "extend" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "extend() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let to_add : Array[Value] = []
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) => to_add.push(item)
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  for item in to_add {
                    values.push(item)
                  }
                  return Ok(Value::None)
                }
              "insert" =>
                if positional.length() != 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "insert() takes exactly two arguments".to_string(),
                    ),
                  )
                } else {
                  let idx = match index_from_value(positional[0], 0) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  let len = values.length()
                  let mut pos = normalize_index(idx, len)
                  if pos < 0 {
                    pos = 0
                  }
                  if pos > len {
                    pos = len
                  }
                  values.push(Value::None)
                  let mut i = len
                  while i > pos {
                    values[i] = values[i - 1]
                    i = i - 1
                  }
                  values[pos] = positional[1]
                  return Ok(Value::None)
                }
              "remove" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "remove() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let needle = positional[0]
                  for i = 0; i < values.length(); i = i + 1 {
                    if eq_value(values[i], needle) {
                      let _ = values.remove(i)
                      return Ok(Value::None)
                    }
                  }
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: list.remove(x): x not in list".to_string(),
                    ),
                  )
                }
              "clear" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "clear() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let mut i = values.length()
                  while i > 0 {
                    i = i - 1
                    let _ = values.remove(i)

                  }
                  return Ok(Value::None)
                }
              "pop" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "pop() takes at most one argument".to_string(),
                    ),
                  )
                }
                if values.length() == 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Index,
                      "pop from empty list".to_string(),
                    ),
                  )
                }
                let mut idx = values.length() - 1
                if positional.length() == 1 {
                  let raw = match positional[0] {
                    Value::Int(v) =>
                      match bigint_to_int_checked(v) {
                        Ok(i) => i
                        Err(err) => return Err(err)
                      }
                    Value::Bool(b) => if b { 1 } else { 0 }
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "invalid index".to_string(),
                        ),
                      )
                  }
                  let normalized = normalize_index(raw, values.length())
                  if normalized < 0 || normalized >= values.length() {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "pop index out of range".to_string(),
                      ),
                    )
                  }
                  idx = normalized
                }
                let item = values.remove(idx)
                return Ok(item)
              }
              _ => ()
            }
          }
        Value::Tuple(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "index" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "index() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = positional[0]
                let start = match index_from_value(
                  if positional.length() >= 2 { positional[1] } else { Value::None },
                  0,
                ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match index_from_value(
                  if positional.length() == 3 { positional[2] } else { Value::None },
                  values.length(),
                ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, values.length())
                let mut end_idx = normalize_index(end, values.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > values.length() {
                  start_idx = values.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > values.length() {
                  end_idx = values.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let mut i = start_idx
                while i < end_idx {
                  if eq_value(values[i], needle) {
                    return Ok(
                      Value::Int(@bigint.BigInt::from_int(i)),
                    )
                  }
                  i += 1
                }
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: tuple.index(x): x not in tuple".to_string(),
                  ),
                )
              }
              _ => ()
            }
          }
        Value::Dict(pairs) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "get" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "get() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let key = positional[0]
                let default_value = if positional.length() == 2 {
                  positional[1]
                } else {
                  Value::None
                }
                let index = match dict_find_index(pairs, key) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return match index {
                  Some(i) => Ok(pairs[i].1)
                  None => Ok(default_value)
                }
              }
              "pop" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "pop() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let key = positional[0]
                let index = match dict_find_index(pairs, key) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if index is Some(i) {
                  let removed = pairs.remove(i)
                  return Ok(removed.1)
                }
                if positional.length() == 2 {
                  return Ok(positional[1])
                }
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Key,
                    "key not found".to_string(),
                  ),
                )
              }
              "setdefault" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "setdefault() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let key = positional[0]
                let default_value = if positional.length() == 2 {
                  positional[1]
                } else {
                  Value::None
                }
                let index = match dict_find_index(pairs, key) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if index is Some(i) {
                  return Ok(pairs[i].1)
                }
                let _ = match dict_set_item(pairs, key, default_value) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(default_value)
              }
              "keys" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "keys() takes no arguments".to_string(),
                    ),
                  )
                }
                return Ok(
                  make_dict_view_instance("dict_keys", Value::Dict(pairs)),
                )
              }
              "values" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "values() takes no arguments".to_string(),
                    ),
                  )
                }
                return Ok(
                  make_dict_view_instance("dict_values", Value::Dict(pairs)),
                )
              }
              "items" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "items() takes no arguments".to_string(),
                    ),
                  )
                }
                return Ok(
                  make_dict_view_instance("dict_items", Value::Dict(pairs)),
                )
              }
              "update" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "update() takes at most one argument".to_string(),
                    ),
                  )
                }
                if positional.length() == 0 || positional[0] is Value::None {
                  return Ok(Value::None)
                }
                let other = positional[0]
                let entries : Array[(Value, Value)] = []
                match other {
                  Value::Dict(other_pairs) =>
                    for pair in other_pairs {
                      entries.push(pair)
                    }
                  _ => {
                    let iterator = match
                      iter_value_to_iterator(other, globals, builtins, io) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    while true {
                      let item = match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(v) => v
                        Err(err) =>
                          if err.exc_type == "StopIteration" {
                            break
                          } else {
                            return Err(err)
                          }
                      }
                      match item {
                        Value::Tuple(values) | Value::List(values) =>
                          if values.length() != 2 {
                            return Err(
                              make_runtime_error(
                                RuntimeErrorKind::Type,
                                "update() sequence element has wrong length".to_string(),
                              ),
                            )
                          } else {
                            entries.push((values[0], values[1]))
                          }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "update() expects (key, value) pairs".to_string(),
                            ),
                          )
                      }
                    }
                  }
                }
                for entry in entries {
                  let key = entry.0
                  let value = entry.1
                  let _ = match dict_set_item(pairs, key, value) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }

                }
                return Ok(Value::None)
              }
              "clear" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "clear() takes no arguments".to_string(),
                    ),
                  )
                }
                let mut i = pairs.length()
                while i > 0 {
                  i = i - 1
                  let _ = pairs.remove(i)

                }
                return Ok(Value::None)
              }
              "__contains__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__contains__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let index = match dict_find_index(pairs, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::Bool(index is Some(_)))
                }
              "__getitem__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__getitem__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let key = positional[0]
                  let index = match dict_find_index(pairs, key) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  match index {
                    Some(i) => return Ok(pairs[i].1)
                    None =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Key,
                          "key not found".to_string(),
                        ),
                      )
                  }
                }
              "__setitem__" =>
                if positional.length() != 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__setitem__() takes exactly two arguments".to_string(),
                    ),
                  )
                } else {
                  let _ = match dict_set_item(pairs, positional[0], positional[1]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::None)
                }
              "__delitem__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__delitem__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let removed = match dict_delete_key(pairs, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if !removed {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Key,
                        "key not found".to_string(),
                      ),
                    )
                  }
                  return Ok(Value::None)
                }
              "__iter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__iter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let keys : Array[Value] = []
                  for pair in pairs {
                    keys.push(pair.0)
                  }
                  return Ok(make_iterator(keys))
                }
              "__len__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__len__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Int(@bigint.BigInt::from_int(pairs.length())))
                }
              _ => ()
            }
          }
        Value::Set(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "add" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "add() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let _ = match set_add_unique(values, positional[0]) {
                    Ok(_) => ()
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::None)
                }
              "remove" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "remove() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let removed = match set_remove_item(values, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if !removed {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Key,
                        "key not found".to_string(),
                      ),
                    )
                  }
                  return Ok(Value::None)
                }
              "discard" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "discard() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let _ = match set_remove_item(values, positional[0]) {
                    Ok(_) => ()
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::None)
                }
              "pop" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "pop() takes no arguments".to_string(),
                    ),
                  )
                } else if values.length() == 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Key,
                      "pop from empty set".to_string(),
                    ),
                  )
                } else {
                  let idx = values.length() - 1
                  let item = values.remove(idx)
                  return Ok(item)
                }
              "clear" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "clear() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let mut i = values.length()
                  while i > 0 {
                    i = i - 1
                    let _ = values.remove(i)

                  }
                  return Ok(Value::None)
                }
              "update" =>
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "update() takes at most one argument".to_string(),
                    ),
                  )
                } else if positional.length() == 0 ||
                  positional[0] is Value::None {
                  return Ok(Value::None)
                } else {
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(values, item) {
                          Ok(_) => ()
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  return Ok(Value::None)
                }
              "issuperset" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "issuperset() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  let mut ok = true
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_find_index(values, item) {
                          Ok(Some(_)) => ()
                          Ok(None) => {
                            ok = false
                            break
                          }
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  return Ok(Value::Bool(ok))
                }
              "issubset" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "issubset() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let other_values : Array[Value] = []
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(other_values, item) {
                          Ok(_) => ()
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  let mut ok = true
                  for item in values {
                    let index = match set_find_index(other_values, item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    if index is None {
                      ok = false
                      break
                    }
                  }
                  return Ok(Value::Bool(ok))
                }
              "__contains__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__contains__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let index = match set_find_index(values, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::Bool(index is Some(_)))
                }
              "__iter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__iter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(make_iterator(values))
                }
              "__len__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__len__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Int(@bigint.BigInt::from_int(values.length())))
                }
              _ => ()
            }
          }
        _ => ()
      }
      let args : Array[Value] = [bound_method.self]
      for item in positional {
        args.push(item)
      }
      if bound_method.function.body.length() == 0 {
        match
          eval_builtin_call(
            bound_method.function.name,
            args,
            keywords,
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(Some(value)) => return Ok(value)
          Ok(None) => ()
          Err(err) => return Err(err)
        }
      }
      (eval_function_with_kwargs_ref.val)(
        bound_method.function,
        args,
        keywords,
        globals,
        builtins,
        io,
      )
    }
    Value::Class(klass) => {
      let is_builtin = match get_named_value(klass.dict, "__module__") {
        Some(Value::Str(module_name)) =>
          module_name == "builtins" && is_builtin_class_name(klass.name)
        _ => false
      }
      if is_builtin {
        match
          eval_builtin_call(
            klass.name,
            positional,
            keywords,
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(Some(value)) => return Ok(value)
          Ok(None) => ()
          Err(err) => return Err(err)
        }
      }
      if klass.name == "BaseExceptionGroup" || klass.name == "ExceptionGroup" {
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              klass.name + "() requires a message and exceptions".to_string(),
            ),
          )
        }
        let message = positional[0]
        let raw_exceptions = match positional[1] {
          Value::List(values) => values
          Value::Tuple(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                klass.name + " exceptions must be a list".to_string(),
              ),
            )
        }
        if raw_exceptions.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              klass.name + " requires at least one exception".to_string(),
            ),
          )
        }
        let mut require_exception = false
        if klass.name == "ExceptionGroup" {
          require_exception = true
        }
        let exceptions : Array[Value] = []
        for exc in raw_exceptions {
          let exc_value = match
            ensure_exception_instance_from_value(exc, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let inst = match exc_value {
            Value::Instance(inst) => inst
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "exceptions must derive from BaseException".to_string(),
                ),
              )
          }
          if require_exception {
            let mro = match class_mro(inst.class) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let mut ok = false
            for cls in mro {
              if cls.name == "Exception" {
                ok = true
                break
              }
            }
            if !ok {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "ExceptionGroup exceptions must derive from Exception".to_string(),
                ),
              )
            }
          }
          exceptions.push(Value::Instance(inst))
        }
        let exception_tuple : Array[Value] = []
        for item in exceptions {
          exception_tuple.push(item)
        }
        let dict : Array[(String, Value)] = []
        dict.push(("__traceback__", Value::None))
        dict.push(
          ("args", Value::Tuple([message, Value::Tuple(exception_tuple)])),
        )
        dict.push(("__cause__", Value::None))
        dict.push(("__context__", Value::None))
        dict.push(("__suppress_context__", Value::Bool(false)))
        dict.push(("message", message))
        dict.push(("exceptions", Value::List(exceptions)))
        return Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
      }
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
        klass.name == "OSError" ||
        klass.name == "FileNotFoundError" ||
        klass.name == "ImportError" ||
        klass.name == "AssertionError" ||
        klass.name == "Warning" ||
        klass.name == "UserWarning" ||
        klass.name == "DeprecationWarning" ||
        klass.name == "PendingDeprecationWarning" ||
        klass.name == "RuntimeWarning" ||
        klass.name == "ImportWarning" ||
        klass.name == "ResourceWarning" ||
        klass.name == "SyntaxError" ||
        klass.name == "IndentationError" ||
        klass.name == "EOFError" ||
        klass.name == "StopIteration" ||
        klass.name == "StopAsyncIteration" {
        let dict : Array[(String, Value)] = []
        dict.push(("__traceback__", Value::None))
        dict.push(("args", Value::Tuple(positional)))
        dict.push(("__cause__", Value::None))
        dict.push(("__context__", Value::None))
        dict.push(("__suppress_context__", Value::Bool(false)))
        if positional.length() > 0 {
          dict.push(("message", positional[0]))
        }
        if klass.name == "StopIteration" || klass.name == "StopAsyncIteration" {
          let value = if positional.length() > 0 {
            positional[0]
          } else {
            Value::None
          }
          dict.push(("value", value))
        }
        return Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
      }
      let new_value = match lookup_class_attr(klass, "__new__") {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let mut inst_value_opt : Value? = None
      match new_value {
        Some(value) => {
          let args : Array[Value] = [Value::Class(klass)]
          for item in positional {
            args.push(item)
          }
          let created = match
            call_callable_with_env(value, args, keywords, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          inst_value_opt = Some(created)
        }
        None => ()
      }
      let init = match lookup_class_attr(klass, "__init__") {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let inst_value = match inst_value_opt {
        Some(value) => value
        None => {
          let inst_dict : Array[(String, Value)] = []
          if class_includes_list(klass) {
            inst_dict.push((list_storage_name, Value::List([])))
          }
          if class_includes_dict(klass) {
            inst_dict.push((dict_storage_name, Value::Dict([])))
          }
          Value::Instance(InstanceValue::{ class: klass, dict: inst_dict })
        }
      }
      match inst_value {
        Value::Instance(inst) => {
          match init {
            Some(Value::Function(func)) =>
              if inst.class.name == klass.name {
                let args : Array[Value] = [Value::Instance(inst)]
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
          Ok(Value::Instance(inst))
        }
        _ => Ok(inst_value)
      }
    }
    Value::Instance(inst) => {
      if inst.class.name == "weakref" {
        if positional.length() != 0 || keywords.length() != 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "weakref() takes no arguments".to_string(),
            ),
          )
        }
        return match get_named_value(inst.dict, "value") {
          Some(v) => Ok(v)
          None => Ok(Value::None)
        }
      }
      // Callable objects: obj(...) dispatches to obj.__call__(...)
      let call_attr = match lookup_class_attr(inst.class, "__call__") {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match call_attr {
        Some(_) => {
          // Reuse the regular attribute lookup path so we also get descriptor
          // behavior and method binding.
          let bound = match
            get_attr_raw_from_value(callee, "__call__", globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          call_callable_with_env(
            bound, positional, keywords, globals, builtins, io,
          )
        }
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              not_callable_message(callee),
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, not_callable_message(callee)),
      )
  }
}
