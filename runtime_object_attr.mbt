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
fn class_has_base_name(klass : ClassValue, name : String) -> Bool {
  match class_mro(klass) {
    Ok(mro) => {
      for cls in mro {
        if cls.name == name {
          return true
        }
      }
      false
    }
    Err(_) => false
  }
}

///|
fn truthy_from_value_with_env(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  match value {
    Value::Instance(_) => {
      // __bool__()
      match get_attr_from_value(value, "__bool__", globals, builtins, io) {
        Ok(callable) => {
          let result = match
            call_callable_with_env(callable, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match result {
            Value::Bool(v) => return Ok(v)
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__bool__ should return bool".to_string(),
                ),
              )
          }
        }
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute => ()
            _ => return Err(err)
          }
      }

      // __len__()
      match get_attr_from_value(value, "__len__", globals, builtins, io) {
        Ok(callable) => {
          let result = match
            call_callable_with_env(callable, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let n = match result {
            Value::Int(v) => v
            Value::Bool(v) => @bigint.BigInt::from_int(if v { 1 } else { 0 })
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__len__ should return int".to_string(),
                ),
              )
          }
          if n < 0N {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ValueError: __len__() should return >= 0".to_string(),
              ),
            )
          }
          return Ok(n != 0N)
        }
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute => ()
            _ => return Err(err)
          }
      }
      Ok(true)
    }
    _ => Ok(bool_from_value(value))
  }
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
        if class_has_base_name(inst.class, "property") {
          match get_named_value(inst.dict, "fget") {
            Some(fget) =>
              match obj {
                Value::None => return Ok(Some(class_attr))
                _ => {
                  if fget is Value::None {
                    let owner_name = match owner {
                      Value::Class(klass) =>
                        match get_named_value(klass.dict, "__qualname__") {
                          Some(Value::Str(text)) => text
                          _ => klass.name
                        }
                      _ => type_name_from_value(owner)
                    }
                    let property_name = match class_attr {
                      Value::Instance(prop_inst) =>
                        match get_named_value(prop_inst.dict, "__name__") {
                          Some(Value::Str(text)) => Some(text)
                          _ => None
                        }
                      _ => None
                    }
                    let msg = match property_name {
                      Some(prop) =>
                        "property '" +
                        prop +
                        "' of '" +
                        owner_name +
                        "' object has no getter"
                      None =>
                        "property of '" + owner_name + "' object has no getter"
                    }
                    return Err(
                      make_runtime_error(RuntimeErrorKind::Attribute, msg),
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
        if class_has_base_name(inst.class, "staticmethod") {
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
        if class_has_base_name(inst.class, "classmethod") {
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
          call_callable_with_env(
            Value::Function(get_fn),
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

  if attr == "__class__" {
    match target {
      Value::Instance(inst) => return Ok(Value::Class(inst.class))
      Value::Class(klass) =>
        match get_named_value(klass.dict, "__mpython_metaclass__") {
          Some(Value::Class(meta)) => return Ok(Value::Class(meta))
          _ => ()
        }
      _ =>
        return Ok(
          Value::Class(
            builtin_class_from_name(type_name_from_value(target), builtins),
          ),
        )
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
      if inst.class.name == "module" && attr == "__dict__" {
        // `module.__dict__` must be a live mapping so stdlib helpers like
        // `sys.modules[mod].__dict__.update(...)` can mutate module globals.
        return Ok(make_module_globals_dict_instance(inst.dict))
      }
      if attr == "__dict__" {
        let pairs : Array[(Value, Value)] = []
        for item in inst.dict {
          pairs.push((Value::Str(item.0), item.1))
        }
        return Ok(Value::Dict(pairs))
      }
      let direct = get_named_value(inst.dict, attr)
      if direct is Some(value) {
        return Ok(value)
      }
      if inst.class.name == "module" {
        // PEP 562: if a module defines `__getattr__`, use it to resolve missing
        // attributes (e.g. unittest's lazy IsolatedAsyncioTestCase import).
        match get_named_value(inst.dict, "__getattr__") {
          Some(getter) =>
            match
              call_callable_with_env(
                getter,
                [Value::Str(attr)],
                [],
                inst.dict,
                builtins,
                io,
              ) {
              Ok(v) => return Ok(v)
              Err(err) => return Err(err)
            }
          None => ()
        }
      }
      fn abstract_flag_from_value(value : Value) -> Result[Bool, RuntimeError] {
        match value {
          Value::Function(func) => {
            let pairs = function_attr_dict(func)
            let idx = match
              dict_find_index(pairs, Value::Str("__isabstractmethod__")) {
              Ok(v) => v
              Err(_) => None
            }
            match idx {
              Some(i) =>
                truthy_from_value_with_env(pairs[i].1, globals, builtins, io)
              None => Ok(false)
            }
          }
          Value::Instance(inner) =>
            if inner.class.name == "classmethod" ||
              inner.class.name == "staticmethod" {
              match get_named_value(inner.dict, "func") {
                Some(func_value) => abstract_flag_from_value(func_value)
                None => Ok(false)
              }
            } else {
              Ok(false)
            }
          _ => Ok(false)
        }
      }

      if class_has_base_name(inst.class, "property") && attr == "__doc__" {
        match get_named_value(inst.dict, "doc") {
          Some(Value::None) | None =>
            match get_named_value(inst.dict, "fget") {
              Some(fget) =>
                match
                  get_attr_from_value(fget, "__doc__", globals, builtins, io) {
                  Ok(v) => return Ok(v)
                  Err(err) =>
                    match err.kind {
                      RuntimeErrorKind::Attribute => return Ok(Value::None)
                      _ => return Err(err)
                    }
                }
              None => return Ok(Value::None)
            }
          Some(value) => return Ok(value)
        }
      }
      if attr == "__isabstractmethod__" {
        if class_has_base_name(inst.class, "property") {
          let mut is_abstract = false
          match get_named_value(inst.dict, "fget") {
            Some(value) =>
              match abstract_flag_from_value(value) {
                Ok(true) => is_abstract = true
                Ok(false) => ()
                Err(err) => return Err(err)
              }
            None => ()
          }
          if !is_abstract {
            match get_named_value(inst.dict, "fset") {
              Some(value) =>
                match abstract_flag_from_value(value) {
                  Ok(true) => is_abstract = true
                  Ok(false) => ()
                  Err(err) => return Err(err)
                }
              None => ()
            }
          }
          if !is_abstract {
            match get_named_value(inst.dict, "fdel") {
              Some(value) =>
                match abstract_flag_from_value(value) {
                  Ok(true) => is_abstract = true
                  Ok(false) => ()
                  Err(err) => return Err(err)
                }
              None => ()
            }
          }
          if !is_abstract {
            match lookup_class_attr(inst.class, "__isabstractmethod__") {
              Ok(Some(value)) =>
                match truthy_from_value_with_env(value, globals, builtins, io) {
                  Ok(true) => is_abstract = true
                  Ok(false) => ()
                  Err(err) => return Err(err)
                }
              Ok(None) => ()
              Err(err) => return Err(err)
            }
          }
          return Ok(Value::Bool(is_abstract))
        }
        if class_has_base_name(inst.class, "classmethod") ||
          class_has_base_name(inst.class, "staticmethod") {
          match get_named_value(inst.dict, "func") {
            Some(func_value) =>
              match abstract_flag_from_value(func_value) {
                Ok(v) => return Ok(Value::Bool(v))
                Err(err) => return Err(err)
              }
            None => return Ok(Value::Bool(false))
          }
        }
      }
      if class_has_base_name(inst.class, "classmethod") ||
        class_has_base_name(inst.class, "staticmethod") {
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
      if inst.class.name == "frame" && attr == "clear" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "frame.clear",
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
                  // Bind like normal instance access.
                  // For class objects, only bind __init_subclass__ so it can be
                  // called as `super().__init_subclass__(...)` without passing
                  // `cls` explicitly (matches CPython behavior).
                  match self_value {
                    Value::Instance(_) =>
                      return Ok(
                        Value::BoundMethod(BoundMethodValue::{
                          function: func,
                          self: self_value,
                        }),
                      )
                    Value::Class(_) =>
                      if attr == "__init_subclass__" {
                        return Ok(
                          Value::BoundMethod(BoundMethodValue::{
                            function: func,
                            self: self_value,
                          }),
                        )
                      }
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
      // Provide list methods on list subclasses (instances storing `$__list__`).
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(_)) =>
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
                self: Value::Instance(inst),
              }),
            )
          } else if attr == "remove" {
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
                self: Value::Instance(inst),
              }),
            )
          } else if attr == "reverse" {
            return Ok(
              Value::BoundMethod(BoundMethodValue::{
                function: FunctionValue::{
                  name: "reverse",
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
        _ => ()
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
    Value::BoundMethod(bound_method) => {
      if attr == "__func__" {
        return Ok(Value::Function(bound_method.function))
      }
      if attr == "__self__" {
        return Ok(bound_method.self)
      }
      get_attr_raw_from_value(
        Value::Function(bound_method.function),
        attr,
        globals,
        builtins,
        io,
      )
    }
    Value::Bool(v) => {
      // bool is a subclass of int in CPython; expose the handful of numeric
      // attributes/methods relied upon by the stdlib `numbers` ABCs.
      let as_int = Value::Int(if v { 1N } else { 0N })
      match attr {
        "real" | "numerator" => return Ok(as_int)
        "imag" => return Ok(Value::Int(0N))
        "denominator" => return Ok(Value::Int(1N))
        "conjugate" =>
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "int.conjugate",
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
        _ => ()
      }
      // Delegate to int attribute handling for methods like `bit_length`.
      get_attr_raw_from_value(as_int, attr, globals, builtins, io)
    }
    Value::Int(_) => {
      match attr {
        "real" | "numerator" => return Ok(target)
        "imag" => return Ok(Value::Int(0N))
        "denominator" => return Ok(Value::Int(1N))
        "conjugate" =>
          return Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "int.conjugate",
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
        _ => ()
      }
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
      if attr == "__index__" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "int.__index__",
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
          "'" +
          type_name_from_value(target) +
          "' object has no attribute '" +
          attr +
          "'",
        ),
      )
    }
    Value::Float(value) =>
      match attr {
        "real" => Ok(Value::Float(value))
        // CPython returns `0.0`; equality with `0` still holds in stdlib tests.
        "imag" => Ok(Value::Float(0.0))
        "conjugate" =>
          Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "float.conjugate",
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
    Value::Complex(real, imag) =>
      match attr {
        "real" => Ok(Value::Float(real))
        "imag" => Ok(Value::Float(imag))
        "conjugate" =>
          Ok(
            Value::BoundMethod(BoundMethodValue::{
              function: FunctionValue::{
                name: "complex.conjugate",
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
      if attr == "columns" {
        match target {
          Value::Tuple(values) =>
            if values.length() >= 1 {
              return Ok(values[0])
            }
          _ => ()
        }
      }
      if attr == "lines" {
        match target {
          Value::Tuple(values) =>
            if values.length() >= 2 {
              return Ok(values[1])
            }
          _ => ()
        }
      }
      return Err(
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
      if attr == "find" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "find",
              params: ["self", "sub", "start", "end"],
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
      if attr == "rfind" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "rfind",
              params: ["self", "sub", "start", "end"],
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
      if attr == "isalnum" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "isalnum",
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
      if attr == "isalpha" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "isalpha",
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
      if attr == "isspace" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "isspace",
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
      if attr == "rpartition" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "rpartition",
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
      if attr == "expandtabs" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "expandtabs",
              params: ["self", "tabsize"],
              defaults: [Value::Int(8N)],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
      if attr == "translate" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "translate",
              params: ["self", "table"],
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
      if attr == "splitlines" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "splitlines",
              params: ["self", "keepends"],
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
      if attr == "removeprefix" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "removeprefix",
              params: ["self", "prefix"],
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
      if attr == "removesuffix" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "removesuffix",
              params: ["self", "suffix"],
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
      if attr == "encode" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "encode",
              params: ["self", "encoding", "errors"],
              defaults: [Value::Str("utf-8"), Value::Str("strict")],
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
    Value::Bytes(_) | Value::MemoryView(_) => {
      if attr == "decode" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "decode",
              params: ["self", "encoding", "errors"],
              defaults: [Value::Str("utf-8"), Value::Str("strict")],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: target,
          }),
        )
      }
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
      if attr == "translate" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "bytes.translate",
              params: ["self", "table"],
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
          "'" +
          type_name_from_value(target) +
          "' object has no attribute '" +
          attr +
          "'",
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
      if attr == "reverse" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "reverse",
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
      if attr == "sort" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "sort",
              params: ["self", "key", "reverse"],
              defaults: [Value::None, Value::Bool(false)],
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
      if attr == "popitem" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "popitem",
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
      if attr == "difference" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "difference",
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
      if attr == "difference_update" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "difference_update",
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
      Err(
        make_runtime_error(
          RuntimeErrorKind::Attribute,
          "'set' object has no attribute '" + attr + "'",
        ),
      )
    }
    Value::ByteArray(_) => {
      if attr == "decode" {
        return Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "decode",
              params: ["self", "encoding", "errors"],
              defaults: [Value::Str("utf-8"), Value::Str("strict")],
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
          let mut co_filename = "<module>".to_string()
          if func.body.length() == 0 {
            co_filename = "<builtins>".to_string()
          } else {
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
            match get_named_value(env, "__file__") {
              Some(Value::Str(text)) => co_filename = text
              _ => ()
            }
          }
          let mut flags = 0N
          if func.is_generator {
            if func.is_async {
              flags = flags + 512N // CO_ASYNC_GENERATOR
            } else {
              flags = flags + 32N // CO_GENERATOR
            }
          } else if func.is_async {
            flags = flags + 128N // CO_COROUTINE
          }
          Ok(make_code_instance_with_meta(flags, co_filename, func.name, 1N))
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
          fn unwrap_stmt(node : Stmt) -> Stmt {
            match node {
              Stmt::WithSpan(span~, stmt~) => {
                let _ = span
                unwrap_stmt(stmt)
              }
              other => other
            }
          }

          if func.body.length() > 0 {
            match unwrap_stmt(func.body[0]) {
              Stmt::ExprStmt(Expr::Literal(Literal::Str(text))) =>
                Ok(Value::Str(text))
              _ => Ok(Value::None)
            }
          } else {
            Ok(Value::None)
          }
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
      } else if attr == "__module__" {
        match get_named_value(klass.dict, "__module__") {
          Some(v) => Ok(v)
          None => Ok(Value::Str("builtins"))
        }
      } else if attr == "__subclasses__" {
        Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "__subclasses__",
              params: ["self"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: Value::Class(klass),
          }),
        )
      } else if attr == "__flags__" {
        // CPython exposes internal type flags on most type objects.
        // The stdlib uses TPFLAGS_IS_ABSTRACT (1<<20) via inspect.isabstract().
        // Provide that bit based on __abstractmethods__.
        let mut is_abstract = false
        match lookup_class_attr(klass, "__abstractmethods__") {
          Ok(Some(Value::Set(items))) =>
            if items.length() > 0 {
              is_abstract = true
            }
          Ok(Some(Value::Tuple(items))) =>
            if items.length() > 0 {
              is_abstract = true
            }
          Ok(Some(Value::List(items))) =>
            if items.length() > 0 {
              is_abstract = true
            }
          Ok(Some(_)) => ()
          Ok(None) => ()
          Err(err) => return Err(err)
        }
        Ok(Value::Int(if is_abstract { 1048576N } else { 0N }))
      } else if attr == "__doc__" {
        Ok(Value::None)
      } else if attr == "__bases__" {
        let bases : Array[Value] = []
        for base in klass.bases {
          bases.push(base)
        }
        Ok(Value::Tuple(bases))
      } else if attr == "__new__" && klass.name == "type" {
        Ok(
          Value::Function(FunctionValue::{
            name: "type.__new__",
            params: ["cls", "name", "bases", "dict"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
      } else if attr == "__dict__" {
        let pairs : Array[(Value, Value)] = []
        for item in klass.dict {
          pairs.push((Value::Str(item.0), item.1))
        }
        Ok(Value::Dict(pairs))
      } else if klass.name == "code" && attr == "__init__" {
        // Introspection-only stub so stdlib utilities (e.g. unittest.mock)
        // can access `types.CodeType.__init__`.
        Ok(
          Value::Function(FunctionValue::{
            name: "code.__init__",
            params: ["self", "*args", "**kwargs"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
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
      } else if klass.name == "list" && attr == "append" {
        // Expose `list.append` as a best-effort descriptor-like stub so pure
        // Python stdlib modules (e.g. multiprocessing.reduction) can introspect
        // it via `type(list.append)`.
        Ok(
          Value::Function(FunctionValue::{
            name: "list.append",
            params: ["self", "object"],
            defaults: [],
            body: [],
            is_generator: false,
            is_async: false,
            closure: [],
          }),
        )
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
      } else if klass.name == "int" && attr == "__add__" {
        // Similar to `list.append`, provide an introspection stub for
        // `int.__add__` used by the stdlib pickling machinery.
        Ok(
          Value::Function(FunctionValue::{
            name: "int.__add__",
            params: ["self", "other"],
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
      } else if klass.name == "bytes" && attr == "fromhex" {
        Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "bytes.fromhex",
              params: ["cls", "string"],
              defaults: [],
              body: [],
              is_generator: false,
              is_async: false,
              closure: [],
            },
            self: Value::Class(klass),
          }),
        )
      } else if klass.name == "bytearray" && attr == "fromhex" {
        Ok(
          Value::BoundMethod(BoundMethodValue::{
            function: FunctionValue::{
              name: "bytearray.fromhex",
              params: ["cls", "string"],
              defaults: [],
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
        (
          attr == "__repr__" ||
          attr == "__str__" ||
          attr == "__format__" ||
          attr == "__reduce_ex__"
        ) {
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
          Ok(Some(Value::Function(func))) =>
            if attr == "__init_subclass__" || attr == "__class_getitem__" {
              // PEP 487 / PEP 560: these are implicitly class methods on the class object.
              Ok(
                Value::BoundMethod(BoundMethodValue::{
                  function: func,
                  self: Value::Class(klass),
                }),
              )
            } else {
              Ok(Value::Function(func))
            }
          Ok(Some(value)) =>
            match apply_descriptor(value, Value::None, Value::Class(klass)) {
              Ok(Some(v)) => Ok(v)
              Ok(None) => Ok(value)
              Err(err) => Err(err)
            }
          Ok(None) => {
            let mut is_enum = false
            let mut member_type_value = Value::Class(
              builtin_class_from_name("object", builtins),
            )
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
        if class_has_base_name(inst.class, "property") {
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
        if class_has_base_name(inst.class, "property") {
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
