///|
/// Iterator protocol helpers (internal).

///|
let iterator_class_ref : Ref[ClassValue?] = { val: None }

///|
let repeat_class_ref : Ref[ClassValue?] = { val: None }

///|
let count_class_ref : Ref[ClassValue?] = { val: None }

///|
let enumerate_class_ref : Ref[ClassValue?] = { val: None }

///|
let rangeiter_class_ref : Ref[ClassValue?] = { val: None }

///|
let cycle_class_ref : Ref[ClassValue?] = { val: None }

///|
let seqiter_class_ref : Ref[ClassValue?] = { val: None }

///|
let zip_class_ref : Ref[ClassValue?] = { val: None }

///|
fn internal_iter_class(name : String, cache : Ref[ClassValue?]) -> ClassValue {
  match cache.val {
    Some(value) => return value
    None => ()
  }
  let dict : Array[(String, Value)] = [
    (
      "__iter__",
      Value::Function(FunctionValue::{
        name: "__mpython.internal_iter",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__next__",
      Value::Function(FunctionValue::{
        name: "__mpython.internal_next",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ]
  if name == "rangeiter" {
    dict.push(
      (
        "__setstate__",
        Value::Function(FunctionValue::{
          name: "rangeiter.__setstate__",
          params: ["self", "state"],
          defaults: [],
          body: [],
          is_generator: false,
          is_async: false,
          closure: [],
        }),
      ),
    )
  }
  let klass = ClassValue::{ name, bases: [], dict }
  cache.val = Some(klass)
  klass
}

///|
fn make_iterator(items_in : Array[Value]) -> Value {
  let items : Array[Value] = []
  for item in items_in {
    items.push(item)
  }
  let dict : Array[(String, Value)] = []
  dict.push(("items", Value::List(items)))
  dict.push(("pos", Value::Int(0N)))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("iterator", iterator_class_ref),
    dict,
  })
}

///|
fn make_repeat_iterator(value : Value, remaining : @bigint.BigInt?) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("value", value))
  match remaining {
    Some(v) => dict.push(("remaining", Value::Int(v)))
    None => dict.push(("remaining", Value::None))
  }
  Value::Instance(InstanceValue::{
    class: internal_iter_class("repeat", repeat_class_ref),
    dict,
  })
}

///|
fn make_count_iterator(start : Value, step : Value) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("current", start))
  dict.push(("step", step))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("count", count_class_ref),
    dict,
  })
}

///|
fn make_cycle_iterator(iterator : Value) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("iterator", iterator))
  dict.push(("saved", Value::List([])))
  dict.push(("pos", Value::Int(0N)))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("cycle", cycle_class_ref),
    dict,
  })
}

///|
fn make_enumerate_iterator(iterator : Value, start : @bigint.BigInt) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("iterator", iterator))
  dict.push(("index", Value::Int(start)))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("enumerate", enumerate_class_ref),
    dict,
  })
}

///|
fn make_range_iterator(
  start : @bigint.BigInt,
  stop : @bigint.BigInt,
  step : @bigint.BigInt,
) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("start", Value::Int(start)))
  dict.push(("current", Value::Int(start)))
  dict.push(("stop", Value::Int(stop)))
  dict.push(("step", Value::Int(step)))
  dict.push(("index", Value::Int(0N)))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("rangeiter", rangeiter_class_ref),
    dict,
  })
}

///|
fn make_seqiter_iterator(target : Value) -> Value {
  let dict : Array[(String, Value)] = []
  dict.push(("target", target))
  dict.push(("index", Value::Int(0N)))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("seqiter", seqiter_class_ref),
    dict,
  })
}

///|
fn make_zip_iterator(iterators_in : Array[Value], strict : Bool) -> Value {
  let iterators : Array[Value] = []
  for it in iterators_in {
    iterators.push(it)
  }
  let dict : Array[(String, Value)] = []
  dict.push(("iterators", Value::List(iterators)))
  dict.push(("strict", Value::Bool(strict)))
  Value::Instance(InstanceValue::{
    class: internal_iter_class("zip", zip_class_ref),
    dict,
  })
}

///|
fn iter_value_to_iterator(
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match value {
    Value::Instance(inst) => {
      // Treat list subclasses (instances carrying `$__list__`) as iterables.
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(values)) => return Ok(make_iterator(values))
        _ => ()
      }
      // Treat tuple subclasses (instances carrying `$__tuple__`) as iterables.
      match get_named_value(inst.dict, tuple_storage_name) {
        Some(Value::Tuple(values)) => return Ok(make_iterator(values))
        _ => ()
      }
      // Treat set/frozenset subclasses as iterables.
      match get_named_value(inst.dict, set_storage_name) {
        Some(Value::Set(values)) => return Ok(make_iterator(values))
        _ => ()
      }
      if inst.class.name == "dict_keys" ||
        inst.class.name == "dict_values" ||
        inst.class.name == "dict_items" {
        let items = match iterable_values(Value::Instance(inst)) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(make_iterator(items))
      } else if inst.class.name == "iterator" ||
        inst.class.name == "generator" ||
        inst.class.name == "repeat" ||
        inst.class.name == "count" ||
        inst.class.name == "cycle" ||
        inst.class.name == "enumerate" ||
        inst.class.name == "rangeiter" ||
        inst.class.name == "zip" {
        Ok(Value::Instance(inst))
      } else {
        // Try the Python protocol first: obj.__iter__() -> iterator
        match
          get_attr_from_value(
            Value::Instance(inst),
            "__iter__",
            globals,
            builtins,
            io,
          ) {
          Ok(iter_method) =>
            call_callable_with_env(iter_method, [], [], globals, builtins, io)
          Err(err) =>
            match err.kind {
              RuntimeErrorKind::Attribute => {
                match
                  get_attr_from_value(
                    Value::Instance(inst),
                    "__getitem__",
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(_) =>
                    return Ok(make_seqiter_iterator(Value::Instance(inst)))
                  Err(err2) =>
                    match err2.kind {
                      RuntimeErrorKind::Attribute => ()
                      _ => return Err(err2)
                    }
                }
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "'" + inst.class.name + "' object is not iterable",
                  ),
                )
              }
              _ => Err(err)
            }
        }
      }
    }
    Value::Class(klass) => {
      let class_value = Value::Class(klass)
      match
        get_attr_from_value(class_value, "__iter__", globals, builtins, io) {
        Ok(iter_method) =>
          call_callable_with_env(iter_method, [], [], globals, builtins, io)
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute => {
              let names_value = get_named_value(klass.dict, "_member_names_")
              let map_value = get_named_value(klass.dict, "_member_map_")
              match (names_value, map_value) {
                (Some(Value::List(names)), Some(Value::Dict(pairs))) => {
                  let items : Array[Value] = []
                  for name_value in names {
                    match name_value {
                      Value::Str(name) => {
                        let idx = match
                          dict_find_index(pairs, Value::Str(name)) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        match idx {
                          Some(i) => items.push(pairs[i].1)
                          None => ()
                        }
                      }
                      _ => ()
                    }
                  }
                  if items.length() == 0 && pairs.length() > 0 {
                    for pair in pairs {
                      items.push(pair.1)
                    }
                  }
                  Ok(make_iterator(items))
                }
                _ => {
                  let mut is_enum = false
                  match class_mro(klass) {
                    Ok(mro) =>
                      for cls in mro {
                        if cls.name == "Enum" ||
                          cls.name == "Flag" ||
                          cls.name == "IntFlag" ||
                          cls.name == "StrEnum" {
                          is_enum = true
                          break
                        }
                      }
                    Err(err) => return Err(err)
                  }
                  if is_enum {
                    let items : Array[Value] = []
                    for pair in klass.dict {
                      if !pair.0.has_prefix("_") {
                        items.push(pair.1)
                      }
                    }
                    if items.length() > 0 {
                      return Ok(make_iterator(items))
                    }
                  }
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "object is not iterable".to_string(),
                    ),
                  )
                }
              }
            }
            _ => Err(err)
          }
      }
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
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
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
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        if pos < @bigint.BigInt::from_int(items.length()) {
          let idx = match bigint_to_int_checked(pos) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let item = items[idx]
          set_named_value(inst.dict, "pos", Value::Int(pos + 1N))
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
      } else if inst.class.name == "repeat" {
        let value = match get_named_value(inst.dict, "value") {
          Some(v) => v
          None => Value::None
        }
        match get_named_value(inst.dict, "remaining") {
          Some(Value::None) => Ok(value)
          Some(Value::Int(v)) =>
            if v <= 0N {
              match default_value {
                Some(v2) => Ok(v2)
                None =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "StopIteration".to_string(),
                    ),
                  )
              }
            } else {
              set_named_value(inst.dict, "remaining", Value::Int(v - 1N))
              Ok(value)
            }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "StopIteration".to_string(),
              ),
            )
        }
      } else if inst.class.name == "count" {
        let current = match get_named_value(inst.dict, "current") {
          Some(v) => v
          None => Value::Int(0N)
        }
        let step = match get_named_value(inst.dict, "step") {
          Some(v) => v
          None => Value::Int(1N)
        }
        match (current, step) {
          (Value::Int(current_i), Value::Int(step_i)) => {
            set_named_value(
              inst.dict,
              "current",
              Value::Int(current_i + step_i),
            )
            Ok(Value::Int(current_i))
          }
          (Value::Float(current_f), Value::Float(step_f)) => {
            set_named_value(
              inst.dict,
              "current",
              Value::Float(current_f + step_f),
            )
            Ok(Value::Float(current_f))
          }
          (Value::Int(current_i), Value::Float(step_f)) => {
            let current_f = match bigint_to_double_checked(current_i) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            set_named_value(
              inst.dict,
              "current",
              Value::Float(current_f + step_f),
            )
            Ok(Value::Float(current_f))
          }
          (Value::Float(current_f), Value::Int(step_i)) => {
            let step_f = match bigint_to_double_checked(step_i) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            set_named_value(
              inst.dict,
              "current",
              Value::Float(current_f + step_f),
            )
            Ok(Value::Float(current_f))
          }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "count() expects numeric values".to_string(),
              ),
            )
        }
      } else if inst.class.name == "zip" {
        let strict = match get_named_value(inst.dict, "strict") {
          Some(Value::Bool(v)) => v
          _ => false
        }
        let iterators = match get_named_value(inst.dict, "iterators") {
          Some(Value::List(values)) => values
          _ => ([] : Array[Value])
        }
        if iterators.length() == 0 {
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
        } else {
          let items : Array[Value] = []
          let mut stop_index : Int? = None
          for i = 0; i < iterators.length(); i = i + 1 {
            match iterator_next(iterators[i], None, globals, builtins, io) {
              Ok(v) => items.push(v)
              Err(err) =>
                if err.exc_type == "StopIteration" {
                  stop_index = Some(i)
                  break
                } else {
                  return Err(err)
                }
            }
          }
          match stop_index {
            None => Ok(Value::Tuple(items))
            Some(i) =>
              if strict {
                for j = i + 1; j < iterators.length(); j = j + 1 {
                  match
                    iterator_next(iterators[j], None, globals, builtins, io) {
                    Ok(_) =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "ValueError: zip() argument lengths differ".to_string(),
                        ),
                      )
                    Err(err) =>
                      if err.exc_type == "StopIteration" {
                        continue
                      } else {
                        return Err(err)
                      }
                  }
                }
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: zip() argument lengths differ".to_string(),
                  ),
                )
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
          }
        }
      } else if inst.class.name == "cycle" {
        let saved = match get_named_value(inst.dict, "saved") {
          Some(Value::List(values)) => values
          _ => []
        }
        let pos0 = match get_named_value(inst.dict, "pos") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let iter_value_opt = get_named_value(inst.dict, "iterator")
        let mut iter_done = false
        match iter_value_opt {
          Some(Value::None) => iter_done = true
          None => iter_done = true
          Some(v) =>
            match iterator_next(v, None, globals, builtins, io) {
              Ok(item) => {
                saved.push(item)
                return Ok(item)
              }
              Err(err) =>
                if err.exc_type == "StopIteration" {
                  iter_done = true
                } else {
                  return Err(err)
                }
            }
        }
        if iter_done {
          // Mark the source iterator as done so we keep cycling over the saved list.
          set_named_value(inst.dict, "iterator", Value::None)
          if saved.length() == 0 {
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
          } else {
            let len_i = @bigint.BigInt::from_int(saved.length())
            let idx_big = if len_i == 0N { 0N } else { pos0 % len_i }
            let idx = match bigint_to_int_checked(idx_big) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            set_named_value(inst.dict, "pos", Value::Int(pos0 + 1N))
            Ok(saved[idx])
          }
        } else {
          // Should be unreachable due to early return in Ok(item) branch.
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "internal cycle iterator error".to_string(),
            ),
          )
        }
      } else if inst.class.name == "rangeiter" {
        let current = match get_named_value(inst.dict, "current") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let start0 = match get_named_value(inst.dict, "start") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => current
        }
        let stop = match get_named_value(inst.dict, "stop") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let step = match get_named_value(inst.dict, "step") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 1N
        }
        let index0 = match get_named_value(inst.dict, "index") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => (current - start0) / step
        }
        let done = if step > 0N { current >= stop } else { current <= stop }
        if done {
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
        } else {
          set_named_value(inst.dict, "current", Value::Int(current + step))
          set_named_value(inst.dict, "index", Value::Int(index0 + 1N))
          Ok(Value::Int(current))
        }
      } else if inst.class.name == "seqiter" {
        let target = match get_named_value(inst.dict, "target") {
          Some(v) => v
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "invalid seqiter iterator".to_string(),
              ),
            )
        }
        let index0 = match get_named_value(inst.dict, "index") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        let getitem = match
          get_attr_from_value(target, "__getitem__", globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match
          call_callable_with_env(
            getitem,
            [Value::Int(index0)],
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(item) => {
            set_named_value(inst.dict, "index", Value::Int(index0 + 1N))
            Ok(item)
          }
          Err(err) =>
            if err.exc_type == "IndexError" {
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
            } else {
              Err(err)
            }
        }
      } else if inst.class.name == "generator" {
        generator_next(Value::Instance(inst), default_value)
      } else if inst.class.name == "enumerate" {
        let inner = match get_named_value(inst.dict, "iterator") {
          Some(v) => v
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "invalid enumerate iterator".to_string(),
              ),
            )
        }
        let index0 = match get_named_value(inst.dict, "index") {
          Some(Value::Int(v)) => v
          Some(Value::Bool(v)) => if v { 1N } else { 0N }
          _ => 0N
        }
        match iterator_next(inner, None, globals, builtins, io) {
          Ok(item) => {
            set_named_value(inst.dict, "index", Value::Int(index0 + 1N))
            Ok(Value::Tuple([Value::Int(index0), item]))
          }
          Err(err) =>
            if err.exc_type == "StopIteration" {
              match default_value {
                Some(v) => Ok(v)
                None => Err(err)
              }
            } else {
              Err(err)
            }
        }
      } else {
        let next_method = match
          get_attr_from_value(
            Value::Instance(inst),
            "__next__",
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(_) =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object is not an iterator",
              ),
            )
        }
        match
          call_callable_with_env(next_method, [], [], globals, builtins, io) {
          Ok(v) => Ok(v)
          Err(err) =>
            if err.exc_type == "StopIteration" {
              match default_value {
                Some(v) => Ok(v)
                None => Err(err)
              }
            } else {
              Err(err)
            }
        }
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
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match iterator_value {
    Value::Instance(inst) =>
      if inst.class.name == "generator" {
        generator_send(Value::Instance(inst), sent_value)
      } else if inst.class.name == "iterator" {
        match sent_value {
          Value::None =>
            iterator_next(Value::Instance(inst), None, globals, builtins, io)
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object does not support send()",
              ),
            )
        }
      } else {
        match sent_value {
          Value::None =>
            iterator_next(Value::Instance(inst), None, globals, builtins, io)
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "'" + inst.class.name + "' object does not support send()",
              ),
            )
        }
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
fn builtin_rangeiter_setstate(
  positional : Array[Value],
  keywords : Array[(String, Value)],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  touch_env(locals, globals, builtins, io)
  let _ = match ensure_no_keywords("rangeiter.__setstate__", keywords) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if positional.length() != 2 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Type,
        "rangeiter.__setstate__() takes exactly one argument".to_string(),
      ),
    )
  }
  let inst = match positional[0] {
    Value::Instance(inst) if inst.class.name == "rangeiter" => inst
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "rangeiter.__setstate__ expects a range iterator".to_string(),
        ),
      )
  }
  let state = match positional[1] {
    Value::Int(v) => v
    Value::Bool(v) => if v { 1N } else { 0N }
    _ =>
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "rangeiter.__setstate__ state must be int".to_string(),
        ),
      )
  }
  let start0 = match get_named_value(inst.dict, "start") {
    Some(Value::Int(v)) => v
    Some(Value::Bool(v)) => if v { 1N } else { 0N }
    _ => 0N
  }
  let step0 = match get_named_value(inst.dict, "step") {
    Some(Value::Int(v)) => v
    Some(Value::Bool(v)) => if v { 1N } else { 0N }
    _ => 1N
  }
  set_named_value(inst.dict, "index", Value::Int(state))
  set_named_value(inst.dict, "current", Value::Int(start0 + step0 * state))
  Ok(Value::None)
}
