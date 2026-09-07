#!/usr/bin/env python3
"""The one reader for domain laws. Every script and hook goes through this.

Human-friendly form (what the template teaches):

    ### D1 — balance MUST NOT go negative
    check:  pytest tests/inv/test_D1.py
    break:  INV_MUTANT=D1 pytest tests/inv/test_D1.py

Legacy one-line form (still read, so older repos keep working):

    D1 | balance MUST NOT go negative | pytest … | INV_MUTANT=D1 pytest …

`check` must pass. `break` must FAIL — it is the bug the law forbids, made runnable. A law needs both to be
in force. A line whose command is TODO/none/empty, or that contains a {{placeholder}}, is a template example.

usage: laws.py <envelope> [--declared|--in-force|--unproven|--protected]
        each prints one normalized `id|law|check|break` line ( --unproven prints `id|law|why` ).
"""
from __future__ import annotations

import re
import sys

HEAD = re.compile(r"^###\s*(D\d+)\s*[—–-]\s*(.+?)\s*$")
FIELD = re.compile(r"^\s*(check|break)\s*:\s*(.*?)\s*$", re.I)
LEGACY = re.compile(r"^(D\d+)\s*\|(.*)$")
# Lines a human owns: a law heading, its check/break, the legacy one-liner, hop state, the autopilot list.
PROTECTED = re.compile(r"^(###\s*D\d+\b|\s*(check|break)\s*:|D\d+\s*\||CURRENT_(HOP|STAGE|SLICE):|AUTOPILOT:)", re.I)


def _blank(cmd: str) -> bool:
    return not cmd or cmd.strip().lower() in ("todo", "none", "-")


def laws(text: str) -> list[dict]:
    """Every declared law, in file order. A template example ({{…}}) is not declared."""
    out, cur = [], None
    for raw in text.replace("\r\n", "\n").split("\n"):
        m = HEAD.match(raw)
        if m:
            if cur:
                out.append(cur)
            cur = {"id": m.group(1), "law": m.group(2), "check": "", "break": ""}
            continue
        if cur:
            f = FIELD.match(raw)
            if f:
                cur[f.group(1).lower()] = f.group(2)
                continue
            if raw.startswith("#") or (raw.strip() and not raw.startswith((" ", "\t"))):
                out.append(cur); cur = None
        g = LEGACY.match(raw)
        if g:
            parts = [p.strip() for p in g.group(2).split("|")]
            out.append({"id": g.group(1), "law": parts[0] if parts else "",
                        "check": parts[1] if len(parts) > 1 else "", "break": parts[2] if len(parts) > 2 else ""})
    if cur:
        out.append(cur)
    return [d for d in out if "{{" not in (d["law"] + d["check"] + d["break"])]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 64
    try:
        text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    except OSError:
        return 0
    mode = sys.argv[2] if len(sys.argv) > 2 else "--declared"
    if mode == "--protected":
        for line in text.replace("\r\n", "\n").split("\n"):
            if PROTECTED.match(line):
                print(line.rstrip())
        return 0
    for d in laws(text):
        proven = not _blank(d["check"]) and not _blank(d["break"])
        if mode == "--in-force" and not proven:
            continue
        if mode == "--unproven":
            if proven:
                continue
            why = "no check command" if _blank(d["check"]) else "no break command (the law cannot be shown to fail)"
            print(f"{d['id']}|{d['law']}|{why}")
            continue
        if mode == "--declared" or (mode == "--in-force" and proven):
            print(f"{d['id']}|{d['law']}|{d['check']}|{d['break']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
