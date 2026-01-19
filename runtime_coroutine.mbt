///|
/// Coroutine runtime (minimal, synchronous `await` support).

///|
priv struct CoroutineState {
  body : Array[Stmt]
  locals : Array[(String, Value)]
  globals : Array[(String, Value)]
  builtins : Array[(String, Value)]
  io : MockIO
  global_names : Array[String]
  nonlocal_names : Array[String]
  closure : Array[(String, Value)]
  mut done : Bool
}

///|
let coroutine_registry : Ref[Array[Ref[CoroutineState]]] = { val: [] }

///|
let coroutine_active_depth : Ref[Int] = { val: 0 }

///|
fn coroutine_is_active() -> Bool {
  coroutine_active_depth.val > 0
}

///|
fn make_coroutine_instance(id : Int) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "coroutine", bases: [], dict: [] },
    dict: [("id", Value::Int(id.to_int64()))],
  })
}

///|
fn coroutine_id_from_instance(inst : InstanceValue) -> Int? {
  match get_named_value(inst.dict, "id") {
    Some(Value::Int(v)) => Some(v.to_int())
    Some(Value::Bool(v)) => Some(if v { 1 } else { 0 })
    _ => None
  }
}

///|
fn coroutine_state_from_value(
  coroutine_value : Value,
) -> Result[Ref[CoroutineState], RuntimeError] {
  match coroutine_value {
    Value::Instance(inst) =>
      if inst.class.name != "coroutine" {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not a coroutine",
          ),
        )
      } else {
        let id = match coroutine_id_from_instance(inst) {
          Some(id) => id
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: invalid coroutine".to_string(),
              ),
            )
        }
        if id < 0 || id >= coroutine_registry.val.length() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "RuntimeError: invalid coroutine id".to_string(),
            ),
          )
        }
        Ok(coroutine_registry.val[id])
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" +
          type_name_from_value(coroutine_value) +
          "' object is not a coroutine",
        ),
      )
  }
}

///|
fn coroutine_new(
  body : Array[Stmt],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
  global_names : Array[String],
  nonlocal_names : Array[String],
  closure : Array[(String, Value)],
) -> Value {
  let state : Ref[CoroutineState] = {
    val: CoroutineState::{
      body,
      locals,
      globals,
      builtins,
      io,
      global_names,
      nonlocal_names,
      closure,
      done: false,
    },
  }
  let id = coroutine_registry.val.length()
  coroutine_registry.val.push(state)
  make_coroutine_instance(id)
}

///|
fn coroutine_await(coroutine_value : Value) -> Result[Value, RuntimeError] {
  let state = match coroutine_state_from_value(coroutine_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if state.val.done {
    return Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "RuntimeError: cannot reuse already awaited coroutine".to_string(),
      ),
    )
  }
  push_closure_env(state.val.closure)
  push_scope_decls_with_nonlocals(
    state.val.global_names,
    state.val.nonlocal_names,
  )
  coroutine_active_depth.val = coroutine_active_depth.val + 1
  let result = eval_block(
    state.val.body,
    state.val.locals,
    state.val.globals,
    state.val.builtins,
    state.val.io,
  )
  coroutine_active_depth.val = coroutine_active_depth.val - 1
  pop_scope_decls()
  pop_closure_env()
  state.val.done = true
  result
}
