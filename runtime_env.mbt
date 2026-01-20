///|
/// Environment and container helpers.

///|
fn normalize_index(index : Int, length : Int) -> Int {
  if index < 0 {
    length + index
  } else {
    index
  }
}

///|
fn index_from_value(value : Value, default : Int) -> Result[Int, RuntimeError] {
  match value {
    Value::None => Ok(default)
    Value::Int(v) => bigint_to_int_checked(v)
    Value::Bool(v) => Ok(if v { 1 } else { 0 })
    Value::Float(v) => Ok(v.to_int())
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, "invalid index".to_string()),
      )
  }
}

///|
fn slice_values(values : Array[Value], start : Int, end : Int) -> Array[Value] {
  let result : Array[Value] = []
  let len = values.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 {
    s = 0
  }
  if e < 0 {
    e = 0
  }
  if s > len {
    s = len
  }
  if e > len {
    e = len
  }
  for i = s; i < e; i = i + 1 {
    result.push(values[i])
  }
  result
}

///|
fn slice_string(chars : Array[Char], start : Int, end : Int) -> String {
  let len = chars.length()
  let mut s = normalize_index(start, len)
  let mut e = normalize_index(end, len)
  if s < 0 {
    s = 0
  }
  if e < 0 {
    e = 0
  }
  if s > len {
    s = len
  }
  if e > len {
    e = len
  }
  let buf = StringBuilder::new()
  for i = s; i < e; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn maybe_index_from_value(value : Value) -> Result[Int?, RuntimeError] {
  match value {
    Value::None => Ok(None)
    _ =>
      match index_from_value(value, 0) {
        Ok(v) => Ok(Some(v))
        Err(err) => Err(err)
      }
  }
}

///|
fn step_from_value(value : Value) -> Result[Int, RuntimeError] {
  match value {
    Value::None => Ok(1)
    _ => index_from_value(value, 1)
  }
}

///|
fn slice_params_from_values(
  length : Int,
  start_value : Value,
  end_value : Value,
  step_value : Value,
) -> Result[(Int, Int, Int), RuntimeError] {
  let step = match step_from_value(step_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if step == 0 {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "ValueError: slice step cannot be zero".to_string(),
      ),
    )
  }
  let start_opt = match maybe_index_from_value(start_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let end_opt = match maybe_index_from_value(end_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if step > 0 {
    let mut start = match start_opt {
      Some(v) => v
      None => 0
    }
    let mut end = match end_opt {
      Some(v) => v
      None => length
    }
    if start < 0 {
      start += length
    }
    if start < 0 {
      start = 0
    }
    if start > length {
      start = length
    }
    if end < 0 {
      end += length
    }
    if end < 0 {
      end = 0
    }
    if end > length {
      end = length
    }
    Ok((start, end, step))
  } else {
    let mut start = match start_opt {
      Some(v) => v
      None => length - 1
    }
    let mut end = match end_opt {
      Some(v) => v
      None => -1
    }
    if start < 0 {
      start += length
    }
    if start < 0 {
      start = -1
    }
    if start >= length {
      start = length - 1
    }
    // For negative-step slices, CPython treats `stop=None` specially:
    // `xs[::-1]` uses `stop=-1` (not normalized), but `xs[:-1:-1]` uses
    // `stop=length-1` (because -1 was explicit).
    if end_opt is Some(_) && end < 0 {
      end += length
    }
    if end < 0 {
      end = -1
    }
    if end >= length {
      end = length - 1
    }
    Ok((start, end, step))
  }
}

///|
fn slice_indices_from_values(
  length : Int,
  start_value : Value,
  end_value : Value,
  step_value : Value,
) -> Result[Array[Int], RuntimeError] {
  if length <= 0 {
    return Ok([])
  }
  let (start, end, step) = match
    slice_params_from_values(length, start_value, end_value, step_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  if step > 0 {
    let mut i = start
    while i < end {
      out.push(i)
      i += step
    }
  } else {
    let mut i = start
    while i > end {
      out.push(i)
      i += step
    }
  }
  Ok(out)
}

///|
fn slice_values_by_indices(
  values : Array[Value],
  indices : Array[Int],
) -> Array[Value] {
  let out : Array[Value] = []
  for idx in indices {
    if idx >= 0 && idx < values.length() {
      out.push(values[idx])
    }
  }
  out
}

///|
fn slice_string_by_indices(chars : Array[Char], indices : Array[Int]) -> String {
  let buf = StringBuilder::new()
  for idx in indices {
    if idx >= 0 && idx < chars.length() {
      buf.write_char(chars[idx])
    }
  }
  buf.to_string()
}

///|
fn is_cell_value(value : Value) -> Bool {
  match value {
    Value::Instance(inst) => inst.class.name == "cell"
    _ => false
  }
}

///|
fn cell_new(value : Value) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "cell", bases: [], dict: [] },
    dict: [("value", value)],
  })
}

///|
fn cell_new_unbound() -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "cell", bases: [], dict: [] },
    dict: [],
  })
}

///|
fn cell_get_value(value : Value) -> Value? {
  match value {
    Value::Instance(inst) =>
      if inst.class.name == "cell" {
        get_named_value(inst.dict, "value")
      } else {
        None
      }
    _ => None
  }
}

///|
fn cell_set_value(cell : Value, value : Value) -> Unit {
  match cell {
    Value::Instance(inst) =>
      if inst.class.name == "cell" {
        set_named_value(inst.dict, "value", value)
      } else {
        ()
      }
    _ => ()
  }
}

///|
fn cell_clear_value(cell : Value) -> Unit {
  match cell {
    Value::Instance(inst) =>
      if inst.class.name == "cell" {
        for idx = 0; idx < inst.dict.length(); idx = idx + 1 {
          if inst.dict[idx].0 == "value" {
            let _ = inst.dict.remove(idx)
            break
          }
        }
      } else {
        ()
      }
    _ => ()
  }
}

///|
fn deref_cell_value(value : Value) -> Value {
  match cell_get_value(value) {
    Some(v) => v
    None => value
  }
}

///|
fn maybe_deref_cell_value(value : Value) -> Value? {
  if is_cell_value(value) {
    cell_get_value(value)
  } else {
    Some(value)
  }
}

///|
fn ensure_local_cell(
  locals : Array[(String, Value)],
  name : String,
  initial : Value,
) -> Unit {
  for i = 0; i < locals.length(); i = i + 1 {
    if locals[i].0 == name {
      if is_cell_value(locals[i].1) {
        return
      }
      locals[i] = (name, cell_new(initial))
      return
    }
  }
  locals.push((name, cell_new(initial)))
}

///|
fn ensure_local_cell_unbound(
  locals : Array[(String, Value)],
  name : String,
) -> Unit {
  for i = 0; i < locals.length(); i = i + 1 {
    if locals[i].0 == name {
      if is_cell_value(locals[i].1) {
        return
      }
      locals[i] = (name, cell_new(locals[i].1))
      return
    }
  }
  locals.push((name, cell_new_unbound()))
}

///|
fn capture_cell_closure(
  locals : Array[(String, Value)],
) -> Array[(String, Value)] {
  let out : Array[(String, Value)] = []
  for pair in locals {
    if is_cell_value(pair.1) {
      out.push(pair)
    }
  }
  out
}

///|
let closure_env_stack : Ref[Array[Array[(String, Value)]]] = { val: [] }

///|
fn push_closure_env(env : Array[(String, Value)]) -> Unit {
  closure_env_stack.val.push(env)
}

///|
fn pop_closure_env() -> Unit {
  if closure_env_stack.val.length() > 0 {
    let _ = closure_env_stack.val.pop()

  }
}

///|
fn current_closure_env() -> Array[(String, Value)] {
  if closure_env_stack.val.length() > 0 {
    closure_env_stack.val[closure_env_stack.val.length() - 1]
  } else {
    []
  }
}

///|
fn get_from_env(
  name : String,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
) -> Value? {
  for pair in locals {
    if pair.0 == name {
      return Some(deref_cell_value(pair.1))
    }
  }
  if closure_env_stack.val.length() > 0 {
    let env = closure_env_stack.val[closure_env_stack.val.length() - 1]
    for pair in env {
      if pair.0 == name {
        return Some(deref_cell_value(pair.1))
      }
    }
  }
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  for pair in builtins {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn set_global_value(
  globals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < globals.length(); i = i + 1 {
    if globals[i].0 == name {
      globals[i] = (name, value)
      return
    }
  }
  globals.push((name, value))
}

///|
fn get_global_value(globals : Array[(String, Value)], name : String) -> Value? {
  for pair in globals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn delete_global_value(globals : Array[(String, Value)], name : String) -> Unit {
  for idx = 0; idx < globals.length(); idx = idx + 1 {
    if globals[idx].0 == name {
      let _ = globals.remove(idx)
      break
    }
  }
}

///|
fn clone_locals(locals : Array[(String, Value)]) -> Array[(String, Value)] {
  let result : Array[(String, Value)] = []
  for pair in locals {
    result.push(pair)
  }
  result
}

///|
fn set_local_value(
  locals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  for i = 0; i < locals.length(); i = i + 1 {
    if locals[i].0 == name {
      if is_cell_value(locals[i].1) {
        cell_set_value(locals[i].1, value)
      } else {
        locals[i] = (name, value)
      }
      return
    }
  }
  locals.push((name, value))
}

///|
fn get_local_value(locals : Array[(String, Value)], name : String) -> Value? {
  for pair in locals {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
fn delete_local_value(locals : Array[(String, Value)], name : String) -> Unit {
  for idx = 0; idx < locals.length(); idx = idx + 1 {
    if locals[idx].0 == name {
      let _ = locals.remove(idx)
      break
    }
  }
}

///|
/// Scope declarations (minimal): tracks `global` names in the active function.
priv struct ScopeDecls {
  globals : Array[String]
  nonlocals : Array[String]
}

///|
let scope_decls_stack : Ref[Array[ScopeDecls]] = { val: [] }

///|
fn push_scope_decls(global_names : Array[String]) -> Unit {
  scope_decls_stack.val.push(ScopeDecls::{
    globals: global_names,
    nonlocals: [],
  })
}

///|
fn push_scope_decls_with_nonlocals(
  global_names : Array[String],
  nonlocal_names : Array[String],
) -> Unit {
  scope_decls_stack.val.push(ScopeDecls::{
    globals: global_names,
    nonlocals: nonlocal_names,
  })
}

///|
fn pop_scope_decls() -> Unit {
  if scope_decls_stack.val.length() > 0 {
    let _ = scope_decls_stack.val.pop()

  }
}

///|
fn in_function_scope() -> Bool {
  scope_decls_stack.val.length() > 0
}

///|
fn scope_name_is_global(name : String) -> Bool {
  if scope_decls_stack.val.length() == 0 {
    return false
  }
  let decls = scope_decls_stack.val[scope_decls_stack.val.length() - 1]
  for n in decls.globals {
    if n == name {
      return true
    }
  }
  false
}

///|
fn scope_name_is_nonlocal(name : String) -> Bool {
  if scope_decls_stack.val.length() == 0 {
    return false
  }
  let decls = scope_decls_stack.val[scope_decls_stack.val.length() - 1]
  for n in decls.nonlocals {
    if n == name {
      return true
    }
  }
  false
}

///|
fn get_scoped_value(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  name : String,
) -> Value? {
  if scope_name_is_global(name) {
    get_global_value(globals, name)
  } else if scope_name_is_nonlocal(name) {
    match lookup_closure_cell(name) {
      Some(cell) => maybe_deref_cell_value(cell)
      None => None
    }
  } else {
    match get_local_value(locals, name) {
      Some(v) => maybe_deref_cell_value(v)
      None => None
    }
  }
}

///|
fn set_scoped_value(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  name : String,
  value : Value,
) -> Unit {
  if scope_name_is_global(name) {
    set_global_value(globals, name, value)
  } else if scope_name_is_nonlocal(name) {
    match lookup_closure_cell(name) {
      Some(cell) => cell_set_value(cell, value)
      None => ()
    }
  } else {
    set_local_value(locals, name, value)
  }
}

///|
fn delete_scoped_value(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  name : String,
) -> Result[Bool, RuntimeError] {
  if scope_name_is_global(name) {
    if get_global_value(globals, name) is Some(_) {
      delete_global_value(globals, name)
      Ok(true)
    } else {
      Ok(false)
    }
  } else if scope_name_is_nonlocal(name) {
    Ok(false)
  } else {
    match get_local_value(locals, name) {
      Some(v) =>
        if is_cell_value(v) {
          if cell_get_value(v) is None {
            Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "UnboundLocalError: local variable '" +
                name +
                "' referenced before assignment",
              ),
            )
          } else {
            cell_clear_value(v)
            Ok(true)
          }
        } else {
          delete_local_value(locals, name)
          Ok(true)
        }
      None => Ok(false)
    }
  }
}

///|
fn lookup_closure_cell(name : String) -> Value? {
  if closure_env_stack.val.length() == 0 {
    return None
  }
  let env = closure_env_stack.val[closure_env_stack.val.length() - 1]
  for pair in env {
    if pair.0 == name && is_cell_value(pair.1) {
      return Some(pair.1)
    }
  }
  None
}

///|
fn merge_cell_closures(
  locals : Array[(String, Value)],
  extra : Array[(String, Value)],
) -> Array[(String, Value)] {
  let out = capture_cell_closure(locals)
  for pair in extra {
    let mut exists = false
    for existing in out {
      if existing.0 == pair.0 {
        exists = true
        break
      }
    }
    if !exists {
      out.push(pair)
    }
  }
  out
}
