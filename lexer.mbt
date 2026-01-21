///|
/// Lexer for the mpython interpreter.

///|
priv enum TokenKind {
  IntLit(@bigint.BigInt)
  FloatLit(Double)
  ComplexLit(Double)
  StrLit(String)
  FStrLit(String)
  BoolLit(Bool)
  NoneLit
  Ident(String)
  LParen
  RParen
  LBracket
  RBracket
  LBrace
  RBrace
  Comma
  Colon
  ColonAssign
  Dot
  Plus
  Minus
  Star
  At
  Slash
  SlashSlash
  Percent
  StarStar
  BitAnd
  BitOr
  BitXor
  ShiftLeft
  ShiftRight
  Tilde
  EqEq
  NotEq
  Lt
  Lte
  Gt
  Gte
  Assign
  And
  Or
  Not
  In
  Is
  If
  Else
  For
  Async
  Def
  Return
  Yield
  Await
  Lambda
  Assert
  Import
  From
  Del
  Global
  Nonlocal
  Raise
  Try
  Except
  Finally
  Class
  Pass
  Break
  Continue
  Eof
} derive(Eq)

///|
priv struct Token {
  kind : TokenKind
  start : Int
  end : Int
  line : Int
  column : Int
}

///|
fn make_parse_error(
  kind : ParseErrorKind,
  message : String,
  token : Token,
) -> ParseError {
  ParseError::{
    kind,
    message,
    span: Span::{
      start: token.start,
      end: token.end,
      line: token.line,
      column: token.column,
    },
  }
}

///|
fn unexpected_token_error(token : Token) -> ParseError {
  let message = if token.kind == Eof {
    "invalid syntax"
  } else if token.kind == RParen {
    "unmatched ')'"
  } else if token.kind == RBracket {
    "unmatched ']'"
  } else if token.kind == RBrace {
    "unmatched '}'"
  } else {
    "invalid syntax"
  }
  make_parse_error(ParseErrorKind::UnexpectedToken, message.to_string(), token)
}

///|
fn substring_chars(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  let safe_start = if start < 0 { 0 } else { start }
  let safe_end = if end > chars.length() { chars.length() } else { end }
  if safe_end <= safe_start {
    return ""
  }
  for i = safe_start; i < safe_end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn substring(source : String, start : Int, end : Int) -> String {
  substring_chars(source.to_array(), start, end)
}

///|
fn find_char(source : String, target : Char) -> Int? {
  let chars = source.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == target {
      return Some(i)
    }
  }
  None
}

///|
fn find_last_char(source : String, target : Char) -> Int? {
  let chars = source.to_array()
  let mut idx = chars.length() - 1
  while idx >= 0 {
    if chars[idx] == target {
      return Some(idx)
    }
    if idx == 0 {
      break
    }
    idx -= 1
  }
  None
}

///|
fn is_alpha(c : Char) -> Bool {
  let code = c.to_int()
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (
    code >= 128 &&
    code != 0xA0 &&
    code != 0xA4 &&
    code != 0xFFFD &&
    code != 0xFF0C &&
    code != 0x3002
  )
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || is_digit(c)
}

///|
fn strip_underscores(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text.to_array() {
    if c != '_' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn digit_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - 48)
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn parse_int_literal(text : String) -> @bigint.BigInt {
  let cleaned = strip_underscores(text)
  let chars = cleaned.to_array()
  let mut start = 0
  let mut base = 10
  if chars.length() >= 2 && chars[0] == '0' {
    match chars[1] {
      'x' | 'X' => {
        base = 16
        start = 2
      }
      'o' | 'O' => {
        base = 8
        start = 2
      }
      'b' | 'B' => {
        base = 2
        start = 2
      }
      _ => {
        base = 10
        start = 0
      }
    }
  }
  let mut value = 0N
  for i = start; i < chars.length(); i = i + 1 {
    let d = digit_value(chars[i])
    if d is Some(d) {
      if d >= base {
        break
      }
      value = value * @bigint.BigInt::from_int(base) +
        @bigint.BigInt::from_int(d)
    } else {
      break
    }
  }
  value
}

///|
fn pow10(exp : Int) -> Double {
  let mut result = 1.0
  let count = if exp < 0 { -exp } else { exp }
  for i = 0; i < count; i = i + 1 {
    result = result * 10.0
  }
  if exp < 0 {
    1.0 / result
  } else {
    result
  }
}

///|
fn parse_float_literal(text : String) -> Double {
  let cleaned = strip_underscores(text)
  let chars = cleaned.to_array()
  let mut value = 0.0
  let mut seen_dot = false
  let mut factor = 0.1
  let mut exp_index : Int? = None
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == 'e' || c == 'E' {
      exp_index = Some(i)
      break
    }
    if c == '.' {
      seen_dot = true
    } else if is_digit(c) {
      if seen_dot {
        value = value + (c.to_int() - 48).to_double() * factor
        factor = factor / 10.0
      } else {
        value = value * 10.0 + (c.to_int() - 48).to_double()
      }
    }
  }
  let mut exp = 0
  if exp_index is Some(index) {
    let mut pos = index + 1
    let mut sign = 1
    if pos < chars.length() {
      if chars[pos] == '+' {
        pos += 1
      } else if chars[pos] == '-' {
        sign = -1
        pos += 1
      }
    }
    let mut exp_value = 0
    for i = pos; i < chars.length(); i = i + 1 {
      let c = chars[i]
      if is_digit(c) {
        exp_value = exp_value * 10 + (c.to_int() - 48)
      } else {
        break
      }
    }
    exp = exp_value * sign
  }
  value * pow10(exp)
}

///|
fn slice_tokens(tokens : Array[Token], start : Int, end : Int) -> Array[Token] {
  let result : Array[Token] = []
  for i = start; i < end; i = i + 1 {
    result.push(tokens[i])
  }
  result
}

///|
fn char_to_string(c : Char) -> String {
  let buf = StringBuilder::new()
  buf.write_char(c)
  buf.to_string()
}

///|
fn parse_hex_sequence(
  chars : Array[Char],
  start : Int,
  count : Int,
) -> (Int, Int)? {
  let mut value = 0
  let mut idx = start
  for i = 0; i < count; i = i + 1 {
    if idx >= chars.length() {
      return None
    }
    let d = digit_value(chars[idx])
    if d is Some(d) {
      value = value * 16 + d
      idx += 1
    } else {
      return None
    }
  }
  Some((value, idx))
}

///|
fn is_valid_codepoint(value : Int) -> Bool {
  value >= 0 && value <= 0x10FFFF && !(value >= 0xD800 && value <= 0xDFFF)
}

///|
fn parse_escape(chars : Array[Char], pos : Int) -> (String, Int) {
  if pos >= chars.length() {
    return ("\\", pos)
  }
  let c = chars[pos]
  match c {
    'n' => ("\n", pos + 1)
    't' => ("\t", pos + 1)
    'r' => ("\r", pos + 1)
    '\\' => ("\\", pos + 1)
    '\'' => ("'", pos + 1)
    '"' => ("\"", pos + 1)
    'x' => {
      let seq = parse_hex_sequence(chars, pos + 1, 2)
      if seq is Some((value, next)) {
        (char_to_string(Int::unsafe_to_char(value)), next)
      } else {
        ("\\x", pos + 1)
      }
    }
    'u' => {
      let seq = parse_hex_sequence(chars, pos + 1, 4)
      if seq is Some((value, next)) {
        if is_valid_codepoint(value) {
          (char_to_string(Int::unsafe_to_char(value)), next)
        } else {
          (substring_chars(chars, pos - 1, next), next)
        }
      } else {
        ("\\u", pos + 1)
      }
    }
    'U' => {
      let seq = parse_hex_sequence(chars, pos + 1, 8)
      if seq is Some((value, next)) {
        if is_valid_codepoint(value) {
          (char_to_string(Int::unsafe_to_char(value)), next)
        } else {
          (substring_chars(chars, pos - 1, next), next)
        }
      } else {
        ("\\U", pos + 1)
      }
    }
    _ =>
      if c >= '0' && c <= '7' {
        let mut value = c.to_int() - 48
        let mut idx = pos + 1
        for i = 0; i < 2; i = i + 1 {
          if idx < chars.length() && chars[idx] >= '0' && chars[idx] <= '7' {
            value = value * 8 + (chars[idx].to_int() - 48)
            idx += 1
          } else {
            break
          }
        }
        (char_to_string(Int::unsafe_to_char(value)), idx)
      } else {
        ("\\" + c.to_string(), pos + 1)
      }
  }
}

///|
fn parse_string_literal(
  chars : Array[Char],
  start : Int,
  raw : Bool,
) -> (String, Int, Bool) {
  let quote = chars[start]
  let triple = start + 2 < chars.length() &&
    chars[start + 1] == quote &&
    chars[start + 2] == quote
  let mut i = if triple { start + 3 } else { start + 1 }
  let buf = StringBuilder::new()
  while i < chars.length() {
    let c = chars[i]
    if !raw && c == '\\' {
      if i + 1 < chars.length() && chars[i + 1] == '\n' {
        // Line continuation inside string literal
        i += 2
        continue
      }
      let (segment, next_i) = parse_escape(chars, i + 1)
      buf.write_string(segment)
      i = next_i
      continue
    }
    if !triple && c == '\n' {
      return (buf.to_string(), i, false)
    }
    if c == quote {
      if triple {
        if i + 2 < chars.length() &&
          chars[i + 1] == quote &&
          chars[i + 2] == quote {
          i += 3
          return (buf.to_string(), i, true)
        }
      } else {
        i += 1
        return (buf.to_string(), i, true)
      }
    }
    buf.write_char(c)
    i += 1
  }
  (buf.to_string(), i, false)
}

///|
fn fstring_has_empty_expr(text : String) -> Bool {
  let chars = text.to_array()
  let mut i = 0
  let len = chars.length()
  while i < len {
    let c = chars[i]
    if c == '{' {
      if i + 1 < len && chars[i + 1] == '{' {
        i += 2
        continue
      }
      let after_open = substring(text, i + 1, len)
      match find_fstring_expr_close(after_open) {
        None => return false
        Some(close_rel) => {
          let close = i + 1 + close_rel
          let inner = substring(text, i + 1, close)
          if inner.trim(chars=" \t").length() == 0 {
            return true
          }
          i = close + 1
          continue
        }
      }
    }
    if c == '}' {
      if i + 1 < len && chars[i + 1] == '}' {
        i += 2
        continue
      }
    }
    i += 1
  }
  false
}

///|
fn tokenize_expr(
  source : String,
  line : Int,
  base_offset : Int,
) -> Result[Array[Token], ParseError] {
  let chars = source.to_array()
  let mut i = 0
  let tokens : Array[Token] = []
  let len = chars.length()
  let mut current_line = line
  let mut line_start = 0
  while i < len {
    let c = chars[i]
    if c == '\n' {
      current_line += 1
      i += 1
      line_start = i
      continue
    }
    if c.to_int() == 0 {
      let token = {
        kind: Eof,
        start: base_offset + i,
        end: base_offset + i + 1,
        line: current_line,
        column: i - line_start + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "ValueError: source code string cannot contain null bytes".to_string(),
          token,
        ),
      )
    }
    if c.to_int() == 0xA0 {
      let token = {
        kind: Eof,
        start: base_offset + i,
        end: base_offset + i + 1,
        line: current_line,
        column: i - line_start + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid non-printable character U+00A0".to_string(),
          token,
        ),
      )
    }
    if c.to_int() == 0xA4 {
      let token = {
        kind: Eof,
        start: base_offset + i,
        end: base_offset + i + 1,
        line: current_line,
        column: i - line_start + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid character '¤' (U+00A4)".to_string(),
          token,
        ),
      )
    }
    if c.to_int() == 0xFFFD {
      let token = {
        kind: Eof,
        start: base_offset + i,
        end: base_offset + i + 1,
        line: current_line,
        column: i - line_start + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid character '�' (U+FFFD)".to_string(),
          token,
        ),
      )
    }
    if c.to_int() == 0xFF0C {
      let token = {
        kind: Eof,
        start: base_offset + i,
        end: base_offset + i + 1,
        line: current_line,
        column: i - line_start + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid character '，' (U+FF0C)".to_string(),
          token,
        ),
      )
    }
    if c.to_int() == 0x3002 {
      let token = {
        kind: Eof,
        start: base_offset + i,
        end: base_offset + i + 1,
        line: current_line,
        column: i - line_start + 1,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "invalid character '。' (U+3002)".to_string(),
          token,
        ),
      )
    }
    if c == '\\' {
      if i + 1 < len && chars[i + 1] == '\n' {
        // Line continuation
        i += 2
        current_line += 1
        line_start = i
        continue
      }
      if i + 1 == len {
        let token = {
          kind: Eof,
          start: base_offset + i,
          end: base_offset + i + 1,
          line: current_line,
          column: i - line_start + 2,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::UnexpectedEof,
            "unexpected EOF while parsing".to_string(),
            token,
          ),
        )
      }
      let token = {
        kind: Eof,
        start: base_offset + i + 1,
        end: base_offset + i + 2,
        line: current_line,
        column: i - line_start + 2,
      }
      return Err(
        make_parse_error(
          ParseErrorKind::Syntax,
          "unexpected character after line continuation character".to_string(),
          token,
        ),
      )
    }
    if c == '#' {
      // Comment until end of line
      while i < len && chars[i] != '\n' {
        i += 1
      }
      continue
    }
    if c == ' ' || c == '\t' {
      i += 1
    } else if c == '.' &&
      i + 2 < len &&
      chars[i + 1] == '.' &&
      chars[i + 2] == '.' {
      tokens.push({
        kind: NoneLit,
        start: base_offset + i,
        end: base_offset + i + 3,
        line: current_line,
        column: i - line_start + 1,
      })
      i += 3
    } else if is_digit(c) || (c == '.' && i + 1 < len && is_digit(chars[i + 1])) {
      let start = i
      let mut has_dot = false
      let mut has_exp = false
      let mut is_prefixed = false
      if c == '0' && i + 1 < len {
        let next = chars[i + 1]
        if next == 'x' ||
          next == 'X' ||
          next == 'o' ||
          next == 'O' ||
          next == 'b' ||
          next == 'B' {
          is_prefixed = true
          let base = if next == 'x' || next == 'X' {
            16
          } else if next == 'o' || next == 'O' {
            8
          } else {
            2
          }
          let label = if base == 16 {
            "hexadecimal"
          } else if base == 8 {
            "octal"
          } else {
            "binary"
          }
          i += 2
          let mut digit_count = 0
          while i < len {
            let d = chars[i]
            if d == '_' {
              i += 1
            } else if digit_value(d) is Some(value) {
              if value >= base {
                let token = {
                  kind: Eof,
                  start: base_offset + i,
                  end: base_offset + i + 1,
                  line: current_line,
                  column: i - line_start + 1,
                }
                return Err(
                  make_parse_error(
                    ParseErrorKind::Syntax,
                    "invalid digit '" +
                    d.to_string() +
                    "' in " +
                    label +
                    " literal",
                    token,
                  ),
                )
              }
              digit_count += 1
              i += 1
            } else {
              break
            }
          }
          if digit_count == 0 {
            let token = {
              kind: Eof,
              start: base_offset + start + 1,
              end: base_offset + start + 2,
              line: current_line,
              column: start - line_start + 2,
            }
            return Err(
              make_parse_error(
                ParseErrorKind::Syntax,
                "invalid " + label + " literal",
                token,
              ),
            )
          }
        }
      }
      if !is_prefixed {
        if c == '.' {
          has_dot = true
          i += 1
        }
        while i < len {
          let d = chars[i]
          if d == '_' {
            i += 1
          } else if is_digit(d) {
            i += 1
          } else if d == '.' && !has_dot && !has_exp {
            has_dot = true
            i += 1
          } else if (d == 'e' || d == 'E') && !has_exp {
            if d == 'e' &&
              i + 3 < len &&
              chars[i + 1] == 'l' &&
              chars[i + 2] == 's' &&
              chars[i + 3] == 'e' {
              break
            }
            let mut exp_index = i + 1
            let mut sign_pos : Int? = None
            if exp_index < len &&
              (chars[exp_index] == '+' || chars[exp_index] == '-') {
              sign_pos = Some(exp_index)
              exp_index += 1
            }
            if exp_index < len && is_digit(chars[exp_index]) {
              has_exp = true
              i = exp_index
            } else {
              let error_pos = match sign_pos {
                Some(pos) => pos
                None => start
              }
              let token = {
                kind: Eof,
                start: base_offset + error_pos,
                end: base_offset + error_pos + 1,
                line: current_line,
                column: error_pos - line_start + 1,
              }
              return Err(
                make_parse_error(
                  ParseErrorKind::Syntax,
                  "invalid decimal literal".to_string(),
                  token,
                ),
              )
            }
          } else {
            break
          }
        }
      }
      let mut is_complex = false
      if i < len && (chars[i] == 'j' || chars[i] == 'J') {
        is_complex = true
      } else if i < len && (is_alpha(chars[i]) || chars[i] == '_') {
        let mut j = i
        while j < len {
          let d = chars[j]
          if is_alnum(d) || d == '_' {
            j += 1
          } else {
            break
          }
        }
        let word = substring(source, i, j)
        let allow_juxtaposed = word == "if" ||
          word == "else" ||
          word == "for" ||
          word == "and" ||
          word == "or" ||
          word == "not" ||
          word == "in" ||
          word == "is"
        if !allow_juxtaposed {
          let token = {
            kind: Eof,
            start: base_offset + i,
            end: base_offset + i + 1,
            line: current_line,
            column: i - line_start + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "invalid decimal literal".to_string(),
              token,
            ),
          )
        }
      }
      let text = substring(source, start, i)
      if is_complex && is_prefixed {
        let token = {
          kind: Eof,
          start: base_offset + start,
          end: base_offset + start + 1,
          line: current_line,
          column: start - line_start + 1,
        }
        return Err(
          make_parse_error(
            ParseErrorKind::Syntax,
            "invalid decimal literal".to_string(),
            token,
          ),
        )
      }
      let complex_value = if is_complex {
        parse_float_literal(text)
      } else {
        0.0
      }
      let kind = if is_complex {
        ComplexLit(complex_value)
      } else if is_prefixed {
        IntLit(parse_int_literal(text))
      } else if has_dot || has_exp {
        FloatLit(parse_float_literal(text))
      } else {
        IntLit(parse_int_literal(text))
      }
      let end_pos = if is_complex { i + 1 } else { i }
      i = end_pos
      tokens.push({
        kind,
        start: base_offset + start,
        end: base_offset + end_pos,
        line: current_line,
        column: start - line_start + 1,
      })
    } else if c == '"' || c == '\'' {
      let start = i
      let start_line = current_line
      let start_column = start - line_start + 1
      let triple = start + 2 < chars.length() &&
        chars[start + 1] == chars[start] &&
        chars[start + 2] == chars[start]
      let (value, next_i, closed) = parse_string_literal(chars, i, false)
      if !closed {
        let mut detected_line = current_line
        for ch in substring_chars(chars, start, chars.length()).to_array() {
          if ch == '\n' {
            detected_line += 1
          }
        }
        let message = if triple {
          "unterminated triple-quoted string literal (detected at line " +
          detected_line.to_string() +
          ")"
        } else {
          "unterminated string literal (detected at line " +
          detected_line.to_string() +
          ")"
        }
        let token = {
          kind: Eof,
          start: base_offset + start,
          end: base_offset + start + 1,
          line: current_line,
          column: start - line_start + 1,
        }
        return Err(make_parse_error(ParseErrorKind::Syntax, message, token))
      }
      i = next_i
      let kind = StrLit(value)
      tokens.push({
        kind,
        start: base_offset + start,
        end: base_offset + i,
        line: start_line,
        column: start_column,
      })
      let mut k = start
      while k < i {
        if chars[k] == '\n' {
          current_line += 1
          line_start = k + 1
        }
        k += 1
      }
    } else if is_alpha(c) || c == '_' {
      let start = i
      let mut raw_prefix = false
      let mut f_prefix = false
      let mut j = i
      while j < len {
        let d = chars[j]
        if d == 'r' || d == 'R' {
          raw_prefix = true
          j += 1
        } else if d == 'f' || d == 'F' {
          f_prefix = true
          j += 1
        } else if d == 'u' || d == 'U' || d == 'b' || d == 'B' {
          j += 1
        } else {
          break
        }
      }
      if j > i && j < len && (chars[j] == '"' || chars[j] == '\'') {
        let triple = j + 2 < chars.length() &&
          chars[j + 1] == chars[j] &&
          chars[j + 2] == chars[j]
        let (value, next_i, closed) = parse_string_literal(chars, j, raw_prefix)
        if !closed {
          let mut detected_line = current_line
          for ch in substring_chars(chars, start, chars.length()).to_array() {
            if ch == '\n' {
              detected_line += 1
            }
          }
          let message = if triple {
            "unterminated triple-quoted string literal (detected at line " +
            detected_line.to_string() +
            ")"
          } else {
            "unterminated string literal".to_string()
          }
          let token = {
            kind: Eof,
            start: base_offset + start,
            end: base_offset + start + 1,
            line: current_line,
            column: start - line_start + 1,
          }
          return Err(make_parse_error(ParseErrorKind::Syntax, message, token))
        }
        if f_prefix && fstring_has_empty_expr(value) {
          let mut err_line = current_line
          let mut err_line_start = line_start
          let mut k = start
          while k < next_i {
            if chars[k] == '\n' {
              err_line += 1
              err_line_start = k + 1
            }
            k += 1
          }
          let token = {
            kind: Eof,
            start: base_offset + next_i - 1,
            end: base_offset + next_i,
            line: err_line,
            column: next_i - err_line_start + 1,
          }
          return Err(
            make_parse_error(
              ParseErrorKind::Syntax,
              "f-string: empty expression not allowed".to_string(),
              token,
            ),
          )
        }
        i = next_i
        let kind = if f_prefix { FStrLit(value) } else { StrLit(value) }
        tokens.push({
          kind,
          start: base_offset + start,
          end: base_offset + i,
          line: current_line,
          column: start - line_start + 1,
        })
        let mut k = start
        while k < i {
          if chars[k] == '\n' {
            current_line += 1
            line_start = k + 1
          }
          k += 1
        }
      } else {
        while i < len {
          let d = chars[i]
          if is_alnum(d) || d == '_' {
            i += 1
          } else {
            break
          }
        }
        let ident = substring(source, start, i)
        let kind = match ident {
          "True" => BoolLit(true)
          "False" => BoolLit(false)
          "None" => NoneLit
          "and" => And
          "or" => Or
          "not" => Not
          "in" => In
          "is" => Is
          "if" => If
          "else" => Else
          "for" => For
          "async" => Async
          "def" => Def
          "return" => Return
          "yield" => Yield
          "await" => Await
          "lambda" => Lambda
          "assert" => Assert
          "import" => Import
          "from" => From
          "del" => Del
          "global" => Global
          "nonlocal" => Nonlocal
          "raise" => Raise
          "try" => Try
          "except" => Except
          "finally" => Finally
          "class" => Class
          "pass" => Pass
          "break" => Break
          "continue" => Continue
          _ => Ident(ident)
        }
        tokens.push({
          kind,
          start: base_offset + start,
          end: base_offset + i,
          line: current_line,
          column: start - line_start + 1,
        })
      }
    } else {
      let start = i
      let (kind, consumed) = match c {
        '(' => (LParen, 1)
        ')' => (RParen, 1)
        '[' => (LBracket, 1)
        ']' => (RBracket, 1)
        '{' => (LBrace, 1)
        '}' => (RBrace, 1)
        ',' => (Comma, 1)
        ':' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (ColonAssign, 2)
          } else {
            (Colon, 1)
          }
        '.' => (Dot, 1)
        '+' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (Plus, 1)
          }
        '-' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (Minus, 1)
          }
        '*' =>
          if i + 1 < len && chars[i + 1] == '*' {
            if i + 2 < len && chars[i + 2] == '=' {
              (Assign, 3)
            } else {
              (StarStar, 2)
            }
          } else if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (Star, 1)
          }
        '@' => (At, 1)
        '/' =>
          if i + 1 < len && chars[i + 1] == '/' {
            if i + 2 < len && chars[i + 2] == '=' {
              (Assign, 3)
            } else {
              (SlashSlash, 2)
            }
          } else if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (Slash, 1)
          }
        '%' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (Percent, 1)
          }
        '&' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (BitAnd, 1)
          }
        '|' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (BitOr, 1)
          }
        '^' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (Assign, 2)
          } else {
            (BitXor, 1)
          }
        '<' =>
          if i + 1 < len && chars[i + 1] == '<' {
            if i + 2 < len && chars[i + 2] == '=' {
              (Assign, 3)
            } else {
              (ShiftLeft, 2)
            }
          } else if i + 1 < len && chars[i + 1] == '=' {
            (Lte, 2)
          } else {
            (Lt, 1)
          }
        '>' =>
          if i + 1 < len && chars[i + 1] == '>' {
            if i + 2 < len && chars[i + 2] == '=' {
              (Assign, 3)
            } else {
              (ShiftRight, 2)
            }
          } else if i + 1 < len && chars[i + 1] == '=' {
            (Gte, 2)
          } else {
            (Gt, 1)
          }
        '~' => (Tilde, 1)
        '=' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (EqEq, 2)
          } else {
            (Assign, 1)
          }
        '!' =>
          if i + 1 < len && chars[i + 1] == '=' {
            (NotEq, 2)
          } else {
            let token = {
              kind: Eof,
              start: base_offset + start,
              end: base_offset + start + 1,
              line: current_line,
              column: start - line_start + 1,
            }
            return Err(unexpected_token_error(token))
          }
        _ => {
          let token = {
            kind: Eof,
            start: base_offset + start,
            end: base_offset + start + 1,
            line: current_line,
            column: start - line_start + 1,
          }
          return Err(unexpected_token_error(token))
        }
      }
      tokens.push({
        kind,
        start: base_offset + start,
        end: base_offset + i,
        line: current_line,
        column: start - line_start + 1,
      })
      i += consumed
    }
  }
  tokens.push({
    kind: Eof,
    start: base_offset + len,
    end: base_offset + len,
    line: current_line,
    column: len - line_start + 1,
  })
  Ok(tokens)
}
