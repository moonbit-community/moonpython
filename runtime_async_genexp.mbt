///|
/// Async generator-expression runtime.

///|
priv struct AsyncGenExpState {
  elt : Expr
  clauses : Array[CompClause]
  filters : Array[Expr]
  locals : Array[(String, Value)]
  globals : Array[(String, Value)]
  builtins : Array[(String, Value)]
  io : MockIO
  iters : Array[Value?]
  mut depth : Int
  mut done : Bool
}

///|
let async_genexp_registry : Ref[Array[Ref[AsyncGenExpState]]] = { val: [] }

///|
fn make_async_genexp_instance(id : Int) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "async_generator", bases: [], dict: [] },
    dict: [("id", Value::Int(@bigint.BigInt::from_int(id)))],
  })
}

///|
fn async_genexp_id_from_instance(
  inst : InstanceValue,
) -> Result[Int?, RuntimeError] {
  match get_named_value(inst.dict, "id") {
    Some(Value::Int(v)) =>
      match bigint_to_int_checked(v) {
        Ok(i) => Ok(Some(i))
        Err(err) => Err(err)
      }
    Some(Value::Bool(v)) => Ok(Some(if v { 1 } else { 0 }))
    _ => Ok(None)
  }
}

///|
fn stop_async_iteration() -> RuntimeError {
  make_runtime_error(
    RuntimeErrorKind::Runtime,
    "StopAsyncIteration".to_string(),
  )
}

///|
fn async_genexp_state_from_value(
  async_genexp_value : Value,
) -> Result[Ref[AsyncGenExpState], RuntimeError] {
  match async_genexp_value {
    Value::Instance(inst) =>
      if inst.class.name != "async_generator" {
        Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "'" + inst.class.name + "' object is not an async generator",
          ),
        )
      } else {
        let id_opt = match async_genexp_id_from_instance(inst) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let id = match id_opt {
          Some(id) => id
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "RuntimeError: invalid async generator".to_string(),
              ),
            )
        }
        if id < 0 || id >= async_genexp_registry.val.length() {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Runtime,
              "RuntimeError: invalid async generator id".to_string(),
            ),
          )
        }
        Ok(async_genexp_registry.val[id])
      }
    _ =>
      Err(
        make_runtime_error(
          RuntimeErrorKind::Type,
          "'" +
          type_name_from_value(async_genexp_value) +
          "' object is not an async generator",
        ),
      )
  }
}

///|
fn async_genexp_new(
  elt : Expr,
  clauses : Array[CompClause],
  filters : Array[Expr],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let iters : Array[Value?] = []
  for _ in clauses {
    iters.push(None)
  }
  let state : Ref[AsyncGenExpState] = {
    val: AsyncGenExpState::{
      elt,
      clauses,
      filters,
      locals,
      globals,
      builtins,
      io,
      iters,
      depth: 0,
      done: false,
    },
  }
  let id = async_genexp_registry.val.length()
  async_genexp_registry.val.push(state)
  make_async_genexp_instance(id)
}

///|
fn async_genexp_next(async_genexp_value : Value) -> Result[Value, RuntimeError] {
  let state = match async_genexp_state_from_value(async_genexp_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if state.val.done {
    return Err(stop_async_iteration())
  }
  let n = state.val.clauses.length()
  if n == 0 {
    state.val.done = true
    return eval_expr_with_env(
      state.val.elt,
      state.val.locals,
      state.val.globals,
      state.val.builtins,
      state.val.io,
    )
  }
  while true {
    if state.val.depth >= n {
      let ok = match
        eval_comp_filters(
          state.val.filters,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      state.val.depth = n - 1
      if ok {
        return eval_expr_with_env(
          state.val.elt,
          state.val.locals,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        )
      }
      continue
    }
    let depth = state.val.depth
    let clause = state.val.clauses[depth]
    let iterator = match state.val.iters[depth] {
      Some(v) => v
      None => {
        let iter_value = match
          eval_expr_with_env(
            clause.iter,
            state.val.locals,
            state.val.globals,
            state.val.builtins,
            state.val.io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let iterator = if clause.is_async {
          let aiter_value = match
            get_attr_from_value(
              iter_value,
              "__aiter__",
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match
            call_callable_with_env(
              aiter_value,
              [],
              [],
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        } else {
          match
            iter_value_to_iterator(
              iter_value,
              state.val.globals,
              state.val.builtins,
              state.val.io,
            ) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
        }
        state.val.iters[depth] = Some(iterator)
        iterator
      }
    }
    let item_res = if clause.is_async {
      let anext_value = match
        get_attr_from_value(
          iterator,
          "__anext__",
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let next_awaitable = match
        call_callable_with_env(
          anext_value,
          [],
          [],
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match coroutine_await(next_awaitable) {
        Ok(v) => Ok(Some(v))
        Err(err) =>
          if err.exc_type == "StopAsyncIteration" {
            Ok(None)
          } else {
            Err(err)
          }
      }
    } else {
      match
        iterator_next(
          iterator,
          None,
          state.val.globals,
          state.val.builtins,
          state.val.io,
        ) {
        Ok(v) => Ok(Some(v))
        Err(err) =>
          if err.exc_type == "StopIteration" {
            Ok(None)
          } else {
            Err(err)
          }
      }
    }
    match item_res {
      Ok(Some(item)) => {
        let _ = match
          bind_comp_targets(
            state.val.locals,
            state.val.globals,
            clause.targets,
            item,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        for i = depth + 1; i < n; i = i + 1 {
          state.val.iters[i] = None
        }
        state.val.depth = depth + 1
      }
      Ok(None) => {
        state.val.iters[depth] = None
        if depth == 0 {
          state.val.done = true
          return Err(stop_async_iteration())
        }
        state.val.depth = depth - 1
      }
      Err(err) => return Err(err)
    }
  }
  return Err(stop_async_iteration())
}

///|
fn async_genexp_make_anext_coroutine(
  async_genexp_value : Value,
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Value {
  let body : Array[Stmt] = [
    Stmt::Return(
      Some(
        Expr::Call(callee=Expr::Name("__mpython_asyncgenexp_next"), args=[
          Expr::Name("self"),
        ]),
      ),
    ),
  ]
  let locals : Array[(String, Value)] = [("self", async_genexp_value)]
  coroutine_new(
    body,
    locals,
    globals,
    builtins,
    io,
    [],
    [],
    [],
    Config::default(),
  )
}
