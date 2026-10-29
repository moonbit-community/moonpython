///|
test "async dict comprehension is validated inside a synchronous function" {
  let expr = parse_tokens_expr(
    tokenize_expr("{i: i async for i in els}", 1, 0, 1).unwrap(),
  ).unwrap()
  assert_true(expr_has_async_comprehension(expr))
  match parse("def bar():\n    {i: i async for i in els}") {
    Err(_) => ()
    Ok(_) => fail("accepted async comprehension")
  }
}
