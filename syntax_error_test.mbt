///|
/// Parser error location tests.

///|
fn parse_error_summary(source : String) -> String {
  match parse(source) {
    Ok(_) => "ok"
    Err(err) =>
      err.message +
      "@" +
      err.span.line.to_string() +
      ":" +
      err.span.column.to_string()
  }
}

///|
test "syntax/unclosed_bracket" {
  inspect(parse_error_summary("x = (1\n"), content="'(' was never closed@1:5")
}

///|
test "syntax/mismatched_bracket" {
  inspect(
    parse_error_summary("x = [1)"),
    content="closing parenthesis ')' does not match opening bracket '['@1:7",
  )
}
