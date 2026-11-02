#!/usr/bin/env python3
"""Who built this hop (t90): one line per Stop (and per claimed handover) in .cascade/builders.

    builders.py <root> --record <host> <model> <session> [claimed]   append one line (best effort, exit 0)
    builders.py <root> --builders                                     this hop's distinct host/model, first seen first
    builders.py <root> --switches                                     `<epoch> <base sha7>` per builder change
    builders.py <root> --gate                                         the switch gate (tests/switch.sh)

The log is local and agent-writable: it can hide a switch if deleted, never fake an accept of a reviewed one.
tests/lib/provenance.py is a different module (the spec gates' git helpers) — this one is about builders.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from laws import hopstate_field   # noqa: E402  (sibling: tests/lib ships as one directory)

LOG = os.path.join(".cascade", "builders")
MAX_LINES = 5000
FIELDS = 9
STAGES = {"05b", "06", "07", "08", "09"}   # the EXECUTE hops that build (C2)
ROW = re.compile(r"^\|\s*R\d+\s*\|")
DISPO = re.compile(r"^(fixed|rejected|human)\s+\S")


def git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def clean(v: str) -> str:
    return re.sub(r"[\t\r\n]", " ", v or "").strip()


def hop(root: str) -> tuple[str, str, str]:
    """From CASCADE_HOPSTATE when autopilot hands over the pre-edge state (C4), else the hop-state file."""
    pre = os.environ.get("CASCADE_HOPSTATE") or os.environ.get("CASCADE_ENVELOPE")
    if pre:
        f = {}
        try:
            for line in open(pre, encoding="utf-8", errors="replace"):
                for k in ("CURRENT_HOP", "CURRENT_STAGE", "CURRENT_SLICE"):
                    if line.startswith(k + ":"):
                        f[k] = line.split(":", 1)[1].strip()
        except OSError:
            pass
        return f.get("CURRENT_HOP", "").upper(), f.get("CURRENT_STAGE", ""), f.get("CURRENT_SLICE", "")
    return (hopstate_field(root, "CURRENT_HOP").upper(), hopstate_field(root, "CURRENT_STAGE"),
            hopstate_field(root, "CURRENT_SLICE"))


def model_of(event: dict) -> str:
    """The event's model, else the transcript's last assistant message.model, else $BDD_MODEL, else unknown."""
    m = event.get("model")
    if isinstance(m, dict):
        m = m.get("id") or m.get("display_name")
    if isinstance(m, str) and m.strip():
        return m.strip()
    found = ""
    try:
        with open(event.get("transcript_path") or "", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                msg = d.get("message") if isinstance(d, dict) else None
                if d.get("type") == "assistant" and isinstance(msg, dict) and isinstance(msg.get("model"), str):
                    found = msg["model"]
    except OSError:
        pass
    return found or os.environ.get("BDD_MODEL", "").strip() or "unknown"


def record(root: str, host: str, model: str, session: str, source: str = "hook") -> None:
    h, stage, slug = hop(root)
    head = git(root, "rev-parse", "--short=7", "HEAD").stdout.strip() or "-"
    row = [str(int(time.time())), clean(host) or "unknown", clean(model) or "unknown", clean(session) or "-",
           h or "-", stage or "-", slug or "-", head, source]
    path = os.path.join(root, LOG)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        lines = []
    lines.append("\t".join(row))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines[-MAX_LINES:]) + "\n")


def hop_lines(root: str) -> list[list[str]]:
    """This hop's lines: same hop/stage/slice, at or after the hop-opening commit's time."""
    h, stage, slug = hop(root)
    try:
        from affected import hop_base   # noqa: PLC0415
        base, _ = hop_base(root)
    except Exception:  # noqa: BLE001
        base = None
    if not base:
        return []
    since = git(root, "show", "-s", "--format=%ct", base).stdout.strip()
    since = int(since) if since.isdigit() else 0
    try:
        raw = open(os.path.join(root, LOG), encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return []
    out = []
    for line in raw:
        p = line.split("\t")
        if len(p) != FIELDS or not p[0].isdigit():
            continue
        if int(p[0]) >= since and (p[4], p[5], p[6]) == (h, stage, slug):
            out.append(p)
    return out


def _folded(lines: list[list[str]]) -> list[tuple[str, list[str]]]:
    """(host/model, line) with host/unknown folded into that host's known model in this hop (C8)."""
    known = {}
    for p in lines:
        if p[2] != "unknown":
            known.setdefault(p[1], p[2])
    return [(f"{p[1]}/{known.get(p[1], p[2]) if p[2] == 'unknown' else p[2]}", p) for p in lines]


def builders(root: str) -> list[str]:
    seen: list[str] = []
    for b, _ in _folded(hop_lines(root)):
        if b not in seen:
            seen.append(b)
    return seen


def switches(root: str) -> list[tuple[int, str]]:
    """Each builder change: (epoch of the first line by the new builder, HEAD on the outgoing builder's last line)."""
    out, prev = [], None
    for b, p in _folded(hop_lines(root)):
        if prev is not None and b != prev[0]:
            out.append((int(p[0]), prev[1][7]))
        prev = (b, p)
    return out


def review_rel(stage: str, slug: str) -> str:
    return f"docs/cascade/{stage}-{slug}-switch-review.md"


def section(text: str, head: str) -> str:
    m = re.search(r"^## " + re.escape(head) + r"[ \t]*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


def gate(root: str) -> tuple[int, list[str]]:
    """(exit code, output lines) for tests/switch.sh."""
    h, stage, slug = hop(root)
    if h != "EXECUTE" or stage not in STAGES or not slug:
        return 0, [f"SWITCH n/a — the switch gate covers EXECUTE of 05b and 06–09 (this hop: {h or 'NONE'} {stage or '-'})"]
    bs = builders(root)
    if len(bs) <= 1:
        return 0, [f"SWITCH none ({bs[0] if bs else 'no builder recorded'})"]
    rel = review_rel(stage, slug)
    chain = " → ".join(bs)
    fails = []
    head_text = git(root, "show", f"HEAD:{rel}")
    if head_text.returncode != 0:
        return 1, [f"FAIL  switch review missing: {rel} (builders: {', '.join(bs)})", "SWITCH red"]
    added = git(root, "log", "--diff-filter=A", "--format=%H %ct", "-1", "--", rel).stdout.split()
    sw = switches(root)
    if not added or (sw and int(added[1]) < sw[-1][0]):
        fails.append("switch review is older than the switch")
    if added:
        after = [c for c in git(root, "rev-list", f"{added[0]}..HEAD").stdout.split() if c]
        product = [c for c in after
                   if any(not f.startswith("docs/cascade/")
                          for f in git(root, "show", "--name-only", "--format=", c).stdout.split())]
        if product:
            fails.append(f"work after the review: {len(product)} commit{'s' if len(product) != 1 else ''}")
    text = head_text.stdout
    rows = [l.split("|")[1].strip() for l in section(text, "Review").splitlines() if ROW.match(l)]
    if not 1 <= len(rows) <= 10:
        fails.append(f"the review has {len(rows)} rows (want 1–10 under ## Review)")
    answers = {}
    for l in section(text, "Dispositions").splitlines():
        if ROW.match(l):
            c = [x.strip() for x in l.strip().strip("|").split("|")]
            if len(c) >= 2:
                answers[c[0]] = c[1]
    fails += [f"unanswered: {r}" for r in rows if not DISPO.match(answers.get(r, ""))]
    if fails:
        return 1, [f"FAIL  {f}" for f in fails] + ["SWITCH red"]
    return 0, [f"SWITCH ok ({chain})"]


def main() -> int:
    a = sys.argv[1:]
    if len(a) < 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 64
    root, cmd = a[0], a[1]
    if cmd == "--record" and len(a) >= 5:
        try:
            record(root, a[2], a[3], a[4], "claimed" if len(a) > 5 and a[5] == "claimed" else "hook")
        except OSError:
            pass
        return 0
    if cmd == "--builders":
        for b in builders(root):
            print(b)
        return 0
    if cmd == "--switches":
        for e, base in switches(root):
            print(f"{e} {base}")
        return 0
    if cmd == "--gate":
        rc, lines = gate(root)
        print("\n".join(lines))
        return rc
    print(f"builders.py: unknown argument {cmd}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
