#!/usr/bin/env python3
"""Stop — a hop does not end without a hop edge (I1).

The last assistant message must end at STITCH NEEDED. Exit 2 blocks the stop and
returns stderr to Claude. Silent unless the repo is actually running a cascade.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

EDGES = ("STITCH NEEDED:", "BARBAR ", "LOOP REFUSED", "BLOCKED")
HALT = "AUTOPILOT HALT"


def autopilot_status(root: str) -> str:
    try:
        return subprocess.run([sys.executable, os.path.join(root, "tests", "lib", "autopilot.py"), "--status", root],
                              capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return "off"


def continue_autopilot(root: str, session: str, status: str, last: str) -> bool:
    """Block the stop while signed edges remain — bounded, and never past an explicit HALT."""
    if not status.startswith("next") or HALT in last:
        return False
    plan_len = 1
    try:
        env = open(os.path.join(root, "docs", "cascade", "envelope.md"), encoding="utf-8", errors="replace").read()
        m = re.search(r"^AUTOPILOT:[ \t]*(.*?)[ \t]*$", env, re.M)
        plan_len = max(1, len([x for x in (m.group(1) if m else "").split(",") if x.strip()]))
    except OSError:
        pass
    cap = 4 * plan_len + 4
    counter = os.path.join(root, ".git", f"cascade-autopilot-{session or 'session'}")
    try:
        n = int(open(counter).read().strip()) if os.path.exists(counter) else 0
    except ValueError:
        n = 0
    if n >= cap:
        print(f"autopilot: continuation cap reached ({cap}) — stopping so a human can look.", file=sys.stderr)
        return False
    with open(counter, "w") as fh:
        fh.write(str(n + 1))
    return True


def last_assistant_text(path: str) -> str:
    last = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("type") != "assistant":
                    continue
                content = (rec.get("message") or {}).get("content") or []
                text = "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
                if text.strip():
                    last = text
    except OSError:
        return ""
    return last


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    root0 = None
    try:
        root0 = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
                               capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        root0 = None
    # Autopilot: a signed list means "keep going" — even across repeated stops — until done, HALT, or the cap.
    if root0:
        status = autopilot_status(root0)
        if status.startswith("next"):
            last = last_assistant_text(ev.get("transcript_path", ""))
            if last and any(e in last for e in EDGES) and continue_autopilot(root0, ev.get("session_id", ""), status, last):
                print(f"AUTOPILOT: signed edges remain — {status}. Advance docs/cascade/envelope.md to exactly that edge "
                      f"(the hooks verify), do the hop, end with its edge line. To stop early, end with "
                      f"'{HALT}: <reason>'.", file=sys.stderr)
                return 2
    if ev.get("stop_hook_active"):
        return 0

    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return 0

    env_path = os.path.join(root, "docs", "cascade", "envelope.md")
    hop = stage = ""
    try:
        with open(env_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("CURRENT_HOP:"):
                    hop = line.split(":", 1)[1].strip().upper()
                elif line.startswith("CURRENT_STAGE:"):
                    stage = line.split(":", 1)[1].strip()
    except OSError:
        return 0
    if hop not in ("GENERATE", "EXECUTE"):
        return 0

    last = last_assistant_text(ev.get("transcript_path", ""))
    if not last:
        return 0
    if any(e in last for e in EDGES):
        return 0

    edge = ("review spec+plan" if hop == "GENERATE" else "accept execute")
    print(
        f"Hop not closed (I1). This is {hop} stage {stage or 'N'}. Every hop ends by "
        f"printing the invariant block and then exactly one edge line:\n"
        f"  STITCH NEEDED: {edge} for stage {stage or 'N'}"
        + (", or send back." if hop == "EXECUTE" else ".") + "\n"
        "Print it now and stop. Do not start the next hop.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
