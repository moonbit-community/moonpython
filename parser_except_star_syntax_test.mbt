///|
fn parser_except_star_status(source : String) -> String {
  match parse(source) {
    Ok(_) => "ok"
    Err(err) => "ERR: " + format_parse_error(err)
  }
}

///|
test "parser/except_star_allows_space_before_star" {
  let source =
    #|try:
    #|  pass
    #|except *TypeError as e:
    #|  pass
  inspect(parser_except_star_status(source), content="ok")
}
