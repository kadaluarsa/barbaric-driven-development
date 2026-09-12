#!/usr/bin/env python3
"""PostToolUse(Write|Edit) — turn a human-approved write into a signature pre-commit can verify.

hop_guard answers `ask` (never `allow`) for a hop flip, an AUTOPILOT/D# change, an <EDIT> change or a law-test
change in an interactive session, and records the intended content hash in $GIT_DIR/cascade-sign-pending.
The write only happens if the human approved the dialog. This hook then verifies the file on disk matches
the pending hash and appends `<sha256> <path>` to $GIT_DIR/cascade-human-ok, which pre-commit consumes once.
The agent cannot forge either file: bash_guard denies any command that names them.
"""
from __future__ import annotations

NAME = "sign_ok.py"

import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _common import already_handled, log
except Exception as _exc:
    # No token can be minted without this module. Say so loudly: silence here looks like a signature that
    # simply did not work, and the human keeps approving dialogs that never land.
    print(f"cascade: {NAME} could not load _common.py ({_exc!r}) — no signature was recorded. "
          "Run `bash tests/sign.sh` and commit again.", file=sys.stderr)
    raise SystemExit(0)

ACTOR = NAME[:-3]


def _verify_laws(root: str, rel: str) -> None:
    """A law signed is not a law proven. Run the strength check now and say so, instead of letting the
    human find out at the next /barbar auto that what they signed protects nothing."""
    if rel != os.path.join("docs", "cascade", "envelope.md"):   # laws live here; hop-state.md has none
        return
    try:
        out = subprocess.run(["bash", os.path.join(root, "tests", "dsharp_strength.sh")], cwd=root,
                             capture_output=True, text=True, timeout=600).stdout
    except Exception:
        return
    bad = [l for l in out.splitlines() if l[:8].strip() in ("RED", "THEATER", "UNPROVEN")]
    score = next((l for l in out.splitlines() if l.startswith("DSHARP ")), "")
    if bad:
        print("cascade: " + score + " — signed, but not yet protecting you:\n  "
              + "\n  ".join(bad[:6])
              + "\n  A law is in force only once its check passes and its break fails.", file=sys.stderr)
    elif score:
        print(f"cascade: {score} — every law green.", file=sys.stderr)


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
    if already_handled(ev, root, NAME):
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
        log(root, ACTOR, "SIGNED", f"{rel} sha={got[:12]} — approved in the permission dialog")
        _verify_laws(root, rel)
    keep = [l for l in lines if not l.endswith(" " + rel)]   # consume the pending record either way
    with open(pending, "w") as fh:
        fh.write("\n".join(keep) + ("\n" if keep else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
