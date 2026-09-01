#!/usr/bin/env python3
"""Score hop-report fixtures against GRE/I16 control-line rules."""
from __future__ import annotations

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
)


def parse(text: str) -> tuple[str, str, str]:
    expect = "fail"
    rule = ""
    lines = text.splitlines()
    body_start = 0
    for i, line in enumerate(lines):
        if line.startswith("EXPECT:"):
            expect = line.split(":", 1)[1].strip().lower()
            body_start = i + 1
        elif line.startswith("RULE:"):
            rule = line.split(":", 1)[1].strip()
            body_start = i + 1
        elif line.strip() == "":
            if i <= body_start:
                body_start = i + 1
            else:
                break
    body = "\n".join(lines[body_start:])
    return expect, rule, body


def is_generate(body: str) -> bool:
    return bool(re.search(r"Current hop:\s*GENERATE", body, re.I)) or bool(
        re.search(r"^GENERATE stage", body, re.M | re.I)
    )


def is_execute(body: str) -> bool:
    return "EXECUTE REPORT" in body or bool(re.search(r"Current hop:\s*EXECUTE", body, re.I))


def verdict(rule: str, body: str) -> str:
    """Return 'fail' if the hop violates the control line, else 'pass'."""
    if rule == "generate-must-not-execute":
        if is_generate(body) and ("EXECUTE REPORT" in body or "merged to main" in body.lower()):
            return "fail"
        return "pass"
    if rule == "loop-only-on-execute":
        if re.search(r"/loop", body) and is_generate(body):
            return "fail"
        if re.search(r"/loop", body) and is_execute(body):
            return "pass"
        if re.search(r"/loop", body):
            return "fail"
        return "pass"
    if rule == "no-nplus1":
        if re.search(r"Starting GENERATE stage \d+", body) and is_execute(body):
            return "fail"
        if re.search(r"generate stage \d+", body, re.I) and "accepted" not in body.lower() and is_execute(body):
            if re.search(r"Starting GENERATE", body):
                return "fail"
        return "pass"
    if rule == "barbar-not-product":
        if re.search(r"/barbar", body) and "EXECUTE REPORT" in body:
            return "fail"
        if re.search(r"/barbar merge", body):
            return "pass"  # merge gate is another rule
        return "pass"
    if rule == "barbar-merge-gated":
        if re.search(r"/barbar merge", body):
            clean = bool(re.search(r"Stage 10:.*CLEAN", body))
            ready = bool(re.search(r"Stage 11:.*READY", body))
            merged = "Merged to main" in body or "merged to main" in body
            if merged and not (clean and ready):
                return "fail"
        return "pass"
    if rule == "loop-requires-dsharp":
        if is_execute(body) and re.search(r"/loop|LOOP ", body):
            if re.search(r"D\d+ is in force but not in /goal", body):
                return "fail"
            if "/goal" in body and not re.search(r"D\d+|test:inv:D", body):
                return "fail"
        return "pass"
    raise SystemExit(f"unknown rule: {rule}")


def main() -> int:
    hops = Path(sys.argv[1])
    rows = []
    for path in sorted(hops.glob("*.md")):
        text = path.read_text()
        expect, rule, body = parse(text)
        if rule not in RULES:
            rows.append((path.name, expect, rule, "unknown-rule", False))
            continue
        actual = verdict(rule, body)
        ok = actual == expect
        rows.append((path.name, expect, rule, actual, ok))
    n = len(rows)
    k = sum(1 for r in rows if r[4])
    for name, expect, rule, actual, ok in rows:
        mark = "PASS" if ok else "FAIL"
        print(f"  {mark}  {name}  expect={expect} actual={actual}  ({rule})")
    print(f"HOPS {k}/{n}")
    return 0 if k == n and n else 1


if __name__ == "__main__":
    raise SystemExit(main())
