///|
fn annotation_has_forbidden_expression(expr : Expr) -> Bool {
  match expr {
    Expr::Yield(_)
    | Expr::YieldFrom(_)
    | Expr::Await(_)
    | Expr::NamedExpr(..) => true
    // A lambda body is a separate code object; its defaults are not.
    Expr::Lambda(defaults~, ..) =>
      defaults.any(annotation_has_forbidden_expression)
    Expr::FString(text) => annotation_fstring_content(text).1
    _ => expression_children(expr).any(annotation_has_forbidden_expression)
  }
}

///|
fn future_annotation_error_line(body : Array[Stmt], line : Int32) -> Int32? {
  for stmt in body {
    let children : Array[Array[Stmt]] = []
    let annotations : Array[Expr] = []
    match stmt {
      Stmt::WithSpan(span~, stmt~) =>
        if future_annotation_error_line([stmt], span.line) is Some(error) {
          return Some(error)
        }
      Stmt::AnnAssign(annotation~, ..) => annotations.push(annotation)
      Stmt::Function(annotations=items, return_annotation~, body~, ..) => {
        for item in items {
          annotations.push(item.1)
        }
        if return_annotation is Some(expr) {
          annotations.push(expr)
        }
        children.push(body)
      }
      Stmt::Class(body~, ..)
      | Stmt::With(body~, ..)
      | Stmt::AsyncWith(body~, ..) => children.push(body)
      Stmt::If(body~, else_body~, ..)
      | Stmt::While(body~, else_body~, ..)
      | Stmt::For(body~, else_body~, ..)
      | Stmt::AsyncFor(body~, else_body~, ..) => {
        children.push(body)
        children.push(else_body)
      }
      Stmt::Match(cases~, ..) =>
        for case in cases {
          children.push(case.2)
        }
      Stmt::Try(body~, handlers~, else_body~, finally_body~) => {
        children.push(body)
        for handler in handlers {
          children.push(handler.body)
        }
        children.push(else_body)
        children.push(finally_body)
      }
      _ => ()
    }
    for expr in annotations {
      if annotation_has_forbidden_expression(expr) {
        return Some(line)
      }
    }
    for child in children {
      if future_annotation_error_line(child, line) is Some(error) {
        return Some(error)
      }
    }
  }
  None
}

///|
fn compile_annotation(
  expr : Expr,
  b : BcBuilder,
  span : Span?,
  future : Bool,
) -> Result[Unit, RuntimeError] {
  if future {
    let index = b.add_const(Value::Str(annotation_source(expr)))
    let _ = b.emit(BcOp::LoadConst(index), span)
    Ok(())
  } else {
    compile_expr(expr, b, span)
  }
}

///|
// Reconstruct annotation expressions from the AST, retaining precedence rather
// than source whitespace/parentheses, as Python's postponed annotations do.
fn annotation_source(expr : Expr, precedence~ : Int32 = 0) -> String {
  fn join(items : Array[Expr]) -> String {
    items.map(fn(item) { annotation_source(item) }).join(", ")
  }
  fn comp(clauses : Array[CompClause], filters : Array[Expr]) -> String {
    let out = StringBuilder()
    for clause in clauses {
      out.write_string(if clause.is_async { " async for " } else { " for " })
      out.write_string(annotation_target_source(clause.target, outer=true))
      out.write_string(" in ")
      out.write_string(annotation_source(clause.iter, precedence=3))
      for filter in clause.filters {
        out.write_string(" if " + annotation_source(filter, precedence=3))
      }
    }
    for filter in unowned_comprehension_filters(clauses, filters) {
      out.write_string(" if ")
      out.write_string(annotation_source(filter, precedence=3))
    }
    out.to_string()
  }
  fn optional(expr : Expr?) -> String {
    match expr {
      Some(expr) => annotation_source(expr)
      None => ""
    }
  }
  let (text, level) = match expr {
    Expr::WithSpan(expr~, ..) => return annotation_source(expr, precedence~)
    Expr::Name(name) => (name, 16)
    Expr::Literal(Literal::Float(value)) => (annotation_float_source(value), 16)
    Expr::Literal(literal) => (repr_fallback(literal_to_value(literal)), 16)
    Expr::Tuple(items) =>
      (
        "(" + join(items) + (if items.length() == 1 { "," } else { "" }) + ")",
        16,
      )
    Expr::List(items) => ("[" + join(items) + "]", 16)
    Expr::Set(items) =>
      (if items.is_empty() { "{*()}" } else { "{" + join(items) + "}" }, 16)
    Expr::Dict(items) =>
      (
        "{" +
        items
        .map(fn(item) {
          match strip_expr_span(item.0) {
            Expr::DoubleStarred(value~) => "**" + annotation_source(value)
            _ => annotation_source(item.0) + ": " + annotation_source(item.1)
          }
        })
        .join(", ") +
        "}",
        16,
      )
    Expr::ListComp(elt~, clauses~, filters~) =>
      ("[" + annotation_source(elt) + comp(clauses, filters) + "]", 16)
    Expr::SetComp(elt~, clauses~, filters~) =>
      ("{" + annotation_source(elt) + comp(clauses, filters) + "}", 16)
    Expr::GenExp(elt~, clauses~, filters~) =>
      ("(" + annotation_source(elt) + comp(clauses, filters) + ")", 16)
    Expr::DictComp(key~, value~, clauses~, filters~) =>
      (
        "{" +
        annotation_source(key) +
        ": " +
        annotation_source(value) +
        comp(clauses, filters) +
        "}",
        16,
      )
    Expr::Lambda(params~, defaults~, body~) => {
      let mut default_index = 0
      let parameters = params
        .map(fn(param) {
          if param.has_suffix("=") {
            let name = substring(param, 0, param.length() - 1)
            let text = name + "=" + annotation_source(defaults[default_index])
            default_index += 1
            text
          } else {
            param
          }
        })
        .join(", ")
      (
        "lambda" +
        (if parameters.is_empty() { "" } else { " " + parameters }) +
        ": " +
        annotation_source(body),
        1,
      )
    }
    Expr::IfExpr(condition~, then_expr~, else_expr~) =>
      (
        annotation_source(then_expr, precedence=3) +
        " if " +
        annotation_source(condition, precedence=3) +
        " else " +
        annotation_source(else_expr, precedence=2),
        2,
      )
    Expr::FString(text) =>
      ("f" + repr_string(annotation_fstring_content(text).0), 16)
    Expr::NamedExpr(name~, value~) =>
      ("(" + name + " := " + annotation_source(value) + ")", 16)
    Expr::Yield(value) =>
      (
        "(yield" +
        (if value is Some(v) { " " + annotation_source(v) } else { "" }) +
        ")",
        16,
      )
    Expr::YieldFrom(value) =>
      ("(yield from " + annotation_source(value) + ")", 16)
    Expr::Await(value) =>
      ("await " + annotation_source(value, precedence=16), 15)
    Expr::Slice(start~, end~, step~) =>
      (
        optional(start) +
        ":" +
        optional(end) +
        (if step is Some(_) { ":" + optional(step) } else { "" }),
        16,
      )
    Expr::Attribute(value~, attr~) =>
      (
        annotation_source(value, precedence=16) +
        (if strip_expr_span(value) is Expr::Literal(Literal::Int(_)) {
          " ."
        } else {
          "."
        }) +
        attr,
        16,
      )
    Expr::Subscript(value~, index~) => {
      let index = match strip_expr_span(index) {
        Expr::Tuple(items) =>
          if items.is_empty() {
            "()"
          } else {
            join(items) + (if items.length() == 1 { "," } else { "" })
          }
        Expr::Starred(..) => annotation_source(index) + ","
        _ => annotation_source(index)
      }
      (annotation_source(value, precedence=16) + "[" + index + "]", 16)
    }
    Expr::Call(callee~, args~) => {
      let arguments = if args.length() == 1 &&
        strip_expr_span(args[0]) is Expr::GenExp(..) {
        let generator = annotation_source(args[0])
        substring(generator, 1, generator.length() - 1)
      } else {
        join(args)
      }
      (annotation_source(callee, precedence=16) + "(" + arguments + ")", 16)
    }
    Expr::Keyword(name~, value~) => (name + "=" + annotation_source(value), 16)
    Expr::Starred(value~) => ("*" + annotation_source(value, precedence=7), 16)
    Expr::DoubleStarred(value~) =>
      ("**" + annotation_source(value, precedence=7), 16)
    Expr::Unary(op~, expr~) => {
      let (op, level) = match op {
        Pos => ("+", 13)
        Neg => ("-", 13)
        Invert => ("~", 13)
        Not => ("not ", 5)
      }
      (op + annotation_source(expr, precedence=level), level)
    }
    Expr::Binary(op~, left~, right~) => {
      let (symbol, level) = match op {
        Add => ("+", 11)
        Sub => ("-", 11)
        Mul => ("*", 12)
        MatMul => ("@", 12)
        Div => ("/", 12)
        FloorDiv => ("//", 12)
        Mod => ("%", 12)
        Pow => ("**", 14)
        ShiftLeft => ("<<", 10)
        ShiftRight => (">>", 10)
        BitAnd => ("&", 9)
        BitXor => ("^", 8)
        BitOr => ("|", 7)
      }
      let power = op is Pow
      (
        annotation_source(left, precedence=level + (if power { 1 } else { 0 })) +
        " " +
        symbol +
        " " +
        annotation_source(right, precedence=if power { 13 } else { level + 1 }),
        level,
      )
    }
    Expr::BoolOp(op~, values~) => {
      let (symbol, level) = match op {
        And => (" and ", 4)
        Or => (" or ", 3)
      }
      (
        values
        .map(fn(value) { annotation_source(value, precedence=level + 1) })
        .join(symbol),
        level,
      )
    }
    Expr::Compare(left~, ops~, comparators~) => {
      let out = StringBuilder()
      out.write_string(annotation_source(left, precedence=7))
      for i in 0..<ops.length() {
        let op = match ops[i] {
          Eq => "=="
          NotEq => "!="
          Lt => "<"
          Lte => "<="
          Gt => ">"
          Gte => ">="
          In => "in"
          NotIn => "not in"
          Is => "is"
          IsNot => "is not"
        }
        out.write_string(
          " " + op + " " + annotation_source(comparators[i], precedence=7),
        )
      }
      (out.to_string(), 6)
    }
  }
  if level < precedence {
    "(" + text + ")"
  } else {
    text
  }
}

///|
fn eval_annotation_with_env(
  expr : Expr,
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  if get_global_value(globals, "__mpython_future_annotations__")
    is Some(Value::Bool(true)) {
    Ok(Value::Str(annotation_source(expr)))
  } else {
    eval_expr_with_env(expr, locals, globals, builtins, io)
  }
}

///|
fn annotation_target_source(target : Target, outer~ : Bool = false) -> String {
  match target {
    Target::Name(name) => name
    Target::Tuple(items) => {
      let text = items
        .map(fn(item) { annotation_target_source(item) })
        .join(", ") +
        (if items.length() == 1 { "," } else { "" })
      if outer && !items.is_empty() {
        text
      } else {
        "(" + text + ")"
      }
    }
    Target::List(items) =>
      "[" +
      items.map(fn(item) { annotation_target_source(item) }).join(", ") +
      "]"
    Target::Starred(target) => "*" + annotation_target_source(target)
    Target::Attribute(value~, attr~) =>
      annotation_source(Expr::Attribute(value~, attr~))
    Target::Subscript(value~, index~) =>
      annotation_source(Expr::Subscript(value~, index~))
  }
}

///|
// F-string replacement expressions have to be validated even though the
// string itself is postponed. Reuse the runtime scanner for brace/string rules.
fn annotation_fstring_content(text : String) -> (String, Bool) {
  let out = StringBuilder()
  let chars = text.to_array()
  let mut i = 0
  let mut forbidden = false
  while i < chars.length() {
    if (chars[i] == '{' || chars[i] == '}') &&
      i + 1 < chars.length() &&
      chars[i + 1] == chars[i] {
      out.write_char(chars[i])
      out.write_char(chars[i])
      i += 2
      continue
    }
    if chars[i] != '{' {
      if chars[i] == '}' {
        forbidden = true
      }
      out.write_char(chars[i])
      i += 1
      continue
    }
    let close = match
      find_fstring_expr_close(substring(text, i + 1, text.length())) {
      Some(close) => i + 1 + close
      None => return (text, true)
    }
    let inner = substring(text, i + 1, close)
    let (expr_and_conv, format) = match find_top_level_format_colon(inner) {
      Some(pos) =>
        (
          substring(inner, 0, pos),
          Some(substring(inner, pos + 1, inner.length())),
        )
      None => (inner, None)
    }
    let (raw, conversion) = match
      find_top_level_fstring_conversion_bang(expr_and_conv) {
      Some(pos) =>
        (
          substring(expr_and_conv, 0, pos),
          substring(expr_and_conv, pos, expr_and_conv.length()),
        )
      None => (expr_and_conv, "")
    }
    let debug = find_top_level_fstring_debug_equal(raw)
    let expression = match debug {
      Some(pos) => substring(raw, 0, pos)
      None => raw
    }
    let expression = match parse_expr(expression.trim(chars=" \t").to_owned()) {
      Ok(expr) => expr
      Err(_) => return (text, true)
    }
    if annotation_has_forbidden_expression(expression) {
      forbidden = true
    }
    if debug is Some(_) {
      out.write_string(raw)
    }
    out.write_string("{" + annotation_source(expression))
    if conversion.is_empty() && debug is Some(_) && format is None {
      out.write_string("!r")
    } else {
      out.write_string(conversion)
    }
    if format is Some(format) {
      let formatted = annotation_fstring_content(format)
      forbidden = forbidden || formatted.1
      out.write_string(":" + formatted.0)
    }
    out.write_char('}')
    i = close + 1
  }
  (out.to_string(), forbidden)
}

///|
// Python's AST unparser uses float repr: scientific notation below 1e-4 and
// from 1e16, a signed two-digit exponent, and a decimal point for integral floats.
fn annotation_float_source(value : Double) -> String {
  if value.is_pos_inf() {
    return "1e309"
  }
  if value.is_neg_inf() {
    return "-1e309"
  }
  let raw = value.to_string()
  let negative = raw.has_prefix("-")
  let unsigned = if negative { substring(raw, 1, raw.length()) } else { raw }
  let parts = unsigned.split("e").to_array()
  let mantissa = parts[0].to_owned()
  let explicit_exp = if parts.length() == 2 {
    @string.parse_int(parts[1]) catch {
      _ => 0
    }
  } else {
    0
  }
  let mut point = 0
  let digits = StringBuilder()
  let mut after_point = false
  for ch in mantissa.to_array() {
    if ch == '.' {
      after_point = true
    } else {
      if !after_point {
        point += 1
      }
      digits.write_char(ch)
    }
  }
  let digits = digits.to_string()
  let mut first = 0
  while first < digits.length() && digits.to_array()[first] == '0' {
    first += 1
  }
  let sign = if negative { "-" } else { "" }
  if first == digits.length() {
    return sign + "0.0"
  }
  let exponent = point + explicit_exp - first - 1
  let mut last = digits.length()
  while last > first + 1 && digits.to_array()[last - 1] == '0' {
    last -= 1
  }
  let significant = substring(digits, first, last)
  if exponent < -4 || exponent >= 16 {
    let exp = exponent.abs().to_string()
    sign +
    substring(significant, 0, 1) +
    (if significant.length() > 1 {
      "." + substring(significant, 1, significant.length())
    } else {
      ""
    }) +
    "e" +
    (if exponent < 0 { "-" } else { "+" }) +
    (if exp.length() < 2 { "0" } else { "" }) +
    exp
  } else if explicit_exp == 0 {
    raw + (if raw.contains(".") { "" } else { ".0" })
  } else {
    // Core currently prints this range in fixed notation. Keep conversion
    // correct if its notation threshold changes.
    let out = StringBuilder()
    out.write_string(sign)
    if exponent < 0 {
      out.write_string("0.")
      for i = 0; i < -exponent - 1; i = i + 1 {
        out.write_char('0')
      }
      out.write_string(significant)
    } else {
      for i = 0; i <= exponent; i = i + 1 {
        out.write_char(
          if i < significant.length() {
            significant.to_array()[i]
          } else {
            '0'
          },
        )
      }
      out.write_char('.')
      if significant.length() > exponent + 1 {
        out.write_string(
          substring(significant, exponent + 1, significant.length()),
        )
      } else {
        out.write_char('0')
      }
    }
    out.to_string()
  }
}
