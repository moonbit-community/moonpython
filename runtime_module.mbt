///|
/// Minimal module objects for `import` support.

///|
fn module_function_stub(name : String) -> Value {
  Value::Function(FunctionValue::{
    name,
    params: [],
    defaults: [],
    body: [],
    is_generator: false,
    is_async: false,
    closure: [],
  })
}

///|
fn make_module_instance(name : String, dict : Array[(String, Value)]) -> Value {
  let module_class = ClassValue::{ name: "module", bases: [], dict: [] }
  Value::Instance(InstanceValue::{
    class: module_class,
    dict: [("__name__", Value::Str(name))] + dict,
  })
}

///|
fn make_math_module() -> Value {
  make_module_instance("math", [
    ("pi", Value::Float(3.141592653589793)),
    ("e", Value::Float(2.718281828459045)),
    ("sqrt", module_function_stub("math.sqrt")),
    ("pow", module_function_stub("math.pow")),
  ])
}
