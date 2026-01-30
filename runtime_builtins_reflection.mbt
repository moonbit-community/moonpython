///|
/// Reflection/object-model builtins (iter/next/property/bool/repr/callable/type/etc).

///|
let abc_cache_token_ref : Ref[@bigint.BigInt] = { val: 0N }

///|
fn builtin_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("iter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "iter() takes exactly one argument".to_string(),
      ),
    )
  }
  let _ = locals
  iter_value_to_iterator(positional[0], globals, builtins, io)
}

///|
fn builtin_next(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("next", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 || positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "next() takes 1 or 2 arguments".to_string(),
      ),
    )
  }
  let default_value : Value? = if positional.length() == 2 {
    Some(positional[1])
  } else {
    None
  }
  let _ = locals
  iterator_next(positional[0], default_value, globals, builtins, io)
}

///|
fn builtin_sys_exc_info(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.exc_info", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "exc_info() takes no arguments".to_string(),
      ),
    )
  }
  match active_exception() {
    None => Ok(Value::Tuple([Value::None, Value::None, Value::None]))
    Some(err) => {
      let exc_value = exception_value_from_runtime_error(
        err, globals, builtins, io,
      )
      let exc_type_value = match exc_value {
        Value::Instance(inst) => Value::Class(inst.class)
        _ => Value::Str(err.exc_type)
      }
      let tb_value = make_traceback_value(err.traceback)
      Ok(Value::Tuple([exc_type_value, exc_value, tb_value]))
    }
  }
}

///|
fn builtin_sys_exception(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.exception", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "exception() takes no arguments".to_string(),
      ),
    )
  }
  match active_exception() {
    None => Ok(Value::None)
    Some(err) =>
      Ok(exception_value_from_runtime_error(err, globals, builtins, io))
  }
}

///|
fn builtin_sys_getframe(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys._getframe", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "_getframe() takes 0 or 1 arguments".to_string(),
      ),
    )
  }
  let mut depth = 0
  if positional.length() == 1 {
    depth = match index_from_value(positional[0], 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  if depth < 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: call stack is not deep enough".to_string(),
      ),
    )
  }
  let frames = snapshot_traceback()
  if depth >= frames.length() {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: call stack is not deep enough".to_string(),
      ),
    )
  }
  let idx = frames.length() - 1 - depth
  let mut frame_value = make_frame_value(frames[idx])
  match frame_value {
    Value::Instance(inst) => {
      set_named_value(
        inst.dict,
        "f_globals",
        make_module_globals_dict_instance(globals),
      )
      // Best-effort f_back chain.
      if idx > 0 {
        set_named_value(inst.dict, "f_back", make_frame_value(frames[idx - 1]))
      }
      frame_value = Value::Instance(inst)
    }
    _ => ()
  }
  Ok(frame_value)
}

///|
fn bigint_to_base_string(
  value_in : @bigint.BigInt,
  base : Int,
  prefix : String,
) -> String {
  // NOTE: BigInt already provides `to_string()` for decimal.
  // For non-decimal, we implement a simple base conversion using div/mod.
  if value_in == 0N {
    return prefix + "0"
  }
  let digits = if base == 2 {
    "01"
  } else if base == 8 {
    "01234567"
  } else {
    "0123456789abcdef"
  }
  let mut value = value_in
  let mut sign = ""
  if value < 0N {
    sign = "-"
    value = -value
  }
  let b = @bigint.BigInt::from_int(base)
  let chars : Array[Char] = []
  let mut n = value
  while n > 0N {
    let d = (n % b).to_int()
    chars.push(digits.to_array()[d])
    n = n / b
  }
  let buf = StringBuilder::new()
  buf.write_string(sign)
  buf.write_string(prefix)
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(chars[i])
    if i == 0 {
      break
    }
  }
  buf.to_string()
}

///|
fn escape_string_for_repr(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text.to_array() {
    if ch == '\\' {
      buf.write_string("\\\\")
    } else if ch == '\'' {
      buf.write_string("\\'")
    } else if ch == '"' {
      buf.write_string("\\\"")
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else if ch == '\r' {
      buf.write_string("\\r")
    } else if ch == '\t' {
      buf.write_string("\\t")
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn repr_fallback(value : Value) -> String {
  fn write_joined(
    buf : StringBuilder,
    values : Array[Value],
    prefix : String,
    suffix : String,
    comma_for_single : Bool,
  ) -> Unit {
    buf.write_string(prefix)
    for i = 0; i < values.length(); i = i + 1 {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(repr_fallback(values[i]))
    }
    if comma_for_single && values.length() == 1 {
      buf.write_char(',')
    }
    buf.write_string(suffix)
  }

  match value {
    Value::Str(text) => "'" + escape_string_for_repr(text) + "'"
    Value::Bytes(values) => bytes_repr(values)
    Value::ByteArray(values) => "bytearray(" + bytes_repr(values) + ")"
    Value::MemoryView(values) => "memoryview(" + bytes_repr(values) + ")"
    Value::List(values) => {
      let buf = StringBuilder::new()
      write_joined(buf, values, "[", "]", false)
      buf.to_string()
    }
    Value::Tuple(values) => {
      let buf = StringBuilder::new()
      write_joined(buf, values, "(", ")", true)
      buf.to_string()
    }
    Value::Dict(pairs) => {
      let buf = StringBuilder::new()
      buf.write_char('{')
      for i = 0; i < pairs.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        buf.write_string(repr_fallback(pairs[i].0))
        buf.write_string(": ")
        buf.write_string(repr_fallback(pairs[i].1))
      }
      buf.write_char('}')
      buf.to_string()
    }
    Value::Set(values) =>
      if values.length() == 0 {
        "set()"
      } else {
        let buf = StringBuilder::new()
        write_joined(buf, values, "{", "}", false)
        buf.to_string()
      }
    Value::Instance(inst) =>
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(values)) => repr_fallback(Value::List(values))
        _ =>
          match get_named_value(inst.dict, tuple_storage_name) {
            Some(Value::Tuple(values)) => repr_fallback(Value::Tuple(values))
            _ => value_to_string(value)
          }
      }
    _ => value_to_string(value)
  }
}

///|
fn make_property_instance(
  klass : ClassValue,
  fget : Value,
  fset : Value,
  fdel : Value,
  doc : Value,
) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("fget", fget))
  dict.push(("fset", fset))
  dict.push(("fdel", fdel))
  dict.push(("doc", doc))
  Value::Instance(InstanceValue::{ class: klass, dict })
}

///|

///|
fn builtin_property(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  if positional.length() > 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "property() takes at most 4 arguments".to_string(),
      ),
    )
  }
  let mut fget = if positional.length() >= 1 {
    positional[0]
  } else {
    Value::None
  }
  let mut fset = if positional.length() >= 2 {
    positional[1]
  } else {
    Value::None
  }
  let mut fdel = if positional.length() >= 3 {
    positional[2]
  } else {
    Value::None
  }
  let mut doc = if positional.length() >= 4 {
    positional[3]
  } else {
    Value::None
  }
  let mut has_fget = positional.length() >= 1
  let mut has_fset = positional.length() >= 2
  let mut has_fdel = positional.length() >= 3
  let mut has_doc = positional.length() >= 4
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "fget" =>
        if has_fget {
          return Err(multiple_values_error("property", "fget"))
        } else {
          fget = value
          has_fget = true
        }
      "fset" =>
        if has_fset {
          return Err(multiple_values_error("property", "fset"))
        } else {
          fset = value
          has_fset = true
        }
      "fdel" =>
        if has_fdel {
          return Err(multiple_values_error("property", "fdel"))
        } else {
          fdel = value
          has_fdel = true
        }
      "doc" =>
        if has_doc {
          return Err(multiple_values_error("property", "doc"))
        } else {
          doc = value
          has_doc = true
        }
      _ => return Err(unexpected_keyword_argument_error("property", key))
    }
  }
  if doc is Value::None && !(fget is Value::None) {
    match get_attr_from_value(fget, "__doc__", globals, builtins, io) {
      Ok(value) => doc = value
      Err(err) =>
        match err.kind {
          RuntimeErrorKind::Attribute => ()
          _ => return Err(err)
        }
    }
  }
  Ok(
    make_property_instance(
      builtin_class_from_name("property", builtins),
      fget,
      fset,
      fdel,
      doc,
    ),
  )
}

///|
fn builtin_property_init(
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
  if positional.length() < 1 || positional.length() > 5 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "property.__init__() takes from 1 to 5 positional arguments".to_string(),
      ),
    )
  }
  let target = positional[0]
  let mut fget = if positional.length() >= 2 {
    positional[1]
  } else {
    Value::None
  }
  let mut fset = if positional.length() >= 3 {
    positional[2]
  } else {
    Value::None
  }
  let mut fdel = if positional.length() >= 4 {
    positional[3]
  } else {
    Value::None
  }
  let mut doc = if positional.length() >= 5 {
    positional[4]
  } else {
    Value::None
  }
  let mut has_fget = positional.length() >= 2
  let mut has_fset = positional.length() >= 3
  let mut has_fdel = positional.length() >= 4
  let mut has_doc = positional.length() >= 5
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "fget" =>
        if has_fget {
          return Err(multiple_values_error("property.__init__", "fget"))
        } else {
          fget = value
          has_fget = true
        }
      "fset" =>
        if has_fset {
          return Err(multiple_values_error("property.__init__", "fset"))
        } else {
          fset = value
          has_fset = true
        }
      "fdel" =>
        if has_fdel {
          return Err(multiple_values_error("property.__init__", "fdel"))
        } else {
          fdel = value
          has_fdel = true
        }
      "doc" =>
        if has_doc {
          return Err(multiple_values_error("property.__init__", "doc"))
        } else {
          doc = value
          has_doc = true
        }
      _ =>
        return Err(unexpected_keyword_argument_error("property.__init__", key))
    }
  }
  match target {
    Value::Instance(inst) => {
      set_named_value(inst.dict, "fget", fget)
      set_named_value(inst.dict, "fset", fset)
      set_named_value(inst.dict, "fdel", fdel)
      set_named_value(inst.dict, "doc", doc)
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "property.__init__() expects a property instance".to_string(),
        ),
      )
  }
}

///|
fn builtin_property_getter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("property.getter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getter() takes exactly two arguments".to_string(),
      ),
    )
  }
  let prop = positional[0]
  let fget = positional[1]
  match prop {
    Value::Instance(inst) => {
      let fset = match get_named_value(inst.dict, "fset") {
        Some(v) => v
        None => Value::None
      }
      let fdel = match get_named_value(inst.dict, "fdel") {
        Some(v) => v
        None => Value::None
      }
      let doc = match get_named_value(inst.dict, "doc") {
        Some(v) => v
        None => Value::None
      }
      Ok(make_property_instance(inst.class, fget, fset, fdel, doc))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "getter() expects a property".to_string(),
        ),
      )
  }
}

///|
fn builtin_property_setter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("property.setter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "setter() takes exactly two arguments".to_string(),
      ),
    )
  }
  let prop = positional[0]
  let fset = positional[1]
  match prop {
    Value::Instance(inst) => {
      let fget = match get_named_value(inst.dict, "fget") {
        Some(v) => v
        None => Value::None
      }
      let fdel = match get_named_value(inst.dict, "fdel") {
        Some(v) => v
        None => Value::None
      }
      let doc = match get_named_value(inst.dict, "doc") {
        Some(v) => v
        None => Value::None
      }
      Ok(make_property_instance(inst.class, fget, fset, fdel, doc))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "setter() expects a property".to_string(),
        ),
      )
  }
}

///|
fn builtin_property_deleter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("property.deleter", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "deleter() takes exactly two arguments".to_string(),
      ),
    )
  }
  let prop = positional[0]
  let fdel = positional[1]
  match prop {
    Value::Instance(inst) => {
      let fget = match get_named_value(inst.dict, "fget") {
        Some(v) => v
        None => Value::None
      }
      let fset = match get_named_value(inst.dict, "fset") {
        Some(v) => v
        None => Value::None
      }
      let doc = match get_named_value(inst.dict, "doc") {
        Some(v) => v
        None => Value::None
      }
      Ok(make_property_instance(inst.class, fget, fset, fdel, doc))
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "deleter() expects a property".to_string(),
        ),
      )
  }
}

///|
fn builtin_property_dunder_get(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("property.__get__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "property.__get__() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let prop = positional[0]
  let obj = positional[1]
  let _owner = if positional.length() == 3 {
    positional[2]
  } else {
    Value::None
  }
  // Match CPython: accessing a property through the class returns the
  // descriptor itself.
  match obj {
    Value::None => return Ok(prop)
    _ => ()
  }
  match prop {
    Value::Instance(inst) => {
      let fget = match get_named_value(inst.dict, "fget") {
        Some(v) => v
        None => Value::None
      }
      match fget {
        Value::None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Attribute,
              "AttributeError: unreadable attribute".to_string(),
            ),
          )
        _ => call_callable_with_env(fget, [obj], [], globals, builtins, io)
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "property.__get__() expects a property".to_string(),
        ),
      )
  }
}

///|
fn builtin_staticmethod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("staticmethod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "staticmethod() takes exactly one argument".to_string(),
      ),
    )
  }
  let dict : Array[(String, Value)] = []
  dict.push(("func", positional[0]))
  let klass = builtin_class_from_name("staticmethod", builtins)
  Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
}

///|
fn builtin_staticmethod_get(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("staticmethod.__get__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__get__() takes exactly 2 arguments".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(inst) =>
      if inst.class.name == "staticmethod" {
        match get_named_value(inst.dict, "func") {
          Some(v) => Ok(v)
          None => Ok(Value::None)
        }
      } else {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "staticmethod.__get__() expects a staticmethod".to_string(),
          ),
        )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "staticmethod.__get__() expects a staticmethod".to_string(),
        ),
      )
  }
}

///|
fn builtin_classmethod(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("classmethod", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "classmethod() takes exactly one argument".to_string(),
      ),
    )
  }
  let dict : Array[(String, Value)] = []
  dict.push(("func", positional[0]))
  let klass = builtin_class_from_name("classmethod", builtins)
  Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
}

///|
fn builtin_classmethod_init(
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
  let _ = match ensure_no_keywords("classmethod.__init__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "classmethod.__init__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let target = positional[0]
  let func_value = positional[1]
  match target {
    Value::Instance(inst) => {
      set_named_value(inst.dict, "func", func_value)
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "classmethod.__init__() expects a classmethod instance".to_string(),
        ),
      )
  }
}

///|
fn builtin_staticmethod_init(
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
  let _ = match ensure_no_keywords("staticmethod.__init__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "staticmethod.__init__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let target = positional[0]
  let func_value = positional[1]
  match target {
    Value::Instance(inst) => {
      set_named_value(inst.dict, "func", func_value)
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "staticmethod.__init__() expects a staticmethod instance".to_string(),
        ),
      )
  }
}

///|
fn builtin_register(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("register", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "register() takes exactly two arguments".to_string(),
      ),
    )
  }
  let cls_value = positional[0]
  let subclass_value = positional[1]
  let subclass = match subclass_value {
    Value::Class(_) => subclass_value
    Value::Function(func) =>
      if func.body.length() == 0 && is_builtin_class_name(func.name) {
        Value::Class(builtin_class_from_name(func.name, builtins))
      } else {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "Can only register classes".to_string(),
          ),
        )
      }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "Can only register classes".to_string(),
        ),
      )
  }
  let cls = match cls_value {
    Value::Class(klass) => klass
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "register() expects a class".to_string(),
        ),
      )
  }
  let already_subclass = match
    issubclass_pair(subclass, Value::Class(cls), globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if already_subclass {
    return Ok(subclass)
  }
  let creates_cycle = match
    issubclass_pair(Value::Class(cls), subclass, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if creates_cycle {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "Refusing to create an inheritance cycle".to_string(),
      ),
    )
  }
  let registry = match get_named_value(cls.dict, "_abc_registry") {
    Some(Value::Set(values)) => values
    _ => []
  }
  match set_add_unique(registry, subclass) {
    Ok(_) => ()
    Err(_) => ()
  }
  set_named_value(cls.dict, "_abc_registry", Value::Set(registry))
  let mro = match class_mro(cls) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for base in mro {
    if base.name == cls.name {
      continue
    }
    let base_registry = match get_named_value(base.dict, "_abc_registry") {
      Some(Value::Set(values)) => values
      _ => []
    }
    match set_add_unique(base_registry, subclass) {
      Ok(_) => ()
      Err(_) => ()
    }
    set_named_value(base.dict, "_abc_registry", Value::Set(base_registry))
  }
  abc_cache_token_ref.val = abc_cache_token_ref.val + 1N
  Ok(subclass)
}

///|
fn builtin_mpython_abc_cache_token(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__mpython_abc_cache_token", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_abc_cache_token() takes no arguments".to_string(),
      ),
    )
  }
  Ok(Value::Int(abc_cache_token_ref.val))
}

///|
fn builtin_mpython_abc_cache_token_bump(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("__mpython_abc_cache_token_bump", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__mpython_abc_cache_token_bump() takes no arguments".to_string(),
      ),
    )
  }
  abc_cache_token_ref.val = abc_cache_token_ref.val + 1N
  Ok(Value::Int(abc_cache_token_ref.val))
}

///|
fn builtin_bool(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("bool", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    return Ok(Value::Bool(false))
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "bool() takes at most one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Instance(_) =>
      match truthy_from_value_with_env(positional[0], globals, builtins, io) {
        Ok(v) => Ok(Value::Bool(v))
        Err(err) => Err(err)
      }
    other => Ok(Value::Bool(bool_from_value(other)))
  }
}

///|
fn builtin_repr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("repr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "repr() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = positional[0]
  match value {
    Value::Str(text) => Ok(Value::Str("'" + escape_string_for_repr(text) + "'"))
    Value::Instance(inst) =>
      if is_base_exception_class_value(inst.class) {
        fn repr_arg(
          arg : Value,
          globals : Array[(String, Value)],
          builtins : Array[(String, Value)],
          io : MockIO,
        ) -> Result[String, RuntimeError] {
          match
            eval_builtin_call("repr", [arg], [], [], globals, builtins, io) {
            Ok(Some(Value::Str(text))) => Ok(text)
            Ok(Some(other)) => Ok(value_to_string(other))
            Ok(None) => Ok(value_to_string(arg))
            Err(err) => Err(err)
          }
        }

        let args : Array[Value] = match
          lookup_instance_field(inst.dict, "args") {
          Some(Value::Tuple(items)) => items
          Some(other) => [other]
          None => []
        }
        if args.length() == 0 {
          Ok(Value::Str(inst.class.name + "()"))
        } else if args.length() == 1 {
          let part = match repr_arg(args[0], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Str(inst.class.name + "(" + part + ")"))
        } else {
          let buf = StringBuilder::new()
          buf.write_string(inst.class.name)
          buf.write_char('(')
          for i = 0; i < args.length(); i = i + 1 {
            if i > 0 {
              buf.write_string(", ")
            }
            let part = match repr_arg(args[i], globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            buf.write_string(part)
          }
          buf.write_char(')')
          Ok(Value::Str(buf.to_string()))
        }
      } else {
        match get_attr_from_value(value, "__repr__", globals, builtins, io) {
          Ok(callable) =>
            match callable {
              Value::BoundMethod(bound) =>
                if bound.function.body.length() > 0 {
                  match
                    (eval_function_with_kwargs_ref.val)(
                      bound.function,
                      [bound.self],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(Value::Str(text)) => Ok(Value::Str(text))
                    Ok(_) =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "__repr__ returned non-string".to_string(),
                        ),
                      )
                    Err(err) => Err(err)
                  }
                } else {
                  Ok(Value::Str(repr_fallback(value)))
                }
              Value::Function(func) =>
                if func.body.length() > 0 {
                  match
                    (eval_function_with_kwargs_ref.val)(
                      func,
                      [value],
                      [],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(Value::Str(text)) => Ok(Value::Str(text))
                    Ok(_) =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "__repr__ returned non-string".to_string(),
                        ),
                      )
                    Err(err) => Err(err)
                  }
                } else {
                  Ok(Value::Str(repr_fallback(value)))
                }
              _ => Ok(Value::Str(repr_fallback(value)))
            }
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute =>
                Ok(Value::Str(repr_fallback(value)))
              _ => Err(err)
            }
        }
      }
    _ => Ok(Value::Str(repr_fallback(value)))
  }
}

///|
fn builtin_ascii(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("ascii", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "ascii() takes exactly one argument".to_string(),
      ),
    )
  }
  match positional[0] {
    Value::Str(text) => Ok(Value::Str("'" + escape_string_for_repr(text) + "'"))
    other => Ok(Value::Str(value_to_string(other)))
  }
}

///|
fn builtin_callable(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("callable", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "callable() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = match positional[0] {
    Value::Function(_) | Value::Class(_) | Value::BoundMethod(_) => true
    Value::Instance(inst) =>
      match lookup_class_attr(inst.class, "__call__") {
        Ok(Some(_)) => true
        Ok(None) => false
        Err(_) => false
      }
    _ => false
  }
  Ok(Value::Bool(value))
}

///|
fn value_matches_builtin_class(obj : Value, name : String) -> Bool {
  match name {
    "function" =>
      match obj {
        Value::Function(_) => true
        _ => false
      }
    "method" =>
      match obj {
        Value::BoundMethod(_) => true
        _ => false
      }
    "int" =>
      match obj {
        Value::Int(_) | Value::Bool(_) => true
        _ => false
      }
    "bool" =>
      match obj {
        Value::Bool(_) => true
        _ => false
      }
    "float" =>
      match obj {
        Value::Float(_) => true
        _ => false
      }
    "complex" =>
      match obj {
        Value::Complex(_, _) => true
        _ => false
      }
    "str" =>
      match obj {
        Value::Str(_) => true
        _ => false
      }
    "bytes" =>
      match obj {
        Value::Bytes(_) => true
        _ => false
      }
    "bytearray" =>
      match obj {
        Value::ByteArray(_) => true
        _ => false
      }
    "memoryview" =>
      match obj {
        Value::MemoryView(_) => true
        _ => false
      }
    "list" =>
      match obj {
        Value::List(_) => true
        _ => false
      }
    "tuple" =>
      match obj {
        Value::Tuple(_) => true
        _ => false
      }
    "dict" =>
      match obj {
        Value::Dict(_) => true
        _ => false
      }
    "set" =>
      match obj {
        Value::Set(_) => true
        _ => false
      }
    "NoneType" =>
      match obj {
        Value::None => true
        _ => false
      }
    _ => false
  }
}

///|
fn builtin_isinstance(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("isinstance", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "isinstance() takes exactly two arguments".to_string(),
      ),
    )
  }
  let obj = positional[0]
  let cls = positional[1]
  fn isinstance_single(obj : Value, cls : Value) -> Result[Bool, RuntimeError] {
    match cls {
      Value::Function(func) =>
        if func.body.length() == 0 {
          let ok = value_matches_builtin_class(obj, func.name)
          Ok(ok)
        } else {
          Ok(false)
        }
      Value::Class(klass) =>
        if klass.name == "type" {
          match obj {
            Value::Class(_) => Ok(true)
            _ => Ok(false)
          }
        } else if get_named_value(klass.dict, "_abc_registry") is Some(_) {
          let obj_cls = match obj {
            Value::Instance(inst) => Value::Class(inst.class)
            Value::Class(c) => Value::Class(c)
            _ =>
              Value::Class(
                builtin_class_from_name(type_name_from_value(obj), builtins),
              )
          }
          let ok = match
            issubclass_pair(obj_cls, Value::Class(klass), globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(ok)
        } else if value_matches_builtin_class(obj, klass.name) {
          Ok(true)
        } else {
          match obj {
            Value::Instance(inst) => {
              let mro = match class_mro(inst.class) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              for c in mro {
                if c.name == klass.name {
                  return Ok(true)
                }
              }
              Ok(false)
            }
            Value::Class(obj_class) =>
              // Class objects are instances of their metaclass. We track a
              // best-effort `__mpython_metaclass__` link for common stdlib needs.
              if klass.name == "object" {
                Ok(true)
              } else {
                let type_class = builtin_class_from_name("type", builtins)
                let meta_value = match
                  get_named_value(obj_class.dict, "__mpython_metaclass__") {
                  Some(Value::Class(meta)) => Value::Class(meta)
                  _ => Value::Class(type_class)
                }
                let ok = match
                  issubclass_pair(
                    meta_value,
                    Value::Class(klass),
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                Ok(ok)
              }
            _ => Ok(false)
          }
        }
      _ =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "isinstance() arg 2 must be a type or tuple of types".to_string(),
          ),
        )
    }
  }

  fn isinstance_multi(obj : Value, cls : Value) -> Result[Bool, RuntimeError] {
    match cls {
      Value::Tuple(values) => {
        for entry in values {
          let ok = match isinstance_multi(obj, entry) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if ok {
            return Ok(true)
          }
        }
        Ok(false)
      }
      _ => isinstance_single(obj, cls)
    }
  }

  let ok = match isinstance_multi(obj, cls) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(ok))
}

///|
fn issubclass_type_error_arg1() -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    "issubclass() arg 1 must be a class".to_string(),
  )
}

///|
fn issubclass_type_error_arg2() -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Type,
    "issubclass() arg 2 must be a class or tuple of classes".to_string(),
  )
}

///|
fn issubclass_matches_builtin_names(
  cls_name : String,
  base_name : String,
) -> Bool {
  if cls_name == base_name {
    true
  } else {
    cls_name == "bool" && base_name == "int"
  }
}

///|
fn is_not_implemented_value(value : Value) -> Bool {
  match value {
    Value::Instance(inst) => inst.class.name == "NotImplementedType"
    _ => false
  }
}

///|
fn issubclass_pair(
  cls : Value,
  base : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Bool, RuntimeError] {
  match base {
    Value::Tuple(values) => {
      for entry in values {
        let ok = match issubclass_pair(cls, entry, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if ok {
          return Ok(true)
        }
      }
      Ok(false)
    }
    Value::Class(base_class) => {
      let subclass_hook = match
        get_attr_raw_from_value(
          Value::Class(base_class),
          "__subclasshook__",
          globals,
          builtins,
          io,
        ) {
        Ok(v) => Some(v)
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute => None
            _ => return Err(err)
          }
      }
      if subclass_hook is Some(hook_value) {
        let result = match
          call_callable_with_env(hook_value, [cls], [], globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if !is_not_implemented_value(result) {
          return Ok(bool_from_value(result))
        }
      }
      match get_named_value(base_class.dict, "_abc_registry") {
        Some(Value::Set(values)) =>
          for item in values {
            match item {
              Value::Class(klass) =>
                if klass.name == base_class.name {
                  return Ok(true)
                }
              _ => ()
            }
            let ok = match issubclass_pair(cls, item, globals, builtins, io) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            if ok {
              return Ok(true)
            }
          }
        _ => ()
      }
      if base_class.name == "type" {
        match cls {
          Value::Class(klass) => {
            let mro = match class_mro(klass) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for c in mro {
              if c.name == "type" {
                return Ok(true)
              }
            }
            Ok(false)
          }
          Value::Function(func) =>
            // Builtin stubs: only `type` itself should be a subclass of `type`.
            Ok(func.body.length() == 0 && func.name == "type")
          _ => Ok(false)
        }
      } else {
        match cls {
          Value::Class(klass) => {
            let mro = match class_mro(klass) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            for c in mro {
              if c.name == base_class.name {
                return Ok(true)
              }
            }
            // If the base provides a custom __subclasses__ implementation,
            // validate it and use it as a fallback (ABCMeta does this).
            match get_named_value(base_class.dict, "__subclasses__") {
              Some(subclasses_value) => {
                let raw = match
                  call_callable_with_env(
                    subclasses_value,
                    [],
                    [],
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let subclasses = match raw {
                  Value::List(values) => values
                  Value::Tuple(values) => values
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "issubclass() arg 2 must be a class or tuple of classes".to_string(),
                      ),
                    )
                }
                for entry in subclasses {
                  match entry {
                    Value::Class(_) => {
                      let ok = match
                        issubclass_pair(cls, entry, globals, builtins, io) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      if ok {
                        return Ok(true)
                      }
                    }
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "issubclass() arg 2 must be a class or tuple of classes".to_string(),
                        ),
                      )
                  }
                }
              }
              None => ()
            }
            Ok(false)
          }
          Value::Function(func) =>
            if func.body.length() == 0 {
              Ok(func.name == base_class.name)
            } else {
              Err(issubclass_type_error_arg1())
            }
          _ => Err(issubclass_type_error_arg1())
        }
      }
    }
    Value::Function(base_func) =>
      if base_func.body.length() == 0 {
        if base_func.name == "type" {
          match cls {
            Value::Class(klass) => {
              let mro = match class_mro(klass) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              for c in mro {
                if c.name == "type" {
                  return Ok(true)
                }
              }
              Ok(false)
            }
            Value::Function(func) =>
              Ok(func.body.length() == 0 && func.name == "type")
            _ => Ok(false)
          }
        } else {
          match cls {
            Value::Class(klass) => Ok(klass.name == base_func.name)
            Value::Function(func) =>
              if func.body.length() == 0 {
                Ok(issubclass_matches_builtin_names(func.name, base_func.name))
              } else {
                Err(issubclass_type_error_arg1())
              }
            _ => Err(issubclass_type_error_arg1())
          }
        }
      } else {
        Err(issubclass_type_error_arg2())
      }
    _ => Err(issubclass_type_error_arg2())
  }
}

///|
fn builtin_issubclass(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("issubclass", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "issubclass() takes exactly two arguments".to_string(),
      ),
    )
  }
  let cls = positional[0]
  let base = positional[1]
  let ok = match issubclass_pair(cls, base, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Bool(ok))
}

///|
fn builtin_type_new(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  // `type.__new__` accepts arbitrary class keywords (`**kwds`) and ignores
  // unknown entries. These keywords are forwarded by metaclasses like
  // `abc.ABCMeta.__new__` and are later consumed by `__init_subclass__`.
  let _ = keywords
  if positional.length() != 4 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "type.__new__() takes exactly 4 arguments".to_string(),
      ),
    )
  }
  let name = match positional[1] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type.__new__() name must be str".to_string(),
        ),
      )
  }
  let base_values : Array[Value] = []
  let raw_bases = match positional[2] {
    Value::Tuple(values) => values
    Value::List(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type.__new__() bases must be a tuple of classes".to_string(),
        ),
      )
  }
  for base in raw_bases {
    match base {
      Value::Class(_) => base_values.push(base)
      Value::Function(func) =>
        if func.body.length() == 0 && is_builtin_class_name(func.name) {
          base_values.push(
            Value::Class(builtin_class_from_name(func.name, builtins)),
          )
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "type.__new__() bases must be a tuple of classes".to_string(),
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "type.__new__() bases must be a tuple of classes".to_string(),
          ),
        )
    }
  }
  if base_values.length() == 0 {
    match get_named_value(builtins, "object") {
      Some(Value::Class(object_class)) =>
        base_values.push(Value::Class(object_class))
      _ => ()
    }
  }
  let class_dict : Array[(String, Value)] = []
  let pairs = match positional[3] {
    Value::Dict(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type.__new__() dict must be a dict".to_string(),
        ),
      )
  }
  for pair in pairs {
    match pair.0 {
      Value::Str(key) => class_dict.push((key, pair.1))
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "type.__new__() dict must have str keys".to_string(),
          ),
        )
    }
  }
  if get_named_value(class_dict, "__name__") is None {
    class_dict.push(("__name__", Value::Str(name)))
  }
  if get_named_value(class_dict, "__qualname__") is None {
    class_dict.push(("__qualname__", Value::Str(name)))
  }
  if get_named_value(class_dict, "__module__") is None {
    match get_named_value(globals, "__name__") {
      Some(Value::Str(module_name)) =>
        class_dict.push(("__module__", Value::Str(module_name)))
      _ => ()
    }
  }
  if get_named_value(class_dict, "hashvalue") is None {
    class_dict.push(("hashvalue", Value::Int(fresh_object_hashvalue())))
  }
  let klass = ClassValue::{ name, bases: base_values, dict: class_dict }
  // Track the metaclass used to construct this class (`type.__new__(mcls, ...)`)
  // so `type(C)` and `isinstance(C, mcls)` behave like CPython.
  match positional[0] {
    Value::Class(meta) =>
      set_named_value(klass.dict, "__mpython_metaclass__", Value::Class(meta))
    _ => ()
  }
  let _ = match class_mro(klass) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Class(klass))
}

///|
fn builtin_sys_getrefcount(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("sys.getrefcount", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getrefcount() takes exactly one argument".to_string(),
      ),
    )
  }
  // Moonpython doesn't expose real refcounts; return a stable placeholder.
  Ok(Value::Int(3N))
}

///|
fn builtin_type(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = keywords
  if positional.length() == 1 {
    let value = positional[0]
    return match value {
      Value::Instance(inst) => Ok(Value::Class(inst.class))
      Value::Class(klass) =>
        match get_named_value(klass.dict, "__mpython_metaclass__") {
          Some(Value::Class(meta)) => Ok(Value::Class(meta))
          _ => Ok(Value::Class(builtin_class_from_name("type", builtins)))
        }
      _ =>
        Ok(
          Value::Class(
            builtin_class_from_name(type_name_from_value(value), builtins),
          ),
        )
    }
  }
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "type() takes 1 or 3 arguments".to_string(),
      ),
    )
  }
  let name = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type() argument 1 must be str".to_string(),
        ),
      )
  }
  let base_values : Array[Value] = []
  let raw_bases = match positional[1] {
    Value::Tuple(values) => values
    Value::List(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type() argument 2 must be a tuple of classes".to_string(),
        ),
      )
  }
  for base in raw_bases {
    match base {
      Value::Class(_) => base_values.push(base)
      Value::Function(func) =>
        if func.body.length() == 0 && is_builtin_class_name(func.name) {
          base_values.push(
            Value::Class(builtin_class_from_name(func.name, builtins)),
          )
        } else {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "type() argument 2 must be a tuple of classes".to_string(),
            ),
          )
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "type() argument 2 must be a tuple of classes".to_string(),
          ),
        )
    }
  }
  if base_values.length() == 0 {
    match get_named_value(builtins, "object") {
      Some(Value::Class(object_class)) =>
        base_values.push(Value::Class(object_class))
      _ => ()
    }
  }
  let class_dict : Array[(String, Value)] = []
  let pairs = match positional[2] {
    Value::Dict(values) => values
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "type() argument 3 must be a dict".to_string(),
        ),
      )
  }
  for pair in pairs {
    match pair.0 {
      Value::Str(key) => class_dict.push((key, pair.1))
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "type() argument 3 must be a dict with str keys".to_string(),
          ),
        )
    }
  }
  if get_named_value(class_dict, "__name__") is None {
    class_dict.push(("__name__", Value::Str(name)))
  }
  if get_named_value(class_dict, "__qualname__") is None {
    class_dict.push(("__qualname__", Value::Str(name)))
  }
  if get_named_value(class_dict, "__module__") is None {
    match get_named_value(globals, "__name__") {
      Some(Value::Str(module_name)) =>
        class_dict.push(("__module__", Value::Str(module_name)))
      _ => ()
    }
  }
  if get_named_value(class_dict, "hashvalue") is None {
    class_dict.push(("hashvalue", Value::Int(fresh_object_hashvalue())))
  }
  let klass = ClassValue::{ name, bases: base_values, dict: class_dict }
  let _ = match class_mro(klass) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Class(klass))
}

///|
fn builtin_id(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("id", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "id() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = positional[0]
  match value {
    Value::Int(v) => Ok(Value::Int(v))
    Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
    Value::Str(text) =>
      Ok(Value::Int(@bigint.BigInt::from_int64(hash_string(text))))
    Value::Function(func) => Ok(Value::Int(function_identity_hash(func)))
    Value::Class(klass) =>
      match class_identity_hash(klass) {
        Some(v) => Ok(Value::Int(v))
        None => {
          let id = fresh_object_hashvalue()
          // Give each class a stable identity so tools like `pickle` can
          // memoize them without collisions.
          klass.dict.push(("hashvalue", Value::Int(id)))
          Ok(Value::Int(id))
        }
      }
    Value::Instance(inst) =>
      match get_named_value(inst.dict, "hashvalue") {
        Some(Value::Int(id)) => Ok(Value::Int(id))
        _ =>
          Ok(
            Value::Int(
              @bigint.BigInt::from_int64(
                hash_string(
                  type_name_from_value(value) + ":" + value_to_string(value),
                ),
              ),
            ),
          )
      }
    _ =>
      Ok(
        Value::Int(
          @bigint.BigInt::from_int64(
            hash_string(
              type_name_from_value(value) + ":" + value_to_string(value),
            ),
          ),
        ),
      )
  }
}

///|
fn builtin_hash(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("hash", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "hash() takes exactly one argument".to_string(),
      ),
    )
  }
  let value = positional[0]
  // Prefer an explicit `__hash__` implementation when present (e.g. unittest.TestCase).
  if value is Value::Instance(_) || value is Value::Class(_) {
    match get_attr_from_value(value, "__hash__", globals, builtins, io) {
      Ok(hash_fn) =>
        if hash_fn is Value::None {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "unhashable type: '" + type_name_from_value(value) + "'",
            ),
          )
        } else {
          let result = match
            call_callable_with_env(hash_fn, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match result {
            Value::Int(v) => return Ok(Value::Int(v))
            Value::Bool(v) => return Ok(Value::Int(if v { 1N } else { 0N }))
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__hash__() should return an int".to_string(),
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
  }
  match hash_value(value) {
    Ok(hash) => Ok(Value::Int(hash))
    Err(err) => Err(err)
  }
}

///|
fn builtin_globals(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = io
  let _ = locals
  let _ = builtins
  let _ = match ensure_no_keywords("globals", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "globals() takes no arguments".to_string(),
      ),
    )
  }
  Ok(make_module_globals_dict_instance(globals))
}

///|
fn module_globals_env_from_self(
  name : String,
  self_value : Value,
) -> Result[Array[(String, Value)], RuntimeError] {
  match self_value {
    Value::Instance(inst) =>
      match get_named_value(inst.dict, "$__env_id__") {
        Some(Value::Int(id)) =>
          match lookup_env_mapping(id) {
            Some(env) => Ok(env)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  name + ": stale globals mapping".to_string(),
                ),
              )
          }
        _ =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              name + ": invalid globals mapping".to_string(),
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          name + ": invalid globals mapping".to_string(),
        ),
      )
  }
}

///|
fn builtin_module_globals_getitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.__getitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__getitem__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.__getitem__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[1] {
    Value::Str(name) =>
      match get_global_value(env, name) {
        Some(v) => Ok(v)
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Key,
              "key not found".to_string(),
            ),
          )
      }
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()),
      )
  }
}

///|
fn builtin_module_globals_setitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.__setitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__setitem__() takes exactly three arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.__setitem__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[1] {
    Value::Str(name) => {
      set_global_value(env, name, positional[2])
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "globals key must be str".to_string(),
        ),
      )
  }
}

///|
fn builtin_module_globals_delitem(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.__delitem__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__delitem__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.__delitem__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[1] {
    Value::Str(name) => {
      delete_global_value(env, name)
      Ok(Value::None)
    }
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()),
      )
  }
}

///|
fn builtin_module_globals_len(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.__len__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__len__() takes exactly one argument".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.__len__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::Int(@bigint.BigInt::from_int(env.length())))
}

///|
fn builtin_module_globals_iter(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.__iter__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__iter__() takes exactly one argument".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.__iter__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys : Array[Value] = []
  for pair in env {
    keys.push(Value::Str(pair.0))
  }
  Ok(make_iterator(keys))
}

///|
fn builtin_module_globals_contains(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.__contains__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__contains__() takes exactly two arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.__contains__", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[1] {
    Value::Str(name) => Ok(Value::Bool(get_global_value(env, name) is Some(_)))
    _ => Ok(Value::Bool(false))
  }
}

///|
fn builtin_module_globals_get(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.get", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "get() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let default_value = if positional.length() == 3 {
    positional[2]
  } else {
    Value::None
  }
  let env = match
    module_globals_env_from_self("module_globals.get", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[1] {
    Value::Str(name) =>
      match get_global_value(env, name) {
        Some(v) => Ok(v)
        None => Ok(default_value)
      }
    _ => Ok(default_value)
  }
}

///|
fn builtin_module_globals_keys(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.keys", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "keys() takes no arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.keys", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let pairs : Array[(Value, Value)] = []
  for pair in env {
    pairs.push((Value::Str(pair.0), pair.1))
  }
  Ok(make_dict_view_instance("dict_keys", Value::Dict(pairs)))
}

///|
fn builtin_module_globals_values(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.values", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "values() takes no arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.values", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let pairs : Array[(Value, Value)] = []
  for pair in env {
    pairs.push((Value::Str(pair.0), pair.1))
  }
  Ok(make_dict_view_instance("dict_values", Value::Dict(pairs)))
}

///|
fn builtin_module_globals_items(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.items", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "items() takes no arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.items", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let pairs : Array[(Value, Value)] = []
  for pair in env {
    pairs.push((Value::Str(pair.0), pair.1))
  }
  Ok(make_dict_view_instance("dict_items", Value::Dict(pairs)))
}

///|
fn builtin_module_globals_pop(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.pop", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() < 2 || positional.length() > 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "pop() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let default_value : Value? = if positional.length() == 3 {
    Some(positional[2])
  } else {
    None
  }
  let env = match
    module_globals_env_from_self("module_globals.pop", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match positional[1] {
    Value::Str(name) =>
      match get_global_value(env, name) {
        Some(v) => {
          delete_global_value(env, name)
          Ok(v)
        }
        None =>
          match default_value {
            Some(v) => Ok(v)
            None =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Key,
                  "key not found".to_string(),
                ),
              )
          }
      }
    _ =>
      match default_value {
        Some(v) => Ok(v)
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Key,
              "key not found".to_string(),
            ),
          )
      }
  }
}

///|
fn builtin_module_globals_update(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.update", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() > 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "update() takes at most one argument".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.update", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 1 {
    return Ok(Value::None)
  }
  let other = positional[1]
  match other {
    Value::None => return Ok(Value::None)
    _ => ()
  }
  match other {
    Value::Dict(pairs) =>
      for pair in pairs {
        match pair.0 {
          Value::Str(name) => set_global_value(env, name, pair.1)
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "globals key must be str".to_string(),
              ),
            )
        }
      }
    Value::Instance(inst) =>
      if class_includes_dict(inst.class) {
        let pairs = match get_named_value(inst.dict, dict_storage_name) {
          Some(Value::Dict(pairs)) => pairs
          Some(_) =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "update() expects a dict".to_string(),
              ),
            )
          None => {
            let pairs : Array[(Value, Value)] = []
            set_named_value(inst.dict, dict_storage_name, Value::Dict(pairs))
            pairs
          }
        }
        for pair in pairs {
          match pair.0 {
            Value::Str(name) => set_global_value(env, name, pair.1)
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "globals key must be str".to_string(),
                ),
              )
          }
        }
      } else {
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
                match values[0] {
                  Value::Str(name) => set_global_value(env, name, values[1])
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "globals key must be str".to_string(),
                      ),
                    )
                }
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
    _ => {
      let iterator = match
        iter_value_to_iterator(other, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      while true {
        let item = match iterator_next(iterator, None, globals, builtins, io) {
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
              match values[0] {
                Value::Str(name) => set_global_value(env, name, values[1])
                _ =>
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "globals key must be str".to_string(),
                    ),
                  )
              }
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
  Ok(Value::None)
}

///|
fn builtin_module_globals_copy(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("module_globals.copy", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "copy() takes no arguments".to_string(),
      ),
    )
  }
  let env = match
    module_globals_env_from_self("module_globals.copy", positional[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let pairs : Array[(Value, Value)] = []
  for item in env {
    pairs.push((Value::Str(item.0), item.1))
  }
  Ok(Value::Dict(pairs))
}

///|
fn builtin_vars(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("vars", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    // vars() -> locals()
    let pairs : Array[(Value, Value)] = []
    for pair in locals {
      pairs.push((Value::Str(pair.0), pair.1))
    }
    return Ok(Value::Dict(pairs))
  }
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "vars() takes at most one argument".to_string(),
      ),
    )
  }
  match get_attr_from_value(positional[0], "__dict__", globals, builtins, io) {
    Ok(v) => Ok(v)
    Err(err) =>
      match err.kind {
        RuntimeErrorKind::Attribute =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "vars() argument must have __dict__ attribute".to_string(),
            ),
          )
        _ => Err(err)
      }
  }
}

///|
fn builtin_locals(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = io
  let _ = globals
  let _ = builtins
  let _ = match ensure_no_keywords("locals", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "locals() takes no arguments".to_string(),
      ),
    )
  }
  let pairs : Array[(Value, Value)] = []
  for pair in locals {
    pairs.push((Value::Str(pair.0), pair.1))
  }
  Ok(Value::Dict(pairs))
}

///|
fn builtin_eval(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let (expr_value, globals_arg, locals_arg) = match
    parse_exec_eval_args("eval", positional, keywords, "expression") {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let expr_text = match expr_value {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "eval() arg 1 must be a string".to_string(),
        ),
      )
  }
  let (locals_env, globals_env, locals_pairs, globals_pairs) = match
    resolve_exec_eval_env("eval", globals_arg, locals_arg, locals, globals) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let expr = match parse_expr(expr_text) {
    Ok(v) => v
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  let _ = match ensure_recursion_available() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  push_traceback_frame("<eval>".to_string(), "<eval>".to_string())
  let result = eval_expr_with_env(expr, locals_env, globals_env, builtins, io)
  pop_traceback_frame()
  match globals_pairs {
    Some(pairs) => sync_env_to_dict(globals_env, pairs)
    None => ()
  }
  match locals_pairs {
    Some(pairs) => sync_env_to_dict(locals_env, pairs)
    None => ()
  }
  result
}

///|
fn builtin_exec(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let (source_value, globals_arg, locals_arg) = match
    parse_exec_eval_args("exec", positional, keywords, "source") {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let source_text = match source_value {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "exec() arg 1 must be a string".to_string(),
        ),
      )
  }
  let (locals_env, globals_env, locals_pairs, globals_pairs) = match
    resolve_exec_eval_env("exec", globals_arg, locals_arg, locals, globals) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let program = match parse(source_text) {
    Ok(v) => v
    Err(err) => return Err(make_parse_runtime_error(err))
  }
  let _ = match ensure_recursion_available() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  push_traceback_frame("<exec>".to_string(), "<exec>".to_string())
  let result = eval_block(
    program.body,
    locals_env,
    globals_env,
    builtins,
    io,
    current_config(),
  )
  pop_traceback_frame()
  match globals_pairs {
    Some(pairs) => sync_env_to_dict(globals_env, pairs)
    None => ()
  }
  match locals_pairs {
    Some(pairs) => sync_env_to_dict(locals_env, pairs)
    None => ()
  }
  match result {
    Ok(_) => Ok(Value::None)
    Err(err) => Err(err)
  }
}

///|
fn builtin_compile(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  if keywords.length() != 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "compile() does not support keyword arguments yet".to_string(),
      ),
    )
  }
  if positional.length() < 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "compile() missing required arguments".to_string(),
      ),
    )
  }
  let source_text = match positional[0] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "compile() arg 1 must be a string".to_string(),
        ),
      )
  }
  let _filename = match positional[1] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "compile() arg 2 must be a string".to_string(),
        ),
      )
  }
  let mode = match positional[2] {
    Value::Str(text) => text
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "compile() arg 3 must be a string".to_string(),
        ),
      )
  }
  if mode == "eval" {
    let _ = match parse_expr(source_text) {
      Ok(v) => v
      Err(err) => return Err(make_parse_runtime_error(err))
    }

  } else if mode == "exec" || mode == "single" {
    let _ = match parse(source_text) {
      Ok(v) => v
      Err(err) => return Err(make_parse_runtime_error(err))
    }

  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "compile() mode must be 'exec', 'eval' or 'single'".to_string(),
      ),
    )
  }

  // Placeholder: we don't model a CodeType yet. Returning the source text keeps
  // `exec(compile(...))` and `eval(compile(...))` usable in practice.
  Ok(Value::Str(source_text))
}

///|
fn builtin_import(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = locals
  if positional.length() > 5 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "__import__() takes at most 5 arguments (" +
        positional.length().to_string() +
        " given)",
      ),
    )
  }

  // Signature: __import__(name, globals=None, locals=None, fromlist=(), level=0)
  let mut name_value : Value? = None
  let mut globals_value = Value::None
  let mut locals_value = Value::None
  let mut fromlist_value : Value = Value::Tuple([])
  let mut level_value : Value = Value::Int(0N)
  if positional.length() >= 1 {
    name_value = Some(positional[0])
  }
  if positional.length() >= 2 {
    globals_value = positional[1]
  }
  if positional.length() >= 3 {
    locals_value = positional[2]
  }
  if positional.length() >= 4 {
    fromlist_value = positional[3]
  }
  if positional.length() == 5 {
    level_value = positional[4]
  }
  for pair in keywords {
    let key = pair.0
    let value = pair.1
    match key {
      "name" =>
        if name_value is Some(_) || positional.length() >= 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__import__() got multiple values for argument 'name'".to_string(),
            ),
          )
        } else {
          name_value = Some(value)
        }
      "globals" =>
        if positional.length() >= 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__import__() got multiple values for argument 'globals'".to_string(),
            ),
          )
        } else {
          globals_value = value
        }
      "locals" =>
        if positional.length() >= 3 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__import__() got multiple values for argument 'locals'".to_string(),
            ),
          )
        } else {
          locals_value = value
        }
      "fromlist" =>
        if positional.length() >= 4 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__import__() got multiple values for argument 'fromlist'".to_string(),
            ),
          )
        } else {
          fromlist_value = value
        }
      "level" =>
        if positional.length() >= 5 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__import__() got multiple values for argument 'level'".to_string(),
            ),
          )
        } else {
          level_value = value
        }
      _ =>
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "__import__() got an unexpected keyword argument '" + key + "'",
          ),
        )
    }
  }

  // Keep compatibility with existing call sites: we don't use `globals/locals`
  // yet, but accept them to match CPython's signature.
  let _ = globals_value
  let _ = locals_value
  let name = match name_value {
    Some(Value::Str(text)) => text
    Some(_) =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "__import__() name must be str".to_string(),
        ),
      )
    None => return Err(missing_required_argument_error("__import__", "name"))
  }
  if name == "" {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: Empty module name".to_string(),
      ),
    )
  }
  match level_value {
    Value::None => ()
    Value::Int(v) =>
      match bigint_to_int_checked(v) {
        Ok(level) =>
          if level != 0 {
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ImportError: relative import level not supported".to_string(),
              ),
            )
          }
        Err(err) => return Err(err)
      }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "__import__() level must be int".to_string(),
        ),
      )
  }
  let module_value = match
    import_module(name, globals, builtins, io, current_config()) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let mut has_fromlist = false
  match fromlist_value {
    Value::None => ()
    Value::List(values) => has_fromlist = values.length() > 0
    Value::Tuple(values) => has_fromlist = values.length() > 0
    _ => has_fromlist = true
  }
  if has_fromlist || !name.contains(".") {
    return Ok(module_value)
  }
  let top_name = module_top_name(name)
  match module_cache_get(top_name) {
    Some(value) => Ok(value)
    None => Ok(module_value)
  }
}

///|
fn builtin_dir(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = io
  let _ = match ensure_no_keywords("dir", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() == 0 {
    let names : Array[Value] = []
    for pair in globals {
      names.push(Value::Str(pair.0))
    }
    return Ok(Value::List(names))
  }
  let _ = builtins
  let _ = locals
  if positional.length() != 1 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "dir() takes 0 or 1 arguments".to_string(),
      ),
    )
  }
  let value = positional[0]

  // __dir__ hook
  match value {
    Value::Instance(_) => {
      let hook = match
        get_attr_from_value(value, "__dir__", globals, builtins, io) {
        Ok(v) => v
        Err(_err) => Value::None
      }
      match hook {
        Value::None => ()
        _ => {
          let result = match
            call_callable_with_env(hook, [], [], globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match result {
            Value::List(_) => return Ok(result)
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "__dir__ must return a list".to_string(),
                ),
              )
          }
        }
      }
    }
    // For type objects, CPython uses the metaclass' `__dir__` (type.__dir__),
    // not the class' own `__dir__` attribute meant for instances.
    _ => ()
  }

  // Default listing: include inherited names, sort, dedup.
  let names : Array[String] = []
  fn push_name(names : Array[String], name : String) -> Unit {
    if name == "__class__" ||
      name == "__mpython_metaclass__" ||
      name == "__name__" ||
      name == "__qualname__" {
      // Hide internal or compatibility-only attributes from `dir()`.
      return
    }
    for existing in names {
      if existing == name {
        return
      }
    }
    names.push(name)
  }

  match value {
    Value::Dict(pairs) =>
      for pair in pairs {
        match pair.0 {
          Value::Str(name) => push_name(names, name)
          _ => ()
        }
      }
    Value::Instance(inst) => {
      for pair in inst.dict {
        push_name(names, pair.0)
      }
      let mro = match class_mro(inst.class) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for cls in mro {
        for pair in cls.dict {
          if pair.0 != "__getattribute__" &&
            pair.0 != "__setattr__" &&
            pair.0 != "__delattr__" {
            push_name(names, pair.0)
          }
        }
      }
    }
    Value::Class(klass) => {
      let mro = match class_mro(klass) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for cls in mro {
        for pair in cls.dict {
          if pair.0 != "__getattribute__" &&
            pair.0 != "__setattr__" &&
            pair.0 != "__delattr__" {
            push_name(names, pair.0)
          }
        }
      }
    }
    _ => ()
  }
  names.sort()
  let out : Array[Value] = []
  for name in names {
    out.push(Value::Str(name))
  }
  Ok(Value::List(out))
}

///|
fn builtin_getattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("getattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io
  let _ = locals
  let _ = globals
  let _ = builtins
  if positional.length() != 2 && positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "getattr() takes 2 or 3 arguments".to_string(),
      ),
    )
  }
  let obj = positional[0]
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
  match get_attr_from_value(obj, name, globals, builtins, io) {
    Ok(value) => Ok(value)
    Err(err) =>
      if positional.length() == 3 {
        Ok(positional[2])
      } else {
        Err(err)
      }
  }
}

///|
fn builtin_hasattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("hasattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io
  let _ = locals
  let _ = globals
  let _ = builtins
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "hasattr() takes exactly two arguments".to_string(),
      ),
    )
  }
  let obj = positional[0]
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
  match get_attr_from_value(obj, name, globals, builtins, io) {
    Ok(_) => Ok(Value::Bool(true))
    Err(_err) => Ok(Value::Bool(false))
  }
}

///|
fn builtin_setattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("setattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io
  let _ = locals
  let _ = globals
  let _ = builtins
  if positional.length() != 3 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "setattr() takes exactly three arguments".to_string(),
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
  let _ = match set_attr_on_value(target, name, value, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}

///|
fn builtin_super(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("super", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = io

  // Support:
  // - super(type, obj)
  // - super() best-effort: uses closure __class__ and locals "self" / "cls"
  let mut thisclass_value : Value = Value::None
  let mut self_value : Value = Value::None
  if positional.length() == 0 {
    fn read_local_name(
      name : String,
      locals : Array[(String, Value)],
    ) -> Result[Value?, RuntimeError] {
      match get_local_value(locals, name) {
        Some(v) =>
          if is_cell_value(v) {
            match cell_get_value(v) {
              Some(value) => Ok(Some(value))
              None => Ok(None)
            }
          } else {
            Ok(Some(v))
          }
        None => Ok(None)
      }
    }

    let cls_opt = match
      lookup_name_value("__class__", locals, globals, builtins) {
      Ok(v) => Some(v)
      Err(err) =>
        if err.exc_type == "NameError" {
          None
        } else {
          return Err(err)
        }
    }
    if cls_opt is None {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: super(): no __class__ in scope".to_string(),
        ),
      )
    }
    thisclass_value = cls_opt.unwrap()
    let self_opt = match read_local_name("self", locals) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let cls_opt2 = match read_local_name("cls", locals) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let mcls_opt = match read_local_name("mcls", locals) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let type_opt = match read_local_name("type", locals) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if self_opt is Some(v) {
      self_value = v
    } else if cls_opt2 is Some(v) {
      self_value = v
    } else if mcls_opt is Some(v) {
      self_value = v
    } else if type_opt is Some(v) {
      self_value = v
    } else {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Runtime,
          "RuntimeError: super(): no self/cls in scope".to_string(),
        ),
      )
    }
  } else if positional.length() == 2 {
    thisclass_value = positional[0]
    self_value = positional[1]
  } else {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "super() takes 0 or 2 arguments".to_string(),
      ),
    )
  }
  let thisclass = match thisclass_value {
    Value::Class(k) => k
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "super() arg 1 must be a type".to_string(),
        ),
      )
  }

  // Determine the dynamic class to do MRO search on
  let self_class = match self_value {
    Value::Instance(inst) => inst.class
    Value::Class(k) => k
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "super() arg 2 must be an instance or type".to_string(),
        ),
      )
  }

  // Ensure thisclass is in self_class mro
  let mro = match class_mro(self_class) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut found = false
  for c in mro {
    if class_identity_equal(c, thisclass) {
      found = true
      break
    }
  }
  if !found {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "super() arguments are inconsistent".to_string(),
      ),
    )
  }
  let dict : Array[(String, Value)] = []
  dict.push(("__thisclass__", Value::Class(thisclass)))
  dict.push(("__self__", self_value))
  dict.push(("__self_class__", Value::Class(self_class)))
  Ok(
    Value::Instance(InstanceValue::{
      class: ClassValue::{ name: "super", bases: [], dict: [] },
      dict,
    }),
  )
}

///|
fn builtin_delattr(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("delattr", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _ = locals
  let _ = builtins
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "delattr() takes exactly two arguments".to_string(),
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
  let _ = match delete_attr_on_value(target, name, globals, builtins, io) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(Value::None)
}
