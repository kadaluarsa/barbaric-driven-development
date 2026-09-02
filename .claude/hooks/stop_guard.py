#!/usr/bin/env python3
"""Stop — a hop does not end without a hop edge (I1).

The last assistant message must end at STITCH NEEDED. Exit 2 blocks the stop and
returns stderr to Claude. Silent unless the repo is actually running a cascade.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

EDGES = ("STITCH NEEDED:", "BARBAR ", "LOOP REFUSED", "BLOCKED")


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
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

    last = ""
    try:
        with open(ev.get("transcript_path", ""), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("type") != "assistant":
                    continue
                content = (rec.get("message") or {}).get("content") or []
                text = "".join(
                    c.get("text", "") for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                )
                if text.strip():
                    last = text
    except OSError:
        return 0
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
