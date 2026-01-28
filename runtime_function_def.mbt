///|
/// Function-definition semantics shared by the AST evaluator and the bytecode VM.

///|
fn make_function_from_template_with_env(
  template : FunctionValue,
  defaults : Array[Value],
  decorators : Array[Value],
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let (global_names, nonlocal_names) = collect_scope_decl_names(template.body)
  let _ = match
    check_scope_decl_conflicts(template.params, global_names, nonlocal_names) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let extra_cells : Array[(String, Value)] = []
  for nonlocal_name in nonlocal_names {
    match get_local_value(locals, nonlocal_name) {
      Some(v) => ensure_local_cell(locals, nonlocal_name, deref_cell_value(v))
      None =>
        match lookup_closure_cell(nonlocal_name) {
          Some(cell) => extra_cells.push((nonlocal_name, cell))
          None =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "SyntaxError: no binding for nonlocal '" +
                nonlocal_name +
                "' found",
              ),
            )
        }
    }
  }
  let inherited = merge_cell_closures(current_closure_env(), extra_cells)
  let closure = merge_cell_closures(locals, inherited)
  let globals_marker = Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "__mpython_globals__", bases: [], dict: [] },
    dict: globals,
  })
  closure.push(("$__mpython_globals__", globals_marker))
  let func = FunctionValue::{
    name: template.name,
    params: template.params,
    defaults,
    body: template.body,
    is_generator: template.is_generator,
    is_async: template.is_async,
    closure,
  }
  let mut defined : Value = Value::Function(func)
  for i = decorators.length(); i > 0; i = i - 1 {
    let decorator_value = decorators[i - 1]
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
                Err(err) => return Err(err)
              }
            Err(err) => return Err(err)
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
            Err(err) => return Err(err)
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
          Err(err) => return Err(err)
        }
    }
  }
  Ok(defined)
}
