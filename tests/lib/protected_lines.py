#!/usr/bin/env python3
"""Exit 1 if human-owned machine-read lines changed between two versions of envelope.md.

Protected: CURRENT_HOP / CURRENT_STAGE / CURRENT_SLICE and every `D# | ... | validator [| twin]` line.
An agent may not flip the hop or rewrite a law's validator. Humans commit those with CASCADE_HUMAN=1.
"""
from __future__ import annotations

import re
import sys

PROTECTED = re.compile(r"^(CURRENT_(HOP|STAGE|SLICE):|AUTOPILOT:|D[0-9]+\s*\|)", re.M)


def protected(text: str) -> list[str]:
    return [ln.rstrip() for ln in text.splitlines() if PROTECTED.match(ln)]


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except FileNotFoundError:
        return ""


def diff(before: str, after: str) -> list[str]:
    b, a = protected(before), protected(after)
    out = [f"- {x}" for x in b if x not in a] + [f"+ {x}" for x in a if x not in b]
    return out


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: protected_lines.py <before> <after>", file=sys.stderr)
        return 64
    changes = diff(read(sys.argv[1]), read(sys.argv[2]))
    if changes:
        print("human-owned envelope lines changed (hop state / D# laws):", file=sys.stderr)
        for c in changes[:8]:
            print(f"  {c}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
