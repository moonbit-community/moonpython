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
  RotTwo
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
  BuildSet(Int) // count
  BuildSlice // pops start, stop, step and pushes a slice instance

  // Collection mutation helpers (used for literal unpacking and call args).
  // Stack (top is right):
  // - ListAppend:  [list, value] -> [list]
  // - ListExtend:  [list, iterable] -> [list]
  // - SetAdd:      [set, value] -> [set]
  // - SetUpdate:   [set, iterable] -> [set]
  // - DictSetItem: [dict, key, value] -> [dict]
  // - DictUpdate:  [dict, mapping] -> [dict]
  // - KwListExtendFromDict: [kw_list, mapping] -> [kw_list]
  // - ListToTuple: [list] -> [tuple]
  ListAppend
  ListExtend
  SetAdd
  SetUpdate
  DictSetItem
  DictUpdate
  KwListExtendFromDict
  ListToTuple

  // f-string evaluation.
  // Pops a raw f-string source text and pushes the formatted result string.
  EvalFString

  // Unpacking.
  UnpackSequence(Int) // count; pops iterable and pushes items (reversed) for STORE
  UnpackEx(Int, Int) // before, after; pops iterable and pushes items + list-rest (reversed) for STORE

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
  // Jump that unwinds `finally`/`with` handlers first (used by break/continue).
  UnwindJump(Int, Int) // absolute pc; number of finally handlers to unwind

  // Exceptions.
  SetupExcept(Int) // absolute pc for exception handler
  SetupFinally(Int) // absolute pc for finally handler
  PopExcept
  EnterFinally(Int) // jump to finally handler and mark it active
  EndExcept
  EndFinally
  CheckExceptionMatch // pops handler type value; pushes bool
  LoadException // pushes current exception instance value
  LoadExceptionType // pushes exception type value for `__exit__` (`<class ...>` or a string fallback)
  LoadExceptionTypeName // pushes exception type name (string), for `__aexit__`
  LoadExceptionTraceback // pushes traceback object value
  HasPendingException // pushes bool; true when a pending exception is being unwound
  ClearPendingException // clears the pending exception (for suppressing in `with`/`async with`)
  // Raise an exception value (instance or class) using Python's `raise` statement semantics.
  // Uses the VM's current pending exception (if any) as implicit context.
  Raise
  // `raise exc from cause` (cause may be None).
  RaiseFrom
  Reraise
  // Assertions.
  // - `AssertFail` pops the message value and raises AssertionError.
  // - `AssertFailNone` raises AssertionError with no message expression.
  AssertFail
  AssertFailNone

  // Async helpers.
  Await // pops coroutine, pushes awaited result

  // `match` statement helpers.
  // - MatchPattern: pops subject; pushes either None (no match) or a list of (name, value) tuples.
  // - MatchBind: pops bindings list; binds names; pushes a restore token.
  // - MatchRestore: pops restore token; restores/deletes previous bindings.
  MatchPattern(Int) // patterns[idx]
  MatchBind
  MatchRestore

  // Generator expression helper.
  // Pops the first iterator (already converted with GetIter), clones current locals,
  // binds it into the cloned locals (when iter_name_idx >= 0), ensures cells for
  // all target names, then returns a generator created via `generator_new`.
  //
  // `template` is a `Value::Function` whose body is the generator body for the genexp.
  // `target_names_const` is a Value::Tuple of Value::Str items.
  GenExpNew(Int, Int, Int) // template const idx, iter_name names idx (or -1), target_names_const idx
  // Like GenExpNew, but returns an async generator expression (created via `async_genexp_new`).
  // `spec` points to `code.genexps`.
  AsyncGenExpNew(Int, Int, Int) // genexps[idx], iter_name names idx (or -1), target_names_const idx

  // Calls.
  CallFunction(Int) // positional arg count
  // CALL_FUNCTION_KW-style: pushes keyword values then a tuple of keyword names.
  CallFunctionKw(Int) // positional arg count
  // Varargs/kwargs call helper (used for *args/**kwargs support).
  // Stack: [callee, positional_list, keyword_pairs_list] -> [result]
  CallFunctionVar

  // Function definitions.
  // Stack effect (top is right):
  //   [decorators..., defaults...] -> [defined_value]
  //
  // `template` is a `Value::Function` carrying name/params/body/flags.
  MakeFunction(Int, Int, Int)

  // Class definitions.
  // Stack effect (top is right):
  //   [decorators..., base_specs, keyword_specs] -> [defined_value]
  //
  // `template` is a `Value::Function` whose body is the class suite.
  MakeClass(Int, Int, Int) // template const idx, class name idx, decorator count

  // Annotations.
  // Pops annotation value and stores it into __annotations__[name] (creating dict if needed).
  StoreAnnotation(Int) // names[idx]

  // Augmented assignment.
  // Stack: [rhs] -> []
  AugAssignName(Int, BinaryOp) // names[idx]
  // Stack: [target, rhs] -> []
  AugAssignAttr(Int, BinaryOp) // names[idx]
  // Stack: [target, index, rhs] -> []
  AugAssignSubscr(BinaryOp)

  // Imports.
  ImportName(Int, Int) // consts[module_name_str], names[alias_idx] or -1
  FromImport(Int, Int, Int) // consts[module_name_str], consts[names_tuple], consts[aliases_tuple]

  // Scope checks.
  CheckInFunctionScope(String) // error message when not in a function scope
  CheckInCoroutineScope(String) // error message when not in a coroutine scope

  // Function boundaries.
  ReturnValue
}

///|
pub(all) struct GenExpSpec {
  elt : Expr
  clauses : Array[CompClause]
  filters : Array[Expr]
}

///|
pub(all) struct BcCode {
  name : String
  filename : String
  consts : Array[Value]
  names : Array[String]
  patterns : Array[Pattern]
  genexps : Array[GenExpSpec]
  ops : Array[BcOp]
  // Optional source mapping; aligned with `ops`.
  spans : Array[Span?]
}

///|
pub fn BcCode::empty(name : String, filename : String) -> BcCode {
  BcCode::{
    name,
    filename,
    consts: [],
    names: [],
    patterns: [],
    genexps: [],
    ops: [],
    spans: [],
  }
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
    BcOp::RotTwo => "RotTwo"
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
    BcOp::BuildSet(n) => "BuildSet(" + n.to_string() + ")"
    BcOp::BuildSlice => "BuildSlice"
    BcOp::ListAppend => "ListAppend"
    BcOp::ListExtend => "ListExtend"
    BcOp::SetAdd => "SetAdd"
    BcOp::SetUpdate => "SetUpdate"
    BcOp::DictSetItem => "DictSetItem"
    BcOp::DictUpdate => "DictUpdate"
    BcOp::KwListExtendFromDict => "KwListExtendFromDict"
    BcOp::ListToTuple => "ListToTuple"
    BcOp::EvalFString => "EvalFString"
    BcOp::UnpackSequence(n) => "UnpackSequence(" + n.to_string() + ")"
    BcOp::UnpackEx(before, after) =>
      "UnpackEx(" + before.to_string() + ", " + after.to_string() + ")"
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
    BcOp::UnwindJump(pc, n) =>
      "UnwindJump(" + pc.to_string() + ", " + n.to_string() + ")"
    BcOp::SetupExcept(pc) => "SetupExcept(" + pc.to_string() + ")"
    BcOp::SetupFinally(pc) => "SetupFinally(" + pc.to_string() + ")"
    BcOp::PopExcept => "PopExcept"
    BcOp::EnterFinally(pc) => "EnterFinally(" + pc.to_string() + ")"
    BcOp::EndExcept => "EndExcept"
    BcOp::EndFinally => "EndFinally"
    BcOp::CheckExceptionMatch => "CheckExceptionMatch"
    BcOp::LoadException => "LoadException"
    BcOp::LoadExceptionType => "LoadExceptionType"
    BcOp::LoadExceptionTypeName => "LoadExceptionTypeName"
    BcOp::LoadExceptionTraceback => "LoadExceptionTraceback"
    BcOp::HasPendingException => "HasPendingException"
    BcOp::ClearPendingException => "ClearPendingException"
    BcOp::Raise => "Raise"
    BcOp::RaiseFrom => "RaiseFrom"
    BcOp::Reraise => "Reraise"
    BcOp::AssertFail => "AssertFail"
    BcOp::AssertFailNone => "AssertFailNone"
    BcOp::Await => "Await"
    BcOp::MatchPattern(i) => "MatchPattern(" + i.to_string() + ")"
    BcOp::MatchBind => "MatchBind"
    BcOp::MatchRestore => "MatchRestore"
    BcOp::GenExpNew(template, iter_name, target_names) =>
      "GenExpNew(" +
      template.to_string() +
      ", " +
      iter_name.to_string() +
      ", " +
      target_names.to_string() +
      ")"
    BcOp::AsyncGenExpNew(template, iter_name, target_names) =>
      "AsyncGenExpNew(" +
      template.to_string() +
      ", " +
      iter_name.to_string() +
      ", " +
      target_names.to_string() +
      ")"
    BcOp::CallFunction(n) => "CallFunction(" + n.to_string() + ")"
    BcOp::CallFunctionKw(n) => "CallFunctionKw(" + n.to_string() + ")"
    BcOp::CallFunctionVar => "CallFunctionVar"
    BcOp::MakeFunction(template, default_count, decorator_count) =>
      "MakeFunction(" +
      template.to_string() +
      ", " +
      default_count.to_string() +
      ", " +
      decorator_count.to_string() +
      ")"
    BcOp::MakeClass(template, name_idx, decorator_count) =>
      "MakeClass(" +
      template.to_string() +
      ", " +
      name_idx.to_string() +
      ", " +
      decorator_count.to_string() +
      ")"
    BcOp::StoreAnnotation(i) => "StoreAnnotation(" + i.to_string() + ")"
    BcOp::AugAssignName(i, op) =>
      "AugAssignName(" + i.to_string() + ", " + binary_repr(op) + ")"
    BcOp::AugAssignAttr(i, op) =>
      "AugAssignAttr(" + i.to_string() + ", " + binary_repr(op) + ")"
    BcOp::AugAssignSubscr(op) => "AugAssignSubscr(" + binary_repr(op) + ")"
    BcOp::ImportName(mod_idx, alias_idx) =>
      "ImportName(" + mod_idx.to_string() + ", " + alias_idx.to_string() + ")"
    BcOp::FromImport(mod_idx, names_idx, aliases_idx) =>
      "FromImport(" +
      mod_idx.to_string() +
      ", " +
      names_idx.to_string() +
      ", " +
      aliases_idx.to_string() +
      ")"
    BcOp::CheckInFunctionScope(msg) => "CheckInFunctionScope(" + msg + ")"
    BcOp::CheckInCoroutineScope(msg) => "CheckInCoroutineScope(" + msg + ")"
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
