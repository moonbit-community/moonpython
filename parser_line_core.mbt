///|
/// Line parser state and basic helpers.

///|
priv struct LineParser {
  lines : Array[String]
  mut index : Int
  offsets : Array[Int]
  mut func_depth : Int
  mut async_depth : Int
}

///|
fn LineParser::new(source : String) -> LineParser {
  let lines : Array[String] = []
  for line in source.split("\n") {
    lines.push(line.to_string())
  }
  let offsets : Array[Int] = []
  let mut offset = 0
  for line in lines {
    offsets.push(offset)
    offset += line.length() + 1
  }
  LineParser::{ lines, index: 0, offsets, func_depth: 0, async_depth: 0 }
}

///|

///|
fn LineParser::peek_next_indent(self : LineParser) -> Int {
  let mut idx = self.index
  while idx < self.lines.length() {
    let line = self.lines[idx]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      idx += 1
      continue
    }
    return count_indent(line)
  }
  0
}

///|
fn LineParser::peek_next_significant_index(self : LineParser) -> Int? {
  let mut idx = self.index
  while idx < self.lines.length() {
    let line = self.lines[idx]
    let trimmed = line.trim(chars=" \t").to_string()
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
      idx += 1
      continue
    }
    return Some(idx)
  }
  None
}

///|
fn LineParser::clamp_line_index(self : LineParser, idx : Int) -> Int {
  if idx < 0 {
    return 0
  }
  if idx >= self.lines.length() {
    if self.lines.length() == 0 {
      return 0
    }
    return self.lines.length() - 1
  }
  idx
}
