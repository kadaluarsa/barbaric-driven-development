#!/usr/bin/env python3
"""The spec-wording benchmark scorer (t94). It reports; it never names a winner and it calls no model.

    specbench.py score FILE     one JSON object per line
    specbench.py --dry-run      score evals/specbench/fixture.jsonl

Each object holds task, arm (A, B or C), run, hidden_pass (true or false), unneeded_lines, repairs, tokens, seconds and
tool_calls. Each task needs each arm with two runs or more. Bad input exits 2 and prints `specbench: input error`.
"""
from __future__ import annotations

import collections
import json
import os
import statistics
import sys

ARMS = ("A", "B", "C")
MEASURES = ("unneeded_lines", "repairs", "tokens", "seconds", "tool_calls")
MIN_RUNS = 2


class InputError(Exception):
    pass


def number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0


def load(path: str) -> list[dict]:
    try:
        with open(path, encoding="utf-8") as fh:
            rows = [json.loads(line) for line in fh if line.strip()]
    except (OSError, ValueError) as exc:
        raise InputError(f"cannot read {os.path.basename(path)}: {type(exc).__name__}") from None
    for row in rows:
        if not isinstance(row, dict):
            raise InputError("each line must be a JSON object")
        if row.get("arm") not in ARMS:
            raise InputError(f"unknown arm: {row.get('arm')!r}")
        if not row.get("task") or "run" not in row:
            raise InputError("each row needs task and run")
        if not isinstance(row.get("hidden_pass"), bool):
            raise InputError("hidden_pass must be true or false")
        for key in MEASURES:
            if not number(row.get(key)):
                raise InputError(f"{key} must be a non-negative number")
    if not rows:
        raise InputError("the file holds no rows")
    counts = collections.Counter((row["task"], row["arm"]) for row in rows)
    for task in sorted({row["task"] for row in rows}):
        for arm in ARMS:
            if counts[(task, arm)] < MIN_RUNS:
                raise InputError(f"task {task} arm {arm} has {counts[(task, arm)]} runs (need {MIN_RUNS})")
    return rows


def report(rows: list[dict]) -> list[str]:
    lines = []
    for arm in ARMS:
        picked = [row for row in rows if row["arm"] == arm]
        rate = sum(row["hidden_pass"] for row in picked) / len(picked)
        parts = [f"ARM {arm} runs={len(picked)} pass_rate={rate:.2f}"]
        for key in MEASURES:
            values = [row[key] for row in picked]
            parts.append(f"{key}={min(values):g}/{statistics.median(values):g}/{max(values):g}")
        lines.append(" ".join(parts))
    lines.append("SPECBENCH report: no gain claimed")
    return lines


def main() -> int:
    args = sys.argv[1:]
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    try:
        if args == ["--dry-run"]:
            path = os.path.join(root, "evals", "specbench", "fixture.jsonl")
        elif len(args) == 2 and args[0] == "score":
            path = args[1]
        else:
            raise InputError("usage: specbench.sh score FILE | --dry-run")
        print("\n".join(report(load(path))))
    except InputError as exc:
        print(f"specbench: input error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
