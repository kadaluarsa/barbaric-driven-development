#!/usr/bin/env python3
"""UserPromptSubmit — the seam between the cascade and craft skills (I14), as mechanism.

While a cascade is running, every prompt gets the current hop class and the skills that are
legal on it, from docs/cascade/skill-binding.md. Cascade precedence is stated each time.
Silent when CURRENT_HOP is NONE, so it costs nothing outside a cascade.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

DESIGN = {"01", "02", "03", "04"}
PRR = {"11"}


def hop_class(hop: str, stage: str) -> str | None:
    hop = hop.upper()
    if hop == "GENERATE":
        return "GENERATE"
    if hop == "EXECUTE":
        st = stage.split()[0] if stage else ""
        if st in DESIGN:
            return "EXECUTE-DESIGN"
        if st in PRR:
            return "EXECUTE-PRR"
        return "EXECUTE-BUILD"
    return None


def main() -> int:
    try:
        ev = json.load(sys.stdin)
        root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
                              capture_output=True, text=True, check=True).stdout.strip()
        env_path = os.path.join(root, "docs", "cascade", "envelope.md")
        hop = stage = slice_ = autopilot = ""
        with open(env_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("CURRENT_HOP:"):
                    hop = line.split(":", 1)[1].strip()
                elif line.startswith("CURRENT_STAGE:"):
                    stage = line.split(":", 1)[1].strip()
                elif line.startswith("CURRENT_SLICE:"):
                    slice_ = line.split(":", 1)[1].strip()
                elif line.startswith("AUTOPILOT:"):
                    autopilot = line.split(":", 1)[1].strip()
        cls = hop_class(hop, stage)
        if cls is None:
            return 0
        allow = deny = "(binding table missing: docs/cascade/skill-binding.md)"
        try:
            with open(os.path.join(root, "docs", "cascade", "skill-binding.md"), encoding="utf-8") as fh:
                for line in fh:
                    m = re.match(r"^\s*([A-Z-]+)\s*\|\s*allow:\s*(.*?)\s*\|\s*deny:\s*(.*?)\s*$", line)
                    if m and m.group(1) == cls:
                        allow, deny = m.group(2) or "(none)", m.group(3) or "(none)"
        except OSError:
            pass
        loop_ok = cls == "EXECUTE-BUILD"
        ctx = (
            f"CASCADE SEAM (I14): Current hop {hop} stage {stage}{' slice ' + slice_ if slice_ else ''} — class {cls}.\n"
            f"Skills allowed this hop: {allow}.\n"
            f"Skills denied this hop: {deny}.\n"
            f"`bash tests/loop.sh` is {'legal' if loop_ok else 'ILLEGAL'} on this hop. "
            f"Cascade outranks every skill: a skill that says 'do not pause' loses to I1 — stop at STITCH NEEDED. "
            f"Name any skipped skill in the hop report.\n"
            f"Laws (D#) apply to every account, tier, flag, mode and currency. A slice never carves an exception "
            f"into a law and never adds a test under an existing D#; if the slice needs the law to change, STOP "
            f"and say so at the edge (I6/I13).\n"
            + (f"AUTOPILOT is ON: signed list = {autopilot}. You may advance CURRENT_HOP yourself ONLY to the next "
               f"signed edge (GENERATE->EXECUTE needs the slice's spec doc; EXECUTE->next needs `bash tests/loop.sh` n/n). "
               f"Still print the edge line at every hop. Stages 10/11 and merge remain human."
               if autopilot else "AUTOPILOT is off: every hop edge is the human's.")
        )
        try:
            _env = open(env_path, encoding="utf-8", errors="replace").read()
            _declared = [l for l in _env.splitlines() if re.match(r"^D\d+\s*\|", l)]
            _proven = [l for l in _declared if "{{" not in l and len([c for c in l.split("|") if c.strip() and c.strip().lower() not in ("todo", "none")]) >= 4]
            if not _proven:
                ctx += "\nNO LAW IN FORCE: propose with `/barbar init` (writes docs/cascade/proposals.md for the human to sign); never write D# lines yourself."
        except OSError:
            pass
        json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ctx}}, sys.stdout)
        return 0
    except Exception as exc:  # never block a prompt; say why the seam is missing
        print(f"cascade seam hook error: {exc}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
