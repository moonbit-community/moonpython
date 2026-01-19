# mpython roadmap (toward Python 3.12)

`mpython` is currently a small Python *parser + interpreter* (MoonBit) that targets a practical subset of the language. This roadmap lists the largest missing pieces relative to **CPython 3.12** and proposes an implementation order that keeps the project usable at every milestone.

## Scope

**In scope**
- Core language syntax + semantics needed to run real-world snippets.
- A small “stdlib surface” (selected builtins + a few modules) sufficient for tests/examples.
- Better diagnostics (SyntaxError/tracebacks) and conformance tests.

**Out of scope (for now)**
- Full CPython stdlib parity, C extensions, packaging, bytecode compatibility, performance parity.
- Security sandboxing (the current interpreter is not a security boundary).

## Biggest gaps vs Python 3.12

### 1) Generators, `yield`, and iterator protocol (high impact)
- [x] `yield` / `yield from` as real syntax nodes.
- [x] Generator objects with `__iter__`/`__next__`, `StopIteration`, `return` in generators, `send`/`throw`/`close`.
- [x] Generator expressions `(x for x in xs)`.
- [x] Drive `for` loops and comprehensions via the iterator protocol, including correct `StopIteration` handling.

### 2) Async/await (Python 3.12 baseline)
- [x] `await` expressions (coroutine-only for now).
- [x] `async def` runtime semantics (coroutines + eager `await` via `__mpython_run` helper).
- [ ] `async for`, `async with`, async comprehensions.
- [ ] Coroutine objects, async generators, and a minimal scheduling story (even if test-only).

### 3) Exceptions (correctness + compatibility)
- [x] Exception chaining: `raise ... from ...`, `__cause__`, `__context__`, `__suppress_context__`.
- [ ] Exception groups + `except*` (PEP 654; required for 3.12 compatibility).
- [x] More accurate exception matching (subclass checks, tuples of exception types).
- [ ] Tracebacks with file/line/column spans and stack frames (not just a formatted message).

### 4) Scoping and locals (correct Python semantics)
- [x] Function assignments default to locals (module uses globals).
- [x] `global` statement routing for reads/writes/deletes (runtime-scanned per function).
- [x] Comprehension scope rules with cell bindings for loop targets (enables CPython-style lambda capture tests).
- [ ] Full closures + cell vars for general nested functions (not only comprehension targets).
- [ ] `nonlocal` behavior enforcement and runtime effects.
- [ ] UnboundLocalError / compile-time local analysis (reads before assignment).
- [ ] `exec`/`eval` scoping rules (if supported).

### 5) Modules and imports (minimal but real)
- [ ] `import` should bind a module object and make attributes available (not a hardcoded allowlist).
- [ ] `from ... import ...` semantics, aliasing, `__import__`.
- [ ] Module objects (`types.ModuleType`-like), module globals, and a simple loader (file-based or embedded).
- [ ] A tiny “stdlib shim” for frequently used modules (`math` as a real module, plus a few more as needed).

### 6) Data model and core types (fill the big holes)
- [ ] Arbitrary-precision integers (`int`), not just 64-bit.
- [ ] `bytes`/`bytearray`/`memoryview`.
- [ ] `complex` numbers.
- [ ] More complete `dict`/`set` behavior (hashing, equality, ordering rules, mutation semantics).
- [ ] Descriptor protocol + attribute access (`__getattribute__`, `__getattr__`, `property`, method binding correctness).

### 7) Python 3.12 language additions / syntax parity
- [ ] Full f-string grammar and semantics (PEP 701): nested expressions, format specs, better error reporting.
- [x] f-string conversions (`!r/!s/!a`) and debug `=` runtime behavior.
- [ ] Type parameter syntax and `type` statements (PEP 695): accept/parse (even if runtime ignores), and preserve AST fidelity.
- [ ] Improved parser error recovery to better match CPython’s SyntaxError locations/messages (pragmatic alignment).

## Proposed milestones

### Milestone A — “Python subset that feels right”
- [ ] Implement iterator protocol + real generators (`yield`, `yield from`, genexpr).
- [ ] Fix scoping model (locals/closures) and align comprehension scoping.
- [ ] Improve exception matching + add basic tracebacks.

### Milestone B — “Can run small programs”
- [ ] Real module/import system (file or embedded), with a minimal stdlib shim.
- [ ] Expand builtins and core types where tests demand it.

### Milestone C — “3.12-focused features”
- [ ] PEP 701 f-strings (parser + runtime).
- [ ] PEP 654 exception groups + `except*`.
- [ ] PEP 695 syntax support (parse/AST first, semantics later).

## Conformance approach

- Treat `aaom-mpython/spec_generated_test.mbt` and the `aaom-mpython/reference_test/` corpus as the main compatibility signals.
- Prefer adding targeted end-to-end tests in MoonBit when implementing each missing feature, then grow the Python reference subset over time.
