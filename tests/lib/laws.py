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

Law shards (t67): laws may also live in docs/cascade/laws/*.md (README.md is not a shard), in the same formats.
They are read after the envelope, in filename order. Callers pass the repo's shard directory with --shards; with
no --shards it is <envelope's dir>/laws, but only for a path ending in docs/cascade/envelope.md — a temporary copy
elsewhere reads no shards (it must never pick up a stray $TMPDIR/laws). One id twice anywhere is FATAL: every
mode prints nothing on stdout, `FATAL duplicate D7: <file>, <file>` on stderr, and exits 2.

usage: laws.py <envelope> [--declared|--in-force|--unproven|--protected|--count|--sources|--summary|--retired] [--shards DIR]
        each prints one normalized `id|law|check|break` line ( --unproven prints `id|law|why`,
        --sources prints `id|file`, --summary prints `file|count|first id|last id` per shard ).
"""
from __future__ import annotations

import glob
import os
import re
import sys

HEAD = re.compile(r"^###\s*(D\d+)\s*[—–-]\s*(.+?)\s*$")
FIELD = re.compile(r"^\s*(check|break|reason|path|tier|retired)\s*:\s*(.*?)\s*$", re.I)
LEGACY = re.compile(r"^(D\d+)\s*\|(.*)$")
# Lines a human owns: a law heading, its check/break/retired, the legacy one-liner, hop state, the autopilot list.
PROTECTED = re.compile(r"^(###\s*D\d+\b|\s*(check|break|retired)\s*:|D\d+\s*\||CURRENT_(HOP|STAGE|SLICE):|AUTOPILOT:)", re.I)
# t68: `retired: <YYYY-MM-DD> — superseded by D<N>` or `retired: <YYYY-MM-DD> — removed — <reason>` (` - ` too).
RETIRED = re.compile(r"^(\d{4}-\d{2}-\d{2})\s+[—–-]\s+(?:superseded by\s+(D\d+)|removed\s+[—–-]\s+(\S.*?))\s*$", re.I)   # em, en or hyphen, as HEAD


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
            cur = {"id": m.group(1), "law": m.group(2), "check": "", "break": "", "reason": "", "path": "", "tier": "",
                   "retired": ""}
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
                        "check": parts[1] if len(parts) > 1 else "",
                        "break": parts[2] if len(parts) > 2 else "",
                        "reason": "", "path": "", "tier": "", "retired": ""})
    if cur:
        out.append(cur)
    return [d for d in out if "{{" not in (d["law"] + d["check"] + d["break"])]


class LawsError(Exception):
    """The laws cannot be read as one unambiguous set (a duplicate id). Every reader must refuse."""


_DEFAULT = object()
SHARD_SUFFIX = os.path.join("docs", "cascade", "envelope.md")


def default_shards(envelope: str) -> str | None:
    """<dir>/laws for a real cascade envelope path; None for anything else (a temp copy, a fixture elsewhere)."""
    norm = os.path.normpath(envelope)
    return os.path.join(os.path.dirname(norm), "laws") if norm.endswith(SHARD_SUFFIX) else None


def shard_files(shards_dir: str | None) -> list[str]:
    if not shards_dir or not os.path.isdir(shards_dir):
        return []
    return sorted(f for f in glob.glob(os.path.join(shards_dir, "*.md"))
                  if os.path.basename(f) != "README.md" and os.path.isfile(f))


def retirement(d: dict, by_id: dict) -> tuple[bool, str, str]:
    """(valid, date, reason-or-why) for a law's `retired:` line (t68). One pass, no recursion: a supersession target
    must be another declared law with no `retired:` line at all, so a cycle (D2->D3, D3->D2) is invalid both ways."""
    import datetime
    m = RETIRED.match((d.get("retired") or "").strip())
    if not m:
        return False, "", 'not "<YYYY-MM-DD> — superseded by D<N>" or "<YYYY-MM-DD> — removed — <reason>"'
    try:
        datetime.date.fromisoformat(m.group(1))
    except ValueError:
        return False, m.group(1), f"{m.group(1)} is not a date"
    target = m.group(2)
    if target:
        t = by_id.get(target.upper())
        if target.upper() == d["id"]:
            return False, m.group(1), "a law cannot supersede itself"
        if t is None:
            return False, m.group(1), f"superseded by {target}, which is not declared"
        if (t.get("retired") or "").strip():
            return False, m.group(1), f"superseded by {target}, which has a retired: line itself"
        return True, m.group(1), f"superseded by {target}"
    return True, m.group(1), f"removed — {m.group(3)}"


def load(envelope: str, shards_dir=_DEFAULT, retired: bool = False) -> list[dict]:
    """Every declared law in the envelope, then in each shard by filename, each with its `source` file.
    Raises LawsError when one id appears twice anywhere (two shards, envelope and shard, or the envelope alone) —
    a retired law's id included: it stays taken (t68). A validly retired law is left out unless retired=True; every
    law then carries `retired_ok` (bool) and `retired_why`."""
    if shards_dir is _DEFAULT:
        shards_dir = default_shards(envelope)
    out: list[dict] = []
    for path in [envelope] + shard_files(shards_dir):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        for d in laws(text):
            d["source"] = path
            out.append(d)
    seen: dict = {}
    for d in out:
        if d["id"] in seen:
            raise LawsError(f"duplicate {d['id']}: {seen[d['id']]}, {d['source']}")
        seen[d["id"]] = d["source"]
    by_id = {d["id"]: d for d in out}
    for d in out:
        d["retired_ok"], d["retired_date"], d["retired_why"] = (
            retirement(d, by_id) if (d.get("retired") or "").strip() else (False, "", ""))
    return out if retired else [d for d in out if not d["retired_ok"]]


def summary(declared: list[dict], envelope: str) -> list[tuple[str, int, str, str]]:
    """(shard file, law count, lowest id, highest id) for every shard that declares a law."""
    by: dict = {}
    for d in declared:
        if d["source"] != envelope:
            by.setdefault(d["source"], []).append(int(d["id"][1:]))
    return [(f, len(v), f"D{min(v)}", f"D{max(v)}") for f, v in sorted(by.items())]


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__.strip().splitlines()[-4], file=sys.stderr)
        return 64
    envelope, rest = args[0], args[1:]
    shards_dir = _DEFAULT
    mode = "--declared"
    i = 0
    while i < len(rest):
        if rest[i] == "--shards" and i + 1 < len(rest):
            shards_dir = rest[i + 1]; i += 2
        else:
            mode = rest[i]; i += 1
    if mode == "--protected":
        try:
            text = open(envelope, encoding="utf-8", errors="replace").read()
        except OSError:
            return 0
        for line in text.replace("\r\n", "\n").split("\n"):
            if PROTECTED.match(line):
                print(line.rstrip())
        return 0
    if shards_dir is _DEFAULT and default_shards(envelope) is None and os.path.isfile(envelope):
        print(f"laws.py: {envelope} is not a docs/cascade/envelope.md path and no --shards was given; "
              "law shards are not read", file=sys.stderr)
    try:
        everything = load(envelope, shards_dir, retired=True)
    except LawsError as exc:
        print(f"FATAL {exc}", file=sys.stderr)
        return 2
    declared = [d for d in everything if not d["retired_ok"]]   # a validly retired law is not a law any more (t68)
    if mode == "--retired":
        for d in everything:
            if d["retired_ok"]:
                print(f"{d['id']}|{d['law']}|{d['retired_date']}|{d['retired_why']}")
            elif (d.get("retired") or "").strip():
                print(f"{d['id']}|{d['law']}|INVALID|{d['retired_why']}")
        return 0
    if mode == "--count":
        print(len(declared))
        return 0
    if mode == "--sources":
        for d in declared:
            print(f"{d['id']}|{d['source']}")
        return 0
    if mode == "--summary":   # one line per shard, for the seam's read-list and preserve (t67)
        for f, n, first, last in summary(declared, envelope):
            print(f"{f}|{n}|{first}|{last}")
        return 0
    for d in declared:
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
            print(f"{d['id']}|{d['law']}|{d['check']}|{d['break']}|{d['reason']}|{d['path']}|{d['tier']}")
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
