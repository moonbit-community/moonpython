///|
/// Attribute lookup, descriptors, and attribute mutation.

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
    Value::None =>
      if attr == "__doc__" {
        Ok(Value::Str("None"))
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Attribute,
            "'NoneType' object has no attribute '" + attr + "'",
          ),
        )
      }
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
    Value::Int(_) => {
      if attr == "bit_length" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "int.bit_length",
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
      if attr == "to_bytes" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "int.to_bytes",
              params: ["self", "length", "byteorder", "signed"],
              defaults: [Value::Bool(false)],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "__hash__" {
        return Ok(
          Value::Function(FunctionValue::{
            name: "__hash__",
            params: [],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
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
      if attr == "lower" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "lower",
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
      if attr == "strip" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "strip",
              params: ["self", "chars"],
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
      if attr == "lstrip" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "lstrip",
              params: ["self", "chars"],
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
      if attr == "rstrip" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "rstrip",
              params: ["self", "chars"],
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
      if attr == "format" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "format",
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
      if attr == "copy" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "copy",
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
          "'list' object has no attribute '" + attr + "'",
        ),
      )
    }
    Value::Dict(_) => {
      if attr == "fromkeys" {
        let dict_class = builtin_class_from_name("dict", builtins)
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "dict.fromkeys",
              params: ["cls", "iterable", "value"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: Value::Class(dict_class),
          }),
        )
      }
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
      if attr == "copy" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "copy",
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
      if attr == "copy" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "copy",
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
    Value::ByteArray(_) => {
      if attr == "copy" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "copy",
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
          "'bytearray' object has no attribute '" + attr + "'",
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
      } else if klass.name == "list" && attr == "copy" {
        Ok(
          Value::Function(FunctionValue::{
            name: "list.copy",
            params: ["self"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
      } else if klass.name == "dict" && attr == "copy" {
        Ok(
          Value::Function(FunctionValue::{
            name: "dict.copy",
            params: ["self"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
      } else if klass.name == "dict" && attr == "fromkeys" {
        Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "dict.fromkeys",
              params: ["cls", "iterable", "value"],
              defaults: [Value::None],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: Value::Class(klass),
          }),
        )
      } else if klass.name == "set" && attr == "copy" {
        Ok(
          Value::Function(FunctionValue::{
            name: "set.copy",
            params: ["self"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
      } else if klass.name == "bytearray" && attr == "copy" {
        Ok(
          Value::Function(FunctionValue::{
            name: "bytearray.copy",
            params: ["self"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
      } else if klass.name == "object" &&
        (attr == "__repr__" ||
         attr == "__str__" ||
         attr == "__format__" ||
         attr == "__reduce_ex__") {
        Ok(
          Value::Function(FunctionValue::{
            name: attr,
            params: ["self"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
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
      } else if klass.name == "int" && attr == "bit_length" {
        Ok(
          Value::Function(FunctionValue::{
            name: "int.bit_length",
            params: ["self"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
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
          Ok(None) => {
            let mut is_enum = false
            let mut member_type_value =
              Value::Class(builtin_class_from_name("object", builtins))
            match class_mro(klass) {
              Ok(mro) =>
                for cls in mro {
                  if cls.name == "Enum" ||
                     cls.name == "Flag" ||
                     cls.name == "IntFlag" ||
                     cls.name == "StrEnum" {
                    is_enum = true
                  }
                  if cls.name == "int" {
                    member_type_value = Value::Class(cls)
                  } else if cls.name == "str" {
                    member_type_value = Value::Class(cls)
                  }
                }
              Err(err) => return Err(err)
            }
            if is_enum {
              match attr {
                "_use_args_" => {
                  let value = Value::Bool(false)
                  set_named_value(klass.dict, attr, value)
                  return Ok(value)
                }
                "_member_names_" => {
                  let value = Value::List([])
                  set_named_value(klass.dict, attr, value)
                  return Ok(value)
                }
                "_member_map_" => {
                  let value = Value::Dict([])
                  set_named_value(klass.dict, attr, value)
                  return Ok(value)
                }
                "_value2member_map_" => {
                  let value = Value::Dict([])
                  set_named_value(klass.dict, attr, value)
                  return Ok(value)
                }
                "_unhashable_values_" => {
                  let value = Value::List([])
                  set_named_value(klass.dict, attr, value)
                  return Ok(value)
                }
                "_member_type_" => {
                  set_named_value(klass.dict, attr, member_type_value)
                  return Ok(member_type_value)
                }
                "_value_repr_" => {
                  let mut repr_value : Value? = None
                  for pair in builtins {
                    if pair.0 == "repr" {
                      repr_value = Some(pair.1)
                      break
                    }
                  }
                  let value = match repr_value {
                    Some(v) => v
                    None =>
                      Value::Function(FunctionValue::{
                        name: "repr",
                        params: ["obj"],
                        defaults: [],
                        body: [],
                        is_generator: false,
                        is_async: false,
                        closure: [],
                      })
                  }
                  set_named_value(klass.dict, attr, value)
                  return Ok(value)
                }
                _ => ()
              }
            }
            if attr == "__repr__" ||
               attr == "__str__" ||
               attr == "__format__" ||
               attr == "__reduce_ex__" {
              return Ok(
                Value::Function(FunctionValue::{
                  name: attr,
                  params: ["self"],
                  defaults: [],
                  body: [],
                  is_generator: false,
                  is_async: false,
                  closure: [],
                }),
              )
            }
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
