///|
/// PEP 695 syntax tests.

///|
fn join_strings(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < items.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(items[i])
  }
  buf.to_string()
}

///|
fn stmt_summary(stmt : Stmt) -> String {
  match stmt {
    Stmt::WithSpan(span=_, stmt=inner) => stmt_summary(inner)
    Stmt::TypeAlias(name~, type_params~, value~) => {
      let _ = value
      "TypeAlias:" + name + "[" + join_strings(type_params) + "]"
    }
    Stmt::Function(
      name~,
      decorators~,
      type_params~,
      params~,
      defaults~,
      annotations~,
      return_annotation~,
      body~,
      is_generator~,
      is_async~
    ) => {
      let _ = decorators
      let _ = params
      let _ = defaults
      let _ = annotations
      let _ = return_annotation
      let _ = body
      let _ = is_generator
      let _ = is_async
      "Function:" + name + "[" + join_strings(type_params) + "]"
    }
    Stmt::Class(name~, decorators~, type_params~, bases~, keywords~, body~) => {
      let _ = decorators
      let _ = bases
      let _ = keywords
      let _ = body
      "Class:" + name + "[" + join_strings(type_params) + "]"
    }
    _ => "<other>"
  }
}

///|
test "pep695/parse_type_params" {
  let source =
    #|type Alias[T, U: int, V = str] = dict[T, U]
    #|def func[T, *Ts, **P](x, y): pass
    #|class Box[T](Base): pass
  let summary = match parse(source) {
    Ok(parsed_module) => {
      let parts : Array[String] = []
      for stmt in parsed_module.body {
        parts.push(stmt_summary(stmt))
      }
      join_strings(parts)
    }
    Err(err) => "ERR: " + format_parse_error(err)
  }
  inspect(
    summary,
    content="TypeAlias:Alias[T, U: int, V = str], " +
      "Function:func[T, *Ts, **P], " +
      "Class:Box[T]",
  )
}

///|
test "pep695/exec_type_alias_no_error" {
  let source =
    #|type Alias[T] = int
    #|value = 1
  inspect(test_exec_error(source), content="ok")
}
