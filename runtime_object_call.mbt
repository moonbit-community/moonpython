///|
/// Callable dispatch and runtime call hooks.

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
            inst_dict.push(("hashvalue", Value::Int(fresh_object_hashvalue())))
            if class_includes_list(klass) {
              inst_dict.push((list_storage_name, Value::List([])))
            }
            if class_includes_dict(klass) {
              inst_dict.push((dict_storage_name, Value::Dict([])))
            }
            Ok(
              Value::Instance(InstanceValue::{ class: klass, dict: inst_dict }),
            )
          }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "__new__() expects a type".to_string(),
              ),
            )
        }
      } else if func.name == "__hash__" && func.body.length() == 0 {
        // Intrinsic: object.__hash__(self)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__hash__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__hash__() takes exactly one argument".to_string(),
            ),
          )
        }
        match hash_value(positional[0]) {
          Ok(hash) => Ok(Value::Int(hash))
          Err(err) => Err(err)
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
      // Intrinsic: object.__init_subclass__(cls, **kwargs)
      if bound_method.function.name == "__init_subclass__" &&
        bound_method.function.body.length() == 0 {
        if positional.length() != 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__init_subclass__() takes no arguments".to_string(),
            ),
          )
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
          } else if bound_method.function.body.length() == 0 &&
            get_named_value(inst.dict, list_storage_name) is Some(_) {
            // Support list subclasses: instances created via object.__new__ for a class
            // that includes `list` in its MRO store their backing array in `$__list__`.
            match get_named_value(inst.dict, list_storage_name) {
              Some(Value::List(values)) => {
                if keywords.length() > 0 && bound_method.function.name != "sort" {
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
                  _ => ()
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
              bound_method.function.name != "split" &&
              bound_method.function.name != "splitlines" &&
              bound_method.function.name != "format" {
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
                let prefixes : Array[String] = []
                match positional[0] {
                  Value::Str(value) => prefixes.push(value)
                  Value::Tuple(values) =>
                    for item in values {
                      match item {
                        Value::Str(value) => prefixes.push(value)
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "startswith() expects a str prefix".to_string(),
                            ),
                          )
                      }
                    }
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "startswith() expects a str prefix".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
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
                let mut matched = false
                for prefix in prefixes {
                  if segment.has_prefix(prefix) {
                    matched = true
                    break
                  }
                }
                return Ok(Value::Bool(matched))
              }
              "find" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "find() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "find() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
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
                if needle.length() == 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(start_idx)))
                }
                let max_start = end_idx - needle.length()
                let mut found = -1
                let mut i = start_idx
                while i <= max_start {
                  if substring(text, i, i + needle.length()) == needle {
                    found = i
                    break
                  }
                  i += 1
                }
                if found < 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(-1)))
                } else {
                  return Ok(Value::Int(@bigint.BigInt::from_int(found)))
                }
              }
              "rfind" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "rfind() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "rfind() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
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
                if needle.length() == 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(end_idx)))
                }
                if needle.length() > end_idx - start_idx {
                  return Ok(Value::Int(@bigint.BigInt::from_int(-1)))
                }
                let mut found = -1
                let mut i = end_idx - needle.length()
                while i >= start_idx {
                  if substring(text, i, i + needle.length()) == needle {
                    found = i
                    break
                  }
                  i -= 1
                }
                if found < 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(-1)))
                } else {
                  return Ok(Value::Int(@bigint.BigInt::from_int(found)))
                }
              }
              "encode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "encode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let bytes = match
                  encode_string_with_encoding(
                    "encode", text, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Bytes(bytes))
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
                let suffixes : Array[String] = []
                match positional[0] {
                  Value::Str(value) => suffixes.push(value)
                  Value::Tuple(values) =>
                    for item in values {
                      match item {
                        Value::Str(value) => suffixes.push(value)
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "endswith() expects a str suffix".to_string(),
                            ),
                          )
                      }
                    }
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "endswith() expects a str suffix".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
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
                let mut matched = false
                for suffix in suffixes {
                  if segment.has_suffix(suffix) {
                    matched = true
                    break
                  }
                }
                return Ok(Value::Bool(matched))
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
                      let tail = substring(
                        text,
                        pos + sep.length(),
                        text.length(),
                      )
                      return Ok(
                        Value::Tuple([
                          Value::Str(head),
                          Value::Str(sep),
                          Value::Str(tail),
                        ]),
                      )
                    }
                    None =>
                      return Ok(
                        Value::Tuple([
                          Value::Str(text),
                          Value::Str(""),
                          Value::Str(""),
                        ]),
                      )
                  }
                }
              "expandtabs" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "expandtabs() takes at most one argument".to_string(),
                    ),
                  )
                }
                let mut tabsize = 8
                if positional.length() == 1 {
                  match positional[0] {
                    Value::Int(v) => tabsize = v.to_int64().to_int()
                    Value::Bool(v) => tabsize = if v { 1 } else { 0 }
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "expandtabs() expects an int tabsize".to_string(),
                        ),
                      )
                  }
                }
                if tabsize < 0 {
                  tabsize = 0
                }
                let chars = text.to_array()
                let buf = StringBuilder::new()
                let mut col = 0
                for c in chars {
                  if c == '\t' {
                    if tabsize == 0 {
                      continue
                    }
                    let space_count = tabsize - col % tabsize
                    for _k = 0; _k < space_count; _k = _k + 1 {
                      buf.write_char(' ')
                    }
                    col += space_count
                  } else {
                    buf.write_char(c)
                    if c == '\n' || c == '\r' {
                      col = 0
                    } else {
                      col += 1
                    }
                  }
                }
                return Ok(Value::Str(buf.to_string()))
              }
              "translate" => {
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "translate() takes exactly one argument".to_string(),
                    ),
                  )
                }
                let table = match positional[0] {
                  Value::Dict(pairs) => pairs
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "translate() expects a dict table".to_string(),
                      ),
                    )
                }
                let chars = text.to_array()
                let buf = StringBuilder::new()
                for c in chars {
                  let code = c.to_int()
                  let idx = match
                    dict_find_index(
                      table,
                      Value::Int(@bigint.BigInt::from_int(code)),
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  match idx {
                    Some(pos) =>
                      match table[pos].1 {
                        Value::None => ()
                        Value::Str(rep) => buf.write_string(rep)
                        Value::Int(v) => {
                          let out_code = v.to_int64().to_int()
                          match out_code.to_char() {
                            Some(ch) => buf.write_char(ch)
                            None =>
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Runtime,
                                  "ValueError: invalid character in translate table".to_string(),
                                ),
                              )
                          }
                        }
                        Value::Bool(v) => {
                          let out_code = if v { 1 } else { 0 }
                          match out_code.to_char() {
                            Some(ch) => buf.write_char(ch)
                            None =>
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Runtime,
                                  "ValueError: invalid character in translate table".to_string(),
                                ),
                              )
                          }
                        }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "translate() table values must be int, str, or None".to_string(),
                            ),
                          )
                      }
                    None => buf.write_char(c)
                  }
                }
                return Ok(Value::Str(buf.to_string()))
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
              "lower" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "lower() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Str(text.to_lower()))
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
                  let limit = if count < 0 || count > total {
                    total
                  } else {
                    count
                  }
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
              "strip" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "strip() takes at most one argument".to_string(),
                    ),
                  )
                }
                let chars_opt = match
                  parse_strip_chars(
                    "strip",
                    if positional.length() == 1 {
                      Some(positional[0])
                    } else {
                      None
                    },
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(
                  Value::Str(strip_text(text, chars_opt, StripMode::Both)),
                )
              }
              "lstrip" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "lstrip() takes at most one argument".to_string(),
                    ),
                  )
                }
                let chars_opt = match
                  parse_strip_chars(
                    "lstrip",
                    if positional.length() == 1 {
                      Some(positional[0])
                    } else {
                      None
                    },
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(
                  Value::Str(strip_text(text, chars_opt, StripMode::Left)),
                )
              }
              "rstrip" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "rstrip() takes at most one argument".to_string(),
                    ),
                  )
                }
                let chars_opt = match
                  parse_strip_chars(
                    "rstrip",
                    if positional.length() == 1 {
                      Some(positional[0])
                    } else {
                      None
                    },
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(
                  Value::Str(strip_text(text, chars_opt, StripMode::Right)),
                )
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
                      return Ok(
                        Value::List([Value::Str(substring(text, i, end))]),
                      )
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
                          while tail_end > i &&
                                is_ascii_whitespace(chars[tail_end - 1]) {
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
              "splitlines" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "splitlines() takes at most 1 argument".to_string(),
                    ),
                  )
                }
                let mut keepends_value : Value? = None
                if positional.length() == 1 {
                  keepends_value = Some(positional[0])
                }
                for pair in keywords {
                  if pair.0 == "keepends" {
                    if keepends_value is Some(_) {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "splitlines() got multiple values for argument 'keepends'".to_string(),
                        ),
                      )
                    }
                    keepends_value = Some(pair.1)
                  } else {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "splitlines() got unexpected keyword argument '" +
                        pair.0 +
                        "'",
                      ),
                    )
                  }
                }
                let keepends = match keepends_value {
                  None => false
                  Some(Value::None) => false
                  Some(Value::Bool(value)) => value
                  Some(_) =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "splitlines() keepends must be bool".to_string(),
                      ),
                    )
                }
                let lines : Array[Value] = []
                let chars = text.to_array()
                let mut builder = StringBuilder::new()
                let mut has_text = false
                let mut i = 0
                while i < chars.length() {
                  let c = chars[i]
                  if c == '\n' || c == '\r' {
                    if keepends {
                      builder.write_char(c)
                      has_text = true
                    }
                    if c == '\r' &&
                      i + 1 < chars.length() &&
                      chars[i + 1] == '\n' {
                      if keepends {
                        builder.write_char('\n')
                        has_text = true
                      }
                      i += 1
                    }
                    lines.push(Value::Str(builder.to_string()))
                    builder = StringBuilder::new()
                    has_text = false
                  } else {
                    builder.write_char(c)
                    has_text = true
                  }
                  i += 1
                }
                if has_text {
                  lines.push(Value::Str(builder.to_string()))
                }
                return Ok(Value::List(lines))
              }
              "format" => {
                let formatted = match
                  format_string_with_args(text, positional, keywords) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(formatted))
              }
              _ => ()
            }
          }
        Value::List(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 && bound_method.function.name != "sort" {
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
              "copy" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let out : Array[Value] = []
                  for item in values {
                    out.push(item)
                  }
                  return Ok(Value::List(out))
                }
              "reverse" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "reverse() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if values.length() == 0 {
                    return Ok(Value::None)
                  }
                  let mut i = 0
                  let mut j = values.length() - 1
                  while i < j {
                    let tmp = values[i]
                    values[i] = values[j]
                    values[j] = tmp
                    i += 1
                    j -= 1
                  }
                  return Ok(Value::None)
                }
              "sort" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "sort() takes at most 2 arguments".to_string(),
                    ),
                  )
                }
                let mut reverse = false
                let mut key_value : Value? = None
                for pair in keywords {
                  if pair.0 == "key" {
                    key_value = Some(pair.1)
                  } else if pair.0 == "reverse" {
                    reverse = bool_from_value(pair.1)
                  } else {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "sort() got unexpected keyword arguments".to_string(),
                      ),
                    )
                  }
                }
                if positional.length() >= 1 {
                  if key_value is Some(_) {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "sort() got multiple values for argument 'key'".to_string(),
                      ),
                    )
                  }
                  key_value = Some(positional[0])
                }
                if positional.length() == 2 {
                  reverse = bool_from_value(positional[1])
                }
                if values.length() == 0 {
                  return Ok(Value::None)
                }
                fn lt_for_sort(
                  a : Value,
                  b : Value,
                  globals : Array[(String, Value)],
                  builtins : Array[(String, Value)],
                  io : MockIO,
                ) -> Result[Bool, RuntimeError] {
                  match (a, b) {
                    (Value::Str(x), Value::Str(y)) => Ok(x < y)
                    (Value::Int(_) | Value::Float(_) | Value::Bool(_), _)
                    | (_, Value::Int(_) | Value::Float(_) | Value::Bool(_)) => {
                      let (_, left_num) = match number_value(a) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      let (_, right_num) = match number_value(b) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      Ok(left_num < right_num)
                    }
                    _ => {
                      let lt = match
                        get_attr_from_value(a, "__lt__", globals, builtins, io) {
                        Ok(v) => v
                        Err(err) =>
                          match err.kind {
                            RuntimeErrorKind::Attribute =>
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Type,
                                  "sort() cannot compare values".to_string(),
                                ),
                              )
                            _ => return Err(err)
                          }
                      }
                      let result = match
                        call_callable_with_env(
                          lt,
                          [b],
                          [],
                          globals,
                          builtins,
                          io,
                        ) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      Ok(bool_from_value(result))
                    }
                  }
                }

                match key_value {
                  Some(key_fn) => {
                    let key_pairs : Array[(Value, Value)] = []
                    for item in values {
                      let key = if key_fn is Value::None {
                        item
                      } else {
                        match
                          call_callable_with_env(
                            key_fn,
                            [item],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      }
                      key_pairs.push((key, item))
                    }
                    fn insertion_sort_pairs_by_key(
                      pairs : Array[(Value, Value)],
                      globals : Array[(String, Value)],
                      builtins : Array[(String, Value)],
                      io : MockIO,
                    ) -> Result[Unit, RuntimeError] {
                      let mut i = 1
                      while i < pairs.length() {
                        let item = pairs[i]
                        let mut j = i
                        while j > 0 {
                          let less = match
                            lt_for_sort(
                              item.0,
                              pairs[j - 1].0,
                              globals,
                              builtins,
                              io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          if !less {
                            break
                          }
                          pairs[j] = pairs[j - 1]
                          j -= 1
                        }
                        pairs[j] = item
                        i += 1
                      }
                      Ok(())
                    }

                    let mut kind_opt : SortKind? = None
                    let mut can_use_fast = true
                    for pair in key_pairs {
                      match sort_kind_for_sorted(pair.0) {
                        Some(kind) =>
                          match kind_opt {
                            None => kind_opt = Some(kind)
                            Some(prev) =>
                              if prev != kind {
                                can_use_fast = false
                              }
                          }
                        None => can_use_fast = false
                      }
                    }
                    let sorted_pairs = if can_use_fast {
                      let kind = match kind_opt {
                        Some(kind) => kind
                        None => return Ok(Value::None)
                      }
                      match stable_sort_pairs_by_key(key_pairs, kind) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                    } else {
                      let _ = match
                        insertion_sort_pairs_by_key(
                          key_pairs, globals, builtins, io,
                        ) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      key_pairs
                    }
                    let sorted_items : Array[Value] = []
                    for pair in sorted_pairs {
                      sorted_items.push(pair.1)
                    }
                    let out = if reverse {
                      reverse_values(sorted_items)
                    } else {
                      sorted_items
                    }
                    replace_array_values(values, out)
                    return Ok(Value::None)
                  }
                  None => {
                    let mut kind_opt : SortKind? = None
                    let mut can_use_fast = true
                    for item in values {
                      match sort_kind_for_sorted(item) {
                        Some(kind) =>
                          match kind_opt {
                            None => kind_opt = Some(kind)
                            Some(prev) =>
                              if prev != kind {
                                can_use_fast = false
                              }
                          }
                        None => can_use_fast = false
                      }
                    }
                    let mut out = if can_use_fast {
                      let kind = match kind_opt {
                        Some(kind) => kind
                        None => return Ok(Value::None)
                      }
                      match stable_sort_for_sorted(values, kind) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                    } else {
                      let out : Array[Value] = []
                      for item in values {
                        out.push(item)
                      }
                      let mut i = 1
                      while i < out.length() {
                        let item = out[i]
                        let mut j = i
                        while j > 0 {
                          let less = match
                            lt_for_sort(item, out[j - 1], globals, builtins, io) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          if !less {
                            break
                          }
                          out[j] = out[j - 1]
                          j -= 1
                        }
                        out[j] = item
                        i += 1
                      }
                      out
                    }
                    if reverse {
                      out = reverse_values(out)
                    }
                    replace_array_values(values, out)
                    return Ok(Value::None)
                  }
                }
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
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
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
                    return Ok(Value::Int(@bigint.BigInt::from_int(i)))
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
              "copy" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                }
                let out_pairs : Array[(Value, Value)] = []
                for pair in pairs {
                  out_pairs.push(pair)
                }
                return Ok(Value::Dict(out_pairs))
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
                  let _ = match
                    dict_set_item(pairs, positional[0], positional[1]) {
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
                  return Ok(
                    Value::Int(@bigint.BigInt::from_int(pairs.length())),
                  )
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
              "copy" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let out : Array[Value] = []
                  for item in values {
                    out.push(item)
                  }
                  return Ok(Value::Set(out))
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
              "difference" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "difference() takes exactly one argument".to_string(),
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
                  let out : Array[Value] = []
                  for item in values {
                    let index = match set_find_index(other_values, item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    if index is None {
                      let _ = match set_add_unique(out, item) {
                        Ok(_) => ()
                        Err(err) => return Err(err)
                      }

                    }
                  }
                  return Ok(Value::Set(out))
                }
              "difference_update" => {
                // Remove all elements found in any of the provided iterables.
                if positional.length() == 0 {
                  return Ok(Value::None)
                }
                let remove_values : Array[Value] = []
                for arg in positional {
                  let iterator = match
                    iter_value_to_iterator(arg, globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(remove_values, item) {
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
                }
                let mut i = values.length()
                while i > 0 {
                  i = i - 1
                  let item = values[i]
                  let index = match set_find_index(remove_values, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if index is Some(_) {
                    let _ = values.remove(i)

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
                  return Ok(
                    Value::Int(@bigint.BigInt::from_int(values.length())),
                  )
                }
              _ => ()
            }
          }
        Value::Bytes(values) =>
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
              "decode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "decode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let text = match
                  decode_bytes_with_encoding(
                    "decode", values, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(text))
              }
              _ => ()
            }
          }
        Value::MemoryView(values) =>
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
              "decode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "decode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let text = match
                  decode_bytes_with_encoding(
                    "decode", values, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(text))
              }
              _ => ()
            }
          }
        Value::ByteArray(values) =>
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
              "decode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "decode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let text = match
                  decode_bytes_with_encoding(
                    "decode", values, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(text))
              }
              "copy" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let out : Array[Int] = []
                  for item in values {
                    out.push(item)
                  }
                  return Ok(Value::ByteArray(out))
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
      if bound_method.function.is_async {
        if bound_method.function.is_generator {
          return (eval_generator_with_kwargs_ref.val)(
            bound_method.function,
            args,
            keywords,
            globals,
            builtins,
            io,
          )
        }
        return (eval_function_with_kwargs_ref.val)(
          bound_method.function,
          args,
          keywords,
          globals,
          builtins,
          io,
        )
      }
      if bound_method.function.is_generator {
        return (eval_generator_with_kwargs_ref.val)(
          bound_method.function,
          args,
          keywords,
          globals,
          builtins,
          io,
        )
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
      let abstract_values_opt = match
        get_named_value(klass.dict, "__abstractmethods__") {
        Some(Value::Set(values)) => Some(values)
        Some(Value::Tuple(values)) => Some(values)
        _ => None
      }
      if abstract_values_opt is Some(values) {
        let names : Array[String] = []
        for item in values {
          match item {
            Value::Str(name) => names.push(name)
            _ => ()
          }
        }
        if names.length() > 0 {
          for i = 0; i < names.length(); i = i + 1 {
            let mut best = i
            for j = i + 1; j < names.length(); j = j + 1 {
              if cmp_string_for_sorted(names[j], names[best]) < 0 {
                best = j
              }
            }
            if best != i {
              let tmp = names[i]
              names[i] = names[best]
              names[best] = tmp
            }
          }
          let builder = StringBuilder::new()
          for i = 0; i < names.length(); i = i + 1 {
            if i > 0 {
              builder.write_string(", ")
            }
            builder.write_string("'" + names[i] + "'")
          }
          let label = if names.length() == 1 { "method" } else { "methods" }
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "class " +
              klass.name +
              " without an implementation for abstract " +
              label +
              " " +
              builder.to_string(),
            ),
          )
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
      // Minimal exception instance payload for any BaseException subclass.
      // This is relied upon by the CPython stdlib (e.g. abc/unittest) for custom
      // exception classes like `class CustomError(Exception): ...`.
      let ok = match is_base_exception_class(klass) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if ok {
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
