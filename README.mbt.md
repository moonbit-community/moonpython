# Milky2018/mpython

A small Python parser + interpreter implemented in MoonBit.

## Run a Python program

This repo currently exposes an **mpython REPL** that reads Python code from stdin.

From the `aaom-mpython/` directory:

```bash
# Run a file
moon run cmd/main < path/to/program.py

# Or run a snippet
printf 'print("hello")\n' | moon run cmd/main
```

Notes:
- `cmd/main` reads all stdin and executes it as a single program.
- The executable currently expects input via stdin redirection/pipe.

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
