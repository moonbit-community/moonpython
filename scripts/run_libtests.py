#!/usr/bin/env python3
"""
Run CPython's Lib/test modules using moonpython.

This is a pragmatic smoke runner (not a full regrtest port).

Notes about exit codes:
- `moon run` does NOT reliably propagate the executed program's exit status.
  That makes pass/fail classification based on `returncode` misleading.
- For accurate exit codes, prefer `--target native` which builds `cmd/main`
  once and executes the resulting `main.exe` directly.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Sequence


SLOW_MODULES = {
    # These modules are known to be computationally heavy under an interpreter.
    "test.test_bigmem",
    "test.test_dynamic",
    "test.test_longexp",
    # pathlib is large and filesystem-heavy; even a mostly-compatible shim can
    # take minutes under an interpreter.
    "test.test_pathlib",
    "test.test_compile",
    "test.test_support",
    "test.test_userstring",
}


@dataclass
class Result:
    module: str
    status: str  # "pass" | "fail" | "skip" | "timeout"
    seconds: float
    exit_code: int
    output: str


_RE_RAN = re.compile(r"^Ran (\d+) tests? in ", re.MULTILINE)
_RE_SKIPPED = re.compile(r"\bskipped=(\d+)\b")
_RE_MISSING_MODULE = re.compile(
    r"(?:ModuleNotFoundError|ImportError): No module named '([^']+)'"
)

# moonpython does not aim to support CPython C extension modules. Some CPython
# tests import these modules unconditionally, which would otherwise show up as
# failures in this smoke runner.
_UNSUPPORTED_C_EXTENSIONS = {
    "_ctypes",
    "_csv",
    "_locale",
    "_lsprof",
    "_socket",
}

_FORCED_SKIP_MODULES = {
    # CPython's `array` is a C extension; moonpython only provides a tiny shim.
    "test.test_array",
    # Known to be computationally heavy under an interpreter; not useful for quick compatibility tracking.
    "test.test_bigmem",
}

_FORCED_SKIP_PREFIXES = {
    # CPython's asyncio heavily relies on real sockets/selectors/threads.
    "test.test_asyncio.",
}

_IGNORED_TEST_PACKAGE_PREFIXES = {
    # These are regrtest internals / support suites, not target smoke modules.
    ("test", "leakers"),
    ("test", "regrtestdata"),
}


def discover_test_modules(lib_dir: Path) -> List[str]:
    test_dir = lib_dir / "test"
    modules: List[str] = []
    for path in sorted(test_dir.rglob("test_*.py")):
        if path.name == "__init__.py":
            continue
        rel = path.relative_to(lib_dir).with_suffix("")
        for prefix in _IGNORED_TEST_PACKAGE_PREFIXES:
            if tuple(rel.parts[: len(prefix)]) == prefix:
                break
        else:
            modules.append(".".join(rel.parts))
    return modules


def forced_skip_reason(module: str) -> Optional[str]:
    if module == "test.test_array":
        return "requires unsupported C extension semantics"
    if module == "test.test_bigmem":
        return "too slow under an interpreter (smoke runner skips it)"
    if module in _FORCED_SKIP_MODULES:
        return "forced skip"
    for prefix in _FORCED_SKIP_PREFIXES:
        if module.startswith(prefix):
            return "requires socket/selectors/threading support"
    return None


def classify(exit_code: int, output: str) -> str:
    # Skip detection first: SkipTest can happen both as an uncaught exception
    # (non-zero exit) and as a unittest result (zero exit).
    if "SkipTest:" in output:
        return "skip"
    if "ResourceDenied:" in output:
        return "skip"
    missing = _RE_MISSING_MODULE.search(output)
    if missing and (
        missing.group(1) in _UNSUPPORTED_C_EXTENSIONS
        or missing.group(1).startswith("_test")
    ):
        return "skip"

    # Unittest "all skipped" is still a success exit code, but we want to track
    # it separately from a real pass.
    ran_m = _RE_RAN.search(output)
    skipped_m = _RE_SKIPPED.search(output)
    if ran_m and skipped_m:
        ran = int(ran_m.group(1))
        skipped = int(skipped_m.group(1))
        if ran == 0 or (skipped > 0 and ran == skipped):
            return "skip"

    # If moonpython printed a traceback, treat it as a failure even if the
    # wrapper returned exit code 0 (which can happen when using `moon run`).
    if "Traceback (most recent call last):" in output:
        return "fail"
    if "FAILED (" in output or "\nFAILED\n" in output:
        return "fail"

    return "pass" if exit_code == 0 else "fail"


def target_dir_path(repo_root: Path, target_dir: Optional[str]) -> Path:
    return (Path(target_dir) if target_dir else (repo_root / "target")).resolve()


def native_exe_candidates(repo_root: Path, target_dir: Optional[str]) -> List[Path]:
    tdir = target_dir_path(repo_root, target_dir)
    return [
        tdir / "native" / "release" / "build" / "cmd" / "main" / "main.exe",
        tdir / "native" / "debug" / "build" / "cmd" / "main" / "main.exe",
    ]


def resolve_native_exe(repo_root: Path, target_dir: Optional[str]) -> Path:
    for path in native_exe_candidates(repo_root, target_dir):
        if path.exists():
            return path
    # Default to the release layout for error messages.
    return native_exe_candidates(repo_root, target_dir)[0]


def ensure_native_runner(repo_root: Path, target_dir: Optional[str], release: bool) -> Path:
    exe = resolve_native_exe(repo_root, target_dir)
    if exe.exists():
        return exe
    cmd: List[str] = [
        "moon",
        "build",
        "--target",
        "native",
        *(["--target-dir", str(target_dir_path(repo_root, target_dir))] if target_dir else []),
        *(["--release"] if release else []),
        "cmd/main",
    ]
    subprocess.run(cmd, cwd=str(repo_root), check=True)
    exe = resolve_native_exe(repo_root, target_dir)
    if not exe.exists():
        raise RuntimeError(f"native runner not found after build: {exe}")
    return exe


def build_run_command(
    repo_root: Path,
    lib_dir: Path,
    module: str,
    extra_args: List[str],
    runner: str,
    target_dir: Optional[str],
    target: str,
    native_release: bool,
) -> Sequence[str]:
    if runner not in {"unittest", "direct"}:
        raise ValueError(f"unknown runner: {runner!r}")
    if target == "native":
        exe = ensure_native_runner(repo_root, target_dir, native_release)
        if runner == "unittest":
            # `python -m unittest test.test_xxx` imports the module under its real
            # name (not as `__main__`). A number of Lib/test modules assume this
            # import-style execution (e.g. repr module qualifiers), so make this
            # the default for the smoke runner.
            return [
                str(exe),
                "--stdlib",
                str(lib_dir),
                "-m",
                "unittest",
                module,
                *extra_args,
            ]
        return [
            str(exe),
            "--stdlib",
            str(lib_dir),
            "-m",
            module,
            *extra_args,
        ]
    # Fallback: keep using moon run for other targets (exit codes may be unreliable).
    if runner == "unittest":
        return [
            "moon",
            "run",
            "--target",
            target,
            *(["--target-dir", target_dir] if target_dir else []),
            "cmd/main",
            "--",
            "--stdlib",
            str(lib_dir),
            "-m",
            "unittest",
            module,
            *extra_args,
        ]
    return [
        "moon",
        "run",
        "--target",
        target,
        *(["--target-dir", target_dir] if target_dir else []),
        "cmd/main",
        "--",
            "--stdlib",
            str(lib_dir),
            "-m",
            module,
            *extra_args,
        ]


def run_one(
    repo_root: Path,
    lib_dir: Path,
    module: str,
    timeout_s: float,
    extra_args: List[str],
    runner: str,
    target_dir: Optional[str],
    target: str,
    native_release: bool,
) -> Result:
    reason = forced_skip_reason(module)
    if reason is not None:
        return Result(
            module=module,
            status="skip",
            seconds=0.0,
            exit_code=0,
            output=f"SkipTest: {reason}\n",
        )
    cmd = list(
        build_run_command(
            repo_root,
            lib_dir,
            module,
            extra_args=extra_args,
            runner=runner,
            target_dir=target_dir,
            target=target,
            native_release=native_release,
        )
    )
    start = time.time()
    try:
        # Run each module in an isolated temp cwd so tests that create files
        # (TESTFN, pathlib/glob benches, etc.) don't pollute the repo root or
        # interfere with subsequent runs.
        with tempfile.TemporaryDirectory(prefix="moonpython-libtest-") as tdir:
            proc = subprocess.run(
                cmd,
                cwd=tdir,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="backslashreplace",
                timeout=timeout_s,
            )
        output = proc.stdout
        status = classify(proc.returncode, output)
        return Result(
            module=module,
            status=status,
            seconds=time.time() - start,
            exit_code=proc.returncode,
            output=output,
        )
    except subprocess.TimeoutExpired as exc:
        def _to_text(value) -> str:
            if value is None:
                return ""
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace")
            return str(value)

        output = _to_text(exc.stdout) + _to_text(exc.stderr)
        return Result(
            module=module,
            status="timeout",
            seconds=time.time() - start,
            exit_code=124,
            output=output,
        )


def iter_selected(modules: List[str], pattern: Optional[str]) -> Iterable[str]:
    if not pattern:
        yield from modules
        return
    rx = re.compile(pattern)
    for mod in modules:
        if rx.search(mod):
            yield mod


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--lib",
        default="Lib",
        help="Path to CPython Lib directory (default: Lib)",
    )
    parser.add_argument(
        "--pattern",
        default=None,
        help="Regex to select test modules (matched against module name)",
    )
    parser.add_argument("--limit", type=int, default=0, help="Run only N tests")
    parser.add_argument(
        "--timeout",
        type=float,
        default=20.0,
        help="Per-module timeout seconds (default: 20)",
    )
    parser.add_argument(
        "--slow-timeout",
        type=float,
        default=1200.0,
        help="Per-module timeout for known slow tests (default: 1200)",
    )
    parser.add_argument(
        "--runner",
        choices=("unittest", "direct"),
        default="unittest",
        help="How to execute a test module (default: unittest). 'unittest' imports modules under their real name; 'direct' runs them as __main__.",
    )
    parser.add_argument(
        "--target",
        default="native",
        help="Execution target (default: native). Non-native targets fall back to `moon run` (exit codes may be unreliable).",
    )
    parser.add_argument(
        "--target-dir",
        default=None,
        help="moon --target-dir value (useful to avoid workspace build locks)",
    )
    parser.add_argument(
        "--native-release",
        action="store_true",
        help="Build native runner in release mode (default: debug)",
    )
    parser.add_argument(
        "--json",
        dest="json_path",
        default=None,
        help="Write a JSON report to this path",
    )
    parser.add_argument(
        "extra_args",
        nargs=argparse.REMAINDER,
        help="Extra args passed to the executed test module (place after '--')",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    lib_dir = (repo_root / args.lib).resolve()
    modules = discover_test_modules(lib_dir)
    selected = list(iter_selected(modules, args.pattern))
    if args.limit and args.limit > 0:
        selected = selected[: args.limit]

    results: List[Result] = []
    counts = {"pass": 0, "fail": 0, "skip": 0, "timeout": 0}
    for idx, mod in enumerate(selected, start=1):
        timeout_s = args.slow_timeout if mod in SLOW_MODULES else args.timeout
        res = run_one(
            repo_root,
            lib_dir,
            mod,
            timeout_s=timeout_s,
            extra_args=args.extra_args or [],
            runner=args.runner,
            target_dir=args.target_dir,
            target=args.target,
            native_release=args.native_release,
        )
        results.append(res)
        counts[res.status] += 1
        print(
            f"[{idx}/{len(selected)}] {mod}: {res.status} ({res.seconds:.2f}s)",
            file=sys.stderr,
        )

    print(
        f"pass={counts['pass']} fail={counts['fail']} skip={counts['skip']} timeout={counts['timeout']}"
    )
    if args.json_path:
        out_path = Path(args.json_path)
        out_path.write_text(
            json.dumps([asdict(r) for r in results], indent=2, ensure_ascii=True) + "\n",
            encoding="utf-8",
        )
    return 0 if counts["fail"] == 0 and counts["timeout"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
