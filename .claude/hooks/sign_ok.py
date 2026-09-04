#!/usr/bin/env python3
"""PostToolUse(Write|Edit) — turn a human-approved write into a signature pre-commit can verify.

hop_guard answers `ask` (never `allow`) for a hop flip, an AUTOPILOT/D# change, an <EDIT> change or a law-test
change in an interactive session, and records the intended content hash in $GIT_DIR/cascade-sign-pending.
The write only happens if the human approved the dialog. This hook then verifies the file on disk matches
the pending hash and appends `<sha256> <path>` to $GIT_DIR/cascade-human-ok, which pre-commit consumes once.
The agent cannot forge either file: bash_guard denies any command that names them.
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if ev.get("tool_name") not in ("Write", "Edit", "MultiEdit"):
        return 0
    path = (ev.get("tool_input") or {}).get("file_path") or ""
    try:
        root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
                              capture_output=True, text=True, check=True).stdout.strip()
        gitdir = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root,
                                capture_output=True, text=True, check=True).stdout.strip()
        gitdir = gitdir if os.path.isabs(gitdir) else os.path.join(root, gitdir)
    except Exception:
        return 0
    pending = os.path.join(gitdir, "cascade-sign-pending")
    if not os.path.exists(pending) or not path:
        return 0
    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(root))   # macOS: /var vs /private/var
    try:
        lines = [l for l in open(pending).read().splitlines() if " " in l]
    except OSError:
        return 0
    want = {l.split(" ", 1)[1]: l.split(" ", 1)[0] for l in lines}   # path -> sha256
    if rel not in want:
        return 0
    try:
        got = hashlib.sha256(open(os.path.join(root, rel), "rb").read()).hexdigest()
    except OSError:
        return 0
    if got == want[rel]:
        with open(os.path.join(gitdir, "cascade-human-ok"), "a") as fh:
            fh.write(f"{got} {rel}\n")
        print(f"cascade: human signature recorded for {rel}", file=sys.stderr)
    keep = [l for l in lines if not l.endswith(" " + rel)]   # consume the pending record either way
    with open(pending, "w") as fh:
        fh.write("\n".join(keep) + ("\n" if keep else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
