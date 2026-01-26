#!/usr/bin/env python3
"""
Run CPython's Lib/test modules using moonpython.

This is a pragmatic smoke runner (not a full regrtest port). It executes each
test module via `moon run cmd/main -- --stdlib Lib -m test.test_x` and records
pass/fail/skip-style outcomes based on exit status and output.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass
class Result:
    module: str
    status: str  # "pass" | "fail" | "skip" | "timeout"
    seconds: float
    exit_code: int
    output: str


def discover_test_modules(lib_dir: Path) -> List[str]:
    test_dir = lib_dir / "test"
    modules: List[str] = []
    for path in sorted(test_dir.rglob("test_*.py")):
        if path.name == "__init__.py":
            continue
        rel = path.relative_to(lib_dir).with_suffix("")
        modules.append(".".join(rel.parts))
    return modules


def classify(exit_code: int, output: str) -> str:
    if exit_code == 0:
        return "pass"
    if "SkipTest:" in output:
        return "skip"
    return "fail"


def run_one(
    repo_root: Path,
    lib_dir: Path,
    module: str,
    timeout_s: float,
    extra_args: List[str],
) -> Result:
    cmd = [
        "moon",
        "run",
        "cmd/main",
        "--",
        "--stdlib",
        str(lib_dir),
        "-m",
        module,
        *extra_args,
    ]
    start = time.time()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(repo_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
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
        output = (exc.stdout or "") + (exc.stderr or "")
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
        "--json",
        dest="json_path",
        default=None,
        help="Write a JSON report to this path",
    )
    parser.add_argument(
        "--",
        dest="extra_args",
        nargs=argparse.REMAINDER,
        help="Extra args passed to the executed test module",
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
        res = run_one(
            repo_root, lib_dir, mod, timeout_s=args.timeout, extra_args=args.extra_args or []
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

