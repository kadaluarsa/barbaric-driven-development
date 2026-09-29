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

One `break:` per law until 2.2.0. A second `break:` line used to be dropped without a word — the parser kept
the last one — so an author believed two bugs were proven when only one ran. Now such a law is UNPROVEN with
that reason, everywhere (t60). Several breaks per law is 2.2.0's.

usage: laws.py <envelope> [--declared|--in-force|--unproven|--protected|--commands]
        each prints one normalized `id|law|check|break` line ( --unproven prints `id|law|why` );
        --commands prints `id<TAB>check|break<TAB>command` for every command slot of every declared law,
        blank ones included, so a law whose commands are still TODO is still a law to the guards.
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
    """Every declared law, in file order. A template example ({{…}}) is not declared.

    Each law is {id, law, check, break, breaks}: `breaks` lists every `break:` line in order and `break` is the
    first, so a caller of the older shape (id, law, check, break) keeps working."""
    out, cur = [], None
    for raw in text.replace("\r\n", "\n").split("\n"):
        m = HEAD.match(raw)
        if m:
            if cur:
                out.append(cur)
            cur = {"id": m.group(1), "law": m.group(2), "check": "", "break": "", "breaks": []}
            continue
        if cur:
            f = FIELD.match(raw)
            if f:
                if f.group(1).lower() == "break":
                    cur["breaks"].append(f.group(2))
                    cur["break"] = cur["breaks"][0]
                else:
                    cur["check"] = f.group(2)
                continue
            if raw.startswith("#") or (raw.strip() and not raw.startswith((" ", "\t"))):
                out.append(cur); cur = None
        g = LEGACY.match(raw)
        if g:
            parts = [p.strip() for p in g.group(2).split("|")]
            brk = parts[2] if len(parts) > 2 else ""
            out.append({"id": g.group(1), "law": parts[0] if parts else "",
                        "check": parts[1] if len(parts) > 1 else "", "break": brk, "breaks": [brk] if brk else []})
    if cur:
        out.append(cur)
    return [d for d in out if "{{" not in (d["law"] + d["check"] + "".join(d["breaks"]))]


def why_unproven(d: dict) -> str:
    """'' when the law is in force, else the reason it is not — the one wording every reader shows."""
    if _blank(d["check"]):
        return "no check command"
    if len(d["breaks"]) > 1:
        return f"{len(d['breaks'])} break: lines — only one is supported until 2.2.0"
    if not d["breaks"] or _blank(d["breaks"][0]):
        return "no break command (the law cannot be shown to fail)"
    return ""


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
        why = why_unproven(d)
        if mode == "--commands":
            print(f"{d['id']}\tcheck\t{d['check']}")
            for b in d["breaks"] or [""]:
                print(f"{d['id']}\tbreak\t{b}")
            continue
        if mode == "--in-force" and why:
            continue
        if mode == "--unproven":
            if why:
                print(f"{d['id']}|{d['law']}|{why}")
            continue
        if mode in ("--declared", "--in-force"):
            # A law with several breaks shows no break here: none of them is the law's red twin until 2.2.0.
            print(f"{d['id']}|{d['law']}|{d['check']}|{'' if len(d['breaks']) > 1 else d['break']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


# --- hop state ---------------------------------------------------------------------------------------
# CURRENT_HOP/STAGE/SLICE and AUTOPILOT live in docs/cascade/hop-state.md: they turn over 3-4 times per
# slice, while the laws beside them change twice a year, and one file made the law history unreadable.
# Repos installed before the split keep everything in the envelope, so fall back when the file is absent.

def hopstate_path(root: str) -> str:
    import os
    h = os.path.join(root, "docs", "cascade", "hop-state.md")
    return h if os.path.exists(h) else os.path.join(root, "docs", "cascade", "envelope.md")


def hopstate_field(root: str, key: str) -> str:
    """CURRENT_HOP / CURRENT_STAGE / CURRENT_SLICE / AUTOPILOT, from wherever hop state lives."""
    try:
        with open(hopstate_path(root), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith(key + ":"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return ""
