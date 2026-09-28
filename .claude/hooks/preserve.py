#!/usr/bin/env python3
"""SessionStart(startup|compact|resume|clear) — re-inject the control line; on startup, only the health notes.

The PRESERVE protocol cannot depend on the agent choosing to reprint invariants
right after its context was squeezed. This injects them from git every time.
Implements I2/I3 as mechanism instead of instruction.

On a plain startup nothing was squeezed — the rules load from AGENTS.md — so the control line is not repeated.
Only two notes can print, each only when true: the plugin/repo version drift and LAYER 1 IS OFF. The first
session on a fresh clone is the one where the git hooks are certain to be off, and it used to hear nothing
(t60). A healthy repo's startup stays silent.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _common import already_event, decisions_tail, git_dir, hopstate, repo_root
except Exception:
    raise SystemExit(0)   # a session must start even if this module is missing; it injects nothing

NAME = "preserve.py"
ACTOR = NAME[:-3]

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


def drift_note(root: str) -> str:
    """The plugin updates machine-wide; a repo's tests/ .githooks/ commands come from install.sh. Say so the
    moment they diverge — a stale repo half is how a fixed bug appears to still be broken."""
    plug = os.environ.get("BDD_PLUGIN_ROOT", "")
    if not plug:
        return ""
    try:
        with open(os.path.join(plug, "VERSION"), encoding="utf-8") as fh:
            plugin_v = fh.read().strip()
        repo_v = ""
        with open(os.path.join(root, ".cascade", "manifest"), encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("version "):
                    repo_v = line.split(None, 1)[1].strip()
                    break
    except OSError:
        return ""
    if repo_v and plugin_v and repo_v != plugin_v:
        return (f"\nBDD VERSION DRIFT: the plugin is {plugin_v}, this repo's scripts are {repo_v}. Fixes in the "
                f"plugin do NOT reach tests/loop.sh, .githooks/ or the commands until the repo is refreshed. "
                f"Tell the human, once, in one line:\n"
                f"  bash {plug}/install.sh . && git add -A && git commit -m 'cascade: update pack to {plugin_v}'")
    return ""


def layer1_note(root: str) -> str:
    """core.hooksPath is git config: per-clone, never committed. A fresh clone on a second machine has
    .githooks/ on disk and git not calling it — Layer 1 off, silently, looking identical to a working repo."""
    if not os.path.isdir(os.path.join(root, ".githooks")):
        return ""
    try:
        hp = subprocess.run(["git", "config", "core.hooksPath"], cwd=root,
                            capture_output=True, text=True).stdout.strip()
    except Exception:
        return ""
    if hp == ".githooks":
        return ""
    where = f"points at '{hp}'" if hp else "is not set (a fresh clone never inherits it — it is git config, not a file)"
    return (f"\nLAYER 1 IS OFF: this repo ships .githooks/ but core.hooksPath {where}. The commit and push "
            f"gates are not running here, and nothing else will say so. Tell the human, once, in one line:\n"
            f"  git config core.hooksPath .githooks")


def emit(ctx: list[str]) -> None:
    json.dump({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "\n".join(ctx)}},
              sys.stdout)


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    source = ev.get("source")
    if source not in ("startup", "compact", "resume", "clear"):
        return 0
    try:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=ev.get("cwd") or os.getcwd(),
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if already_event(ev, root, NAME, "session_id"):
            return 0
    except Exception:
        return 0

    env_path = os.path.join(root, "docs", "cascade", "envelope.md")   # laws
    if not os.path.exists(env_path):
        return 0

    if source == "startup":
        notes = [n for n in (drift_note(root), layer1_note(root)) if n]
        if notes:
            emit(["CASCADE — session start:"] + notes)
        return 0

    hop = stage = slice_ = ""
    dsharp: list[str] = []
    with open(hopstate(root), encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.rstrip("\n")
            if s.startswith("CURRENT_HOP:"):
                hop = s.split(":", 1)[1].strip()
            elif s.startswith("CURRENT_STAGE:"):
                stage = s.split(":", 1)[1].strip()
            elif s.startswith("CURRENT_SLICE:"):
                slice_ = s.split(":", 1)[1].strip()
    laws_py = os.path.join(root, "tests", "lib", "laws.py")
    # "In force" is laws.py's verdict (--in-force), as seam.py reads it — not re-derived here from the first
    # break, which called a law with an unrunnable second break in force while every other reader did not (t60).
    in_force_ids = {l.split("|", 1)[0] for l in subprocess.run(
        [sys.executable, "-B", laws_py, env_path, "--in-force"], capture_output=True, text=True).stdout.splitlines()}
    for line in subprocess.run(
        [sys.executable, "-B", laws_py, env_path, "--declared"], capture_output=True, text=True,
    ).stdout.splitlines():
        p = line.split("|")
        if len(p) < 4:
            continue
        in_force = p[0] in in_force_ids
        dsharp.append(f"  {p[0]}  {p[1]}  ->  " + (f"IN FORCE: {p[2]}" if in_force
                      else "NOT IN FORCE (needs a check and a break that fails; STOP and ask)"))
    any_proven = bool(in_force_ids - {""})

    ctx = [INVARIANTS, f"Current hop: {hop or 'UNSET'} stage {stage or 'UNSET'}"]
    if slice_:
        ctx.append(f"Current slice: {slice_}")
    ctx.append("Domain laws (D#):")
    ctx.extend(dsharp or ["  (none declared)"])
    ctx.append("\nConfirm Current hop is unchanged, then do only that hop.")
    ctx.extend(n for n in (drift_note(root), layer1_note(root)) if n)

    # The morning after an unattended run: what was denied, signed, or went red is in the log, not in git.
    recent = decisions_tail(root, 12)
    if recent:
        ctx.append("\nLast decisions this repo recorded (`.cascade/decisions.log`, newest last):\n  "
                   + "\n  ".join(recent))

    if not any_proven:
        ctx.append("\nCASCADE NOT INITIALIZED: no law (D#) is in force — the envelope still has the placeholder or unproven "
                   "lines. Tell the human, once, in one line: run `/barbar init` to scan this repo and propose laws + audit "
                   "rows for them to sign, or fill docs/cascade/envelope.md by hand. Do not invent laws yourself (I13).")

    emit(ctx)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
