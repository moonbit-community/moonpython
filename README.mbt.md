# moonbit-community/moonpython

A small Python parser + interpreter implemented in MoonBit.

## Status

Recent additions:
- PEP 701 f-strings (escaped braces, nested format specs, debug `=`).
- PEP 695 syntax support for type parameters and `type` statements (parse/AST only).
- Improved SyntaxError reporting for bracket mismatches and unclosed brackets.

Notes:
- Type parameters and `type` aliases are parsed and preserved in the AST; runtime behavior is currently a no-op.

## Roadmap

See `ROADMAP.md` for the current checklist and milestone status.

## Testing

This repo has two test layers:

1) MoonBit tests in this repo (fast feedback for parser/runtime/bytecode)
2) A pragmatic CPython `Lib/test` smoke runner (compatibility tracking)

### Quick checks

```bash
moon check --target native
moon fmt
```

### Run MoonBit tests

Note: the generated spec suite (`spec_generated_test.mbt`) is large, so the first
compile/run can take a while. Prefer `--target native` for speed.

```bash
moon test --target native
```

Useful variants:

```bash
# Run a single test file
moon test --target native -p moonbit-community/moonpython -f parser_line_test.mbt

# Run a subset by name (glob)
moon test --target native -F 'generated/expr/1454'

# Update snapshots when behavior intentionally changes
moon test --target native --update
```

### Parse-only smoke check

`cmd/main` supports `--parse-only` to validate parsing without execution:

```bash
moon run cmd/main -- --parse-only path/to/file.py
```

## Run a Python program (file)

From the `moonpython/` directory:

```bash
moon run cmd/main -- path/to/program.py
```

Example:

```bash
moon run cmd/main -- examples/tasks.py
```

## Run a module (`-m`)

`cmd/main` supports `-m` (package `__main__.py` preferred when present):

```bash
moon run cmd/main -- --stdlib Lib -m test.test_range
```

## Using the CPython `Lib/` snapshot

This repo vendors CPython's `Lib/` under `moonpython/Lib/`. You can point the
interpreter to it with `--stdlib`:

```bash
moon run cmd/main -- --stdlib Lib examples/stdlib_imports.py
```

Notes:
- `--stdlib` accepts any directory; `Lib/` is the current CPython snapshot.
- We do **not** support C extensions; only pure-Python modules are expected to run.

## Smoke-run `Lib/test`

There's a pragmatic runner in `scripts/run_libtests.py` that executes
`Lib/test/test_*.py` modules via `unittest` (import-style execution) and reports
pass/fail/timeout status:

```bash
python3 scripts/run_libtests.py --target native --target-dir _build
```

You can also run a single `Lib/test` module directly:

```bash
moon run cmd/main --target native -- --stdlib Lib -m unittest test.test_unittest.test_case
```

Useful flags:
- `--pattern REGEX`: only run matching modules
- `--timeout SECONDS`: per-module timeout (default: 20)
- `--slow-timeout SECONDS`: timeout for known slow modules (default: 600)
- `--target-dir DIR`: pass through to `moon --target-dir` to avoid build locks
- `--native-release`: build the native runner in release mode
- `--runner direct`: run modules as `__main__` instead of importing via `unittest`

Example: focus on unittest-related modules:

```bash
python3 scripts/run_libtests.py --target native --target-dir _build \
  --pattern '^test\\.test_unittest($|\\.)' --timeout 120
```

## Compatibility checklist

This is a coarse, user-facing checklist (not a full spec).

- [x] Parser + AST for a large subset of Python 3 syntax
- [x] PEP 701 f-strings (basic escaped braces, nested format specs, debug `=`)
- [x] PEP 654 `except*` syntax (parse + basic handling)
- [x] `match` / `case` parsing (pattern matching syntax)
- [x] PEP 695 type parameter / `type` statement syntax (parse/AST only; runtime no-op)
- [x] Bytecode compiler + VM for module execution (default execution path)
- [x] Bytecode execution for normal functions (function bodies compile to bytecode)
- [x] Compilation failures are surfaced (no silent fallback to the legacy AST evaluator)
- [x] `scripts/run_libtests.py` runner for CPython `Lib/test` smoke runs
- [x] `Lib/test`: `test.test_unittest.*` passes on `--target native` (some modules may be skipped)
- [x] `Lib/test`: `test.test_pprint` passes on `--target native` (some modules may be skipped)

Not implemented / incomplete (selected highlights):

- [ ] Full CPython `Lib/test` compatibility (many modules still fail)
- [ ] CPython C extension modules (e.g. `_socket`, `_ctypes`, `_locale`)
- [ ] Full `threading` / `multiprocessing` semantics (many tests rely on OS threads/sockets)
- [ ] Bytecode compiler parity for all statements/expressions (some constructs still raise `NotImplementedError`)
- [ ] Full `unittest.mock` behavior parity (work in progress)

## REPL / stdin runner

Use `cmd/repl` to execute code from stdin (line-by-line):

```bash
printf 'print("hello")\n' | moon run cmd/repl
```

Notes:
- `cmd/main` runs a file path argument.
- `cmd/repl` reads stdin, splits by lines, and executes each line.
- In `cmd/repl`, use `:quit` / `:exit` to stop early.

## Library usage

If you want to call the interpreter from MoonBit code:

```moonbit
let source = "print(\"hi\")\n"
let result = @mpython.Interpreter::new().exec_source(source)
match result {
  Ok(run) => {
    // run.value / run.stdout / run.stderr
  }
  Err(err) => {
    let msg = @mpython.format_runtime_error(err)
  }
}
```
