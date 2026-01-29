///|
/// Regression tests for comprehension unpacking error semantics under bytecode.

///|
fn bc4_find_listcomp_template(code : BcCode) -> FunctionValue? {
  for c in code.consts {
    match c {
      Value::Function(func) =>
        if func.name == "<listcomp>" {
          return Some(func)
        }
      _ => ()
    }
  }
  None
}

///|
test "bytecode/listcomp_unpack_mismatch_errors_as_typeerror" {
  let source = "[a for a, b, c in [(1, 2)]]"
  let program = match parse(source) {
    Ok(v) => v
    Err(err) => {
      inspect(format_parse_error(err))
      panic()
    }
  }
  let code = match compile_module_to_bc(program, "<test>".to_string()) {
    Ok(v) => v
    Err(err) => {
      inspect(format_runtime_error(err))
      panic()
    }
  }
  let template_opt = bc4_find_listcomp_template(code)
  inspect(template_opt is Some(_), content="true")
  let template = template_opt.unwrap()
  let inner_code = match
    compile_stmts_to_bc(template.body, template.name, "<test>".to_string()) {
    Ok(v) => v
    Err(err) => {
      inspect(format_runtime_error(err))
      panic()
    }
  }
  let mut has_setup_except = false
  let mut setup_pc = -1
  let mut pop_pc = -1
  let mut unpack_pc = -1
  let mut i = 0
  for op in inner_code.ops {
    if pop_pc < 0 {
      match op {
        BcOp::PopExcept => pop_pc = i
        _ => ()
      }
    }
    match op {
      BcOp::SetupExcept(_) => {
        has_setup_except = true
        if setup_pc < 0 {
          setup_pc = i
        }
      }
      BcOp::UnpackSequence(n) => if n == 3 && unpack_pc < 0 { unpack_pc = i }
      _ => ()
    }
    if has_setup_except && pop_pc >= 0 && unpack_pc >= 0 {
      break
    }
    i = i + 1
  }
  inspect(has_setup_except, content="true")
  inspect(setup_pc >= 0 && pop_pc >= 0 && unpack_pc >= 0, content="true")
  inspect(setup_pc < unpack_pc && unpack_pc < pop_pc, content="true")
  inspect(test_exec_error(source), content="TypeError: cannot unpack")
}
