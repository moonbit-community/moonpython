///|
/// Object core helpers for name lookup and class MRO.

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
fn class_equal(a : ClassValue, b : ClassValue) -> Bool {
  if a.name != b.name {
    return false
  }
  if a.bases.length() != b.bases.length() {
    return false
  }
  if a.dict.length() != b.dict.length() {
    return false
  }
  for i = 0; i < a.bases.length(); i = i + 1 {
    match (a.bases[i], b.bases[i]) {
      (Value::Class(left), Value::Class(right)) =>
        if left.name != right.name {
          return false
        }
      (Value::Function(left), Value::Function(right)) =>
        if left.name != right.name {
          return false
        }
      _ => return false
    }
  }
  for i = 0; i < a.dict.length(); i = i + 1 {
    if a.dict[i].0 != b.dict[i].0 {
      return false
    }
  }
  true
}

///|
fn class_in_list(
  list : Array[ClassValue],
  klass : ClassValue,
  start : Int,
) -> Bool {
  for i = start; i < list.length(); i = i + 1 {
    if class_equal(list[i], klass) {
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
        if class_in_list(other, head, 1) {
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
      if seq.length() > 0 && class_equal(seq[0], pick) {
        let _ = seq.remove(0)

      }
    }
  }
  Ok(out)
}

///|
fn class_mro_with_seen(
  klass : ClassValue,
  seen : Array[ClassValue],
) -> Result[Array[ClassValue], RuntimeError] {
  for item in seen {
    if class_equal(item, klass) {
      return Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "cannot create a consistent method resolution order".to_string(),
        ),
      )
    }
  }
  let next_seen : Array[ClassValue] = []
  for item in seen {
    next_seen.push(item)
  }
  next_seen.push(klass)
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
fn class_includes_tuple(klass : ClassValue) -> Bool {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(_) => return false
  }
  for cls in mro {
    if cls.name == "tuple" {
      return true
    }
  }
  false
}

///|
fn class_includes_set(klass : ClassValue) -> Bool {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(_) => return false
  }
  for cls in mro {
    if cls.name == "set" {
      return true
    }
  }
  false
}

///|
fn class_includes_frozenset(klass : ClassValue) -> Bool {
  let mro = match class_mro(klass) {
    Ok(value) => value
    Err(_) => return false
  }
  for cls in mro {
    if cls.name == "frozenset" {
      return true
    }
  }
  false
}
