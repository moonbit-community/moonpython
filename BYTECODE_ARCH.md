# MoonPython Bytecode Architecture (MicroPython-Style)

This repo is migrating from an AST-walking interpreter to:

1) Parser -> AST (existing)
2) Bytecode compiler (new)
3) Bytecode VM / interpreter (new)

The design and naming follow MicroPython's structure as closely as practical,
while still integrating with MoonPython's existing `Value` runtime and builtins.

## Local Reference Checkout

For implementation guidance, keep a local checkout of MicroPython at:

- `micropython-reference/` (gitignored; not committed)

Key MicroPython files to compare against:

- `py/compile.c` (compiler pipeline)
- `py/bc.h`, `py/bc.c` (bytecode format helpers)
- `py/vm.c` (VM execution loop)
- `py/obj*.c` (object model / runtime helpers)

## Goals Of This Refactor

- Keep public API (`Interpreter::exec`, `Interpreter::eval_source`, CLI behavior)
  stable while swapping the execution engine underneath.
- Allow incremental migration: unsupported constructs in the bytecode compiler/VM
  can temporarily fall back to the old AST evaluator until parity is reached.

