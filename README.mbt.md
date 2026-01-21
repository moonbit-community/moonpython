# Milky2018/mpython

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

## Run a Python program (file)

From the `aaom-mpython/` directory:

```bash
moon run cmd/main -- path/to/program.py
```

Example:

```bash
moon run cmd/main -- examples/tasks.py
```

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
