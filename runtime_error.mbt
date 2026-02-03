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
        "StopAsyncIteration:", "UnicodeError:", "UnicodeDecodeError:", "UnicodeEncodeError:",
        "UnicodeTranslateError:", "ModuleNotFoundError:", "OSError:", "FileNotFoundError:",
        "FileExistsError:", "PermissionError:", "IsADirectoryError:", "NotADirectoryError:",
        "SystemExit:", "SkipTest:", "struct.error:", "BufferError:", "RecursionError:",
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
          let mut type_name = prefix.trim(chars=":").to_string()
          if type_name == "struct.error" {
            // `struct.error` is exposed as an exception class named `error` from
            // the `_struct` module. Matching relies on class names.
            type_name = "error".to_string()
          }
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
let active_frame_env_stack : Ref[Array[TracebackEnv]] = { val: [] }

///|
let active_span_stack : Ref[Array[Span]] = { val: [] }

///|
fn snapshot_frame_env_stack() -> Array[TracebackEnv] {
  let stack = active_frame_env_stack.val
  if stack.length() == 0 {
    []
  } else {
    [stack[stack.length() - 1]]
  }
}

///|
fn set_traceback_frame_env(
  locals : Array[(String, Value)],
  globals : Array[(String, Value)],
) -> Unit {
  if active_frame_env_stack.val.length() == 0 {
    return
  }
  let idx = active_frame_env_stack.val.length() - 1
  active_frame_env_stack.val[idx] = TracebackEnv::{ locals, globals }
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
  // Capture only the currently executing (innermost) frame at raise-time.
  // Outer frames are appended as the exception unwinds through callers, which
  // more closely matches CPython's traceback growth semantics.
  let stack = active_frame_stack.val
  if stack.length() == 0 {
    return []
  }
  let frames : Array[TracebackFrame] = []
  let f0 = stack[stack.length() - 1]
  frames.push(TracebackFrame::{
    name: f0.name,
    filename: f0.filename,
    line: f0.line,
    column: f0.column,
    end_column: 0,
  })
  // Best-effort: map the active span stack onto the active frame stack so
  // callers can display accurate "last instruction" locations for nested calls
  // (e.g. decorators, multi-line expressions, recursion).
  let spans = active_span_stack.val
  if spans.length() > frames.length() {
    // In the AST evaluator spans can nest within a single frame, making the
    // span stack longer than the frame stack. In that case, only trust the
    // current (innermost) span to avoid corrupting outer frame locations.
    match current_span() {
      Some(span) => {
        let mut last = frames[frames.length() - 1]
        let mut width = span.end - span.start
        if width <= 0 {
          width = 1
        }
        let end_column = if width > 512 { 0 } else { span.column + width }
        last = TracebackFrame::{
          name: last.name,
          filename: last.filename,
          line: span.line,
          column: span.column,
          end_column,
        }
        frames[frames.length() - 1] = last
      }
      None => ()
    }
    return frames
  }
  let mut i = 0
  let max = if frames.length() < spans.length() {
    frames.length()
  } else {
    spans.length()
  }
  while i < max {
    let frame_idx = frames.length() - 1 - i
    let span_idx = spans.length() - 1 - i
    let span = spans[span_idx]
    let last = frames[frame_idx]
    let mut width = span.end - span.start
    if width <= 0 {
      width = 1
    }
    let end_column = if width > 512 { 0 } else { span.column + width }
    frames[frame_idx] = TracebackFrame::{
      name: last.name,
      filename: last.filename,
      line: span.line,
      column: span.column,
      end_column,
    }
    i = i + 1
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
fn ensure_recursion_available() -> Result[Unit, RuntimeError] {
  if active_frame_stack.val.length() >= current_config().max_recursion {
    Err(
      make_runtime_error(
        RuntimeErrorKind::Runtime,
        "RecursionError: maximum recursion depth exceeded".to_string(),
      ),
    )
  } else {
    Ok(())
  }
}

///|
fn push_traceback_frame(name : String, filename : String) -> Unit {
  active_frame_stack.val.push(TracebackFrame::{
    name,
    filename,
    line: 1,
    column: 1,
    end_column: 0,
  })
  active_frame_env_stack.val.push(TracebackEnv::{ locals: [], globals: [] })
}

///|
fn pop_traceback_frame() -> Unit {
  if active_frame_stack.val.length() == 0 {
    return
  }
  let _ = active_frame_stack.val.remove(active_frame_stack.val.length() - 1)
  if active_frame_env_stack.val.length() > 0 {
    let _ = active_frame_env_stack.val.remove(
      active_frame_env_stack.val.length() - 1,
    )

  }
}

///|
fn push_active_span(span : Span) -> Unit {
  active_span_stack.val.push(span)
}

///|
fn pop_active_span() -> Unit {
  if active_span_stack.val.length() == 0 {
    return
  }
  let span = active_span_stack.val.remove(active_span_stack.val.length() - 1)
  // Record the last completed source location for the currently active frame.
  // This intentionally happens on span pop (end of an instruction/step) so
  // callers paused in a nested call keep their previous `f_lineno` value.
  if active_frame_stack.val.length() == 0 {
    return
  }
  let idx = active_frame_stack.val.length() - 1
  let last = active_frame_stack.val[idx]
  let mut width = span.end - span.start
  if width <= 0 {
    width = 1
  }
  let end_column = if width > 512 { 0 } else { span.column + width }
  active_frame_stack.val[idx] = TracebackFrame::{
    name: last.name,
    filename: last.filename,
    line: span.line,
    column: span.column,
    end_column,
  }
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
    traceback_envs: snapshot_frame_env_stack(),
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
    traceback_envs: [],
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
