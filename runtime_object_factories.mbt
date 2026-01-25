///|
/// Object factories for dict views, code, and type aliases.

///|
let env_registry_counter : Ref[@bigint.BigInt] = { val: 1N }

///|
let env_registry : Ref[Array[(@bigint.BigInt, Array[(String, Value)])]] = {
  val: [],
}

///|
fn register_env_mapping(env : Array[(String, Value)]) -> @bigint.BigInt {
  let id = env_registry_counter.val
  env_registry_counter.val = id + 1N
  env_registry.val.push((id, env))
  id
}

///|
fn lookup_env_mapping(id : @bigint.BigInt) -> Array[(String, Value)]? {
  for pair in env_registry.val {
    if pair.0 == id {
      return Some(pair.1)
    }
  }
  None
}

///|
let module_globals_dict_class_ref : Ref[ClassValue?] = { val: None }

///|
fn module_globals_dict_class() -> ClassValue {
  match module_globals_dict_class_ref.val {
    Some(klass) => return klass
    None => ()
  }
  let dict : Array[(String, Value)] = [
    (
      "__getitem__",
      Value::Function(FunctionValue::{
        name: "module_globals.__getitem__",
        params: ["self", "key"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__setitem__",
      Value::Function(FunctionValue::{
        name: "module_globals.__setitem__",
        params: ["self", "key", "value"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__delitem__",
      Value::Function(FunctionValue::{
        name: "module_globals.__delitem__",
        params: ["self", "key"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__iter__",
      Value::Function(FunctionValue::{
        name: "module_globals.__iter__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__len__",
      Value::Function(FunctionValue::{
        name: "module_globals.__len__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "__contains__",
      Value::Function(FunctionValue::{
        name: "module_globals.__contains__",
        params: ["self", "key"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "get",
      Value::Function(FunctionValue::{
        name: "module_globals.get",
        params: ["self", "key", "default"],
        defaults: [Value::None],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "keys",
      Value::Function(FunctionValue::{
        name: "module_globals.keys",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "values",
      Value::Function(FunctionValue::{
        name: "module_globals.values",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "items",
      Value::Function(FunctionValue::{
        name: "module_globals.items",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "pop",
      Value::Function(FunctionValue::{
        name: "module_globals.pop",
        params: ["self", "key", "default"],
        defaults: [Value::None],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "update",
      Value::Function(FunctionValue::{
        name: "module_globals.update",
        params: ["self", "other"],
        defaults: [Value::None],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
    (
      "copy",
      Value::Function(FunctionValue::{
        name: "module_globals.copy",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  ]
  let klass = ClassValue::{ name: "module_globals_dict", bases: [], dict }
  module_globals_dict_class_ref.val = Some(klass)
  klass
}

///|
fn make_module_globals_dict_instance(env : Array[(String, Value)]) -> Value {
  Value::Instance(InstanceValue::{
    class: module_globals_dict_class(),
    dict: [("$__env_id__", Value::Int(register_env_mapping(env)))],
  })
}

///|
fn make_dict_view_class(name : String) -> ClassValue {
  let dict : Array[(String, Value)] = []
  dict.push(
    (
      "__iter__",
      Value::Function(FunctionValue::{
        name: "__iter__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  dict.push(
    (
      "__len__",
      Value::Function(FunctionValue::{
        name: "__len__",
        params: ["self"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  dict.push(
    (
      "__contains__",
      Value::Function(FunctionValue::{
        name: "__contains__",
        params: ["self", "item"],
        defaults: [],
        body: [],
        is_generator: false,
        is_async: false,
        closure: [],
      }),
    ),
  )
  ClassValue::{ name, bases: [], dict }
}

///|
fn make_dict_view_instance(view_name : String, dict_value : Value) -> Value {
  Value::Instance(InstanceValue::{
    class: make_dict_view_class(view_name),
    dict: [("dict", dict_value)],
  })
}

///|
fn make_code_instance_with_meta(
  flags : @bigint.BigInt,
  filename : String,
  name : String,
  firstlineno : @bigint.BigInt,
) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "code", bases: [], dict: [] },
    dict: [
      ("co_flags", Value::Int(flags)),
      ("co_filename", Value::Str(filename)),
      ("co_name", Value::Str(name)),
      ("co_qualname", Value::Str(name)),
      ("co_firstlineno", Value::Int(firstlineno)),
    ],
  })
}

///|
fn make_code_instance(flags : @bigint.BigInt) -> Value {
  make_code_instance_with_meta(
    flags,
    "<code>".to_string(),
    "<code>".to_string(),
    1N,
  )
}

///|
fn make_generic_alias(origin : Value, args : Array[Value]) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "GenericAlias", bases: [], dict: [] },
    dict: [("__origin__", origin), ("__args__", Value::Tuple(args))],
  })
}

///|
fn make_union_type(args : Array[Value]) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "UnionType", bases: [], dict: [] },
    dict: [("__args__", Value::Tuple(args))],
  })
}
