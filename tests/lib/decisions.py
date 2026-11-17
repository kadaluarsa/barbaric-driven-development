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

Source (t103): each line ends `  src=<test|agent|human>`. Actors `sign_ok` and `human` are always `human` (a signature
is never hidden). Any other actor takes BDD_LOG_SRC when it is `test`, `agent` or `human`, else `agent`. The test
suites set BDD_LOG_SRC=test (enforcement.sh, regress.sh, barbar.sh's farm, each goal line of loop.sh). Lines written
before 3.5.5 have no field and read as `unknown`. `tail()` hides `src=test` lines and strips the field; rotation drops
`src=test` lines first. The field is a label for reports, not evidence: nothing authenticates it.

usage:  decisions.py <root> <actor> <verdict> <detail>...   # append one line
        decisions.py <root> --tail [n]                      # the last n real lines (default 40), field stripped
        decisions.py <root> --tail-all [n]                  # the last n raw lines, test lines and fields included
"""
from __future__ import annotations

import datetime
import os
import re
import sys

LOG = os.path.join(".cascade", "decisions.log")
MAX_BYTES = 2_000_000   # a long unattended run should not grow without bound
KEEP = 2000
SOURCES = ("test", "agent", "human")
FIELD = re.compile(r"  src=([a-z]+)$")


def source(line: str) -> str:
    """The line's src= value, or `unknown` for a line written before the field existed."""
    m = FIELD.search(line.rstrip("\n"))
    return m.group(1) if m else "unknown"


def display(line: str) -> str:
    """The line without its trailing `  src=<x>` field."""
    return FIELD.sub("", line.rstrip("\n"))


def _source_for(actor: str) -> str:
    if actor in ("sign_ok", "human"):
        return "human"
    env = os.environ.get("BDD_LOG_SRC", "")
    return env if env in SOURCES else "agent"


def _rotate(lines: list[str]) -> list[str]:
    """Keep the newest KEEP lines, real lines first: test lines only fill what is left (t103)."""
    idx = [i for i, l in enumerate(lines) if source(l) != "test"][-KEEP:]
    room = KEEP - len(idx)
    if room > 0:
        idx += [i for i, l in enumerate(lines) if source(l) == "test"][-room:]
    return [lines[i] for i in sorted(idx)]


def log_path(root: str) -> str:
    return os.path.join(root, LOG)


def record(root: str, actor: str, verdict: str, detail: str) -> None:
    """Never raise: a logging failure must not change what a guard decides."""
    try:
        p = log_path(root)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.exists(p) and os.path.getsize(p) > MAX_BYTES:
            with open(p, encoding="utf-8", errors="replace") as fh:
                keep = _rotate(fh.readlines())
            with open(p, "w", encoding="utf-8") as fh:
                fh.writelines(keep)
        ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        line = " ".join(str(detail).split())[:400]
        with open(p, "a", encoding="utf-8") as fh:
            fh.write(f"{ts}  {actor:<11} {verdict:<7} {line}  src={_source_for(actor)}\n")
    except Exception:
        pass


def tail(root: str, n: int = 40) -> str:
    """The last n lines that are not src=test, field stripped, in file order."""
    try:
        with open(log_path(root), encoding="utf-8", errors="replace") as fh:
            real = [display(l) + "\n" for l in fh.readlines() if source(l) != "test"]
        return "".join(real[-n:]) if n > 0 else ""
    except OSError:
        return ""


def tail_all(root: str, n: int = 40) -> str:
    try:
        with open(log_path(root), encoding="utf-8", errors="replace") as fh:
            return "".join(fh.readlines()[-n:]) if n > 0 else ""
    except OSError:
        return ""


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[-3].strip(), file=sys.stderr)
        return 2
    root = argv[1]
    if argv[2] in ("--tail", "--tail-all"):
        n = int(argv[3]) if len(argv) > 3 and argv[3].isdigit() else 40
        sys.stdout.write(tail(root, n) if argv[2] == "--tail" else tail_all(root, n))
        return 0
    record(root, argv[2], argv[3] if len(argv) > 3 else "", " ".join(argv[4:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
