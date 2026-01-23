///|
/// Runtime error helpers.

///|
fn runtime_error_exc(
  kind : RuntimeErrorKind,
  message : String,
) -> (String, Array[String]) {
  match kind {
    RuntimeErrorKind::ZeroDivision =>
      ("ZeroDivisionError".to_string(), [message])
    RuntimeErrorKind::Name => ("NameError".to_string(), [message])
    RuntimeErrorKind::Type => ("TypeError".to_string(), [message])
    RuntimeErrorKind::Attribute => ("AttributeError".to_string(), [message])
    RuntimeErrorKind::Index => ("IndexError".to_string(), [message])
    RuntimeErrorKind::Key => ("KeyError".to_string(), [message])
    RuntimeErrorKind::NotImplemented =>
      ("NotImplementedError".to_string(), [message])
    RuntimeErrorKind::Runtime => {
      let prefixes : Array[String] = [
        "ValueError:", "OverflowError:", "ImportError:", "AssertionError:", "RuntimeError:",
        "EOFError:", "SyntaxError:", "IndentationError:", "StopIteration:", "UnboundLocalError:",
        "StopAsyncIteration:",
        "SystemExit:",
      ]
      if message == "StopIteration" {
        return ("StopIteration".to_string(), [])
      }
      if message == "StopAsyncIteration" {
        return ("StopAsyncIteration".to_string(), [])
      }
      if message == "SystemExit" {
        return ("SystemExit".to_string(), [])
      }
      for prefix in prefixes {
        if message.has_prefix(prefix) {
          let type_name = prefix.trim(chars=":").to_string()
          let mut rest = match message.strip_prefix(prefix) {
            Some(view) => view.to_string()
            None => "".to_string()
          }
          if rest.has_prefix(" ") {
            rest = match rest.strip_prefix(" ") {
              Some(view) => view.to_string()
              None => rest
            }
          }
          let args = if rest.length() == 0 { [] } else { [rest] }
          return (type_name.to_string(), args)
        }
      }
      if message.has_prefix("line ") {
        return ("SyntaxError".to_string(), [message])
      }
      ("RuntimeError".to_string(), [message])
    }
  }
}

///|
let active_frame_stack : Ref[Array[TracebackFrame]] = { val: [] }

///|
let active_span_stack : Ref[Array[Span]] = { val: [] }

///|
fn clone_traceback_stack(
  stack : Array[TracebackFrame],
) -> Array[TracebackFrame] {
  let out : Array[TracebackFrame] = []
  for frame in stack {
    out.push(frame)
  }
  out
}

///|
fn current_span() -> Span? {
  if active_span_stack.val.length() == 0 {
    None
  } else {
    Some(active_span_stack.val[active_span_stack.val.length() - 1])
  }
}

///|
fn snapshot_traceback() -> Array[TracebackFrame] {
  let frames = clone_traceback_stack(active_frame_stack.val)
  if frames.length() == 0 {
    return frames
  }
  match current_span() {
    Some(span) => {
      let mut last = frames[frames.length() - 1]
      last = TracebackFrame::{
        name: last.name,
        filename: last.filename,
        line: span.line,
        column: span.column,
      }
      frames[frames.length() - 1] = last
    }
    None => ()
  }
  frames
}

///|
fn current_traceback_filename() -> String {
  if active_frame_stack.val.length() == 0 {
    "<module>".to_string()
  } else {
    active_frame_stack.val[active_frame_stack.val.length() - 1].filename
  }
}

///|
fn push_traceback_frame(name : String, filename : String) -> Unit {
  active_frame_stack.val.push(TracebackFrame::{
    name,
    filename,
    line: 1,
    column: 1,
  })
}

///|
fn pop_traceback_frame() -> Unit {
  if active_frame_stack.val.length() == 0 {
    return
  }
  let _ = active_frame_stack.val.remove(active_frame_stack.val.length() - 1)

}

///|
fn push_active_span(span : Span) -> Unit {
  active_span_stack.val.push(span)
  if active_frame_stack.val.length() == 0 {
    return
  }
  let idx = active_frame_stack.val.length() - 1
  let last = active_frame_stack.val[idx]
  active_frame_stack.val[idx] = TracebackFrame::{
    name: last.name,
    filename: last.filename,
    line: span.line,
    column: span.column,
  }
}

///|
fn pop_active_span() -> Unit {
  if active_span_stack.val.length() == 0 {
    return
  }
  let _ = active_span_stack.val.remove(active_span_stack.val.length() - 1)

}

///|
fn make_runtime_error(
  kind : RuntimeErrorKind,
  message : String,
) -> RuntimeError {
  let (exc_type, exc_args) = runtime_error_exc(kind, message)
  RuntimeError::{
    kind,
    message,
    span: current_span(),
    traceback: snapshot_traceback(),
    exc_type,
    exc_args,
    exc_value: None,
    exc_cause: None,
    exc_context: None,
    exc_suppress_context: false,
  }
}

///|
fn make_parse_runtime_error(error : ParseError) -> RuntimeError {
  let message = format_parse_error(error)
  let (exc_type, exc_args) = match error.kind {
    ParseErrorKind::Indentation => ("IndentationError".to_string(), [message])
    _ => ("SyntaxError".to_string(), [message])
  }
  RuntimeError::{
    kind: RuntimeErrorKind::Runtime,
    message,
    span: Some(error.span),
    traceback: [],
    exc_type,
    exc_args,
    exc_value: None,
    exc_cause: None,
    exc_context: None,
    exc_suppress_context: false,
  }
}

///|
pub fn format_parse_error(error : ParseError) -> String {
  if error.message.has_prefix("ValueError:") ||
    error.message.has_prefix("ImportError:") ||
    error.message.has_prefix("NameError:") ||
    error.message.has_prefix("AssertionError:") {
    return error.message
  }
  let msg = match error.kind {
    ParseErrorKind::Indentation => "expected indented block".to_string()
    _ =>
      if error.message == "unmatched ')'" ||
        error.message == "unmatched ']'" ||
        error.message == "unmatched '}'" {
        error.message
      } else {
        "invalid syntax".to_string()
      }
  }
  "line " + error.span.line.to_string() + ":1 " + msg
}

///|
pub fn format_runtime_error(error : RuntimeError) -> String {
  match error.kind {
    RuntimeErrorKind::ZeroDivision => "ZeroDivisionError: " + error.message
    RuntimeErrorKind::Name => "NameError: " + error.message
    RuntimeErrorKind::Type => "TypeError: " + error.message
    RuntimeErrorKind::Attribute => "AttributeError: " + error.message
    RuntimeErrorKind::Index => "IndexError: " + error.message
    RuntimeErrorKind::Key => "KeyError: " + error.message
    RuntimeErrorKind::NotImplemented => "NotImplementedError: " + error.message
    RuntimeErrorKind::Runtime => error.message
  }
}

///|
pub fn format_runtime_error_with_traceback(
  error : RuntimeError,
  limit : Int,
) -> String {
  if limit == 0 || error.traceback.length() == 0 {
    return format_runtime_error(error)
  }
  let buf = StringBuilder::new()
  buf.write_string("Traceback (most recent call last):\n")
  let start = if error.traceback.length() > limit {
    error.traceback.length() - limit
  } else {
    0
  }
  for i = start; i < error.traceback.length(); i = i + 1 {
    let frame = error.traceback[i]
    buf.write_string("  File \"")
    buf.write_string(frame.filename)
    buf.write_string("\", line ")
    buf.write_string(frame.line.to_string())
    buf.write_string(", column ")
    buf.write_string(frame.column.to_string())
    buf.write_string(", in ")
    buf.write_string(frame.name)
    buf.write_char('\n')
  }
  buf.write_string(format_runtime_error(error))
  buf.to_string()
}
