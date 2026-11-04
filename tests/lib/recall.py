#!/usr/bin/env python3
"""The recall index (t85): where this slice's work lives, for an agent whose context was just compacted.

    recall.py <root>     one line per artifact that exists; nothing unless a GENERATE or EXECUTE hop names a slice

Pointers, not content: a path, a line anchor, one line of status. Computed from files — never a summary of chat.
Every line is cut at 240 characters and at most 25 are printed. Errors are not caught: a non-zero exit tells
preserve.py to discard whatever was printed (t85 §2).
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from laws import hopstate_field   # noqa: E402  (sibling: tests/lib ships as one directory)

WIDTH = 240
MAX_LINES = 25
BRIEF_CHARS = 200
HALTS = {"HALT", "BUDGET", "CAP", "WATCHDOG", "NUDGECAP"}
TAIL_SHOWN = 12        # preserve.py prints this many decisions already
LOG_SCAN = 2000
ROW = re.compile(r"^\|\s*C\d+\s*\|")


def rel(*parts: str) -> str:
    return os.path.join("docs", "cascade", *parts)


def read(root: str, path: str) -> str | None:
    try:
        with open(os.path.join(root, path), encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def brief(root: str, slug: str) -> str | None:
    path = rel("05b-briefs.md")
    text = read(root, path)
    if text is None:
        return None
    lines = text.splitlines()
    head = re.compile(r"^- " + re.escape(slug) + r":(.*)$")
    for i, line in enumerate(lines):
        m = head.match(line)
        if not m:
            continue
        body = [m.group(1)]
        for nxt in lines[i + 1:]:   # continuation lines are indented; a column-0 line or a blank ends the brief (C1)
            if not nxt.strip() or not nxt[0].isspace():
                break
            body.append(nxt)
        words = " ".join(" ".join(body).split())
        return f"brief      {path}:{i + 1}  {words[:BRIEF_CHARS]}"
    return None


def anchors(text: str) -> str:
    want = (("plan", re.compile(r"^# Stage .*PLAN\s*$")),
            ("AC", re.compile(r"^## Acceptance criteria\s*$")),
            ("scope", re.compile(r"^## In scope this execute\s*$")))
    found = []
    lines = text.splitlines()
    for name, pat in want:
        for i, line in enumerate(lines):
            if pat.match(line):
                found.append(f"{name} :{i + 1}")
                break
    return f"  ({', '.join(found)})" if found else ""


def section(text: str, head: str) -> str:
    m = re.search(r"^## " + re.escape(head) + r"[ \t]*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


def critique(root: str, stage: str, slug: str) -> str | None:
    path = rel(f"{stage}-{slug}-critique.md")
    text = read(root, path)
    if text is None:
        return None
    k = sum(1 for h in ("Brief", "Spec") for l in section(text, h).splitlines() if ROW.match(l))
    m = sum(1 for l in section(text, "Dispositions").splitlines() if ROW.match(l))
    return f"critique   {path}  ({k} findings, {m} answered)"


def goal(root: str, slug: str) -> str | None:
    path = rel("goal.md")
    text = read(root, path)
    if text is None:
        return None
    gs = [l.split(":", 1)[1].strip() for l in text.splitlines() if l.startswith("GOAL_SLICE:")]
    n = sum(1 for l in text.splitlines() if l.startswith("VALIDATOR:"))
    owner = gs[-1] if gs else ""
    whose = f"for {slug}" if owner == slug else f"for ANOTHER slice: {owner or '(none)'} — reset it"
    return f"goal       {path}  ({whose}; {n} validators)"


def ago(epoch: str) -> str:
    try:
        s = max(0, int(time.time()) - int(epoch))
    except ValueError:
        return "?"
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if s >= size:
            return f"{s // size}{unit}"
    return f"{s}s"


def base_of(root: str) -> str:
    try:
        from affected import hop_base   # noqa: PLC0415
    except ImportError:
        return ""
    sha, _why = hop_base(root)
    return sha or ""


def loop(root: str, slug: str, base: str) -> str | None:
    if not base:
        return None
    try:
        from watchdog import history   # noqa: PLC0415
    except ImportError:
        return None
    mine = [p for p in history(root) if p[1] == base and p[3] == slug]
    if not mine:
        return None
    p = mine[-1]
    fail = f", {p[7]}" if p[7] != "-" else ""
    return f"loop       .cascade/loop-history (logs in .cascade/loop/): last pass {ago(p[0])} ago, LOOP {p[4]}{fail}"


def halt(root: str) -> str | None:
    text = read(root, os.path.join(".cascade", "decisions.log"))
    if text is None:
        return None
    lines = [l for l in text.splitlines() if l.strip()][-LOG_SCAN:]
    for i in range(len(lines) - 1, -1, -1):
        bits = lines[i].split()
        if len(bits) >= 3 and bits[2] in HALTS:
            if i >= len(lines) - TAIL_SHOWN:
                return None   # preserve.py prints it in its own tail (C8)
            return f"halt       .cascade/decisions.log record: {' '.join(lines[i].split())}"
    return None


def commits(root: str, base: str) -> str | None:
    if not base:
        return None
    r = subprocess.run(["git", "-C", root, "log", "--format=%s", f"{base}..HEAD"], capture_output=True, text=True)
    if r.returncode:
        return None
    subj = [l for l in r.stdout.splitlines() if l.strip()]
    newest = f"; newest: {subj[0]}" if subj else ""
    return f"commits    {len(subj)} since the hop opened at {base[:7]}{newest}"


def index(root: str) -> list[str]:
    hop = hopstate_field(root, "CURRENT_HOP").upper()
    stage, slug = hopstate_field(root, "CURRENT_STAGE"), hopstate_field(root, "CURRENT_SLICE")
    if hop not in ("GENERATE", "EXECUTE") or not slug:
        return []
    out: list[str | None] = []
    if stage == "05b":
        out.append(brief(root, slug))
    spec = rel(f"{stage}-{slug}.md")
    text = read(root, spec)
    if text is not None:
        out.append(f"spec       {spec}{anchors(text)}")
    out.append(critique(root, stage, slug))
    if os.path.isfile(os.path.join(root, rel(f"{stage}-{slug}-candidates.md"))):
        out.append(f"candidates {rel(f'{stage}-{slug}-candidates.md')}")
    if hop == "EXECUTE":
        out.append(goal(root, slug))
    base = base_of(root)
    out.append(loop(root, slug, base))
    out.append(halt(root))
    out.append(commits(root, base))
    return [l[:WIDTH] for l in out if l][:MAX_LINES]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: recall.py <root>", file=sys.stderr)
        return 64
    for line in index(sys.argv[1]):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
