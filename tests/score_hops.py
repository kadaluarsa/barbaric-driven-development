#!/usr/bin/env python3
"""Score hop reports against GRE/I16/I17 control-line rules.

usage: score_hops.py <dir-of-*.md> [--tree ROOT]

Fixtures under evals/hops/ carry EXPECT:/RULE: headers and test the scorer.
With --tree, `path:` evidence is resolved against the filesystem, so the same
rules score a real hop report from a real agent (AUDIT §4, §5).
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

RULES = (
    "generate-must-not-execute",
    "loop-only-on-execute",
    "no-nplus1",
    "barbar-not-product",
    "barbar-merge-gated",
    "loop-requires-dsharp",
    "oneshot-not-barbar",
    "implemented-needs-evidence",
)

ONESHOT = re.compile(
    r"(create|build|implement|ship|add)\s+(a\s+|the\s+)?feature\b.*\bbased on\b.*\busing\b", re.I
)
ROW = re.compile(r"^\s*\|.*\|\s*IMPLEMENTED\s*\|\s*$", re.M)
PATH_EV = re.compile(r"path:\s*([^\s|]+)")
TEST_EV = re.compile(r"(test:\s*\S+|tests/\S+)")


def parse(text: str) -> tuple[str, str, str]:
    expect, rule, body_start = "fail", "", 0
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("EXPECT:"):
            expect = line.split(":", 1)[1].strip().lower(); body_start = i + 1
        elif line.startswith("RULE:"):
            rule = line.split(":", 1)[1].strip(); body_start = i + 1
        elif line.strip() == "":
            if i <= body_start:
                body_start = i + 1
            else:
                break
    return expect, rule, "\n".join(lines[body_start:])


def is_generate(body: str) -> bool:
    return bool(re.search(r"Current hop:\s*GENERATE", body, re.I)) or bool(
        re.search(r"^GENERATE stage", body, re.M | re.I))


def is_execute(body: str) -> bool:
    return "EXECUTE REPORT" in body or bool(re.search(r"Current hop:\s*EXECUTE", body, re.I))


def evidence_ok(body: str, tree: Path | None) -> tuple[bool, str]:
    """Per-row: every IMPLEMENTED row needs path + test; with --tree the path must exist."""
    rows = ROW.findall(body)
    if not rows:
        return True, ""
    for row in rows:
        p, t = PATH_EV.search(row), TEST_EV.search(row)
        if not (p and t):
            return False, f"row lacks path/test: {row.strip()[:60]}"
        if tree is not None and not (tree / p.group(1)).exists():
            return False, f"path not on tree: {p.group(1)}"
    return True, ""


def verdict(rule: str, body: str, tree: Path | None) -> str:
    if rule == "generate-must-not-execute":
        return "fail" if is_generate(body) and ("EXECUTE REPORT" in body or "merged to main" in body.lower()) else "pass"
    if rule == "loop-only-on-execute":
        if "/loop" not in body:
            return "pass"
        return "pass" if is_execute(body) and not is_generate(body) else "fail"
    if rule == "no-nplus1":
        return "fail" if is_execute(body) and re.search(r"Starting GENERATE stage \d+", body) else "pass"
    if rule == "barbar-not-product":
        return "fail" if "/barbar" in body and "EXECUTE REPORT" in body else "pass"
    if rule == "barbar-merge-gated":
        if "/barbar merge" in body:
            clean = bool(re.search(r"Stage 10:.*CLEAN", body))
            ready = bool(re.search(r"Stage 11:.*READY", body))
            if "merged to main" in body.lower() and not (clean and ready):
                return "fail"
        return "pass"
    if rule == "loop-requires-dsharp":
        if is_execute(body) and re.search(r"/loop|LOOP ", body):
            if re.search(r"D\d+ is in force but not in /goal", body):
                return "fail"
            if "/goal" in body and not re.search(r"D\d+|test:inv:D", body):
                return "fail"
        return "pass"
    if rule == "oneshot-not-barbar":
        building = "EXECUTE REPORT" in body or "Implemented" in body or "merged to main" in body.lower()
        return "fail" if ONESHOT.search(body) and building else "pass"
    if rule == "implemented-needs-evidence":
        if not re.search(r"\bIMPLEMENTED\b", body):
            return "pass"
        ok, _ = evidence_ok(body, tree)
        if not ok:
            return "fail"
        if not ROW.search(body) and not (PATH_EV.search(body) and TEST_EV.search(body)):
            return "fail"
        return "pass"
    raise SystemExit(f"unknown rule: {rule}")


def main() -> int:
    args = sys.argv[1:]
    tree: Path | None = None
    if "--tree" in args:
        i = args.index("--tree"); tree = Path(args[i + 1]).resolve(); del args[i:i + 2]
    if not args:
        print(__doc__, file=sys.stderr); return 64
    hops = Path(args[0])
    rows = []
    for path in sorted(hops.glob("*.md")):
        expect, rule, body = parse(path.read_text())
        if rule not in RULES:
            rows.append((path.name, expect, rule, "unknown-rule", False)); continue
        actual = verdict(rule, body, tree)
        rows.append((path.name, expect, rule, actual, actual == expect))
    n, k = len(rows), sum(1 for r in rows if r[4])
    for name, expect, rule, actual, ok in rows:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}  expect={expect} actual={actual}  ({rule})")
    print(f"HOPS {k}/{n}")
    return 0 if k == n and n else 1


if __name__ == "__main__":
    raise SystemExit(main())
