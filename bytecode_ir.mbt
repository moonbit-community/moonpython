///|
/// MicroPython-style bytecode IR.
///
/// NOTE: This is an internal representation (not a stable public API).
/// The intent is to keep the VM stack-based, with explicit jumps and
/// a small constant/name pool similar in spirit to MicroPython.

///|
pub(all) enum BcOp {
  Nop
  PopTop
  DupTop
  RotThree

  // Stack pushes.
  LoadConst(Int) // consts[idx]
  LoadName(Int) // names[idx]

  // Stack pops.
  StoreName(Int) // names[idx]
  DeleteName(Int) // names[idx]

  // Attribute / subscript.
  LoadAttr(Int) // names[idx]
  StoreAttr(Int) // names[idx]
  DeleteAttr(Int) // names[idx]
  LoadSubscr
  StoreSubscr
  DeleteSubscr

  // Builders.
  BuildTuple(Int) // count
  BuildList(Int) // count
  BuildMap(Int) // pair_count

  // Iteration (MicroPython-style).
  GetIter
  ForIter(Int) // absolute pc to jump to on StopIteration; pops iterator on stop

  // Operators.
  Unary(UnaryOp)
  Binary(BinaryOp)
  Compare(CompareOp)

  // Control flow.
  Jump(Int) // absolute pc
  JumpIfFalse(Int) // absolute pc; consumes TOS
  JumpIfTrue(Int) // absolute pc; consumes TOS
  JumpIfFalseOrPop(Int) // absolute pc; keeps TOS on jump, else pops it
  JumpIfTrueOrPop(Int) // absolute pc; keeps TOS on jump, else pops it

  // Exceptions.
  SetupExcept(Int) // absolute pc for exception handler
  PopExcept
  EndExcept
  CheckExceptionMatch // pops handler type value; pushes bool
  LoadException // pushes current exception instance value
  Reraise

  // Calls.
  CallFunction(Int) // positional arg count

  // Function definitions.
  // Stack effect (top is right):
  //   [decorators..., defaults...] -> [defined_value]
  //
  // `template` is a `Value::Function` carrying name/params/body/flags.
  MakeFunction(Int, Int, Int)

  // Function boundaries.
  ReturnValue
}

///|
pub(all) struct BcCode {
  name : String
  filename : String
  consts : Array[Value]
  names : Array[String]
  ops : Array[BcOp]
  // Optional source mapping; aligned with `ops`.
  spans : Array[Span?]
}

///|
pub fn BcCode::empty(name : String, filename : String) -> BcCode {
  BcCode::{ name, filename, consts: [], names: [], ops: [], spans: [] }
}

///|
fn bc_op_repr(op : BcOp) -> String {
  fn unary_repr(u : UnaryOp) -> String {
    match u {
      UnaryOp::Pos => "Pos"
      UnaryOp::Neg => "Neg"
      UnaryOp::Not => "Not"
      UnaryOp::Invert => "Invert"
    }
  }

  fn binary_repr(b : BinaryOp) -> String {
    match b {
      BinaryOp::Add => "Add"
      BinaryOp::Sub => "Sub"
      BinaryOp::Mul => "Mul"
      BinaryOp::MatMul => "MatMul"
      BinaryOp::Div => "Div"
      BinaryOp::FloorDiv => "FloorDiv"
      BinaryOp::Mod => "Mod"
      BinaryOp::Pow => "Pow"
      BinaryOp::ShiftLeft => "ShiftLeft"
      BinaryOp::ShiftRight => "ShiftRight"
      BinaryOp::BitAnd => "BitAnd"
      BinaryOp::BitXor => "BitXor"
      BinaryOp::BitOr => "BitOr"
    }
  }

  fn compare_repr(c : CompareOp) -> String {
    match c {
      CompareOp::Eq => "Eq"
      CompareOp::NotEq => "NotEq"
      CompareOp::Lt => "Lt"
      CompareOp::Lte => "Lte"
      CompareOp::Gt => "Gt"
      CompareOp::Gte => "Gte"
      CompareOp::In => "In"
      CompareOp::NotIn => "NotIn"
      CompareOp::Is => "Is"
      CompareOp::IsNot => "IsNot"
    }
  }

  match op {
    BcOp::Nop => "Nop"
    BcOp::PopTop => "PopTop"
    BcOp::DupTop => "DupTop"
    BcOp::RotThree => "RotThree"
    BcOp::LoadConst(i) => "LoadConst(" + i.to_string() + ")"
    BcOp::LoadName(i) => "LoadName(" + i.to_string() + ")"
    BcOp::StoreName(i) => "StoreName(" + i.to_string() + ")"
    BcOp::DeleteName(i) => "DeleteName(" + i.to_string() + ")"
    BcOp::LoadAttr(i) => "LoadAttr(" + i.to_string() + ")"
    BcOp::StoreAttr(i) => "StoreAttr(" + i.to_string() + ")"
    BcOp::DeleteAttr(i) => "DeleteAttr(" + i.to_string() + ")"
    BcOp::LoadSubscr => "LoadSubscr"
    BcOp::StoreSubscr => "StoreSubscr"
    BcOp::DeleteSubscr => "DeleteSubscr"
    BcOp::BuildTuple(n) => "BuildTuple(" + n.to_string() + ")"
    BcOp::BuildList(n) => "BuildList(" + n.to_string() + ")"
    BcOp::BuildMap(n) => "BuildMap(" + n.to_string() + ")"
    BcOp::GetIter => "GetIter"
    BcOp::ForIter(pc) => "ForIter(" + pc.to_string() + ")"
    BcOp::Unary(u) => "Unary(" + unary_repr(u) + ")"
    BcOp::Binary(b) => "Binary(" + binary_repr(b) + ")"
    BcOp::Compare(c) => "Compare(" + compare_repr(c) + ")"
    BcOp::Jump(pc) => "Jump(" + pc.to_string() + ")"
    BcOp::JumpIfFalse(pc) => "JumpIfFalse(" + pc.to_string() + ")"
    BcOp::JumpIfTrue(pc) => "JumpIfTrue(" + pc.to_string() + ")"
    BcOp::JumpIfFalseOrPop(pc) => "JumpIfFalseOrPop(" + pc.to_string() + ")"
    BcOp::JumpIfTrueOrPop(pc) => "JumpIfTrueOrPop(" + pc.to_string() + ")"
    BcOp::SetupExcept(pc) => "SetupExcept(" + pc.to_string() + ")"
    BcOp::PopExcept => "PopExcept"
    BcOp::EndExcept => "EndExcept"
    BcOp::CheckExceptionMatch => "CheckExceptionMatch"
    BcOp::LoadException => "LoadException"
    BcOp::Reraise => "Reraise"
    BcOp::CallFunction(n) => "CallFunction(" + n.to_string() + ")"
    BcOp::MakeFunction(template, default_count, decorator_count) =>
      "MakeFunction(" +
      template.to_string() +
      ", " +
      default_count.to_string() +
      ", " +
      decorator_count.to_string() +
      ")"
    BcOp::ReturnValue => "ReturnValue"
  }
}

///|
pub fn bc_disassemble(code : BcCode) -> String {
  let b = StringBuilder::new()
  b.write_string("BcCode(" + code.name + ")\n")
  for i = 0; i < code.ops.length(); i = i + 1 {
    let op = code.ops[i]
    b.write_string(i.to_string())
    b.write_string(": ")
    b.write_string(bc_op_repr(op))
    match code.spans[i] {
      Some(span) =>
        b.write_string(
          "  # " + span.line.to_string() + ":" + span.column.to_string(),
        )
      None => ()
    }
    b.write_string("\n")
  }
  b.to_string()
}
