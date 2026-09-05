#!/usr/bin/env python3
"""SessionStart(compact|resume|clear) — re-inject the control line.

The PRESERVE protocol cannot depend on the agent choosing to reprint invariants
right after its context was squeezed. This injects them from git every time.
Implements I2/I3 as mechanism instead of instruction.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

INVARIANTS = """\
CASCADE CONTROL LINE — re-injected from git after a context break (I2/I3).
Durable truth is docs/cascade/. Chat residue is not. Do not reconstruct locks from
compacted conversation.

I1  One hop per reply: GENERATE or EXECUTE of one stage. Never both. Never N+1.
I4  No product code before 05 is accepted. 05b is the only build hop, one named slice.
I7  Stage 10 IMPLEMENTED needs a path in the tree AND a named test. Reports are not proof.
I9  /goal is this hop's DoD. Run `bash tests/loop.sh`, do not type LOOP k/n yourself.
I13 A D# without a validator command is not in force. STOP and ask; do not code around it.
I15 GENERATE stops at spec+plan. /loop illegal on GENERATE, 01-04, 11. No auto-merge
    before CLEAN 10 + 11 READY. The human stays on every hop edge.
I17 Chat is not evidence. A violation is a red test, not a stronger prompt.
I18 Enforcement is layered: CI > git hooks > agent hooks > prose. Never weaken a layer
    to make a hop pass.

Every reply ends with the invariant block and exactly one of:
  STITCH NEEDED: review spec+plan for stage N
  STITCH NEEDED: accept execute for stage N, or send back
"""


def _already(ev: dict, root: str) -> bool:
    """Plugin and project hooks may both be wired; a prompt/stop is handled once."""
    k = (ev.get("session_id") or "") + "-" + str(ev.get("hook_event_name", "")) + "-" + str(ev.get("source", ""))
    if not ev.get("session_id") or not root:
        return False
    try:
        gitdir = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root, capture_output=True, text=True, check=True).stdout.strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(root, gitdir)
        d = os.path.join(gitdir, "cascade-seen"); os.makedirs(d, exist_ok=True)
        m = os.path.join(d, "preserve.py-" + k[:120])
        if os.path.exists(m):
            return True
        open(m, "w").close(); return False
    except Exception:
        return False


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if ev.get("source") not in ("compact", "resume", "clear"):
        return 0
    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if _already(ev, root):
            return 0
    except Exception:
        return 0

    env_path = os.path.join(root, "docs", "cascade", "envelope.md")
    if not os.path.exists(env_path):
        return 0

    hop = stage = slice_ = ""
    dsharp: list[str] = []
    any_proven = False
    with open(env_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.rstrip("\n")
            if s.startswith("CURRENT_HOP:"):
                hop = s.split(":", 1)[1].strip()
            elif s.startswith("CURRENT_STAGE:"):
                stage = s.split(":", 1)[1].strip()
            elif s.startswith("CURRENT_SLICE:"):
                slice_ = s.split(":", 1)[1].strip()
            elif s[:1] == "D" and "|" in s and s.split("|")[0].strip()[1:].isdigit() and "{{" not in s:   # placeholders are examples
                parts = [p.strip() for p in s.split("|")]
                has_val = len(parts) > 2 and parts[2] and parts[2].lower() not in ("todo", "none")
                has_twin = len(parts) > 3 and parts[3] and parts[3].lower() not in ("todo", "none")
                in_force = bool(has_val and has_twin and "{{" not in s)
                any_proven = any_proven or in_force
                dsharp.append(
                    f"  {parts[0]}  {parts[1]}  ->  "
                    + (f"IN FORCE: {parts[2]}" if in_force else "NOT IN FORCE (needs validator + red twin; STOP and ask)")
                )

    ctx = [INVARIANTS, f"Current hop: {hop or 'UNSET'} stage {stage or 'UNSET'}"]
    if slice_:
        ctx.append(f"Current slice: {slice_}")
    ctx.append("Domain laws (D#):")
    ctx.extend(dsharp or ["  (none declared)"])
    ctx.append("\nConfirm Current hop is unchanged, then do only that hop.")
    if not any_proven:
        ctx.append("\nCASCADE NOT INITIALIZED: no law (D#) is in force — the envelope still has the placeholder or unproven "
                   "lines. Tell the human, once, in one line: run `/barbar init` to scan this repo and propose laws + audit "
                   "rows for them to sign, or fill docs/cascade/envelope.md by hand. Do not invent laws yourself (I13).")

    json.dump(
        {"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": "\n".join(ctx),
        }},
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
