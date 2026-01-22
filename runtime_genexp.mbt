///|
/// Generator expression helpers.

///|
fn genexp_targets_to_target(targets : Array[String]) -> Target {
  if targets.length() == 1 {
    Target::Name(targets[0])
  } else {
    let out : Array[Target] = []
    for name in targets {
      out.push(Target::Name(name))
    }
    Target::Tuple(out)
  }
}

///|
fn genexp_filters_to_condition(filters : Array[Expr]) -> Expr? {
  if filters.length() == 0 {
    None
  } else if filters.length() == 1 {
    Some(filters[0])
  } else {
    Some(Expr::BoolOp(op=BoolOp::And, values=filters))
  }
}

///|
fn genexp_to_generator_body(
  elt : Expr,
  clauses : Array[CompClause],
  filters : Array[Expr],
) -> Array[Stmt] {
  let inner : Array[Stmt] = [Stmt::Yield(Some(elt))]
  let conditioned = match genexp_filters_to_condition(filters) {
    Some(cond) => [Stmt::If(condition=cond, body=inner, else_body=[])]
    None => inner
  }
  let mut body = conditioned
  let mut i = clauses.length()
  while i > 0 {
    i = i - 1
    let clause = clauses[i]
    body = [
      Stmt::For(
        target=genexp_targets_to_target(clause.targets),
        iter=clause.iter,
        body~,
        else_body=[],
      ),
    ]
  }
  body
}

///|
fn genexp_local_taken(locals : Array[(String, Value)], name : String) -> Bool {
  for pair in locals {
    if pair.0 == name {
      return true
    }
  }
  false
}

///|
fn fresh_genexp_local(locals : Array[(String, Value)]) -> String {
  let base = "__mpython_genexp_iter".to_string()
  if !genexp_local_taken(locals, base) {
    return base
  }
  let mut i = 0
  while true {
    let candidate = base + "_" + i.to_string()
    if !genexp_local_taken(locals, candidate) {
      return candidate
    }
    i = i + 1
  }
  base
}
