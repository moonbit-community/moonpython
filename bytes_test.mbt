///|
/// Bytes/bytearray/memoryview tests.

///|
fn run_stdout_bytes(source : String) -> String {
  let io = MockIO::new([])
  match Interpreter::with_io(Config::default(), io).exec_source(source) {
    Ok(run) => run.stdout
    Err(err) => "ERR: " + format_runtime_error(err)
  }
}

///|
test "bytes/constructors" {
  let source =
    #|b = bytes([65, 66, 67])
    #|print(b)
    #|ba = bytearray(b)
    #|print(ba)
    #|mv = memoryview(bytes([65]))
    #|print(mv)
  inspect(
    run_stdout_bytes(source),
    content="b'ABC'\nbytearray(b'ABC')\nmemoryview(b'A')\n",
  )
}

///|
test "bytes/sequence_ops" {
  let source =
    #|b = bytes([65, 66, 67, 68])
    #|print(b[1])
    #|print(b[1:3])
    #|ba = bytearray([97, 98, 99])
    #|print(ba[2])
    #|print(ba[1:])
    #|mv = memoryview(bytes([120, 121, 122]))
    #|print(mv[0])
    #|print(mv[1:])
    #|print(len(b))
    #|print(bytes([65]) + bytes([66]))
    #|print(bytes([67]) * 3)
    #|print(2 in bytes([1, 2, 3]))
  inspect(
    run_stdout_bytes(source),
    content="66\nb'BC'\n99\nbytearray(b'bc')\n120\nmemoryview(b'yz')\n4\nb'AB'\nb'CCC'\nTrue\n",
  )
}

///|
test "bytes/fromhex" {
  let source =
    #|print(bytes.fromhex("00ff"))
    #|print(bytes.fromhex("00 ff 0a"))
  inspect(run_stdout_bytes(source), content="b'\\x00\\xff'\nb'\\x00\\xff\\n'\n")
}

///|
test "bytearray/extend" {
  let source =
    #|ba = bytearray()
    #|ba.extend(bytes.fromhex("6162"))
    #|ba.extend([67, 68])
    #|print(ba)
  inspect(run_stdout_bytes(source), content="bytearray(b'abCD')\n")
}
