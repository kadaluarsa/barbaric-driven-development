#!/usr/bin/env python3
"""The run log: one line per decision any layer made, appended, never rewritten.

Git records what succeeded. It does not record what was denied, what was signed, which law went red at
3am, or why autopilot stopped — and that is exactly what you need the morning after an unattended run.

    2026-09-08T03:14:22Z  hop_guard   DENY   src/Ledger.kt — product path on a GENERATE hop
    2026-09-08T03:22:10Z  dsharp      RED    D3 — break passed, so the test cannot fail (THEATER)
    2026-09-08T03:22:11Z  stop_guard  HALT   D3 theater

Append-only in the sense that matters here: every writer opens with "a" and writes one line. The file is
local (untracked, like .cascade/manifest) — a record for the human, not evidence a gate depends on. No
gate reads it; nothing fails if it is missing, unwritable, or deleted.

usage:  decisions.py <root> <actor> <verdict> <detail>...   # append one line
        decisions.py <root> --tail [n]                      # read the last n (default 40)
"""
from __future__ import annotations

import datetime
import os
import sys

LOG = os.path.join(".cascade", "decisions.log")
MAX_BYTES = 2_000_000   # a long unattended run should not grow without bound


def log_path(root: str) -> str:
    return os.path.join(root, LOG)


def record(root: str, actor: str, verdict: str, detail: str) -> None:
    """Never raise: a logging failure must not change what a guard decides."""
    try:
        p = log_path(root)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.exists(p) and os.path.getsize(p) > MAX_BYTES:
            with open(p, encoding="utf-8", errors="replace") as fh:
                keep = fh.readlines()[-2000:]
            with open(p, "w", encoding="utf-8") as fh:
                fh.writelines(keep)
        ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        line = " ".join(str(detail).split())[:400]
        with open(p, "a", encoding="utf-8") as fh:
            fh.write(f"{ts}  {actor:<11} {verdict:<7} {line}\n")
    except Exception:
        pass


def tail(root: str, n: int = 40) -> str:
    try:
        with open(log_path(root), encoding="utf-8", errors="replace") as fh:
            return "".join(fh.readlines()[-n:])
    except OSError:
        return ""


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[-2].strip(), file=sys.stderr)
        return 2
    root = argv[1]
    if argv[2] == "--tail":
        n = int(argv[3]) if len(argv) > 3 and argv[3].isdigit() else 40
        sys.stdout.write(tail(root, n))
        return 0
    record(root, argv[2], argv[3] if len(argv) > 3 else "", " ".join(argv[4:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
