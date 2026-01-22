///|
/// Module-backed helpers (asyncio/_thread/_weakref/itertools/coroutine/code).

///|
fn builtin_mpython_run(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_run", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_run() takes exactly one argument".to_string(),
      ),
    )
  }
  coroutine_await(positional[0])
}

///|
fn builtin_mpython_asyncgenexp_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgenexp_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgenexp_next() takes exactly one argument".to_string(),
      ),
    )
  }
  async_genexp_next(positional[0])
}

///|
fn builtin_mpython_asyncgen_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_next() takes exactly one argument".to_string(),
      ),
    )
  }
  async_generator_next(positional[0])
}

///|
fn builtin_mpython_asyncgen_send(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_send", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_send() takes exactly two arguments".to_string(),
      ),
    )
  }
  async_generator_send(positional[0], positional[1])
}

///|
fn builtin_mpython_asyncgen_throw(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_throw", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_throw() takes exactly two arguments".to_string(),
      ),
    )
  }
  async_generator_throw(positional[0], positional[1])
}

///|
fn builtin_mpython_asyncgen_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("__mpython_asyncgen_close", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_asyncgen_close() takes exactly one argument".to_string(),
      ),
    )
  }
  async_generator_close(positional[0])
}

///|
fn builtin_asyncio_run(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("asyncio.run", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "asyncio.run() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "coroutine" {
        coroutine_await(positional[0])
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" +
            type_name_from_value(positional[0]) +
            "' object can't be used in 'await' expression",
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" +
          type_name_from_value(positional[0]) +
          "' object can't be used in 'await' expression",
        ),
      )
  }
}

///|
fn builtin_asyncio_gather(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  let _ = globals
  let _ = builtins
  let _ = io
  let _ = match ensure_no_keywords("asyncio.gather", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  for coro in positional {
    let value = match coro {
      Value::Instance(inst) =>
        if inst.class.name == "coroutine" {
          match coroutine_await(coro) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "'" +
              type_name_from_value(coro) +
              "' object can't be used in 'await' expression",
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" +
            type_name_from_value(coro) +
            "' object can't be used in 'await' expression",
          ),
        )
    }
    results.push(value)
  }
  Ok(Value::List(results))
}

///|
fn builtin_thread_get_ident(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.get_ident", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.get_ident() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(1N))
}

///|
fn builtin_thread_allocate_lock(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_thread.allocate_lock", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_thread.allocate_lock() takes no arguments".to_string(),
      ),
    )
  }
  let klass = thread_rlock_class(builtins)
  Ok(Value::Instance(InstanceValue::{ class: klass, dict: [] }))
}

///|
fn make_weakref_instance(
  value : Value,
  klass_opt : ClassValue?,
) -> Value {
  let hash = @bigint.BigInt::from_int64(hash_string(value_to_string(value)))
  let dict : Array[(String, Value)] = [
    ("value", value),
    ("hashvalue", Value::Int(hash)),
  ]
  let klass = match klass_opt {
    Some(value) => value
    None => ClassValue::{ name: "weakref", bases: [], dict: [] }
  }
  Value::Instance(InstanceValue::{ class: klass, dict })
}

///|
fn builtin_weakref_ref(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.ref", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut cls_opt : ClassValue? = None
  let mut start = 0
  if positional.length() > 0 {
    match positional[0] {
      Value::Class(klass) => {
        cls_opt = Some(klass)
        start = 1
      }
      _ => ()
    }
  }
  let remaining = positional.length() - start
  if remaining != 1 && remaining != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "ref() takes one or two arguments".to_string(),
      ),
    )
  }
  Ok(make_weakref_instance(positional[start], cls_opt))
}

///|
fn builtin_weakref_proxy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.proxy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "proxy() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(positional[0])
}

///|
fn builtin_weakref_getweakrefcount(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.getweakrefcount", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getweakrefcount() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::Int(0N))
}

///|
fn builtin_weakref_getweakrefs(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref.getweakrefs", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getweakrefs() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::List([]))
}

///|
fn builtin_weakref_remove_dead_weakref(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("_weakref._remove_dead_weakref", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_remove_dead_weakref() takes exactly two arguments".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Dict(pairs) => {
      let _ = match dict_delete_key(pairs, positional[1]) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "_remove_dead_weakref() argument must be dict".to_string(),
        ),
      )
  }
}

///|
fn builtin_weakref_hash(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("weakref.__hash__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__hash__() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      match get_named_value(inst.dict, "hashvalue") {
        Some(Value::Int(value)) => Ok(Value::Int(value))
        Some(_) | None => Ok(Value::Int(0N))
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "__hash__() expects a weakref instance".to_string(),
        ),
      )
  }
}
///|
fn builtin_code_replace(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if positional.length() == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "code.replace() missing code object".to_string(),
      ),
    )
  }
  let mut flags = 0N
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "code" {
        match get_named_value(inst.dict, "co_flags") {
          Some(Value::Int(v)) => flags = v
          Some(Value::Bool(v)) => flags = if v { 1N } else { 0N }
          _ => ()
        }
      }
    _ => ()
  }
  for kw in keywords {
    if kw.0 == "co_flags" {
      let value = match index_from_value(kw.1, 0) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      flags = @bigint.BigInt::from_int(value)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "code.replace() got an unexpected keyword '" + kw.0 + "'",
        ),
      )
    }
  }
  Ok(make_code_instance(flags))
}

///|
fn builtin_coroutine_close(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("coroutine.close", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "coroutine.close() takes exactly one argument".to_string(),
      ),
    )
  }
  Ok(Value::None)
}

///|
fn builtin_itertools_chain(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.chain", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items : Array[Value] = []
  for iter_value in positional {
    let values = match iterable_values(iter_value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    for item in values {
      items.push(item)
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_chain_from_iterable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.chain.from_iterable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "chain.from_iterable() takes exactly one argument".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let items : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        let values = match iterable_values(item) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        for value in values {
          items.push(value)
        }
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_accumulate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut initial_opt : Value? = None
  for pair in keywords {
    if pair.0 == "initial" {
      initial_opt = Some(pair.1)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "accumulate() got unexpected keyword arguments".to_string(),
        ),
      )
    }
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "accumulate() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let func_opt = if positional.length() == 2 { Some(positional[1]) } else { None }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  let mut acc_opt : Value? = initial_opt
  if acc_opt is None {
    if items.length() == 0 {
      return Ok(make_iterator(results))
    }
    acc_opt = Some(items[0])
    results.push(items[0])
  } else {
    results.push(acc_opt.unwrap())
  }
  let start = if initial_opt is Some(_) { 0 } else { 1 }
  for i = start; i < items.length(); i = i + 1 {
    let current = acc_opt.unwrap()
    let next = match func_opt {
      Some(func) =>
        match func {
          Value::None => {
            let (a_is_float, a_num) = match number_value(current) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let (b_is_float, b_num) = match number_value(items[i]) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            let sum = a_num + b_num
            if a_is_float || b_is_float {
              Value::Float(sum)
            } else {
              Value::Int(@bigint.BigInt::from_int64(sum.to_int64()))
            }
          }
          _ =>
            match call_callable_with_env(
              func,
              [current, items[i]],
              [],
              globals,
              builtins,
              io,
            ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
        }
      None => {
        let (a_is_float, a_num) = match number_value(current) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let (b_is_float, b_num) = match number_value(items[i]) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let sum = a_num + b_num
        if a_is_float || b_is_float {
          Value::Float(sum)
        } else {
          Value::Int(@bigint.BigInt::from_int64(sum.to_int64()))
        }
      }
    }
    acc_opt = Some(next)
    results.push(next)
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_groupby(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut key_fn_opt : Value? = None
  for pair in keywords {
    if pair.0 == "key" {
      key_fn_opt = Some(pair.1)
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "groupby() got unexpected keyword arguments".to_string(),
        ),
      )
    }
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "groupby() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  if positional.length() == 2 {
    if key_fn_opt is Some(_) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "groupby() got multiple values for argument 'key'".to_string(),
        ),
      )
    }
    key_fn_opt = Some(positional[1])
  }
  let items = match iterable_values(positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  let mut current_key_opt : Value? = None
  let mut current_items : Array[Value] = []
  for item in items {
    let key = match key_fn_opt {
      Some(func) =>
        match func {
          Value::None => item
          _ =>
            match call_callable_with_env(
              func,
              [item],
              [],
              globals,
              builtins,
              io,
            ) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
        }
      None => item
    }
    if current_key_opt is None {
      current_key_opt = Some(key)
      current_items.push(item)
    } else if eq_value(current_key_opt.unwrap(), key) {
      current_items.push(item)
    } else {
      results.push(
        Value::Tuple([
          current_key_opt.unwrap(),
          make_iterator(current_items),
        ]),
      )
      current_key_opt = Some(key)
      current_items = [item]
    }
  }
  if current_key_opt is Some(_) {
    results.push(
      Value::Tuple([
        current_key_opt.unwrap(),
        make_iterator(current_items),
      ]),
    )
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_repeat(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.repeat", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "repeat() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let value = positional[0]
  if positional.length() == 1 || positional[1] is Value::None {
    return Ok(make_repeat_iterator(value, None))
  }
  let times = match index_from_value(positional[1], 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = if times < 0 { 0 } else { times }
  Ok(make_repeat_iterator(value, Some(@bigint.BigInt::from_int(count))))
}

///|
fn builtin_itertools_starmap(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.starmap", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "starmap() takes exactly two arguments".to_string(),
      ),
    )
  }
  let func = positional[0]
  let iterator = match
    iter_value_to_iterator(positional[1], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let results : Array[Value] = []
  while true {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        let args = match item {
          Value::Tuple(values) => values
          Value::List(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "starmap() argument must yield tuples".to_string(),
              ),
            )
        }
        let value = match
          call_callable_with_env(func, args, [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        results.push(value)
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(results))
}

///|
fn builtin_itertools_count(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.count", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "count() takes at most two arguments".to_string(),
      ),
    )
  }
  let start_value = if positional.length() > 0 {
    match positional[0] {
      Value::Bool(v) =>
        Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
      Value::Int(_) | Value::Float(_) => positional[0]
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "count() start must be a number".to_string(),
          ),
        )
    }
  } else {
    Value::Int(0N)
  }
  let step_value = if positional.length() > 1 {
    match positional[1] {
      Value::Bool(v) =>
        Value::Int(@bigint.BigInt::from_int(if v { 1 } else { 0 }))
      Value::Int(_) | Value::Float(_) => positional[1]
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "count() step must be a number".to_string(),
          ),
        )
    }
  } else {
    Value::Int(1N)
  }
  Ok(make_count_iterator(start_value, step_value))
}
///|
fn builtin_itertools_islice(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.islice", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "islice() takes 2 to 4 arguments".to_string(),
      ),
    )
  }
  let iterator = match
    iter_value_to_iterator(positional[0], globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let start = if positional.length() >= 3 {
    match index_from_value(positional[1], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    0
  }
  let stop_value = if positional.length() >= 3 {
    positional[2]
  } else {
    positional[1]
  }
  let stop = match index_from_value(stop_value, 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let step = if positional.length() == 4 {
    match index_from_value(positional[3], 1) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  } else {
    1
  }
  if step <= 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: step must be positive".to_string(),
      ),
    )
  }
  let items : Array[Value] = []
  let mut idx = 0
  while idx < stop {
    match iterator_next(iterator, None, globals, builtins, io) {
      Ok(item) => {
        if idx >= start && ((idx - start) % step == 0) {
          items.push(item)
        }
        idx += 1
      }
      Err(err) =>
        if err.exc_type == "StopIteration" {
          break
        } else {
          return Err(err)
        }
    }
  }
  Ok(make_iterator(items))
}

///|
fn builtin_itertools_permutations(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("itertools.permutations", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "permutations() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let values = match positional[0] {
    Value::Str(text) => {
      let out : Array[Value] = []
      for ch in text.to_array() {
        let buf = StringBuilder::new()
        buf.write_char(ch)
        out.push(Value::Str(buf.to_string()))
      }
      out
    }
    Value::List(items) => items
    Value::Tuple(items) => items
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "permutations() expects a str or sequence".to_string(),
        ),
      )
  }
  let r = if positional.length() == 2 {
    match positional[1] {
      Value::Int(v) =>
        match bigint_to_int_checked(v) {
          Ok(value) => value
          Err(err) => return Err(err)
        }
      Value::Bool(v) => if v { 1 } else { 0 }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "permutations() r must be int".to_string(),
          ),
        )
    }
  } else {
    values.length()
  }
  if r < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: r must be non-negative".to_string(),
      ),
    )
  }
  if r > values.length() {
    return Ok(Value::List([]))
  }
  fn build_permutations(values : Array[Value], r : Int) -> Array[Value] {
    if r == 0 {
      return [Value::Tuple([])]
    }
    let out : Array[Value] = []
    for i = 0; i < values.length(); i = i + 1 {
      let first = values[i]
      let rest : Array[Value] = []
      for j = 0; j < values.length(); j = j + 1 {
        if j != i {
          rest.push(values[j])
        }
      }
      let tails = build_permutations(rest, r - 1)
      for tail in tails {
        match tail {
          Value::Tuple(items) => {
            let combined : Array[Value] = [first]
            for item in items {
              combined.push(item)
            }
            out.push(Value::Tuple(combined))
          }
          _ => ()
        }
      }
    }
    out
  }
  Ok(Value::List(build_permutations(values, r)))
}

///|
fn builtin_itertools_product(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let mut repeat = 1
  for item in keywords {
    if item.0 == "repeat" {
      match item.1 {
        Value::Int(v) =>
          match bigint_to_int_checked(v) {
            Ok(value) => repeat = value
            Err(err) => return Err(err)
          }
        Value::Bool(v) => repeat = if v { 1 } else { 0 }
        _ =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "product() repeat must be int".to_string(),
            ),
          )
      }
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "product() got unexpected keyword argument".to_string(),
        ),
      )
    }
  }
  if repeat < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: repeat must be non-negative".to_string(),
      ),
    )
  }
  if repeat == 0 || positional.length() == 0 {
    return Ok(Value::List([Value::Tuple([])]))
  }
  fn to_values(value : Value) -> Result[Array[Value], RuntimeError] {
    match value {
      Value::Str(text) => {
        let out : Array[Value] = []
        for ch in text.to_array() {
          let buf = StringBuilder::new()
          buf.write_char(ch)
          out.push(Value::Str(buf.to_string()))
        }
        Ok(out)
      }
      Value::List(items) => Ok(items)
      Value::Tuple(items) => Ok(items)
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "product() expects a str or sequence".to_string(),
          ),
        )
    }
  }
  let pools : Array[Array[Value]] = []
  for item in positional {
    let values = match to_values(item) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    pools.push(values)
  }
  let expanded : Array[Array[Value]] = []
  for pool in pools {
    for i = 0; i < repeat; i = i + 1 {
      expanded.push(pool)
    }
  }
  let mut results : Array[Value] = [Value::Tuple([])]
  for pool in expanded {
    let next : Array[Value] = []
    for item in results {
      match item {
        Value::Tuple(items) =>
          for value in pool {
            let combo : Array[Value] = []
            for v in items {
              combo.push(v)
            }
            combo.push(value)
            next.push(Value::Tuple(combo))
          }
        _ => ()
      }
    }
    results = next
  }
  Ok(Value::List(results))
}
