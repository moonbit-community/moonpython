///|
/// Bytecode builder helpers (constant/name pooling and jump patching).

///|
pub(all) struct BcBuilder {
  code : BcCode
}

///|
pub fn BcBuilder::new(name : String, filename : String) -> BcBuilder {
  BcBuilder::{ code: BcCode::empty(name, filename) }
}

///|
pub fn BcBuilder::emit(self : BcBuilder, op : BcOp, span : Span?) -> Int {
  let pc = self.code.ops.length()
  self.code.ops.push(op)
  self.code.spans.push(span)
  pc
}

///|
pub fn BcBuilder::intern_name(self : BcBuilder, name : String) -> Int {
  for i = 0; i < self.code.names.length(); i = i + 1 {
    if self.code.names[i] == name {
      return i
    }
  }
  let idx = self.code.names.length()
  self.code.names.push(name)
  idx
}

///|
pub fn BcBuilder::add_const(self : BcBuilder, value : Value) -> Int {
  let idx = self.code.consts.length()
  self.code.consts.push(value)
  idx
}

///|
pub fn bc_patch_jump(code : BcCode, pc : Int, target : Int) -> Unit {
  match code.ops[pc] {
    BcOp::Jump(_) => code.ops[pc] = BcOp::Jump(target)
    BcOp::JumpIfFalse(_) => code.ops[pc] = BcOp::JumpIfFalse(target)
    BcOp::JumpIfTrue(_) => code.ops[pc] = BcOp::JumpIfTrue(target)
    BcOp::JumpIfFalseOrPop(_) => code.ops[pc] = BcOp::JumpIfFalseOrPop(target)
    BcOp::JumpIfTrueOrPop(_) => code.ops[pc] = BcOp::JumpIfTrueOrPop(target)
    BcOp::ForIter(_) => code.ops[pc] = BcOp::ForIter(target)
    BcOp::SetupExcept(_) => code.ops[pc] = BcOp::SetupExcept(target)
    BcOp::SetupFinally(_) => code.ops[pc] = BcOp::SetupFinally(target)
    BcOp::EnterFinally(_) => code.ops[pc] = BcOp::EnterFinally(target)
    _ => ()
  }
}
