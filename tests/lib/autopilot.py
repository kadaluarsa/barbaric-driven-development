#!/usr/bin/env python3
"""Autopilot — pre-signed hop edges (opt-in).

The human signs, inside <EDIT> in envelope.md:
    AUTOPILOT: 05b checkout, 05b refunds, 06 controls
Then an agent may change CURRENT_HOP/STAGE/SLICE itself — but only along that list:
    NONE (or off-list)      -> GENERATE <first entry>
    GENERATE entry[i]       -> EXECUTE  entry[i]        if a spec doc for the slice exists under docs/cascade/
    EXECUTE  entry[i]       -> GENERATE entry[i+1]      if `tests/loop.sh` exits 0 right now
Nothing else. Stages 10 and 11 can never be on the list. D# lines and the AUTOPILOT line stay human-owned.

usage: autopilot.py <before-envelope> <after-envelope> <repo-root>   -> exit 0 = allowed transition
"""
from __future__ import annotations

import glob
import os
import re
import subprocess
import sys

ALLOWED_STAGES = {"05b", "06", "07", "08", "09"}
FIELD = re.compile(r"^(CURRENT_HOP|CURRENT_STAGE|CURRENT_SLICE|AUTOPILOT):[ \t]*(.*?)[ \t]*$", re.M)   # never \s: it eats newlines
DLINE = re.compile(r"^D\d+\s*\|(?!.*\{\{).*$", re.M)   # a {{placeholder}} line is an example, not a law


def fields(text: str) -> dict:
    d = {"CURRENT_HOP": "", "CURRENT_STAGE": "", "CURRENT_SLICE": "", "AUTOPILOT": ""}
    for m in FIELD.finditer(text):
        d[m.group(1)] = m.group(2).strip()
    return d


def entries(spec: str) -> list[tuple[str, str]]:
    out = []
    for part in [p.strip() for p in spec.split(",") if p.strip()]:
        bits = part.split()
        if len(bits) < 2:
            raise ValueError(f"bad AUTOPILOT entry {part!r}: want 'STAGE SLICE'")
        stage, slice_ = bits[0], " ".join(bits[1:])
        if stage not in ALLOWED_STAGES:
            raise ValueError(f"AUTOPILOT entry {part!r}: stage {stage} may not be pre-signed (only {sorted(ALLOWED_STAGES)})")
        out.append((stage, slice_))
    return out


def decide(before: str, after: str, root: str) -> str | None:
    """Return None if the change is an allowed autopilot transition, else the reason it is not."""
    b, a = fields(before), fields(after)
    if a["AUTOPILOT"] != b["AUTOPILOT"]:
        return "the AUTOPILOT line is human-owned"
    if sorted(DLINE.findall(before)) != sorted(DLINE.findall(after)):
        return "D# lines are human-owned"
    if not b["AUTOPILOT"]:
        return "autopilot is off (no AUTOPILOT line signed by a human)"
    try:
        plan = entries(b["AUTOPILOT"])
    except ValueError as exc:
        return str(exc)
    cur = (b["CURRENT_STAGE"], b["CURRENT_SLICE"])
    nxt = (a["CURRENT_HOP"].upper(), a["CURRENT_STAGE"], a["CURRENT_SLICE"])
    idx = plan.index(cur) if cur in plan else -1
    hop = b["CURRENT_HOP"].upper()

    if idx < 0 or hop in ("", "NONE"):
        want = ("GENERATE",) + plan[0]
        return None if nxt == want else f"next allowed edge is GENERATE {plan[0][0]} {plan[0][1]}"
    if hop == "GENERATE":
        want = ("EXECUTE",) + plan[idx]
        if nxt != want:
            return f"next allowed edge is EXECUTE {plan[idx][0]} {plan[idx][1]}"
        specs = [p for p in glob.glob(os.path.join(root, "docs", "cascade", "*.md"))
                 if plan[idx][1] in os.path.basename(p) and os.path.basename(p) not in ("envelope.md", "goal.md")]
        return None if specs else f"no spec doc for slice {plan[idx][1]!r} under docs/cascade/ — GENERATE first"
    if hop == "EXECUTE":
        if idx + 1 >= len(plan):
            return "end of the signed list — a human takes the next edge"
        want = ("GENERATE",) + plan[idx + 1]
        if nxt != want:
            return f"next allowed edge is GENERATE {plan[idx + 1][0]} {plan[idx + 1][1]}"
        try:
            # Evaluate the loop against the pre-edge envelope: the working tree may already say GENERATE.
            env = dict(os.environ, CASCADE_ENVELOPE=sys.argv[1] if len(sys.argv) > 1 else "")
            rc = subprocess.run(["bash", os.path.join(root, "tests", "loop.sh")], cwd=root, env=env,
                                capture_output=True, text=True, timeout=1200).returncode
        except Exception as exc:  # noqa: BLE001
            return f"could not run tests/loop.sh ({exc!r})"
        return None if rc == 0 else "tests/loop.sh is not n/n — the hop is not done"
    return f"unknown hop {hop!r}"


def status(root: str) -> str:
    """'off' | 'done' | 'next GENERATE 05b x' | 'next EXECUTE 05b x' | 'error: …' — for hooks and commands."""
    env_path = os.path.join(root, "docs", "cascade", "envelope.md")
    try:
        f = fields(open(env_path, encoding="utf-8", errors="replace").read())
    except OSError:
        return "off"
    if not f["AUTOPILOT"]:
        return "off"
    try:
        plan = entries(f["AUTOPILOT"])
    except ValueError as exc:
        return f"error: {exc}"
    cur = (f["CURRENT_STAGE"], f["CURRENT_SLICE"]); hop = f["CURRENT_HOP"].upper()
    idx = plan.index(cur) if cur in plan else -1
    if idx < 0 or hop in ("", "NONE"):
        return f"next GENERATE {plan[0][0]} {plan[0][1]}"
    if hop == "GENERATE":
        return f"next EXECUTE {plan[idx][0]} {plan[idx][1]}"
    if idx + 1 >= len(plan):
        return "done"
    return f"next GENERATE {plan[idx + 1][0]} {plan[idx + 1][1]}"


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--status":
        print(status(sys.argv[2])); return 0
    if len(sys.argv) != 4:
        print("usage: autopilot.py <before> <after> <root> | --status <root>", file=sys.stderr)
        return 64
    before = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    after = open(sys.argv[2], encoding="utf-8", errors="replace").read()
    why = decide(before, after, sys.argv[3])
    if why:
        print(f"autopilot: not allowed — {why}", file=sys.stderr)
        return 1
    print("autopilot: allowed edge", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
