///|
/// Object factories for dict views, code, and type aliases.

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
fn make_code_instance(flags : @bigint.BigInt) -> Value {
  Value::Instance(InstanceValue::{
    class: ClassValue::{ name: "code", bases: [], dict: [] },
    dict: [("co_flags", Value::Int(flags))],
  })
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
