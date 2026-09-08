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

While a hop is open, every reply ends with the invariant block and exactly one of:
  STITCH NEEDED: review spec+plan for stage <the real stage>
  STITCH NEEDED: accept execute for stage <the real stage>, or send back
When no hop is running, end normally: a question is not a hop, and an edge line over
one is noise that hides the real edge.
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
    for line in subprocess.run(
        [sys.executable, "-B", os.path.join(root, "tests", "lib", "laws.py"), env_path, "--declared"],
        capture_output=True, text=True,
    ).stdout.splitlines():
        p = line.split("|")
        if len(p) < 4:
            continue
        in_force = bool(p[2].strip() and p[3].strip())
        any_proven = any_proven or in_force
        dsharp.append(f"  {p[0]}  {p[1]}  ->  " + (f"IN FORCE: {p[2]}" if in_force
                      else "NOT IN FORCE (needs a check and a break that fails; STOP and ask)"))

    ctx = [INVARIANTS, f"Current hop: {hop or 'UNSET'} stage {stage or 'UNSET'}"]
    if slice_:
        ctx.append(f"Current slice: {slice_}")
    ctx.append("Domain laws (D#):")
    ctx.extend(dsharp or ["  (none declared)"])
    ctx.append("\nConfirm Current hop is unchanged, then do only that hop.")

    # The plugin updates machine-wide; a repo's tests/ .githooks/ commands come from install.sh. Say so
    # the moment they diverge — a stale repo half is how a fixed bug appears to still be broken.
    plug = os.environ.get("BDD_PLUGIN_ROOT", "")
    if plug:
        try:
            with open(os.path.join(plug, "VERSION"), encoding="utf-8") as fh:
                plugin_v = fh.read().strip()
            repo_v = ""
            with open(os.path.join(root, ".cascade", "manifest"), encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("version "):
                        repo_v = line.split(None, 1)[1].strip()
                        break
            if repo_v and plugin_v and repo_v != plugin_v:
                ctx.append(
                    f"\nBDD VERSION DRIFT: the plugin is {plugin_v}, this repo's scripts are {repo_v}. Fixes in the "
                    f"plugin do NOT reach tests/loop.sh, .githooks/ or the commands until the repo is refreshed. "
                    f"Tell the human, once, in one line:\n"
                    f"  bash {plug}/install.sh . && git add -A && git commit -m 'cascade: update pack to {plugin_v}'"
                )
        except OSError:
            pass
    # core.hooksPath is git config: per-clone, never committed. A fresh clone on a second machine has
    # .githooks/ on disk and git not calling it — Layer 1 off, silently, looking identical to a working repo.
    if os.path.isdir(os.path.join(root, ".githooks")):
        try:
            hp = subprocess.run(["git", "config", "core.hooksPath"], cwd=root,
                                capture_output=True, text=True).stdout.strip()
        except Exception:
            hp = ".githooks"
        if hp != ".githooks":
            where = f"points at '{hp}'" if hp else "is not set (a fresh clone never inherits it — it is git config, not a file)"
            ctx.append(
                f"\nLAYER 1 IS OFF: this repo ships .githooks/ but core.hooksPath {where}. The commit and push "
                f"gates are not running here, and nothing else will say so. Tell the human, once, in one line:\n"
                f"  git config core.hooksPath .githooks")

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
