///|
/// Bytecode VM (stack machine), inspired by MicroPython's `py/vm.c`.
///
/// This VM reuses MoonPython's existing runtime helpers (`Value`, builtins,
/// attribute lookup, call protocol, etc.) for semantics.

///|
priv enum VmBlockKind {
  Except(Int)
  ExceptHandler
  Finally(Int)
  FinallyHandler
}

///|
priv struct VmBlock {
  kind : VmBlockKind
  stack_height : Int
  // Whether this block pushed an active exception onto `active_exception_stack`.
  pushed_exc : Bool
  // `except*` state (stored on the active ExceptHandler block).
  star_base_err : RuntimeError?
  star_remaining_group : Value?
  star_active_match : Bool
}

///|

///|
fn vm_trim_runtime_error_for_active_handler(err : RuntimeError) -> RuntimeError {
  // See `runtime_block.mbt::trim_runtime_error_for_active_handler`.
  let active_len = active_frame_stack.val.length()
  if active_len <= 1 {
    return err
  }
  // Only trim when the traceback appears to be a full snapshot of the active
  // frame stack. With incremental traceback growth (caller-frame injection),
  // trimming here would incorrectly drop legitimate outer frames.
  if err.traceback.length() != active_len {
    return err
  }
  let drop = active_len - 1
  if err.traceback.length() <= drop {
    return err
  }
  let trimmed_tb : Array[TracebackFrame] = []
  for i = drop; i < err.traceback.length(); i = i + 1 {
    trimmed_tb.push(err.traceback[i])
  }
  let trimmed_envs : Array[TracebackEnv] = []
  if err.traceback_envs.length() == err.traceback.length() {
    for i = drop; i < err.traceback_envs.length(); i = i + 1 {
      trimmed_envs.push(err.traceback_envs[i])
    }
  }
  RuntimeError::{
    kind: err.kind,
    message: err.message,
    span: err.span,
    traceback: trimmed_tb,
    traceback_envs: trimmed_envs,
    exc_type: err.exc_type,
    exc_args: err.exc_args,
    exc_value: err.exc_value,
    exc_cause: err.exc_cause,
    exc_context: err.exc_context,
    exc_suppress_context: err.exc_suppress_context,
  }
}

///|
fn pop_stack(stack : Array[Value]) -> Result[Value, RuntimeError] {
  if stack.length() == 0 {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "bytecode vm: stack underflow".to_string(),
      ),
    )
  } else {
    Ok(stack.remove(stack.length() - 1))
  }
}

///|
fn pop_n(stack : Array[Value], n : Int) -> Result[Array[Value], RuntimeError] {
  if n < 0 || stack.length() < n {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "bytecode vm: stack underflow".to_string(),
      ),
    )
  }
  let tmp : Array[Value] = []
  for _i = 0; _i < n; _i = _i + 1 {
    tmp.push(stack.remove(stack.length() - 1))
  }
  // Caller expects left-to-right order; we popped right-to-left.
  let out : Array[Value] = []
  for i = tmp.length() - 1; i >= 0; i = i - 1 {
    out.push(tmp[i])
    if i == 0 {
      break
    }
  }
  Ok(out)
}

///|
fn unary_op_value(
  op : UnaryOp,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  // Keep this small initially; extend by extracting the full logic from
  // `runtime_eval_expr.mbt` as the VM reaches parity.
  match op {
    UnaryOp::Not => {
      let ok = match truthy_from_value_with_env(value, globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(Value::Bool(!ok))
    }
    UnaryOp::Neg =>
      match value {
        Value::Int(v) => Ok(Value::Int(-v))
        Value::Float(v) => Ok(Value::Float(-v))
        Value::Complex(real, imag) => Ok(Value::Complex(-real, -imag))
        Value::Bool(v) => Ok(Value::Int(-(if v { 1N } else { 0N })))
        other =>
          match get_attr_from_value(other, "__neg__", globals, builtins, io) {
            Ok(callable) =>
              call_callable_with_env(callable, [], [], globals, builtins, io)
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bad operand type for unary -".to_string(),
                    ),
                  )
                _ => Err(err)
              }
          }
      }
    UnaryOp::Pos =>
      match value {
        Value::Bool(v) => Ok(Value::Int(if v { 1N } else { 0N }))
        Value::Int(_) | Value::Float(_) | Value::Complex(_, _) => Ok(value)
        other =>
          match get_attr_from_value(other, "__pos__", globals, builtins, io) {
            Ok(callable) =>
              call_callable_with_env(callable, [], [], globals, builtins, io)
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute => Ok(other)
                _ => Err(err)
              }
          }
      }
    UnaryOp::Invert =>
      match value {
        Value::Int(v) => Ok(Value::Int(-(v + 1N)))
        Value::Bool(v) => {
          // CPython 3.13+: `~bool` is deprecated.
          let import_value = match get_named_value(builtins, "__import__") {
            Some(v) => v
            None =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "missing builtins.__import__".to_string(),
                ),
              )
          }
          let warnings_module = match
            call_callable_with_env(
              import_value,
              [Value::Str("warnings")],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let warn_fn = match
            get_attr_from_value(warnings_module, "warn", globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let category = match get_named_value(builtins, "DeprecationWarning") {
            Some(Value::Class(k)) => Value::Class(k)
            _ => Value::None
          }
          let _ = match
            call_callable_with_env(
              warn_fn,
              [
                Value::Str(
                  "Bitwise inversion on bool is deprecated".to_string(),
                ),
                category,
                Value::Int(2N),
              ],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          Ok(Value::Int(-((if v { 1N } else { 0N }) + 1N)))
        }
        other =>
          match
            get_attr_from_value(other, "__invert__", globals, builtins, io) {
            Ok(callable) =>
              call_callable_with_env(callable, [], [], globals, builtins, io)
            Err(err) =>
              match err.kind {
                RuntimeErrorKind::Attribute =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bad operand type for unary ~".to_string(),
                    ),
                  )
                _ => Err(err)
              }
          }
      }
  }
}

///|
fn get_subscr_value(
  target : Value,
  index : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  fn slice_parts_from_value(value : Value) -> (Value, Value, Value)? {
    match value {
      Value::Instance(inst) if inst.class.name == "slice" => {
        let start = match get_named_value(inst.dict, "start") {
          Some(v) => v
          None => Value::None
        }
        let stop = match get_named_value(inst.dict, "stop") {
          Some(v) => v
          None => Value::None
        }
        let step = match get_named_value(inst.dict, "step") {
          Some(v) => v
          None => Value::None
        }
        Some((start, stop, step))
      }
      _ => None
    }
  }

  match target {
    Value::Dict(pairs) => {
      let found = match dict_find_index(pairs, index) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match found {
        Some(i) => Ok(pairs[i].1)
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Key,
              "key not found".to_string(),
            ),
          )
      }
    }
    Value::List(items) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) =>
          match slice_indices_from_values(items.length(), start, stop, step) {
            Ok(indices) => {
              let out : Array[Value] = []
              for idx in indices {
                if idx >= 0 && idx < items.length() {
                  out.push(items[idx])
                }
              }
              Ok(Value::List(out))
            }
            Err(err) => Err(err)
          }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, items.length())
              if idx < 0 || idx >= items.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                Ok(items[idx])
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Tuple(items) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) =>
          match slice_indices_from_values(items.length(), start, stop, step) {
            Ok(indices) => {
              let out : Array[Value] = []
              for idx in indices {
                if idx >= 0 && idx < items.length() {
                  out.push(items[idx])
                }
              }
              Ok(Value::Tuple(out))
            }
            Err(err) => Err(err)
          }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, items.length())
              if idx < 0 || idx >= items.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                Ok(items[idx])
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Str(text) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) => {
          let chars = text.to_array()
          match slice_indices_from_values(chars.length(), start, stop, step) {
            Ok(indices) =>
              Ok(Value::Str(slice_string_by_indices(chars, indices)))
            Err(err) => Err(err)
          }
        }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let chars = text.to_array()
              let idx = normalize_index(i, chars.length())
              if idx < 0 || idx >= chars.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                Ok(Value::Str(char_to_string(chars[idx])))
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Bytes(bytes) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) =>
          match slice_indices_from_values(bytes.length(), start, stop, step) {
            Ok(indices) =>
              Ok(Value::Bytes(slice_ints_by_indices(bytes, indices)))
            Err(err) => Err(err)
          }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, bytes.length())
              if idx < 0 || idx >= bytes.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                Ok(Value::Int(@bigint.BigInt::from_int(bytes[idx])))
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::ByteArray(bytes) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) =>
          match slice_indices_from_values(bytes.length(), start, stop, step) {
            Ok(indices) =>
              Ok(Value::ByteArray(slice_ints_by_indices(bytes, indices)))
            Err(err) => Err(err)
          }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, bytes.length())
              if idx < 0 || idx >= bytes.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                Ok(Value::Int(@bigint.BigInt::from_int(bytes[idx])))
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::MemoryView(bytes) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) =>
          match slice_indices_from_values(bytes.length(), start, stop, step) {
            Ok(indices) => {
              let step_bigint = match step {
                Value::None => 1N
                Value::Int(v) => v
                Value::Bool(v) => if v { 1N } else { 0N }
                _ => 1N
              }
              let sliced = Value::MemoryView(
                slice_ints_by_indices(bytes, indices),
              )
              if step_bigint != 1N {
                let dict : Array[(String, Value)] = [
                  ("__mpython_bytes__", sliced),
                  ("__mpython_contiguous__", Value::Bool(false)),
                ]
                Ok(
                  Value::Instance(InstanceValue::{
                    class: builtin_class_from_name("memoryview", builtins),
                    dict,
                  }),
                )
              } else {
                Ok(sliced)
              }
            }
            Err(err) => Err(err)
          }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, bytes.length())
              if idx < 0 || idx >= bytes.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                Ok(Value::Int(@bigint.BigInt::from_int(bytes[idx])))
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Instance(inst) => {
      // Treat tuple/list subclasses as sequences when they carry the internal
      // storage. This is required for namedtuple (unittest logging watcher).
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(items)) =>
          return get_subscr_value(
            Value::List(items),
            index,
            globals,
            builtins,
            io,
          )
        _ => ()
      }
      match get_named_value(inst.dict, tuple_storage_name) {
        Some(Value::Tuple(items)) =>
          return get_subscr_value(
            Value::Tuple(items),
            index,
            globals,
            builtins,
            io,
          )
        _ => ()
      }
      match get_attr_from_value(target, "__getitem__", globals, builtins, io) {
        Ok(getitem) =>
          call_callable_with_env(getitem, [index], [], globals, builtins, io)
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "'" +
                  type_name_from_value(target) +
                  "' object is not subscriptable",
                ),
              )
            _ => Err(err)
          }
      }
    }
    Value::Function(func) => {
      // Support `list[int]`-style generic aliases for builtin collection types.
      if func.body.length() == 0 && is_generic_alias_origin_name(func.name) {
        let args = match index {
          Value::Tuple(values) => values
          _ => [index]
        }
        return Ok(
          make_generic_alias(
            Value::Class(builtin_class_from_name(func.name, builtins)),
            args,
          ),
        )
      }
      // PEP 560: if a class (or builtin type modelled as Value::Function)
      // defines __class_getitem__, use it for subscription.
      match
        get_attr_from_value(target, "__class_getitem__", globals, builtins, io) {
        Ok(class_getitem) => {
          let args = match class_getitem {
            Value::BoundMethod(_) => [index]
            Value::Function(_) => [target, index]
            Value::Class(_) => [target, index]
            _ => [index]
          }
          call_callable_with_env(class_getitem, args, [], globals, builtins, io)
        }
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "subscript requires sequence".to_string(),
                ),
              )
            _ => Err(err)
          }
      }
    }
    Value::Class(klass) => {
      if is_generic_alias_origin_name(klass.name) {
        let args = match index {
          Value::Tuple(values) => values
          _ => [index]
        }
        return Ok(make_generic_alias(Value::Class(klass), args))
      }
      match
        get_attr_from_value(target, "__class_getitem__", globals, builtins, io) {
        Ok(class_getitem) => {
          let args = match class_getitem {
            Value::BoundMethod(_) => [index]
            Value::Function(_) => [target, index]
            Value::Class(_) => [target, index]
            _ => [index]
          }
          call_callable_with_env(class_getitem, args, [], globals, builtins, io)
        }
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "subscript requires sequence".to_string(),
                ),
              )
            _ => Err(err)
          }
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "subscript requires sequence".to_string(),
        ),
      )
  }
}

///|
fn set_subscr_value(
  target : Value,
  index : Value,
  value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  fn slice_parts_from_value(value : Value) -> (Value, Value, Value)? {
    match value {
      Value::Instance(inst) if inst.class.name == "slice" => {
        let start = match get_named_value(inst.dict, "start") {
          Some(v) => v
          None => Value::None
        }
        let stop = match get_named_value(inst.dict, "stop") {
          Some(v) => v
          None => Value::None
        }
        let step = match get_named_value(inst.dict, "step") {
          Some(v) => v
          None => Value::None
        }
        Some((start, stop, step))
      }
      _ => None
    }
  }

  match target {
    Value::List(items) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) => {
          let indices = match
            slice_indices_from_values(items.length(), start, stop, step) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let (start_i, end_i, step_i) = match
            slice_params_from_values(items.length(), start, stop, step) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let new_items = match iterable_values(value) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if step_i == 1 {
            let merged : Array[Value] = []
            for i = 0; i < start_i; i = i + 1 {
              merged.push(items[i])
            }
            for item in new_items {
              merged.push(item)
            }
            for i = end_i; i < items.length(); i = i + 1 {
              merged.push(items[i])
            }
            replace_array_values(items, merged)
            Ok(())
          } else {
            if new_items.length() != indices.length() {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "ValueError: attempt to assign sequence of size " +
                  new_items.length().to_string() +
                  " to extended slice of size " +
                  indices.length().to_string(),
                ),
              )
            }
            for i = 0; i < indices.length(); i = i + 1 {
              items[indices[i]] = new_items[i]
            }
            Ok(())
          }
        }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, items.length())
              if idx < 0 || idx >= items.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "list assignment index out of range".to_string(),
                  ),
                )
              } else {
                items[idx] = value
                Ok(())
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Dict(pairs) => {
      let _ = match dict_set_item(pairs, index, value) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(())
    }
    Value::ByteArray(bytes) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) => {
          let indices = match
            slice_indices_from_values(bytes.length(), start, stop, step) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let (start_i, end_i, step_i) = match
            slice_params_from_values(bytes.length(), start, stop, step) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let new_bytes = match value {
            Value::Bytes(items)
            | Value::ByteArray(items)
            | Value::MemoryView(items) => Ok(items)
            _ =>
              bytes_from_iterable(
                "bytearray.__setitem__", value, globals, builtins, io,
              )
          }
          let new_bytes = match new_bytes {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if step_i == 1 {
            let merged : Array[Int] = []
            for i = 0; i < start_i; i = i + 1 {
              merged.push(bytes[i])
            }
            for b in new_bytes {
              merged.push(b & 0xFF)
            }
            for i = end_i; i < bytes.length(); i = i + 1 {
              merged.push(bytes[i])
            }
            while bytes.length() > 0 {
              let _ = bytes.remove(bytes.length() - 1)

            }
            for b in merged {
              bytes.push(b)
            }
            Ok(())
          } else {
            if new_bytes.length() != indices.length() {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "ValueError: attempt to assign sequence of size " +
                  new_bytes.length().to_string() +
                  " to extended slice of size " +
                  indices.length().to_string(),
                ),
              )
            }
            for i = 0; i < indices.length(); i = i + 1 {
              bytes[indices[i]] = new_bytes[i] & 0xFF
            }
            Ok(())
          }
        }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, bytes.length())
              if idx < 0 || idx >= bytes.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "bytearray index out of range".to_string(),
                  ),
                )
              } else {
                let b = match byte_from_value("bytearray.__setitem__", value) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                bytes[idx] = b
                Ok(())
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Instance(inst) => {
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(items)) =>
          return set_subscr_value(
            Value::List(items),
            index,
            value,
            globals,
            builtins,
            io,
          )
        _ => ()
      }
      match get_named_value(inst.dict, tuple_storage_name) {
        Some(Value::Tuple(_)) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "'" +
              type_name_from_value(target) +
              "' object does not support item assignment",
            ),
          )
        _ => ()
      }
      match get_attr_from_value(target, "__setitem__", globals, builtins, io) {
        Ok(setitem) =>
          match
            call_callable_with_env(
              setitem,
              [index, value],
              [],
              globals,
              builtins,
              io,
            ) {
            Ok(_) => Ok(())
            Err(err) => Err(err)
          }
        Err(err) =>
          match err.kind {
            RuntimeErrorKind::Attribute =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "'" +
                  type_name_from_value(target) +
                  "' object does not support item assignment",
                ),
              )
            _ => Err(err)
          }
      }
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object does not support item assignment".to_string(),
        ),
      )
  }
}

///|
fn delete_subscr_value(
  target : Value,
  index : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Unit, RuntimeError] {
  fn slice_parts_from_value(value : Value) -> (Value, Value, Value)? {
    match value {
      Value::Instance(inst) if inst.class.name == "slice" => {
        let start = match get_named_value(inst.dict, "start") {
          Some(v) => v
          None => Value::None
        }
        let stop = match get_named_value(inst.dict, "stop") {
          Some(v) => v
          None => Value::None
        }
        let step = match get_named_value(inst.dict, "step") {
          Some(v) => v
          None => Value::None
        }
        Some((start, stop, step))
      }
      _ => None
    }
  }

  match target {
    Value::List(items) =>
      match slice_parts_from_value(index) {
        Some((start, stop, step)) => {
          let indices = match
            slice_indices_from_values(items.length(), start, stop, step) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          if indices.length() == 0 {
            return Ok(())
          }
          let remove_mask : Array[Bool] = []
          for i = 0; i < items.length(); i = i + 1 {
            remove_mask.push(false)
          }
          for idx in indices {
            if idx >= 0 && idx < remove_mask.length() {
              remove_mask[idx] = true
            }
          }
          let next : Array[Value] = []
          for i = 0; i < items.length(); i = i + 1 {
            if !remove_mask[i] {
              next.push(items[i])
            }
          }
          replace_array_values(items, next)
          Ok(())
        }
        None =>
          match index_from_value(index, 0) {
            Ok(i) => {
              let idx = normalize_index(i, items.length())
              if idx < 0 || idx >= items.length() {
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Index,
                    "index out of range".to_string(),
                  ),
                )
              } else {
                let _ = items.remove(idx)
                Ok(())
              }
            }
            Err(err) => Err(err)
          }
      }
    Value::Dict(pairs) => {
      let removed = match dict_delete_key(pairs, index) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if removed {
        Ok(())
      } else {
        Err(
          make_runtime_error(RuntimeErrorKind::Key, "key not found".to_string()),
        )
      }
    }
    Value::Instance(inst) => {
      match get_named_value(inst.dict, list_storage_name) {
        Some(Value::List(items)) =>
          return delete_subscr_value(
            Value::List(items),
            index,
            globals,
            builtins,
            io,
          )
        _ => ()
      }
      match get_named_value(inst.dict, tuple_storage_name) {
        Some(Value::Tuple(_)) =>
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "object does not support item deletion".to_string(),
            ),
          )
        _ => ()
      }
      let delitem = match
        get_attr_from_value(target, "__delitem__", globals, builtins, io) {
        Ok(v) => v
        Err(err) =>
          return match err.kind {
            RuntimeErrorKind::Attribute =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "object does not support item deletion".to_string(),
                ),
              )
            _ => Err(err)
          }
      }
      let _ = match
        call_callable_with_env(delitem, [index], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(())
    }
    Value::ByteArray(_) => {
      let delitem = match
        get_attr_from_value(target, "__delitem__", globals, builtins, io) {
        Ok(v) => v
        Err(err) =>
          return match err.kind {
            RuntimeErrorKind::Attribute =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "object does not support item deletion".to_string(),
                ),
              )
            _ => Err(err)
          }
      }
      let _ = match
        call_callable_with_env(delitem, [index], [], globals, builtins, io) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(())
    }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "object does not support item deletion".to_string(),
        ),
      )
  }
}

///|

///|
fn vm_unwind_return(stack : Array[Value], blocks : Array[VmBlock]) -> Int? {
  while blocks.length() > 0 {
    let blk = blocks.remove(blocks.length() - 1)
    while stack.length() > blk.stack_height {
      let _ = stack.remove(stack.length() - 1)

    }
    match blk.kind {
      VmBlockKind::Finally(target) => {
        // Mark as active so exceptions inside the finally do not re-enter it.
        blocks.push(VmBlock::{
          kind: VmBlockKind::FinallyHandler,
          stack_height: stack.length(),
          pushed_exc: false,
          star_base_err: None,
          star_remaining_group: None,
          star_active_match: false,
        })
        return Some(target)
      }
      // A return bypasses exception handlers; just drop them.
      VmBlockKind::Except(_)
      | VmBlockKind::ExceptHandler
      | VmBlockKind::FinallyHandler => {
        if blk.pushed_exc {
          let _ = active_exception_stack.val.pop()

        }
        continue
      }
    }
  }
  None
}

///|
pub fn bc_exec(
  code : BcCode,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  fn refresh_raised_exception_traceback(
    inst : InstanceValue,
    err : RuntimeError,
  ) -> RuntimeError {
    // `raise exc` uses the raise site for outer frames, but when raising an
    // already-caught exception instance that carries an existing traceback, we
    // must preserve its original tail (see CPython's test_traceback).
    let current_tb = snapshot_traceback()
    let current_envs = snapshot_frame_env_stack()
    let has_existing_tb = match get_named_value(inst.dict, "__traceback__") {
      Some(Value::None) => false
      Some(_) => true
      None => false
    }
    if has_existing_tb {
      // `runtime_error_from_exception_instance` uses the instance's traceback
      // when present; treat that as the tail we need to preserve.
      let tail = err.traceback
      let combined : Array[TracebackFrame] = []
      for f in current_tb {
        combined.push(f)
      }
      for f in tail {
        combined.push(f)
      }
      RuntimeError::{
        kind: err.kind,
        message: err.message,
        span: err.span,
        traceback: combined,
        traceback_envs: current_envs,
        exc_type: err.exc_type,
        exc_args: err.exc_args,
        exc_value: err.exc_value,
        exc_cause: err.exc_cause,
        exc_context: err.exc_context,
        exc_suppress_context: err.exc_suppress_context,
      }
    } else {
      RuntimeError::{
        kind: err.kind,
        message: err.message,
        span: err.span,
        traceback: current_tb,
        traceback_envs: current_envs,
        exc_type: err.exc_type,
        exc_args: err.exc_args,
        exc_value: err.exc_value,
        exc_cause: err.exc_cause,
        exc_context: err.exc_context,
        exc_suppress_context: err.exc_suppress_context,
      }
    }
  }

  fn prepend_current_callsite_frame(
    err : RuntimeError,
    callsite_span : Span?,
  ) -> RuntimeError {
    // When an exception bubbles out of a callee back to its caller (even if the
    // caller catches it), CPython adds the caller frame (at the call site) to
    // the traceback chain. Do the same here so stdlib formatting (notably
    // ExceptionGroup reporting in Lib/test/test_traceback.py) matches.
    let active_frames = active_frame_stack.val
    if active_frames.length() == 0 {
      return err
    }
    let caller_raw = active_frames[active_frames.length() - 1]
    let caller_frame = match callsite_span {
      Some(s) => {
        let mut width = s.end - s.start
        if width <= 0 {
          width = 1
        }
        let end_column = if width > 512 { 0 } else { s.column + width }
        TracebackFrame::{
          name: caller_raw.name,
          filename: caller_raw.filename,
          line: s.line,
          column: s.column,
          end_column,
        }
      }
      None => caller_raw
    }
    if err.traceback.length() > 0 {
      let head = err.traceback[0]
      if head.name == caller_frame.name &&
        head.filename == caller_frame.filename &&
        head.line == caller_frame.line &&
        // Avoid duplicating frames for errors raised directly in the caller
        // frame (e.g. builtins). For recursive unwinding, we still want
        // repeated frames so traceback.py can shrink them.
        err.traceback.length() == 1 &&
        err.exc_type != "RecursionError" {
        return err
      }
    }
    let combined_frames : Array[TracebackFrame] = []
    combined_frames.push(caller_frame)
    for f in err.traceback {
      combined_frames.push(f)
    }
    let combined_envs : Array[TracebackEnv] = []
    if err.traceback_envs.length() == err.traceback.length() {
      let env_stack = active_frame_env_stack.val
      if env_stack.length() > 0 {
        combined_envs.push(env_stack[env_stack.length() - 1])
        for env in err.traceback_envs {
          combined_envs.push(env)
        }
      }
    }
    RuntimeError::{
      kind: err.kind,
      message: err.message,
      span: err.span,
      traceback: combined_frames,
      traceback_envs: if combined_envs.length() == combined_frames.length() {
        combined_envs
      } else {
        err.traceback_envs
      },
      exc_type: err.exc_type,
      exc_args: err.exc_args,
      exc_value: err.exc_value,
      exc_cause: err.exc_cause,
      exc_context: err.exc_context,
      exc_suppress_context: err.exc_suppress_context,
    }
  }

  let stack : Array[Value] = []
  let blocks : Array[VmBlock] = []
  let mut pending_exc : RuntimeError? = None
  let mut pending_return : Value? = None
  let mut pending_jump_target : Int? = None
  let mut pending_jump_count = 0
  let mut pc = 0
  fn find_current_except_handler_block(blocks : Array[VmBlock]) -> Int? {
    let mut i = blocks.length()
    while i > 0 {
      i = i - 1
      match blocks[i].kind {
        VmBlockKind::ExceptHandler => return Some(i)
        _ => ()
      }
    }
    None
  }

  fn find_except_star_handler_block(blocks : Array[VmBlock]) -> Int? {
    let mut i = blocks.length()
    while i > 0 {
      i = i - 1
      match blocks[i].kind {
        VmBlockKind::ExceptHandler =>
          match blocks[i].star_base_err {
            Some(_) => return Some(i)
            None => ()
          }
        _ => ()
      }
    }
    None
  }

  fn ensure_except_star_handler_classes(
    handler_classes : Array[ClassValue],
  ) -> Result[Unit, RuntimeError] {
    for klass in handler_classes {
      let mro = match class_mro(klass) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for cls in mro {
        if cls.name == "BaseExceptionGroup" || cls.name == "ExceptionGroup" {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "except* cannot catch exception groups".to_string(),
            ),
          )
        }
      }
    }
    Ok(())
  }

  while pc < code.ops.length() {
    let op = code.ops[pc]
    let span = code.spans[pc]
    match span {
      Some(s) => push_active_span(s)
      None => ()
    }
    let mut next_pc = pc + 1
    let step : Result[Unit, RuntimeError] = match op {
      BcOp::Nop => Ok(())
      BcOp::PopTop =>
        match pop_stack(stack) {
          Ok(_) => Ok(())
          Err(err) => Err(err)
        }
      BcOp::DupTop =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          stack.push(stack[stack.length() - 1])
          Ok(())
        }
      BcOp::RotTwo =>
        if stack.length() < 2 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let b = stack.remove(stack.length() - 1)
          let a = stack.remove(stack.length() - 1)
          // [a, b] -> [b, a]
          stack.push(b)
          stack.push(a)
          Ok(())
        }
      BcOp::RotThree =>
        if stack.length() < 3 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let c = stack.remove(stack.length() - 1)
          let b = stack.remove(stack.length() - 1)
          let a = stack.remove(stack.length() - 1)
          // [a, b, c] -> [c, a, b]
          stack.push(c)
          stack.push(a)
          stack.push(b)
          Ok(())
        }
      BcOp::LoadConst(i) => {
        stack.push(code.consts[i])
        Ok(())
      }
      BcOp::LoadName(i) => {
        let name = code.names[i]
        match lookup_name_value(name, locals, globals, builtins) {
          Ok(v) => {
            stack.push(v)
            Ok(())
          }
          Err(err) => Err(err)
        }
      }
      BcOp::StoreName(i) => {
        let name = code.names[i]
        match pop_stack(stack) {
          Ok(v) => {
            set_scoped_value(locals, globals, name, v)
            Ok(())
          }
          Err(err) => Err(err)
        }
      }
      BcOp::DeleteName(i) => {
        let name = code.names[i]
        if scope_name_is_nonlocal(name) {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "SyntaxError: can't delete nonlocal".to_string(),
            ),
          )
        }
        match delete_scoped_value(locals, globals, name) {
          Ok(true) => Ok(())
          Ok(false) =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Name,
                "name '" + name + "' is not defined",
              ),
            )
          Err(err) => Err(err)
        }
      }
      BcOp::LoadAttr(i) => {
        let attr = code.names[i]
        match pop_stack(stack) {
          Ok(target) =>
            match get_attr_from_value(target, attr, globals, builtins, io) {
              Ok(v) => {
                stack.push(v)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      }
      BcOp::StoreAttr(i) => {
        let attr = code.names[i]
        match pop_stack(stack) {
          Ok(value) =>
            match pop_stack(stack) {
              Ok(target) =>
                match
                  set_attr_on_value(target, attr, value, globals, builtins, io) {
                  Ok(_) => Ok(())
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      }
      BcOp::DeleteAttr(i) => {
        let attr = code.names[i]
        match pop_stack(stack) {
          Ok(target) =>
            delete_attr_on_value(target, attr, globals, builtins, io)
          Err(err) => Err(err)
        }
      }
      BcOp::LoadSubscr =>
        match pop_stack(stack) {
          Ok(index) =>
            match pop_stack(stack) {
              Ok(target) =>
                match get_subscr_value(target, index, globals, builtins, io) {
                  Ok(v) => {
                    stack.push(v)
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::StoreSubscr =>
        match pop_stack(stack) {
          Ok(value) =>
            match pop_stack(stack) {
              Ok(index) =>
                match pop_stack(stack) {
                  Ok(target) =>
                    match
                      set_subscr_value(
                        target, index, value, globals, builtins, io,
                      ) {
                      Ok(_) => Ok(())
                      Err(err) => Err(err)
                    }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::DeleteSubscr =>
        match pop_stack(stack) {
          Ok(index) =>
            match pop_stack(stack) {
              Ok(target) =>
                delete_subscr_value(target, index, globals, builtins, io)
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::BuildTuple(n) =>
        match pop_n(stack, n) {
          Ok(values) => {
            stack.push(Value::Tuple(values))
            Ok(())
          }
          Err(err) => Err(err)
        }
      BcOp::BuildList(n) =>
        match pop_n(stack, n) {
          Ok(values) => {
            stack.push(Value::List(values))
            Ok(())
          }
          Err(err) => Err(err)
        }
      BcOp::BuildMap(pair_count) =>
        match pop_n(stack, pair_count * 2) {
          Ok(values) => {
            let out : Array[(Value, Value)] = []
            let mut err_opt : RuntimeError? = None
            for i = 0; i < values.length(); i = i + 2 {
              match dict_set_item(out, values[i], values[i + 1]) {
                Ok(_) => ()
                Err(err) => {
                  err_opt = Some(err)
                  break
                }
              }
            }
            match err_opt {
              Some(err) => Err(err)
              None => {
                stack.push(Value::Dict(out))
                Ok(())
              }
            }
          }
          Err(err) => Err(err)
        }
      BcOp::BuildSet(n) =>
        match pop_n(stack, n) {
          Ok(values) => {
            let out : Array[Value] = []
            let mut err_opt : RuntimeError? = None
            for v in values {
              match set_add_unique(out, v) {
                Ok(_) => ()
                Err(err) => {
                  err_opt = Some(err)
                  break
                }
              }
            }
            match err_opt {
              Some(err) => Err(err)
              None => {
                stack.push(Value::Set(out))
                Ok(())
              }
            }
          }
          Err(err) => Err(err)
        }
      BcOp::BuildSlice =>
        match pop_stack(stack) {
          Ok(step) =>
            match pop_stack(stack) {
              Ok(stop) =>
                match pop_stack(stack) {
                  Ok(start) => {
                    let dict : Array[(String, Value)] = []
                    dict.push(("start", start))
                    dict.push(("stop", stop))
                    dict.push(("step", step))
                    let klass = builtin_class_from_name("slice", builtins)
                    stack.push(
                      Value::Instance(InstanceValue::{ class: klass, dict }),
                    )
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::ListAppend =>
        match pop_stack(stack) {
          Ok(value) =>
            if stack.length() == 0 {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: ListAppend missing list".to_string(),
                ),
              )
            } else {
              let idx = stack.length() - 1
              match stack[idx] {
                Value::List(values) => {
                  values.push(value)
                  stack[idx] = Value::List(values)
                  Ok(())
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bytecode vm: ListAppend expects list".to_string(),
                    ),
                  )
              }
            }
          Err(err) => Err(err)
        }
      BcOp::ListExtend =>
        match pop_stack(stack) {
          Ok(iterable) =>
            if stack.length() == 0 {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: ListExtend missing list".to_string(),
                ),
              )
            } else {
              let idx = stack.length() - 1
              match stack[idx] {
                Value::List(values) =>
                  match iterable_values(iterable) {
                    Ok(items) => {
                      for item in items {
                        values.push(item)
                      }
                      stack[idx] = Value::List(values)
                      Ok(())
                    }
                    Err(err) => Err(err)
                  }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bytecode vm: ListExtend expects list".to_string(),
                    ),
                  )
              }
            }
          Err(err) => Err(err)
        }
      BcOp::SetAdd =>
        match pop_stack(stack) {
          Ok(value) =>
            if stack.length() == 0 {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: SetAdd missing set".to_string(),
                ),
              )
            } else {
              let idx = stack.length() - 1
              match stack[idx] {
                Value::Set(values) =>
                  match set_add_unique(values, value) {
                    Ok(_) => {
                      stack[idx] = Value::Set(values)
                      Ok(())
                    }
                    Err(err) => Err(err)
                  }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bytecode vm: SetAdd expects set".to_string(),
                    ),
                  )
              }
            }
          Err(err) => Err(err)
        }
      BcOp::SetUpdate =>
        match pop_stack(stack) {
          Ok(iterable) =>
            if stack.length() == 0 {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: SetUpdate missing set".to_string(),
                ),
              )
            } else {
              let idx = stack.length() - 1
              match stack[idx] {
                Value::Set(values) =>
                  match iterable_values(iterable) {
                    Ok(items) => {
                      let mut err_opt : RuntimeError? = None
                      for item in items {
                        match set_add_unique(values, item) {
                          Ok(_) => ()
                          Err(err) => {
                            err_opt = Some(err)
                            break
                          }
                        }
                      }
                      match err_opt {
                        Some(err) => Err(err)
                        None => {
                          stack[idx] = Value::Set(values)
                          Ok(())
                        }
                      }
                    }
                    Err(err) => Err(err)
                  }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bytecode vm: SetUpdate expects set".to_string(),
                    ),
                  )
              }
            }
          Err(err) => Err(err)
        }
      BcOp::DictSetItem =>
        match pop_stack(stack) {
          Ok(value) =>
            match pop_stack(stack) {
              Ok(key) =>
                if stack.length() == 0 {
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "bytecode vm: DictSetItem missing dict".to_string(),
                    ),
                  )
                } else {
                  let idx = stack.length() - 1
                  match stack[idx] {
                    Value::Dict(pairs) =>
                      match dict_set_item(pairs, key, value) {
                        Ok(_) => {
                          stack[idx] = Value::Dict(pairs)
                          Ok(())
                        }
                        Err(err) => Err(err)
                      }
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "bytecode vm: DictSetItem expects dict".to_string(),
                        ),
                      )
                  }
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::DictUpdate =>
        match pop_stack(stack) {
          Ok(mapping) =>
            if stack.length() == 0 {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: DictUpdate missing dict".to_string(),
                ),
              )
            } else {
              let idx = stack.length() - 1
              match stack[idx] {
                Value::Dict(out) => {
                  let update_result : Result[Unit, RuntimeError] = match
                    mapping {
                    Value::Dict(pairs) => {
                      let mut err_opt : RuntimeError? = None
                      for pair in pairs {
                        match dict_set_item(out, pair.0, pair.1) {
                          Ok(_) => ()
                          Err(err) => {
                            err_opt = Some(err)
                            break
                          }
                        }
                      }
                      match err_opt {
                        Some(err) => Err(err)
                        None => Ok(())
                      }
                    }
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "dict update sequence element has wrong length".to_string(),
                        ),
                      )
                  }
                  match update_result {
                    Ok(_) => {
                      stack[idx] = Value::Dict(out)
                      Ok(())
                    }
                    Err(err) => Err(err)
                  }
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bytecode vm: DictUpdate expects dict".to_string(),
                    ),
                  )
              }
            }
          Err(err) => Err(err)
        }
      BcOp::KwListExtendFromDict =>
        match pop_stack(stack) {
          Ok(mapping) =>
            if stack.length() == 0 {
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: KwListExtendFromDict missing list".to_string(),
                ),
              )
            } else {
              let idx = stack.length() - 1
              match stack[idx] {
                Value::List(values) => {
                  let extend_result : Result[Unit, RuntimeError] = match
                    mapping {
                    Value::Dict(pairs) => {
                      let mut err_opt : RuntimeError? = None
                      for pair in pairs {
                        match pair.0 {
                          Value::Str(name) =>
                            values.push(
                              Value::Tuple([Value::Str(name), pair.1]),
                            )
                          _ => {
                            err_opt = Some(
                              make_runtime_error(
                                RuntimeErrorKind::Type,
                                "keywords must be strings".to_string(),
                              ),
                            )
                            break
                          }
                        }
                      }
                      match err_opt {
                        Some(e) => Err(e)
                        None => Ok(())
                      }
                    }
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "keywords must be strings".to_string(),
                        ),
                      )
                  }
                  match extend_result {
                    Ok(_) => {
                      stack[idx] = Value::List(values)
                      Ok(())
                    }
                    Err(err) => Err(err)
                  }
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "bytecode vm: KwListExtendFromDict expects list".to_string(),
                    ),
                  )
              }
            }
          Err(err) => Err(err)
        }
      BcOp::ListToTuple =>
        match pop_stack(stack) {
          Ok(v) =>
            match v {
              Value::List(values) => {
                stack.push(Value::Tuple(values))
                Ok(())
              }
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "bytecode vm: ListToTuple expects list".to_string(),
                  ),
                )
            }
          Err(err) => Err(err)
        }
      BcOp::EvalFString =>
        match pop_stack(stack) {
          Ok(v) =>
            match v {
              Value::Str(text) =>
                match eval_fstring_text(text, locals, globals, builtins, io) {
                  Ok(out) => {
                    stack.push(Value::Str(out))
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "bytecode vm: EvalFString expects a string".to_string(),
                  ),
                )
            }
          Err(err) => Err(err)
        }
      BcOp::UnpackSequence(n) =>
        match pop_stack(stack) {
          Ok(assigned) => {
            let items = match assigned {
              Value::Tuple(values) => Ok(values)
              Value::List(values) => Ok(values)
              _ =>
                match iter_value_to_iterator(assigned, globals, builtins, io) {
                  Ok(iterator_value) => {
                    let acc : Array[Value] = []
                    let mut err_opt : RuntimeError? = None
                    while true {
                      match
                        iterator_next(
                          iterator_value,
                          None,
                          globals,
                          builtins,
                          io,
                        ) {
                        Ok(v) => acc.push(v)
                        Err(err) =>
                          if err.exc_type == "StopIteration" {
                            break
                          } else {
                            err_opt = Some(err)
                            break
                          }
                      }
                    }
                    match err_opt {
                      Some(e) => Err(e)
                      None => Ok(acc)
                    }
                  }
                  Err(err) =>
                    match err.kind {
                      RuntimeErrorKind::Type =>
                        if err.message == "object is not iterable" {
                          Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "cannot unpack non-iterable".to_string(),
                            ),
                          )
                        } else {
                          Err(err)
                        }
                      _ => Err(err)
                    }
                }
            }
            match items {
              Ok(values) =>
                if values.length() != n {
                  if values.length() < n {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "ValueError: not enough values to unpack (expected " +
                        n.to_string() +
                        ")",
                      ),
                    )
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "ValueError: too many values to unpack (expected " +
                        n.to_string() +
                        ")",
                      ),
                    )
                  }
                } else {
                  // Push in reverse so the first target consumes the first value.
                  let mut i = n
                  while i > 0 {
                    i -= 1
                    stack.push(values[i])
                  }
                  Ok(())
                }
              Err(err) => Err(err)
            }
          }
          Err(err) => Err(err)
        }
      BcOp::UnpackEx(before, after) =>
        match pop_stack(stack) {
          Ok(assigned) => {
            let items = match assigned {
              Value::Tuple(values) => Ok(values)
              Value::List(values) => Ok(values)
              _ =>
                match iter_value_to_iterator(assigned, globals, builtins, io) {
                  Ok(iterator_value) => {
                    let acc : Array[Value] = []
                    let mut err_opt : RuntimeError? = None
                    while true {
                      match
                        iterator_next(
                          iterator_value,
                          None,
                          globals,
                          builtins,
                          io,
                        ) {
                        Ok(v) => acc.push(v)
                        Err(err) =>
                          if err.exc_type == "StopIteration" {
                            break
                          } else {
                            err_opt = Some(err)
                            break
                          }
                      }
                    }
                    match err_opt {
                      Some(e) => Err(e)
                      None => Ok(acc)
                    }
                  }
                  Err(err) =>
                    match err.kind {
                      RuntimeErrorKind::Type =>
                        if err.message == "object is not iterable" {
                          Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "cannot unpack non-iterable".to_string(),
                            ),
                          )
                        } else {
                          Err(err)
                        }
                      _ => Err(err)
                    }
                }
            }
            match items {
              Ok(values) => {
                let min_expected = before + after
                if values.length() < min_expected {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: not enough values to unpack (expected at least " +
                      min_expected.to_string() +
                      ")",
                    ),
                  )
                }
                let out : Array[Value] = []
                // leading fixed items
                for i = 0; i < before; i = i + 1 {
                  out.push(values[i])
                }
                // starred captures the middle into a list
                let mid_end = values.length() - after
                let mid : Array[Value] = []
                for i = before; i < mid_end; i = i + 1 {
                  mid.push(values[i])
                }
                out.push(Value::List(mid))
                // trailing fixed items
                for i = mid_end; i < values.length(); i = i + 1 {
                  out.push(values[i])
                }
                // Push in reverse so the first target consumes the first value.
                let mut i = out.length()
                while i > 0 {
                  i -= 1
                  stack.push(out[i])
                }
                Ok(())
              }
              Err(err) => Err(err)
            }
          }
          Err(err) => Err(err)
        }
      BcOp::GetIter =>
        match pop_stack(stack) {
          Ok(value) =>
            match iter_value_to_iterator(value, globals, builtins, io) {
              Ok(iter) => {
                stack.push(iter)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::ForIter(target) =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let iter = stack[stack.length() - 1]
          match iterator_next(iter, None, globals, builtins, io) {
            Ok(item) => {
              // Keep iterator on stack; push current item.
              stack.push(item)
              Ok(())
            }
            Err(err) =>
              if err.exc_type == "StopIteration" {
                // Pop iterator and jump out of the loop.
                let _ = stack.remove(stack.length() - 1)
                next_pc = target
                Ok(())
              } else {
                Err(err)
              }
          }
        }
      BcOp::Unary(op) =>
        match pop_stack(stack) {
          Ok(value) =>
            match unary_op_value(op, value, globals, builtins, io) {
              Ok(out) => {
                stack.push(out)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Binary(op) =>
        match pop_stack(stack) {
          Ok(right) =>
            match pop_stack(stack) {
              Ok(left) =>
                match
                  eval_binary_op_values(op, left, right, globals, builtins, io) {
                  Ok(out) => {
                    stack.push(out)
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Compare(op) =>
        match pop_stack(stack) {
          Ok(right) =>
            match pop_stack(stack) {
              Ok(left) =>
                match
                  compare_values_with_env(
                    op, left, right, globals, builtins, io,
                  ) {
                  Ok(ok) => {
                    stack.push(Value::Bool(ok))
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Jump(target) => {
        next_pc = target
        Ok(())
      }
      BcOp::UnwindJump(target, n) => {
        // `break`/`continue` in a `finally` suite must override any pending
        // return/exception being unwound into this handler.
        if blocks.length() > 0 {
          let top = blocks[blocks.length() - 1]
          match top.kind {
            VmBlockKind::FinallyHandler => {
              pending_exc = None
              pending_return = None
              pending_jump_target = None
              pending_jump_count = 0
            }
            _ => ()
          }
        }
        if n <= 0 {
          next_pc = target
          Ok(())
        } else {
          pending_jump_target = Some(target)
          pending_jump_count = n
          match vm_unwind_return(stack, blocks) {
            Some(handler) => {
              next_pc = handler
              Ok(())
            }
            None => {
              pending_jump_target = None
              pending_jump_count = 0
              next_pc = target
              Ok(())
            }
          }
        }
      }
      BcOp::JumpIfFalse(target) =>
        match pop_stack(stack) {
          Ok(v) =>
            match truthy_from_value_with_env(v, globals, builtins, io) {
              Ok(ok) => {
                if !ok {
                  next_pc = target
                }
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::JumpIfTrue(target) =>
        match pop_stack(stack) {
          Ok(v) =>
            match truthy_from_value_with_env(v, globals, builtins, io) {
              Ok(ok) => {
                if ok {
                  next_pc = target
                }
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::JumpIfFalseOrPop(target) =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let v = stack[stack.length() - 1]
          match truthy_from_value_with_env(v, globals, builtins, io) {
            Ok(ok) => {
              if !ok {
                next_pc = target
              } else {
                let _ = stack.remove(stack.length() - 1)

              }
              Ok(())
            }
            Err(err) => Err(err)
          }
        }
      BcOp::JumpIfTrueOrPop(target) =>
        if stack.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: stack underflow".to_string(),
            ),
          )
        } else {
          let v = stack[stack.length() - 1]
          match truthy_from_value_with_env(v, globals, builtins, io) {
            Ok(ok) => {
              if ok {
                next_pc = target
              } else {
                let _ = stack.remove(stack.length() - 1)

              }
              Ok(())
            }
            Err(err) => Err(err)
          }
        }
      BcOp::SetupExcept(target) => {
        blocks.push(VmBlock::{
          kind: VmBlockKind::Except(target),
          stack_height: stack.length(),
          pushed_exc: false,
          star_base_err: None,
          star_remaining_group: None,
          star_active_match: false,
        })
        Ok(())
      }
      BcOp::SetupFinally(target) => {
        blocks.push(VmBlock::{
          kind: VmBlockKind::Finally(target),
          stack_height: stack.length(),
          pushed_exc: false,
          star_base_err: None,
          star_remaining_group: None,
          star_active_match: false,
        })
        Ok(())
      }
      BcOp::PopExcept =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::Except(_) => Ok(())
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: PopExcept on non-except block".to_string(),
                ),
              )
          }
        }
      BcOp::EnterFinally(target) =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::Finally(_) => {
              blocks.push(VmBlock::{
                kind: VmBlockKind::FinallyHandler,
                stack_height: blk.stack_height,
                pushed_exc: false,
                star_base_err: None,
                star_remaining_group: None,
                star_active_match: false,
              })
              next_pc = target
              Ok(())
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: EnterFinally on non-finally block".to_string(),
                ),
              )
          }
        }
      BcOp::EndExcept =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::ExceptHandler => {
              if blk.pushed_exc {
                let _ = active_exception_stack.val.pop()

              }
              pending_exc = None
              Ok(())
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: EndExcept on non-handler block".to_string(),
                ),
              )
          }
        }
      BcOp::EndFinally =>
        if blocks.length() == 0 {
          Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: block underflow".to_string(),
            ),
          )
        } else {
          let blk = blocks.remove(blocks.length() - 1)
          match blk.kind {
            VmBlockKind::FinallyHandler => {
              if blk.pushed_exc {
                let _ = active_exception_stack.val.pop()

              }
              match pending_return {
                Some(v) =>
                  match vm_unwind_return(stack, blocks) {
                    Some(target) => {
                      next_pc = target
                      Ok(())
                    }
                    None => {
                      pending_return = None
                      if span is Some(_) {
                        pop_active_span()
                      }
                      return Ok(v)
                    }
                  }
                None =>
                  match pending_jump_target {
                    Some(target) => {
                      pending_jump_count = pending_jump_count - 1
                      if pending_jump_count <= 0 {
                        pending_jump_target = None
                        pending_jump_count = 0
                        next_pc = target
                        Ok(())
                      } else {
                        match vm_unwind_return(stack, blocks) {
                          Some(handler) => {
                            next_pc = handler
                            Ok(())
                          }
                          None => {
                            // Inconsistent unwind count; fall back to the jump.
                            pending_jump_target = None
                            pending_jump_count = 0
                            next_pc = target
                            Ok(())
                          }
                        }
                      }
                    }
                    None =>
                      match pending_exc {
                        Some(err) => Err(err)
                        None => Ok(())
                      }
                  }
              }
            }
            _ =>
              Err(
                make_runtime_error(
                  RuntimeErrorKind::Runtime,
                  "bytecode vm: EndFinally on non-handler block".to_string(),
                ),
              )
          }
        }
      BcOp::CheckExceptionMatch =>
        match pop_stack(stack) {
          Ok(exc_value) =>
            match pending_exc {
              Some(err) =>
                match handler_classes_from_value(exc_value, builtins) {
                  Ok(handler_classes) => {
                    let mut matches = false
                    let mut match_error : RuntimeError? = None
                    for klass in handler_classes {
                      match exception_matches_handler(err, klass, builtins) {
                        Ok(true) => {
                          matches = true
                          break
                        }
                        Ok(false) => ()
                        Err(e) => {
                          match_error = Some(e)
                          break
                        }
                      }
                    }
                    match match_error {
                      Some(e) => Err(e)
                      None => {
                        stack.push(Value::Bool(matches))
                        Ok(())
                      }
                    }
                  }
                  Err(e) => Err(e)
                }
              None =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: no pending exception".to_string(),
                  ),
                )
            }
          Err(err) => Err(err)
        }
      BcOp::LoadException =>
        match pending_exc {
          Some(err) => {
            let v = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            stack.push(v)
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::HasPendingException => {
        stack.push(Value::Bool(pending_exc is Some(_)))
        Ok(())
      }
      BcOp::ClearPendingException => {
        pending_exc = None
        Ok(())
      }
      BcOp::EnsureExceptionGroup =>
        match pending_exc {
          Some(err) => {
            let group_value = match
              exception_group_from_runtime_error(err, globals, builtins, io) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            match group_value {
              Value::Instance(inst) => {
                let group_err0 = vm_trim_runtime_error_for_active_handler(
                  runtime_error_from_exception_instance(inst),
                )
                // Avoid attaching PEP 657 caret positions to exception-group
                // dispatch locations (CPython does not show carets for these).
                let group_err = RuntimeError::{
                  kind: group_err0.kind,
                  message: group_err0.message,
                  span: None,
                  traceback: group_err0.traceback,
                  traceback_envs: group_err0.traceback_envs,
                  exc_type: group_err0.exc_type,
                  exc_args: group_err0.exc_args,
                  exc_value: group_err0.exc_value,
                  exc_cause: group_err0.exc_cause,
                  exc_context: group_err0.exc_context,
                  exc_suppress_context: group_err0.exc_suppress_context,
                }
                pending_exc = Some(group_err)
                if active_exception_stack.val.length() > 0 {
                  let _ = active_exception_stack.val.pop()
                  active_exception_stack.val.push(group_err)
                }
                Ok(())
              }
              _ => Ok(())
            }
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::ExceptStarInit =>
        match pending_exc {
          Some(err) => {
            let group_value = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            let idx_opt = find_current_except_handler_block(blocks)
            match idx_opt {
              Some(idx) => {
                let blk = blocks[idx]
                blocks[idx] = VmBlock::{
                  kind: blk.kind,
                  stack_height: blk.stack_height,
                  pushed_exc: blk.pushed_exc,
                  star_base_err: Some(err),
                  star_remaining_group: Some(group_value),
                  star_active_match: false,
                }
                Ok(())
              }
              None =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: ExceptStarInit without an active except handler".to_string(),
                  ),
                )
            }
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::ExceptStarMatch =>
        match pop_stack(stack) {
          Ok(exc_value) => {
            let idx_opt = find_except_star_handler_block(blocks)
            match idx_opt {
              None =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: ExceptStarMatch without ExceptStarInit".to_string(),
                  ),
                )
              Some(idx) => {
                let blk = blocks[idx]
                match blk.star_remaining_group {
                  None => {
                    stack.push(Value::Bool(false))
                    Ok(())
                  }
                  Some(group_value) =>
                    match handler_classes_from_value(exc_value, builtins) {
                      Ok(handler_classes) => {
                        let _ = match
                          ensure_except_star_handler_classes(handler_classes) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        let (matched_opt, remaining_opt) = match
                          exception_group_split_by_classes(
                            group_value, handler_classes, globals, builtins, io,
                          ) {
                          Ok(v) => v
                          Err(err) => return Err(err)
                        }
                        match matched_opt {
                          None => {
                            stack.push(Value::Bool(false))
                            Ok(())
                          }
                          Some(matched_group) => {
                            // Update remaining group state for subsequent handlers.
                            blocks[idx] = VmBlock::{
                              kind: blk.kind,
                              stack_height: blk.stack_height,
                              pushed_exc: blk.pushed_exc,
                              star_base_err: blk.star_base_err,
                              star_remaining_group: remaining_opt,
                              star_active_match: true,
                            }
                            // Set the current exception (pending + active) to the matched group.
                            let match_err0 = match matched_group {
                              Value::Instance(inst) =>
                                runtime_error_from_exception_instance(inst)
                              _ =>
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Type,
                                    "except* requires an ExceptionGroup".to_string(),
                                  ),
                                )
                            }
                            let match_err1 = vm_trim_runtime_error_for_active_handler(
                              match_err0,
                            )
                            let match_err = RuntimeError::{
                              kind: match_err1.kind,
                              message: match_err1.message,
                              span: None,
                              traceback: match_err1.traceback,
                              traceback_envs: match_err1.traceback_envs,
                              exc_type: match_err1.exc_type,
                              exc_args: match_err1.exc_args,
                              exc_value: match_err1.exc_value,
                              exc_cause: match_err1.exc_cause,
                              exc_context: match_err1.exc_context,
                              exc_suppress_context: match_err1.exc_suppress_context,
                            }
                            pending_exc = Some(match_err)
                            if active_exception_stack.val.length() == 0 {
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Runtime,
                                  "bytecode vm: no active exception".to_string(),
                                ),
                              )
                            }
                            let _ = active_exception_stack.val.pop()
                            active_exception_stack.val.push(match_err)
                            stack.push(Value::Bool(true))
                            Ok(())
                          }
                        }
                      }
                      Err(err) => Err(err)
                    }
                }
              }
            }
          }
          Err(err) => Err(err)
        }
      BcOp::ExceptStarEndHandler => {
        let idx_opt = find_except_star_handler_block(blocks)
        match idx_opt {
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: ExceptStarEndHandler without ExceptStarInit".to_string(),
              ),
            )
          Some(idx) => {
            let blk = blocks[idx]
            match (blk.star_base_err, blk.star_active_match) {
              (Some(base_err), true) => {
                // Restore the base exception as the active exception for subsequent handler matching.
                if active_exception_stack.val.length() == 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "bytecode vm: no active exception".to_string(),
                    ),
                  )
                }
                let _ = active_exception_stack.val.pop()
                active_exception_stack.val.push(base_err)
                blocks[idx] = VmBlock::{
                  kind: blk.kind,
                  stack_height: blk.stack_height,
                  pushed_exc: blk.pushed_exc,
                  star_base_err: blk.star_base_err,
                  star_remaining_group: blk.star_remaining_group,
                  star_active_match: false,
                }
              }
              _ => ()
            }
            // Keep pending exception cleared while running handler code.
            pending_exc = None
            stack.push(Value::Bool(blk.star_remaining_group is Some(_)))
            Ok(())
          }
        }
      }
      BcOp::ExceptStarRaiseRemaining => {
        let idx_opt = find_except_star_handler_block(blocks)
        match idx_opt {
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: ExceptStarRaiseRemaining without ExceptStarInit".to_string(),
              ),
            )
          Some(idx) => {
            let blk = blocks[idx]
            match blk.star_remaining_group {
              None =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: no remaining exception group".to_string(),
                  ),
                )
              Some(rem) => {
                let err0 = match rem {
                  Value::Instance(inst) =>
                    runtime_error_from_exception_instance(inst)
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "except* requires an ExceptionGroup".to_string(),
                      ),
                    )
                }
                // Avoid attaching the base exception as implicit context when re-raising
                // the remaining group: it is logically a continuation of the original.
                let err = if err0.exc_context is None && err0.exc_cause is None {
                  RuntimeError::{
                    kind: err0.kind,
                    message: err0.message,
                    span: err0.span,
                    traceback: err0.traceback,
                    traceback_envs: err0.traceback_envs,
                    exc_type: err0.exc_type,
                    exc_args: err0.exc_args,
                    exc_value: err0.exc_value,
                    exc_cause: err0.exc_cause,
                    exc_context: Some(Value::None),
                    exc_suppress_context: err0.exc_suppress_context,
                  }
                } else {
                  err0
                }
                Err(err)
              }
            }
          }
        }
      }
      BcOp::AssertFail =>
        match pop_stack(stack) {
          Ok(msg_value) =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "AssertionError: " + value_to_string(msg_value),
              ),
            )
          Err(err) => Err(err)
        }
      BcOp::AssertFailNone =>
        Err(
          make_runtime_error(
            RuntimeErrorKind::Runtime,
            "AssertionError: ".to_string(),
          ),
        )
      BcOp::LoadExceptionType =>
        match pending_exc {
          Some(err) => {
            let exc_value = exception_value_from_runtime_error(
              err, globals, builtins, io,
            )
            let exc_type_value = match exc_value {
              Value::Instance(inst) => Value::Class(inst.class)
              _ => Value::Str(err.exc_type)
            }
            stack.push(exc_type_value)
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::LoadExceptionTypeName =>
        match pending_exc {
          Some(err) => {
            stack.push(Value::Str(err.exc_type))
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::LoadExceptionTraceback =>
        match pending_exc {
          Some(err) => {
            stack.push(
              make_traceback_value_with_env(
                err.traceback,
                err.traceback_envs,
                frame_builtins_dict_from_builtins(builtins),
                err.span,
              ),
            )
            Ok(())
          }
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: no pending exception".to_string(),
              ),
            )
        }
      BcOp::Raise =>
        match pop_stack(stack) {
          Ok(exc_value) => {
            let context_err_opt = active_exception()
            match
              ensure_exception_instance_from_value(
                exc_value, globals, builtins, io,
              ) {
              Ok(inst_value) => {
                let err0_opt = match inst_value {
                  Value::Instance(inst) =>
                    Some(
                      refresh_raised_exception_traceback(
                        inst,
                        runtime_error_from_exception_instance(inst),
                      ),
                    )
                  _ => None
                }
                match err0_opt {
                  Some(err0) => {
                    let err1 = match (context_err_opt, err0.exc_context) {
                      (Some(ctx_err), None) => {
                        let ctx_value = exception_value_from_runtime_error(
                          ctx_err, globals, builtins, io,
                        )
                        RuntimeError::{
                          kind: err0.kind,
                          message: err0.message,
                          span: err0.span,
                          traceback: err0.traceback,
                          traceback_envs: err0.traceback_envs,
                          exc_type: err0.exc_type,
                          exc_args: err0.exc_args,
                          exc_value: err0.exc_value,
                          exc_cause: err0.exc_cause,
                          exc_context: Some(ctx_value),
                          exc_suppress_context: err0.exc_suppress_context,
                        }
                      }
                      _ => err0
                    }
                    // Keep the raised exception object's core metadata in sync so
                    // stdlib helpers can rely on `exc.__traceback__`, etc.
                    match err1.exc_value {
                      Some(Value::Instance(inst)) => {
                        set_named_value(
                          inst.dict,
                          "__traceback__",
                          make_traceback_value_with_env(
                            err1.traceback,
                            err1.traceback_envs,
                            frame_builtins_dict_from_builtins(builtins),
                            err1.span,
                          ),
                        )
                        set_named_value(
                          inst.dict,
                          "__cause__",
                          match err1.exc_cause {
                            Some(v) => v
                            None => Value::None
                          },
                        )
                        set_named_value(
                          inst.dict,
                          "__context__",
                          match err1.exc_context {
                            Some(v) => v
                            None => Value::None
                          },
                        )
                        set_named_value(
                          inst.dict,
                          "__suppress_context__",
                          Value::Bool(err1.exc_suppress_context),
                        )
                      }
                      _ => ()
                    }
                    Err(err1)
                  }
                  None =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "RuntimeError: invalid exception".to_string(),
                      ),
                    )
                }
              }
              Err(err) => Err(err)
            }
          }
          Err(err) => Err(err)
        }
      BcOp::RaiseFrom =>
        match pop_stack(stack) {
          Ok(cause_value) =>
            match pop_stack(stack) {
              Ok(exc_value) => {
                let context_err_opt = active_exception()
                match
                  ensure_exception_instance_from_value(
                    exc_value, globals, builtins, io,
                  ) {
                  Ok(inst_value) => {
                    let err0_opt = match inst_value {
                      Value::Instance(inst) =>
                        Some(
                          refresh_raised_exception_traceback(
                            inst,
                            runtime_error_from_exception_instance(inst),
                          ),
                        )
                      _ => None
                    }
                    match err0_opt {
                      Some(err0) => {
                        let err1 = match (context_err_opt, err0.exc_context) {
                          (Some(ctx_err), None) => {
                            let ctx_value = exception_value_from_runtime_error(
                              ctx_err, globals, builtins, io,
                            )
                            RuntimeError::{
                              kind: err0.kind,
                              message: err0.message,
                              span: err0.span,
                              traceback: err0.traceback,
                              traceback_envs: err0.traceback_envs,
                              exc_type: err0.exc_type,
                              exc_args: err0.exc_args,
                              exc_value: err0.exc_value,
                              exc_cause: err0.exc_cause,
                              exc_context: Some(ctx_value),
                              exc_suppress_context: err0.exc_suppress_context,
                            }
                          }
                          _ => err0
                        }
                        let cause_inst = match cause_value {
                          Value::None => Ok(Value::None)
                          _ =>
                            ensure_exception_instance_from_value(
                              cause_value, globals, builtins, io,
                            )
                        }
                        match cause_inst {
                          Ok(cause_inst) => {
                            let err2 = RuntimeError::{
                              kind: err1.kind,
                              message: err1.message,
                              span: err1.span,
                              traceback: err1.traceback,
                              traceback_envs: err1.traceback_envs,
                              exc_type: err1.exc_type,
                              exc_args: err1.exc_args,
                              exc_value: err1.exc_value,
                              exc_cause: Some(cause_inst),
                              exc_context: err1.exc_context,
                              exc_suppress_context: true,
                            }
                            match err2.exc_value {
                              Some(Value::Instance(inst)) => {
                                set_named_value(
                                  inst.dict,
                                  "__traceback__",
                                  make_traceback_value_with_env(
                                    err2.traceback,
                                    err2.traceback_envs,
                                    frame_builtins_dict_from_builtins(builtins),
                                    err2.span,
                                  ),
                                )
                                set_named_value(
                                  inst.dict,
                                  "__cause__",
                                  match err2.exc_cause {
                                    Some(v) => v
                                    None => Value::None
                                  },
                                )
                                set_named_value(
                                  inst.dict,
                                  "__context__",
                                  match err2.exc_context {
                                    Some(v) => v
                                    None => Value::None
                                  },
                                )
                                set_named_value(
                                  inst.dict,
                                  "__suppress_context__",
                                  Value::Bool(err2.exc_suppress_context),
                                )
                              }
                              _ => ()
                            }
                            Err(err2)
                          }
                          Err(err) => Err(err)
                        }
                      }
                      None =>
                        Err(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "RuntimeError: invalid exception".to_string(),
                          ),
                        )
                    }
                  }
                  Err(err) => Err(err)
                }
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::Reraise =>
        match active_exception() {
          Some(e) => Err(e)
          None =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: No active exception to reraise".to_string(),
              ),
            )
        }
      BcOp::Await =>
        match pop_stack(stack) {
          Ok(coro) =>
            match coroutine_await(coro) {
              Ok(v) => {
                stack.push(v)
                Ok(())
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::MatchPattern(pat_idx) =>
        match pop_stack(stack) {
          Ok(subject) => {
            let pattern = code.patterns[pat_idx]
            match match_pattern(subject, pattern) {
              Some(bindings) => {
                let pairs : Array[Value] = []
                for binding in bindings {
                  pairs.push(Value::Tuple([Value::Str(binding.0), binding.1]))
                }
                stack.push(Value::List(pairs))
                Ok(())
              }
              None => {
                stack.push(Value::None)
                Ok(())
              }
            }
          }
          Err(err) => Err(err)
        }
      BcOp::MatchBind =>
        match pop_stack(stack) {
          Ok(bindings_val) =>
            match bindings_val {
              Value::List(items) => {
                let restore : Array[Value] = []
                let mut err_opt : RuntimeError? = None
                for item in items {
                  if err_opt is Some(_) {
                    break
                  }
                  match item {
                    Value::Tuple(pair) =>
                      if pair.length() != 2 {
                        err_opt = Some(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "bytecode vm: MatchBind expects (name, value) pairs".to_string(),
                          ),
                        )
                      } else {
                        let name = match pair[0] {
                          Value::Str(text) => text
                          _ => {
                            err_opt = Some(
                              make_runtime_error(
                                RuntimeErrorKind::Runtime,
                                "bytecode vm: MatchBind name must be str".to_string(),
                              ),
                            )
                            ""
                          }
                        }
                        if err_opt is None {
                          let value = pair[1]
                          let prev_opt = get_scoped_value(locals, globals, name)
                          let existed = prev_opt is Some(_)
                          let prev_value = match prev_opt {
                            Some(v) => v
                            None => Value::None
                          }
                          restore.push(
                            Value::Tuple([
                              Value::Str(name),
                              Value::Bool(existed),
                              prev_value,
                            ]),
                          )
                          set_scoped_value(locals, globals, name, value)
                        }
                      }
                    _ =>
                      err_opt = Some(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "bytecode vm: MatchBind expects a list of tuples".to_string(),
                        ),
                      )
                  }
                }
                match err_opt {
                  Some(e) => Err(e)
                  None => {
                    stack.push(Value::List(restore))
                    Ok(())
                  }
                }
              }
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: MatchBind expects a list".to_string(),
                  ),
                )
            }
          Err(err) => Err(err)
        }
      BcOp::MatchRestore =>
        match pop_stack(stack) {
          Ok(restore_val) =>
            match restore_val {
              Value::List(items) => {
                let mut err_opt : RuntimeError? = None
                for item in items {
                  if err_opt is Some(_) {
                    break
                  }
                  match item {
                    Value::Tuple(tup) =>
                      if tup.length() != 3 {
                        err_opt = Some(
                          make_runtime_error(
                            RuntimeErrorKind::Runtime,
                            "bytecode vm: MatchRestore expects (name, existed, value)".to_string(),
                          ),
                        )
                      } else {
                        let name = match tup[0] {
                          Value::Str(text) => text
                          _ => {
                            err_opt = Some(
                              make_runtime_error(
                                RuntimeErrorKind::Runtime,
                                "bytecode vm: MatchRestore name must be str".to_string(),
                              ),
                            )
                            ""
                          }
                        }
                        let existed = match tup[1] {
                          Value::Bool(v) => v
                          _ => {
                            err_opt = Some(
                              make_runtime_error(
                                RuntimeErrorKind::Runtime,
                                "bytecode vm: MatchRestore existed must be bool".to_string(),
                              ),
                            )
                            false
                          }
                        }
                        let value = tup[2]
                        if err_opt is None {
                          if existed {
                            set_scoped_value(locals, globals, name, value)
                          } else {
                            let _ = delete_scoped_value(locals, globals, name)

                          }
                        }
                      }
                    _ =>
                      err_opt = Some(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "bytecode vm: MatchRestore expects a list of tuples".to_string(),
                        ),
                      )
                  }
                }
                match err_opt {
                  Some(e) => Err(e)
                  None => Ok(())
                }
              }
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: MatchRestore expects a list".to_string(),
                  ),
                )
            }
          Err(err) => Err(err)
        }
      BcOp::GenExpNew(template_idx, iter_name_idx, target_names_const_idx) =>
        match
          (if iter_name_idx >= 0 { pop_stack(stack) } else { Ok(Value::None) }) {
          Ok(iter_or_dummy) => {
            let iter_value : Value? = if iter_name_idx >= 0 {
              Some(iter_or_dummy)
            } else {
              None
            }
            match code.consts[template_idx] {
              Value::Function(template) => {
                let gen_locals = clone_locals(locals)
                match iter_value {
                  Some(it) => {
                    let iter_name = code.names[iter_name_idx]
                    set_local_value(gen_locals, iter_name, it)
                  }
                  None => ()
                }
                match code.consts[target_names_const_idx] {
                  Value::Tuple(items) => {
                    let mut err_opt : RuntimeError? = None
                    for item in items {
                      match item {
                        Value::Str(name) =>
                          if name != "_" {
                            ensure_local_cell(gen_locals, name, Value::None)
                          }
                        _ =>
                          err_opt = Some(
                            make_runtime_error(
                              RuntimeErrorKind::Runtime,
                              "bytecode vm: GenExpNew target names must be strings".to_string(),
                            ),
                          )
                      }
                      if err_opt is Some(_) {
                        break
                      }
                    }
                    match err_opt {
                      Some(e) => Err(e)
                      None => {
                        let filename = current_traceback_filename()
                        let gen = generator_new(
                          template.body,
                          gen_locals,
                          globals,
                          builtins,
                          io,
                          [],
                          [],
                          current_closure_env(),
                          template.name,
                          filename,
                        )
                        stack.push(gen)
                        Ok(())
                      }
                    }
                  }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "bytecode vm: GenExpNew target names must be a tuple".to_string(),
                      ),
                    )
                }
              }
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "bytecode vm: GenExpNew template is not a function".to_string(),
                  ),
                )
            }
          }
          Err(err) => Err(err)
        }
      BcOp::AsyncGenExpNew(spec_idx, iter_name_idx, target_names_const_idx) =>
        match
          (if iter_name_idx >= 0 { pop_stack(stack) } else { Ok(Value::None) }) {
          Ok(iter_or_dummy) => {
            let iter_value : Value? = if iter_name_idx >= 0 {
              Some(iter_or_dummy)
            } else {
              None
            }
            let gen_locals = clone_locals(locals)
            match iter_value {
              Some(it) => {
                let iter_name = code.names[iter_name_idx]
                set_local_value(gen_locals, iter_name, it)
              }
              None => ()
            }
            match code.consts[target_names_const_idx] {
              Value::Tuple(items) => {
                let mut err_opt : RuntimeError? = None
                for item in items {
                  match item {
                    Value::Str(name) =>
                      if name != "_" {
                        ensure_local_cell(gen_locals, name, Value::None)
                      }
                    _ =>
                      err_opt = Some(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "bytecode vm: AsyncGenExpNew target names must be strings".to_string(),
                        ),
                      )
                  }
                  if err_opt is Some(_) {
                    break
                  }
                }
                match err_opt {
                  Some(e) => Err(e)
                  None => {
                    let spec = code.genexps[spec_idx]
                    let gen = async_genexp_new(
                      spec.elt,
                      spec.clauses,
                      spec.filters,
                      gen_locals,
                      globals,
                      builtins,
                      io,
                    )
                    stack.push(gen)
                    Ok(())
                  }
                }
              }
              _ =>
                Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: AsyncGenExpNew target names must be a tuple".to_string(),
                  ),
                )
            }
          }
          Err(err) => Err(err)
        }
      BcOp::CallFunction(argc) =>
        match pop_n(stack, argc) {
          Ok(args) =>
            match pop_stack(stack) {
              Ok(callee) =>
                match callee {
                  // Builtins need access to the caller's locals for features like
                  // zero-arg `super()`. The AST evaluator special-cases this via
                  // `eval_builtin_call`, so mirror that here.
                  Value::Function(func) if func.body.length() == 0 =>
                    match
                      eval_builtin_call(
                        func.name,
                        args,
                        [],
                        locals,
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(Some(out)) => {
                        stack.push(out)
                        Ok(())
                      }
                      Ok(None) =>
                        match
                          call_callable_with_env(
                            Value::Function(func),
                            args,
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(out) => {
                            stack.push(out)
                            Ok(())
                          }
                          Err(err) =>
                            Err(prepend_current_callsite_frame(err, span))
                        }
                      Err(err) => Err(err)
                    }
                  _ =>
                    match
                      call_callable_with_env(
                        callee,
                        args,
                        [],
                        globals,
                        builtins,
                        io,
                      ) {
                      Ok(out) => {
                        stack.push(out)
                        Ok(())
                      }
                      Err(err) => Err(prepend_current_callsite_frame(err, span))
                    }
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::CallFunctionKw(argc) =>
        match pop_stack(stack) {
          Ok(kw_names_val) => {
            let kw_names = match kw_names_val {
              Value::Tuple(values) => {
                let names : Array[String] = []
                for v in values {
                  match v {
                    Value::Str(name) => names.push(name)
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "bytecode vm: CallFunctionKw expects tuple of str names".to_string(),
                        ),
                      )
                  }
                }
                names
              }
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "bytecode vm: CallFunctionKw expects tuple of keyword names".to_string(),
                  ),
                )
            }
            let kwc = kw_names.length()
            match pop_n(stack, kwc) {
              Ok(kw_values) =>
                match pop_n(stack, argc) {
                  Ok(pos_args) =>
                    match pop_stack(stack) {
                      Ok(callee) => {
                        let keywords : Array[(String, Value)] = []
                        for i = 0; i < kwc; i = i + 1 {
                          keywords.push((kw_names[i], kw_values[i]))
                        }
                        match callee {
                          Value::Function(func) if func.body.length() == 0 =>
                            match
                              eval_builtin_call(
                                func.name,
                                pos_args,
                                keywords,
                                locals,
                                globals,
                                builtins,
                                io,
                              ) {
                              Ok(Some(out)) => {
                                stack.push(out)
                                Ok(())
                              }
                              Ok(None) =>
                                match
                                  call_callable_with_env(
                                    Value::Function(func),
                                    pos_args,
                                    keywords,
                                    globals,
                                    builtins,
                                    io,
                                  ) {
                                  Ok(out) => {
                                    stack.push(out)
                                    Ok(())
                                  }
                                  Err(err) =>
                                    Err(
                                      prepend_current_callsite_frame(err, span),
                                    )
                                }
                              Err(err) => Err(err)
                            }
                          _ =>
                            match
                              call_callable_with_env(
                                callee, pos_args, keywords, globals, builtins, io,
                              ) {
                              Ok(out) => {
                                stack.push(out)
                                Ok(())
                              }
                              Err(err) =>
                                Err(prepend_current_callsite_frame(err, span))
                            }
                        }
                      }
                      Err(err) => Err(err)
                    }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          }
          Err(err) => Err(err)
        }
      BcOp::CallFunctionVar =>
        match pop_stack(stack) {
          Ok(keyword_pairs_val) =>
            match pop_stack(stack) {
              Ok(positional_list_val) =>
                match pop_stack(stack) {
                  Ok(callee) => {
                    let positional = match positional_list_val {
                      Value::List(values) => values
                      Value::Tuple(values) => values
                      _ =>
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Type,
                            "bytecode vm: CallFunctionVar expects positional list".to_string(),
                          ),
                        )
                    }
                    let keyword_items = match keyword_pairs_val {
                      Value::List(values) => values
                      Value::Tuple(values) => values
                      _ =>
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Type,
                            "bytecode vm: CallFunctionVar expects keyword list".to_string(),
                          ),
                        )
                    }
                    let keywords : Array[(String, Value)] = []
                    for item in keyword_items {
                      match item {
                        Value::Tuple(pair) =>
                          if pair.length() != 2 {
                            return Err(
                              make_runtime_error(
                                RuntimeErrorKind::Type,
                                "bytecode vm: CallFunctionVar keyword pair arity".to_string(),
                              ),
                            )
                          } else {
                            match pair[0] {
                              Value::Str(name) => keywords.push((name, pair[1]))
                              _ =>
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Type,
                                    "keywords must be strings".to_string(),
                                  ),
                                )
                            }
                          }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "bytecode vm: CallFunctionVar expects keyword tuples".to_string(),
                            ),
                          )
                      }
                    }
                    match callee {
                      Value::Function(func) if func.body.length() == 0 =>
                        match
                          eval_builtin_call(
                            func.name,
                            positional,
                            keywords,
                            locals,
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(Some(out)) => {
                            stack.push(out)
                            Ok(())
                          }
                          Ok(None) =>
                            match
                              call_callable_with_env(
                                Value::Function(func),
                                positional,
                                keywords,
                                globals,
                                builtins,
                                io,
                              ) {
                              Ok(out) => {
                                stack.push(out)
                                Ok(())
                              }
                              Err(err) =>
                                Err(prepend_current_callsite_frame(err, span))
                            }
                          Err(err) => Err(err)
                        }
                      _ =>
                        match
                          call_callable_with_env(
                            callee, positional, keywords, globals, builtins, io,
                          ) {
                          Ok(out) => {
                            stack.push(out)
                            Ok(())
                          }
                          Err(err) =>
                            Err(prepend_current_callsite_frame(err, span))
                        }
                    }
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::MakeFunction(template, default_count, decorator_count) =>
        match pop_n(stack, default_count) {
          Ok(defaults) =>
            match pop_n(stack, decorator_count) {
              Ok(decorators) => {
                let template_value = code.consts[template]
                match template_value {
                  Value::Function(template_func) =>
                    match
                      make_function_from_template_with_env(
                        template_func, defaults, decorators, locals, globals, builtins,
                        io,
                      ) {
                      Ok(defined) => {
                        stack.push(defined)
                        Ok(())
                      }
                      Err(err) => Err(prepend_current_callsite_frame(err, span))
                    }
                  _ =>
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "bytecode vm: MakeFunction template is not a function".to_string(),
                      ),
                    )
                }
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::MakeClass(template, name_idx, decorator_count) =>
        match pop_stack(stack) {
          Ok(keyword_specs_val) =>
            match pop_stack(stack) {
              Ok(base_specs_val) =>
                match pop_n(stack, decorator_count) {
                  Ok(decorator_values) => {
                    fn inner() -> Result[Unit, RuntimeError] {
                      let class_name = code.names[name_idx]
                      let template_value = code.consts[template]
                      let body = match template_value {
                        Value::Function(template_func) => template_func.body
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "bytecode vm: MakeClass template is not a function".to_string(),
                            ),
                          )
                      }
                      let base_specs = match base_specs_val {
                        Value::List(items) => items
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Runtime,
                              "bytecode vm: MakeClass expects base spec list".to_string(),
                            ),
                          )
                      }
                      let raw_base_values : Array[Value] = []
                      for spec in base_specs {
                        match spec {
                          Value::Tuple(values) if values.length() == 2 =>
                            match values[0] {
                              Value::Bool(true) => {
                                let iter_value = values[1]
                                let items = match iterable_values(iter_value) {
                                  Ok(v) => v
                                  Err(err) => return Err(err)
                                }
                                for item in items {
                                  raw_base_values.push(item)
                                }
                              }
                              Value::Bool(false) =>
                                raw_base_values.push(values[1])
                              _ =>
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Runtime,
                                    "bytecode vm: invalid base spec".to_string(),
                                  ),
                                )
                            }
                          _ =>
                            return Err(
                              make_runtime_error(
                                RuntimeErrorKind::Runtime,
                                "bytecode vm: invalid base spec".to_string(),
                              ),
                            )
                        }
                      }
                      let base_values : Array[Value] = []
                      for base_value in raw_base_values {
                        let expanded = match base_value {
                          Value::Instance(_) =>
                            match
                              get_attr_from_value(
                                base_value, "__mro_entries__", globals, builtins,
                                io,
                              ) {
                              Ok(mro_entries) => {
                                let bases_tuple : Array[Value] = []
                                for item in raw_base_values {
                                  bases_tuple.push(item)
                                }
                                let entries = match
                                  call_callable_with_env(
                                    mro_entries,
                                    [Value::Tuple(bases_tuple)],
                                    [],
                                    globals,
                                    builtins,
                                    io,
                                  ) {
                                  Ok(value) => value
                                  Err(err) => return Err(err)
                                }
                                match entries {
                                  Value::Tuple(values) => values
                                  Value::List(values) => values
                                  _ =>
                                    return Err(
                                      make_runtime_error(
                                        RuntimeErrorKind::Type,
                                        "base class must be a class".to_string(),
                                      ),
                                    )
                                }
                              }
                              Err(_) =>
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Type,
                                    "base class must be a class".to_string(),
                                  ),
                                )
                            }
                          _ => [base_value]
                        }
                        for value in expanded {
                          match value {
                            Value::Class(_) => base_values.push(value)
                            Value::Function(func) =>
                              if func.body.length() == 0 &&
                                is_builtin_class_name(func.name) {
                                base_values.push(
                                  Value::Class(
                                    builtin_class_from_name(func.name, builtins),
                                  ),
                                )
                              } else {
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Type,
                                    "base class must be a class".to_string(),
                                  ),
                                )
                              }
                            other => base_values.push(other)
                          }
                        }
                      }
                      let keyword_specs = match keyword_specs_val {
                        Value::List(items) => items
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Runtime,
                              "bytecode vm: MakeClass expects keyword spec list".to_string(),
                            ),
                          )
                      }
                      let class_kwargs : Array[(String, Value)] = []
                      let mut metaclass_value : Value? = None
                      for spec in keyword_specs {
                        let (key, value) = match spec {
                          Value::Tuple(values) if values.length() == 2 =>
                            match values[0] {
                              Value::Str(k) => (k, values[1])
                              _ =>
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Runtime,
                                    "bytecode vm: class keyword name must be str".to_string(),
                                  ),
                                )
                            }
                          _ =>
                            return Err(
                              make_runtime_error(
                                RuntimeErrorKind::Runtime,
                                "bytecode vm: invalid class keyword spec".to_string(),
                              ),
                            )
                        }
                        if key == "**" {
                          let pairs = match
                            dict_pairs_from_value("class", value) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          for pair in pairs {
                            match pair.0 {
                              Value::Str(k) =>
                                if k == "metaclass" {
                                  metaclass_value = Some(pair.1)
                                } else {
                                  set_global_value(class_kwargs, k, pair.1)
                                }
                              _ =>
                                return Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Type,
                                    "keywords must be strings".to_string(),
                                  ),
                                )
                            }
                          }
                          continue
                        }
                        if key == "metaclass" {
                          metaclass_value = Some(value)
                          continue
                        }
                        set_global_value(class_kwargs, key, value)
                      }
                      if base_values.length() == 0 {
                        for pair in builtins {
                          if pair.0 == "object" {
                            match pair.1 {
                              Value::Class(object_class) =>
                                base_values.push(Value::Class(object_class))
                              _ => ()
                            }
                            break
                          }
                        }
                      }
                      for base_value in base_values {
                        match base_value {
                          Value::Class(base_class) =>
                            match
                              get_named_value(base_class.dict, "__module__") {
                              Some(Value::Str(module_name)) =>
                                if module_name == "builtins" &&
                                  base_class.name == "bool" {
                                  return Err(
                                    make_runtime_error(
                                      RuntimeErrorKind::Type,
                                      "type 'bool' is not an acceptable base type".to_string(),
                                    ),
                                  )
                                }
                              _ => ()
                            }
                          _ => ()
                        }
                      }
                      let module_name_value = get_global_value(
                        globals, "__name__",
                      )
                      if module_name_value is None {
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Name,
                            "name '__name__' is not defined",
                          ),
                        )
                      }
                      let module_name = match module_name_value.unwrap() {
                        Value::Str(text) => text
                        other => value_to_string(other)
                      }
                      let class_dict : Array[(String, Value)] = []
                      let mut qualname = class_name
                      match get_global_value(locals, "__qualname__") {
                        Some(Value::Str(parent)) =>
                          qualname = parent + "." + class_name
                        _ => ()
                      }
                      class_dict.push(("__module__", Value::Str(module_name)))
                      class_dict.push(("__qualname__", Value::Str(qualname)))
                      ensure_local_cell(class_dict, "__class__", Value::None)
                      let mut pushed_closure = false
                      if has_active_closure_env() {
                        for i = 0; i < locals.length(); i = i + 1 {
                          let name = locals[i].0
                          let value = locals[i].1
                          if !is_cell_value(value) {
                            ensure_local_cell(locals, name, value)
                          }
                        }
                        let class_closure = merge_cell_closures(
                          locals,
                          current_closure_env(),
                        )
                        push_closure_env(class_closure)
                        pushed_closure = true
                      }
                      let flow = match
                        eval_block_flow(
                          body,
                          class_dict,
                          globals,
                          builtins,
                          io,
                          current_config(),
                          0,
                        ) {
                        Ok(value) => value
                        Err(err) => return Err(err)
                      }
                      if pushed_closure {
                        pop_closure_env()
                      }
                      match flow {
                        BlockFlow::Normal(_) => ()
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Runtime,
                              "SyntaxError: invalid class body".to_string(),
                            ),
                          )
                      }
                      let mut selected_meta = Value::Class(
                        builtin_class_from_name("type", builtins),
                      )
                      match metaclass_value {
                        Some(v) => selected_meta = v
                        None =>
                          for base_value in base_values {
                            match base_value {
                              Value::Class(base_class) =>
                                match
                                  get_named_value(
                                    base_class.dict,
                                    "__mpython_metaclass__",
                                  ) {
                                  Some(Value::Class(meta)) => {
                                    selected_meta = Value::Class(meta)
                                    break
                                  }
                                  _ => ()
                                }
                              _ => ()
                            }
                          }
                      }
                      let namespace_pairs : Array[(Value, Value)] = []
                      for pair in class_dict {
                        namespace_pairs.push((Value::Str(pair.0), pair.1))
                      }
                      let metaclass_args : Array[Value] = [
                        Value::Str(class_name),
                        Value::Tuple(base_values),
                        Value::Dict(namespace_pairs),
                      ]
                      let created_value = match
                        call_callable_with_env(
                          selected_meta, metaclass_args, class_kwargs, globals, builtins,
                          io,
                        ) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      fn apply_decorators(
                        defined0 : Value,
                        decorator_values : Array[Value],
                        locals : Array[(String, Value)],
                        globals : Array[(String, Value)],
                        builtins : Array[(String, Value)],
                        io : MockIO,
                      ) -> Result[Value, RuntimeError] {
                        let mut defined = defined0
                        for i = decorator_values.length(); i > 0; i = i - 1 {
                          let decorator_value = decorator_values[i - 1]
                          defined = match decorator_value {
                            Value::Function(dec_func) =>
                              if dec_func.body.length() == 0 {
                                match
                                  eval_builtin_call(
                                    dec_func.name,
                                    [defined],
                                    [],
                                    locals,
                                    globals,
                                    builtins,
                                    io,
                                  ) {
                                  Ok(Some(value)) => value
                                  Ok(None) =>
                                    match
                                      call_callable_with_env(
                                        decorator_value,
                                        [defined],
                                        [],
                                        globals,
                                        builtins,
                                        io,
                                      ) {
                                      Ok(value) => value
                                      Err(err) =>
                                        return Err(
                                          prepend_current_callsite_frame(
                                            err, span,
                                          ),
                                        )
                                    }
                                  Err(err) =>
                                    return Err(
                                      prepend_current_callsite_frame(err, span),
                                    )
                                }
                              } else {
                                match
                                  call_callable_with_env(
                                    decorator_value,
                                    [defined],
                                    [],
                                    globals,
                                    builtins,
                                    io,
                                  ) {
                                  Ok(value) => value
                                  Err(err) =>
                                    return Err(
                                      prepend_current_callsite_frame(err, span),
                                    )
                                }
                              }
                            _ =>
                              match
                                call_callable_with_env(
                                  decorator_value,
                                  [defined],
                                  [],
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(value) => value
                                Err(err) =>
                                  return Err(
                                    prepend_current_callsite_frame(err, span),
                                  )
                              }
                          }
                        }
                        Ok(defined)
                      }

                      match created_value {
                        Value::Class(klass) => {
                          match get_named_value(class_dict, "__class__") {
                            Some(cell) =>
                              cell_set_value(cell, Value::Class(klass))
                            None => ()
                          }
                          if get_named_value(klass.dict, "hashvalue") is None {
                            // Some metaclasses (notably EnumMeta) treat setting a
                            // new int-valued attribute as defining a new enum
                            // member. Avoid injecting our identity hash into such
                            // classes to keep stdlib enums (e.g. calendar.Month)
                            // behaving predictably.
                            let mut should_set = true
                            for base_value in base_values {
                              match base_value {
                                Value::Class(base_class) =>
                                  if base_class.name == "Enum" ||
                                    base_class.name == "IntEnum" ||
                                    base_class.name == "StrEnum" {
                                    should_set = false
                                    break
                                  }
                                _ => ()
                              }
                            }
                            if should_set {
                              set_named_value(
                                klass.dict,
                                "hashvalue",
                                Value::Int(fresh_object_hashvalue()),
                              )
                            }
                          }
                          if get_named_value(
                              klass.dict,
                              "__mpython_metaclass__",
                            )
                            is None {
                            match selected_meta {
                              Value::Class(meta) =>
                                set_named_value(
                                  klass.dict,
                                  "__mpython_metaclass__",
                                  Value::Class(meta),
                                )
                              _ => ()
                            }
                          }
                          let _ = match class_mro(klass) {
                            Ok(_) => ()
                            Err(err) => return Err(err)
                          }
                          for pair in klass.dict {
                            match pair.1 {
                              Value::Instance(desc_inst) =>
                                if class_has_base_name(
                                    desc_inst.class,
                                    "property",
                                  ) {
                                  if get_named_value(desc_inst.dict, "__name__")
                                    is None {
                                    set_named_value(
                                      desc_inst.dict,
                                      "__name__",
                                      Value::Str(pair.0),
                                    )
                                  }
                                }
                              _ => ()
                            }
                          }
                          fn value_is_abstract(
                            value : Value,
                            globals : Array[(String, Value)],
                            builtins : Array[(String, Value)],
                            io : MockIO,
                          ) -> Result[Bool, RuntimeError] {
                            match
                              get_attr_from_value(
                                value, "__isabstractmethod__", globals, builtins,
                                io,
                              ) {
                              Ok(flag) =>
                                truthy_from_value_with_env(
                                  flag, globals, builtins, io,
                                )
                              Err(err) =>
                                match err.kind {
                                  RuntimeErrorKind::Attribute => Ok(false)
                                  _ =>
                                    if err.exc_type == "AttributeError" {
                                      Ok(false)
                                    } else {
                                      Err(err)
                                    }
                                }
                            }
                          }

                          let abstract_names : Array[Value] = []
                          for pair in class_dict {
                            let is_abstract = match
                              value_is_abstract(pair.1, globals, builtins, io) {
                              Ok(v) => v
                              Err(err) => return Err(err)
                            }
                            if is_abstract {
                              let _ = set_add_unique(
                                abstract_names,
                                Value::Str(pair.0),
                              )

                            }
                          }
                          let mut has_abstractmethods_attr = false
                          for base_value in base_values {
                            match base_value {
                              Value::Class(base_class) => {
                                let base_abs = get_named_value(
                                  base_class.dict,
                                  "__abstractmethods__",
                                )
                                if base_abs is Some(_) {
                                  has_abstractmethods_attr = true
                                }
                                match base_abs {
                                  Some(Value::Set(items))
                                  | Some(Value::Tuple(items)) =>
                                    for item in items {
                                      match item {
                                        Value::Str(name) =>
                                          match lookup_class_attr(klass, name) {
                                            Ok(Some(value)) => {
                                              let is_abstract = match
                                                value_is_abstract(
                                                  value, globals, builtins, io,
                                                ) {
                                                Ok(v) => v
                                                Err(err) => return Err(err)
                                              }
                                              if is_abstract {
                                                let _ = set_add_unique(
                                                  abstract_names,
                                                  Value::Str(name),
                                                )

                                              }
                                            }
                                            _ => ()
                                          }
                                        _ => ()
                                      }
                                    }
                                  _ => ()
                                }
                              }
                              _ => ()
                            }
                          }
                          if abstract_names.length() > 0 ||
                            has_abstractmethods_attr {
                            set_named_value(
                              klass.dict,
                              "__abstractmethods__",
                              Value::Set(abstract_names),
                            )
                          }
                          let inherited_init_subclass : Value? = match
                            class_mro(klass) {
                            Ok(mro) => {
                              let mut found : Value? = None
                              for i = 1; i < mro.length(); i = i + 1 {
                                match
                                  get_named_value(
                                    mro[i].dict,
                                    "__init_subclass__",
                                  ) {
                                  Some(Value::Function(func)) => {
                                    found = Some(
                                      Value::BoundMethod(BoundMethodValue::{
                                        function: func,
                                        self: Value::Class(klass),
                                      }),
                                    )
                                    break
                                  }
                                  _ => ()
                                }
                              }
                              found
                            }
                            Err(_) => None
                          }
                          match inherited_init_subclass {
                            Some(hook) => {
                              let _ = match
                                call_callable_with_env(
                                  hook,
                                  [],
                                  class_kwargs,
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(value) => value
                                Err(err) => return Err(err)
                              }

                            }
                            None => ()
                          }
                          let defined = match
                            apply_decorators(
                              Value::Class(klass),
                              decorator_values,
                              locals,
                              globals,
                              builtins,
                              io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          stack.push(defined)
                          Ok(())
                        }
                        other => {
                          let defined = match
                            apply_decorators(
                              other, decorator_values, locals, globals, builtins,
                              io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          stack.push(defined)
                          Ok(())
                        }
                      }
                    }

                    inner()
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::StoreAnnotation(i) =>
        match pop_stack(stack) {
          Ok(ann_value) => {
            let name = code.names[i]
            let pairs = match
              get_scoped_value(locals, globals, "__annotations__") {
              Some(Value::Dict(pairs)) => pairs
              Some(_) =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "__annotations__ must be a dict".to_string(),
                  ),
                )
              None => {
                let pairs : Array[(Value, Value)] = []
                set_scoped_value(
                  locals,
                  globals,
                  "__annotations__",
                  Value::Dict(pairs),
                )
                pairs
              }
            }
            let _ = match dict_set_item(pairs, Value::Str(name), ann_value) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            Ok(())
          }
          Err(err) => Err(err)
        }
      BcOp::AugAssignName(i, op) =>
        match pop_stack(stack) {
          Ok(rhs) => {
            let name = code.names[i]
            match lookup_name_value(name, locals, globals, builtins) {
              Ok(current) =>
                match
                  eval_augassign_op_values(
                    op, current, rhs, globals, builtins, io,
                  ) {
                  Ok(next) => {
                    set_scoped_value(locals, globals, name, next)
                    Ok(())
                  }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          }
          Err(err) => Err(err)
        }
      BcOp::AugAssignAttr(i, op) =>
        match pop_stack(stack) {
          Ok(target) =>
            match pop_stack(stack) {
              Ok(rhs) => {
                let attr = code.names[i]
                match get_attr_from_value(target, attr, globals, builtins, io) {
                  Ok(current) =>
                    match
                      eval_augassign_op_values(
                        op, current, rhs, globals, builtins, io,
                      ) {
                      Ok(next) =>
                        match
                          set_attr_on_value(
                            target, attr, next, globals, builtins, io,
                          ) {
                          Ok(_) => Ok(())
                          Err(err) => Err(err)
                        }
                      Err(err) => Err(err)
                    }
                  Err(err) => Err(err)
                }
              }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::AugAssignSubscr(op) =>
        match pop_stack(stack) {
          Ok(index) =>
            match pop_stack(stack) {
              Ok(target) =>
                match pop_stack(stack) {
                  Ok(rhs) =>
                    match
                      get_subscr_value(target, index, globals, builtins, io) {
                      Ok(current) =>
                        match
                          eval_augassign_op_values(
                            op, current, rhs, globals, builtins, io,
                          ) {
                          Ok(next) =>
                            match
                              set_subscr_value(
                                target, index, next, globals, builtins, io,
                              ) {
                              Ok(_) => Ok(())
                              Err(err) => Err(err)
                            }
                          Err(err) => Err(err)
                        }
                      Err(err) => Err(err)
                    }
                  Err(err) => Err(err)
                }
              Err(err) => Err(err)
            }
          Err(err) => Err(err)
        }
      BcOp::ImportName(mod_idx, alias_idx) => {
        let mod_value = code.consts[mod_idx]
        let module_name = match mod_value {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: ImportName expects module name str".to_string(),
              ),
            )
        }
        match
          import_module(module_name, globals, builtins, io, current_config()) {
          Ok(module_value) => {
            let binding = if alias_idx >= 0 {
              code.names[alias_idx]
            } else {
              module_top_name(module_name)
            }
            let binding_value = if alias_idx >= 0 {
              module_value
            } else if module_name.contains(".") {
              match module_cache_get(binding) {
                Some(value) => value
                None => module_value
              }
            } else {
              module_value
            }
            set_scoped_value(locals, globals, binding, binding_value)
            Ok(())
          }
          Err(err) => Err(err)
        }
      }
      BcOp::FromImport(mod_idx, names_idx, aliases_idx) => {
        let mod_value = code.consts[mod_idx]
        let module_name = match mod_value {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: FromImport expects module name str".to_string(),
              ),
            )
        }
        let names_value = code.consts[names_idx]
        let aliases_value = code.consts[aliases_idx]
        let names = match names_value {
          Value::Tuple(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: FromImport expects tuple of names".to_string(),
              ),
            )
        }
        let aliases = match aliases_value {
          Value::Tuple(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "bytecode vm: FromImport expects tuple of aliases".to_string(),
              ),
            )
        }
        if names.length() != aliases.length() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "bytecode vm: FromImport expects equal names/aliases".to_string(),
            ),
          )
        }
        match resolve_relative_module_name(module_name, globals) {
          Ok(resolved_name) => {
            if resolved_name == "__future__" {
              for item in names {
                match item {
                  Value::Str(sym) =>
                    if sym == "annotations" {
                      set_global_value(
                        globals,
                        "__mpython_future_annotations__",
                        Value::Bool(true),
                      )
                    }
                  _ => ()
                }
              }
            }
            match
              import_module(
                resolved_name,
                globals,
                builtins,
                io,
                current_config(),
              ) {
              Ok(module_value) => {
                for i = 0; i < names.length(); i = i + 1 {
                  let name = match names[i] {
                    Value::Str(s) => s
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "bytecode vm: FromImport name must be str".to_string(),
                        ),
                      )
                  }
                  let alias_opt : String? = match aliases[i] {
                    Value::None => None
                    Value::Str(s) => Some(s)
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "bytecode vm: FromImport alias must be str/None".to_string(),
                        ),
                      )
                  }
                  if name == "*" {
                    match module_value {
                      Value::Instance(inst) => {
                        let mut imported_any = false
                        match get_named_value(inst.dict, "__all__") {
                          Some(Value::List(items))
                          | Some(Value::Tuple(items)) =>
                            for item in items {
                              match item {
                                Value::Str(sym) =>
                                  match
                                    get_attr_from_value(
                                      module_value, sym, globals, builtins, io,
                                    ) {
                                    Ok(value) => {
                                      set_scoped_value(
                                        locals, globals, sym, value,
                                      )
                                      imported_any = true
                                    }
                                    Err(err) => return Err(err)
                                  }
                                _ => ()
                              }
                            }
                          _ => ()
                        }
                        if !imported_any {
                          for pair in inst.dict {
                            if pair.0 != "__name__" && !pair.0.has_prefix("_") {
                              set_scoped_value(locals, globals, pair.0, pair.1)
                            }
                          }
                        }
                      }
                      _ => ()
                    }
                    continue
                  }
                  let imported = match
                    get_attr_from_value(
                      module_value, name, globals, builtins, io,
                    ) {
                    Ok(value) => Ok(value)
                    Err(err) =>
                      match err.kind {
                        RuntimeErrorKind::Attribute => {
                          let submodule = resolved_name + "." + name
                          match
                            import_module(
                              submodule,
                              globals,
                              builtins,
                              io,
                              current_config(),
                            ) {
                            Ok(value) => Ok(value)
                            Err(err) => {
                              let missing_submodule_message = "ModuleNotFoundError: No module named '" +
                                submodule +
                                "'"
                              if err.exc_type == "ModuleNotFoundError" &&
                                err.message == missing_submodule_message {
                                Err(
                                  make_runtime_error(
                                    RuntimeErrorKind::Runtime,
                                    "ImportError: cannot import name '" +
                                    name +
                                    "' from '" +
                                    resolved_name +
                                    "'",
                                  ),
                                )
                              } else {
                                Err(err)
                              }
                            }
                          }
                        }
                        _ => Err(err)
                      }
                  }
                  match imported {
                    Ok(value) => {
                      let binding = match alias_opt {
                        Some(alias_name) => alias_name
                        None => name
                      }
                      set_scoped_value(locals, globals, binding, value)
                    }
                    Err(err) => return Err(err)
                  }
                }
                Ok(())
              }
              Err(err) => Err(err)
            }
          }
          Err(err) => Err(err)
        }
      }
      BcOp::CheckInFunctionScope(msg) =>
        if !in_function_scope() {
          Err(make_runtime_error(RuntimeErrorKind::Runtime, msg))
        } else {
          Ok(())
        }
      BcOp::CheckInCoroutineScope(msg) =>
        if !coroutine_is_active() {
          Err(make_runtime_error(RuntimeErrorKind::Runtime, msg))
        } else {
          Ok(())
        }
      BcOp::ReturnValue =>
        match pop_stack(stack) {
          Ok(v) =>
            match vm_unwind_return(stack, blocks) {
              Some(target) => {
                pending_return = Some(v)
                next_pc = target
                Ok(())
              }
              None => {
                if span is Some(_) {
                  pop_active_span()
                }
                return Ok(v)
              }
            }
          Err(err) => Err(err)
        }
    }
    match span {
      Some(_) => pop_active_span()
      None => ()
    }
    match step {
      Ok(_) => pc = next_pc
      Err(err) => {
        // An exception overrides any pending return (including one in-flight from
        // an inner finally handler).
        pending_return = None
        pending_jump_target = None
        pending_jump_count = 0
        let mut handler_pc : Int? = None
        let mut exc = err
        // If we are currently handling another exception (inside an except/finally
        // path), attach it as implicit context, mirroring CPython's behavior.
        match active_exception() {
          Some(ctx_err) =>
            if exc.exc_context is None &&
              exc.exc_cause is None &&
              !exc.exc_suppress_context {
              let ctx_value = exception_value_from_runtime_error(
                ctx_err, globals, builtins, io,
              )
              exc = RuntimeError::{
                kind: exc.kind,
                message: exc.message,
                span: exc.span,
                traceback: exc.traceback,
                traceback_envs: exc.traceback_envs,
                exc_type: exc.exc_type,
                exc_args: exc.exc_args,
                exc_value: exc.exc_value,
                exc_cause: exc.exc_cause,
                exc_context: Some(ctx_value),
                exc_suppress_context: exc.exc_suppress_context,
              }
            }
          None => ()
        }
        let exc_for_handler = vm_trim_runtime_error_for_active_handler(exc)
        // Unwind blocks until we find a handler.
        while blocks.length() > 0 {
          let blk = blocks.remove(blocks.length() - 1)
          while stack.length() > blk.stack_height {
            let _ = stack.remove(stack.length() - 1)

          }
          match blk.kind {
            VmBlockKind::Except(target) => {
              pending_exc = Some(exc_for_handler)
              blocks.push(VmBlock::{
                kind: VmBlockKind::ExceptHandler,
                stack_height: stack.length(),
                pushed_exc: true,
                star_base_err: None,
                star_remaining_group: None,
                star_active_match: false,
              })
              active_exception_stack.val.push(exc_for_handler)
              handler_pc = Some(target)
              break
            }
            VmBlockKind::Finally(target) => {
              pending_exc = Some(exc_for_handler)
              blocks.push(VmBlock::{
                kind: VmBlockKind::FinallyHandler,
                stack_height: stack.length(),
                pushed_exc: true,
                star_base_err: None,
                star_remaining_group: None,
                star_active_match: false,
              })
              active_exception_stack.val.push(exc_for_handler)
              handler_pc = Some(target)
              break
            }
            VmBlockKind::ExceptHandler => {
              // An exception raised while already in an except path.
              if blk.pushed_exc {
                let _ = active_exception_stack.val.pop()

              }
              pending_exc = None
              continue
            }
            VmBlockKind::FinallyHandler => {
              // An exception raised while already in a finally path.
              if blk.pushed_exc {
                let _ = active_exception_stack.val.pop()

              }
              pending_exc = None
              continue
            }
          }
        }
        match handler_pc {
          Some(target) => pc = target
          None => return Err(exc)
        }
      }
    }
  }

  // If bytecode falls off the end, return None.
  Ok(Value::None)
}
