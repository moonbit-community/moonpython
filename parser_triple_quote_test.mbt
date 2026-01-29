///|
fn parser_triple_quote_status(expr_source : String) -> String {
  match parse_expr(expr_source) {
    Ok(_) => "ok"
    Err(err) => "ERR: " + format_parse_error(err)
  }
}

///|
test "parser/triple_quote_string_literal" {
  inspect(parser_triple_quote_status("\"\"\"hello\"\"\""), content="ok")
}
