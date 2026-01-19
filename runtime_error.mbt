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
        "EOFError:", "SyntaxError:", "IndentationError:", "StopIteration:",
      ]
      if message == "StopIteration" {
        return ("StopIteration".to_string(), [])
      }
      for prefix in prefixes {
        if message.has_prefix(prefix) {
          let type_name = prefix.substring(start=0, end=prefix.length() - 1)
          let mut rest = message.substring(
            start=prefix.length(),
            end=message.length(),
          )
          if rest.has_prefix(" ") {
            rest = rest.substring(start=1, end=rest.length())
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
fn make_runtime_error(
  kind : RuntimeErrorKind,
  message : String,
) -> RuntimeError {
  let (exc_type, exc_args) = runtime_error_exc(kind, message)
  RuntimeError::{
    kind,
    message,
    span: None,
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
    span: None,
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
