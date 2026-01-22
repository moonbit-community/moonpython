///|
/// mpython interpreter specification
///
/// This file defines the public API contract for a MoonBit-based
/// Python interpreter. Implementations should live in separate files
/// and satisfy the behavior expressed in the spec-driven tests.

///|
/// Source span for errors and diagnostics
pub(all) struct Span {
  start : Int
  end : Int
  line : Int
  column : Int
} derive(ToJson)

///|
/// Literal values that appear in source code
pub enum Literal {
  None
  Bool(Bool)
  Int(@bigint.BigInt)
  Float(Double)
  Complex(Double, Double)
  Str(String)
  Bytes(Array[Int])
} derive(ToJson)

///|
/// Unary operators
pub enum UnaryOp {
  Pos
  Neg
  Not
  Invert
} derive(ToJson)

///|
/// Binary operators
pub enum BinaryOp {
  Add
  Sub
  Mul
  MatMul
  Div
  FloorDiv
  Mod
  Pow
  ShiftLeft
  ShiftRight
  BitAnd
  BitXor
  BitOr
} derive(ToJson)

///|
/// Boolean operators
pub enum BoolOp {
  And
  Or
} derive(ToJson)

///|
/// Comparison operators
pub enum CompareOp {
  Eq
  NotEq
  Lt
  Lte
  Gt
  Gte
  In
  NotIn
  Is
  IsNot
} derive(ToJson)

///|
/// A comprehension clause: `for <targets> in <iter>` (optionally `async for`).
pub struct CompClause {
  is_async : Bool
  targets : Array[String]
  iter : Expr
} derive(ToJson)

///|
/// Expression nodes
pub enum Expr {
  Literal(Literal)
  Name(String)
  Tuple(Array[Expr])
  List(Array[Expr])
  ListComp(elt~ : Expr, clauses~ : Array[CompClause], filters~ : Array[Expr])
  GenExp(elt~ : Expr, clauses~ : Array[CompClause], filters~ : Array[Expr])
  Dict(Array[(Expr, Expr)])
  DictComp(
    key~ : Expr,
    value~ : Expr,
    clauses~ : Array[CompClause],
    filters~ : Array[Expr]
  )
  Set(Array[Expr])
  SetComp(elt~ : Expr, clauses~ : Array[CompClause], filters~ : Array[Expr])
  Lambda(params~ : Array[String], defaults~ : Array[Expr], body~ : Expr)
  IfExpr(condition~ : Expr, then_expr~ : Expr, else_expr~ : Expr)
  FString(String)
  NamedExpr(name~ : String, value~ : Expr)
  Yield(Expr?)
  YieldFrom(Expr)
  Await(Expr)
  Slice(start~ : Expr?, end~ : Expr?, step~ : Expr?)
  Attribute(value~ : Expr, attr~ : String)
  Subscript(value~ : Expr, index~ : Expr)
  Call(callee~ : Expr, args~ : Array[Expr])
  Keyword(name~ : String, value~ : Expr)
  Starred(value~ : Expr)
  DoubleStarred(value~ : Expr)
  Unary(op~ : UnaryOp, expr~ : Expr)
  Binary(op~ : BinaryOp, left~ : Expr, right~ : Expr)
  BoolOp(op~ : BoolOp, values~ : Array[Expr])
  Compare(left~ : Expr, ops~ : Array[CompareOp], comparators~ : Array[Expr])
} derive(ToJson)

///|
/// Assignment targets
pub enum Target {
  Name(String)
  Tuple(Array[Target])
  List(Array[Target])
  Attribute(value~ : Expr, attr~ : String)
  Subscript(value~ : Expr, index~ : Expr)
} derive(ToJson)

///|
/// Match statement patterns (minimal)
pub enum Pattern {
  Wildcard
  Literal(Literal)
  Name(String)
  Tuple(Array[Pattern])
} derive(ToJson)

///|
/// Try/except handler (supports except*)
pub struct ExceptHandler {
  is_star : Bool
  exc : Expr?
  name : String?
  body : Array[Stmt]
} derive(ToJson)

///|
/// Statement nodes
pub enum Stmt {
  ExprStmt(Expr)
  Assign(target~ : Target, value~ : Expr)
  AugAssign(target~ : Target, op~ : BinaryOp, value~ : Expr)
  TypeAlias(name~ : String, type_params~ : Array[String], value~ : Expr)
  Return(Expr?)
  Yield(Expr?)
  YieldFrom(Expr)
  If(condition~ : Expr, body~ : Array[Stmt], else_body~ : Array[Stmt])
  Match(subject~ : Expr, cases~ : Array[(Pattern, Expr?, Array[Stmt])])
  While(condition~ : Expr, body~ : Array[Stmt], else_body~ : Array[Stmt])
  For(
    target~ : Target,
    iter~ : Expr,
    body~ : Array[Stmt],
    else_body~ : Array[Stmt]
  )
  AsyncFor(
    target~ : Target,
    iter~ : Expr,
    body~ : Array[Stmt],
    else_body~ : Array[Stmt]
  )
  Break
  Continue
  Function(
    name~ : String,
    decorators~ : Array[Expr],
    type_params~ : Array[String],
    params~ : Array[String],
    defaults~ : Array[Expr],
    body~ : Array[Stmt],
    is_generator~ : Bool,
    is_async~ : Bool
  )
  Pass
  Global(Array[String])
  Nonlocal(Array[String])
  Assert(condition~ : Expr, message~ : Expr?)
  Raise(exc~ : Expr?, cause~ : Expr?)
  Del(Array[Target])
  Import(module_name~ : String, alias_name~ : String?)
  FromImport(module_name~ : String, names~ : Array[(String, String?)])
  With(context~ : Expr, target~ : String?, body~ : Array[Stmt])
  AsyncWith(context~ : Expr, target~ : String?, body~ : Array[Stmt])
  Try(
    body~ : Array[Stmt],
    handlers~ : Array[ExceptHandler],
    else_body~ : Array[Stmt],
    finally_body~ : Array[Stmt]
  )
  Class(
    name~ : String,
    decorators~ : Array[Expr],
    type_params~ : Array[String],
    bases~ : Array[Expr],
    keywords~ : Array[(String, Expr)],
    body~ : Array[Stmt]
  )
  WithSpan(span~ : Span, stmt~ : Stmt)
} derive(ToJson)

///|
/// Parsed module
pub struct Module {
  body : Array[Stmt]
} derive(ToJson)

///|
/// Parse error categories
pub(all) enum ParseErrorKind {
  Syntax
  Indentation
  UnexpectedToken
  UnexpectedEof
} derive(ToJson)

///|
/// Parse error details
pub(all) struct ParseError {
  kind : ParseErrorKind
  message : String
  span : Span
} derive(ToJson)

///|
/// Runtime error categories
pub(all) enum RuntimeErrorKind {
  Name
  Type
  Attribute
  Index
  Key
  ZeroDivision
  NotImplemented
  Runtime
} derive(ToJson)

///|
/// Runtime error details
pub(all) struct RuntimeError {
  kind : RuntimeErrorKind
  message : String
  span : Span?
  traceback : Array[TracebackFrame]
  exc_type : String
  exc_args : Array[String]
  exc_value : Value?
  exc_cause : Value?
  exc_context : Value?
  exc_suppress_context : Bool
} derive(ToJson)

///|
/// Traceback frame data captured at runtime
pub(all) struct TracebackFrame {
  name : String
  filename : String
  line : Int
  column : Int
} derive(ToJson)

///|
/// Wrap RuntimeError as an error type for use with `raise`
pub suberror MpythonError {
  MpythonError(RuntimeError)
}

///|
/// Test result from running a test directory
pub struct TestResult {
  passed : Int
  failed : Int
  errors : Array[String]
} derive(ToJson)

///|
/// Interpreter configuration
pub struct Config {
  max_recursion : Int
  traceback_limit : Int
  track_spans : Bool
  /// When `false`, only built-in shim modules (e.g. `math`) are allowed.
  ///
  /// This is used by `Interpreter::new_spec()` to keep the environment deterministic.
  allow_filesystem_imports : Bool
  /// Additional roots for resolving `import <name>` from files.
  ///
  /// The interpreter always searches the main script directory (when `main_path` is set)
  /// and the current working directory (".") first.
  import_paths : Array[String]
  /// Path of the "main" script being executed (CLI-only).
  main_path : String?
} derive(ToJson)

///|
/// Runtime values
pub struct FunctionValue {
  name : String
  params : Array[String]
  defaults : Array[Value]
  body : Array[Stmt]
  is_generator : Bool
  is_async : Bool
  closure : Array[(String, Value)]
} derive(ToJson)

///|
/// A Python class object (minimal)
///
/// `dict` is the class namespace holding methods and attributes.
pub struct ClassValue {
  name : String
  bases : Array[Value]
  dict : Array[(String, Value)]
} derive(ToJson)

///|
/// A Python instance object (minimal)
pub struct InstanceValue {
  class : ClassValue
  dict : Array[(String, Value)]
} derive(ToJson)

///|
/// A bound method (minimal descriptor result)
pub struct BoundMethodValue {
  function : FunctionValue
  self : Value
} derive(ToJson)

///|
/// Runtime values available to user code
pub enum Value {
  None
  Bool(Bool)
  Int(@bigint.BigInt)
  Float(Double)
  Complex(Double, Double)
  Str(String)
  Bytes(Array[Int])
  ByteArray(Array[Int])
  MemoryView(Array[Int])
  List(Array[Value])
  Tuple(Array[Value])
  Dict(Array[(Value, Value)])
  Set(Array[Value])
  Function(FunctionValue)
  Class(ClassValue)
  Instance(InstanceValue)
  BoundMethod(BoundMethodValue)
} derive(ToJson)

///|
/// Results produced after executing code
pub struct RunResult {
  value : Value
  stdout : String
  stderr : String
  globals : Array[(String, Value)]
} derive(ToJson)

///|
/// In-memory IO buffers for testing
pub struct MockIO {
  stdin : Array[String]
  stdin_pos : Ref[Int]
  stdout : StringBuilder
  stderr : StringBuilder
}

///|
/// Stateful interpreter
pub struct Interpreter {
  config : Config
  globals : Array[(String, Value)]
  builtins : Array[(String, Value)]
  io : MockIO
}

///|
/// Build a default configuration
#declaration_only
pub fn Config::default() -> Config {
  ...
}

///|
/// Create a new interpreter with default configuration
#declaration_only
pub fn Interpreter::new() -> Interpreter {
  ...
}

///|
/// Create a new interpreter with custom configuration
#declaration_only
pub fn Interpreter::with_config(config : Config) -> Interpreter {
  ...
}

///|
/// Create a new interpreter with builtins
#declaration_only
pub fn Interpreter::with_builtins(
  builtins : Array[(String, Value)],
  config : Config,
) -> Interpreter {
  ...
}

///|
/// Create a new interpreter with explicit IO
#declaration_only
pub fn Interpreter::with_io(config : Config, io : MockIO) -> Interpreter {
  ...
}

///|
/// Create mock IO buffers
#declaration_only
pub fn MockIO::new(stdin : Array[String]) -> MockIO {
  ...
}

///|
/// Read a line from stdin (without newline)
#declaration_only
pub fn MockIO::read_line(self : MockIO) -> String? {
  ...
}

///|
/// Write to stdout
#declaration_only
pub fn MockIO::write_stdout(self : MockIO, text : String) -> Unit {
  ...
}

///|
/// Write to stderr
#declaration_only
pub fn MockIO::write_stderr(self : MockIO, text : String) -> Unit {
  ...
}

///|
/// Retrieve stdout contents
#declaration_only
pub fn MockIO::take_stdout(self : MockIO) -> String {
  ...
}

///|
/// Retrieve stderr contents
#declaration_only
pub fn MockIO::take_stderr(self : MockIO) -> String {
  ...
}

///|
/// Parse a full module from source
#declaration_only
pub fn parse(source : String) -> Result[Module, ParseError] {
  ...
}

///|
/// Parse a single expression from source
#declaration_only
pub fn parse_expr(source : String) -> Result[Expr, ParseError] {
  ...
}

///|
/// Execute a parsed module
#declaration_only
pub fn Interpreter::exec(
  self : Interpreter,
  program : Module,
) -> Result[RunResult, RuntimeError] {
  ...
}

///|
/// Execute source text directly
#declaration_only
pub fn Interpreter::exec_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  ...
}

///|
/// Evaluate a single expression source
#declaration_only
pub fn Interpreter::eval_source(
  self : Interpreter,
  source : String,
) -> Result[RunResult, RuntimeError] {
  ...
}

///|
/// Evaluate a single expression
#declaration_only
pub fn Interpreter::eval(
  self : Interpreter,
  expr : Expr,
) -> Result[Value, RuntimeError] {
  ...
}

///|
/// Retrieve a global variable
#declaration_only
pub fn Interpreter::get_global(self : Interpreter, name : String) -> Value? {
  ...
}

///|
/// Set a global variable
#declaration_only
pub fn Interpreter::set_global(
  self : Interpreter,
  name : String,
  value : Value,
) -> Unit {
  ...
}

///|
/// Render a parse error for diagnostics
#declaration_only
pub fn format_parse_error(error : ParseError) -> String {
  ...
}

///|
/// Render a runtime error for diagnostics
#declaration_only
pub fn format_runtime_error(error : RuntimeError) -> String {
  ...
}

///|
/// Render a runtime error with traceback frames
#declaration_only
pub fn format_runtime_error_with_traceback(
  error : RuntimeError,
  limit : Int,
) -> String {
  ...
}

///|
/// Execute all tests in a directory (like python -m test)
#declaration_only
pub fn Interpreter::execute_test_dir(
  self : Interpreter,
  path : String,
) -> TestResult raise MpythonError {
  ...
}
