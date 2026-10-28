#!/usr/bin/env python3
"""SessionStart — re-inject the control line, and keep a plugin-mode repo on the plugin's version.

compact|resume|clear: the PRESERVE protocol cannot depend on the agent choosing to reprint invariants
right after its context was squeezed. This injects them from git every time.
Implements I2/I3 as mechanism instead of instruction.

Every source, startup included (t62): when the plugin is newer than the repo's shipped scripts, refresh them
with the plugin's install.sh if that is provably safe, else say why not and what to run. On startup that one
line is all this hook prints — and nothing when versions match.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from _common import already_event, decisions_tail, git_dir, hopstate, hopstate_field, repo_root
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
I13 A D# (envelope or law shard) without a validator command is not in force. STOP and ask; do not code around it.
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


def _vkey(v: str) -> tuple:
    return tuple(int(x) if x.isdigit() else 0 for x in v.split("."))


def _git(root: str, *args: str, timeout: int = 20) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, timeout=timeout, env=env)


def _refresh_blocker(root: str, plug: str, plugin_v: str, repo_v: str) -> str:
    """Why a refresh is not provably safe right now, or '' when it is (t62 §4, conditions 1–5)."""
    if _vkey(plugin_v) < _vkey(repo_v):
        return "the repo is newer than the plugin, and a refresh never downgrades"
    if os.environ.get("BDD_AUTO_REFRESH") == "0":
        return "BDD_AUTO_REFRESH=0 is set"
    if os.path.exists(os.path.join(root, ".cascade", "disabled", "state.json")):
        return "BDD is stood down in this repo"
    hop = hopstate_field(root, "CURRENT_HOP")
    if hop and hop != "NONE":
        here = " ".join(x for x in (hop, hopstate_field(root, "CURRENT_STAGE"), hopstate_field(root, "CURRENT_SLICE")) if x)
        return f"a hop is open ({here}); it refreshes at the next session start once the cascade is idle"
    if not os.path.isfile(os.path.join(plug, "install.sh")):
        return "the plugin has no install.sh"
    if _git(root, "status", "--porcelain").stdout.strip():
        return "the working tree has uncommitted changes; commit or stash them, then start a session"
    chk = subprocess.run(["bash", os.path.join(plug, "install.sh"), "--check", root], cwd=root,
                         capture_output=True, text=True, timeout=15)
    edited = [l for l in chk.stdout.splitlines() if l.startswith(("DRIFTED", "MISSING", "IGNORED", "UNWIRED"))]
    if edited:
        return f"a shipped file differs from what was installed ({edited[0].split(None, 1)[-1].strip()}), and a refresh never overwrites your edits"
    return ""


def _refresh(root: str, plug: str, mode: str) -> str:
    """Refresh this clean repo from the plugin's install.sh. '' on success, else why nothing was changed.

    install.sh runs in a temporary worktree of HEAD, never in the user's tree. Only when it and --check both pass
    is the result applied, with one `git apply` (all hunks or none) onto a tree checked clean a moment before. A
    failure, a timeout or a concurrent edit therefore never leaves a half-refreshed tree or touches anyone's work,
    and nothing has to be rolled back."""
    gd = git_dir(root) or os.path.join(root, ".git")
    lock, log = os.path.join(gd, "cascade-refresh.lock"), os.path.join(gd, "cascade-refresh.log")
    try:
        os.mkdir(lock)
    except FileExistsError:
        # The hook's own timeout is 180s (hooks.json): an older lock belongs to a session that was killed.
        if time.time() - os.path.getmtime(lock) < 300:
            return "another session is refreshing this repo right now"
        os.rmdir(lock)
        os.mkdir(lock)
    except OSError as exc:
        return f"could not take the refresh lock ({exc})"
    install = os.path.join(plug, "install.sh")
    tmp = tempfile.mkdtemp(prefix="bdd-refresh-")
    wt = os.path.join(tmp, "wt")
    try:
        _git(root, "worktree", "prune")
        # No hooks: a product's post-checkout (LFS, husky) has no business running for a staging copy.
        if _git(root, "-c", "core.hooksPath=/dev/null", "worktree", "add", "--quiet", "--detach", wt, "HEAD",
                timeout=30).returncode != 0:
            return "could not stage the refresh in a temporary worktree; nothing in this repo was changed"
        with open(log, "w") as fh:
            ok = subprocess.run(["bash", install, "--plugin" if mode == "plugin" else "--no-plugin", wt], cwd=wt,
                                stdout=fh, stderr=subprocess.STDOUT, timeout=40).returncode == 0
        ok = ok and subprocess.run(["bash", install, "--check", wt], cwd=wt, capture_output=True,
                                   timeout=15).returncode == 0
        if not ok:
            return f"install.sh or its --check failed in a temporary worktree; nothing in this repo was changed (log: {log})"
        _git(wt, "add", "-A")
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        patch = subprocess.run(["git", "diff", "--cached", "--binary", "HEAD"], cwd=wt, capture_output=True,
                               timeout=20, env=env).stdout
        if _git(root, "status", "--porcelain").stdout.strip():
            return "the working tree changed while the refresh was prepared; nothing was applied"
        if patch.strip() and subprocess.run(["git", "apply", "--whitespace=nowarn", "-"], cwd=root, input=patch,
                                            capture_output=True, timeout=20, env=env).returncode != 0:
            return "the refresh could not be applied (git apply refused it); nothing in this repo was changed"
        return ""
    except subprocess.TimeoutExpired as exc:
        return f"a step timed out ({' '.join(map(str, exc.cmd[:2]))}); nothing in this repo was changed"
    except OSError as exc:
        return f"the refresh could not run ({exc}); nothing in this repo was changed"
    finally:
        _git(root, "worktree", "remove", "--force", wt)
        shutil.rmtree(tmp, ignore_errors=True)
        try:
            os.rmdir(lock)
        except OSError:
            pass


def refresh_or_notice(root: str) -> str:
    """Plugin mode: the context line about the plugin/repo version, or '' when they match (t62 §4)."""
    plug = os.environ.get("BDD_PLUGIN_ROOT", "")
    if not plug:
        return ""
    try:
        with open(os.path.join(plug, "VERSION"), encoding="utf-8") as fh:
            plugin_v = fh.read().strip()
        repo_v = mode = ""
        with open(os.path.join(root, ".cascade", "manifest"), encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("version "):
                    repo_v = line.split(None, 1)[1].strip()
                elif line.startswith("mode "):
                    mode = line.split(None, 1)[1].strip()
    except OSError:
        return ""
    if not repo_v or not plugin_v or repo_v == plugin_v:
        return ""
    if os.path.realpath(plug) == os.path.realpath(root):
        return ""                                          # the pack itself: it is the source, never a target
    try:
        why = _refresh_blocker(root, plug, plugin_v, repo_v) or _refresh(root, plug, mode)
    except Exception as exc:  # noqa: BLE001 — a session must start; say what happened instead
        why = f"the check could not run ({type(exc).__name__})"
    if not why:
        n = len(_git(root, "status", "--porcelain").stdout.splitlines())
        return (f"\nBDD REFRESHED: this repo's shipped scripts were brought from {repo_v} to {plugin_v} to match the "
                f"plugin ({n} paths changed; goal.md, envelope.md and hop-state.md untouched; nothing committed). "
                f"Tell the human, once, in one line, and commit them on their own:\n"
                f"  git add -A && git commit -m 'cascade: update pack to {plugin_v}'")
    return (f"\nBDD VERSION DRIFT: the plugin is {plugin_v}, this repo's scripts are {repo_v}, not refreshed "
            f"automatically: {why}. Fixes in the plugin do NOT reach tests/loop.sh, .githooks/ or the commands until "
            f"the repo is refreshed. Tell the human, once, in one line:\n"
            f"  bash {plug}/install.sh . && git add -A && git commit -m 'cascade: update pack to {plugin_v}'")


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    source = ev.get("source")
    if source not in ("startup", "compact", "resume", "clear", "fork"):
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

    drift = refresh_or_notice(root)
    if source == "startup":
        # A plain start gets the version line and nothing else: the control line is for context breaks (T15).
        if drift:
            json.dump({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": drift.strip()}},
                      sys.stdout)
        return 0

    env_path = os.path.join(root, "docs", "cascade", "envelope.md")   # laws
    shards = os.path.join(root, "docs", "cascade", "laws")            # law shards (t67)
    has_shards = os.path.isdir(shards) and any(f.endswith(".md") and f != "README.md" for f in os.listdir(shards))
    if not os.path.exists(env_path) and not has_shards:
        return 0

    hop = stage = slice_ = ""
    dsharp: list[str] = []
    any_proven = False
    with open(hopstate(root), encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.rstrip("\n")
            if s.startswith("CURRENT_HOP:"):
                hop = s.split(":", 1)[1].strip()
            elif s.startswith("CURRENT_STAGE:"):
                stage = s.split(":", 1)[1].strip()
            elif s.startswith("CURRENT_SLICE:"):
                slice_ = s.split(":", 1)[1].strip()
    # PRESERVE (t67): envelope laws in full, as before; a shard the current spec names in full; every other shard
    # as one summary line — at thousands of laws, re-injecting all of them would undo what the split saves.
    _laws = [sys.executable, "-B", os.path.join(root, "tests", "lib", "laws.py"), env_path, "--shards", shards]
    _decl = subprocess.run(_laws + ["--declared"], capture_output=True, text=True)
    if _decl.returncode != 0:
        dsharp.append("  LAWS UNREADABLE: " + ((_decl.stderr.strip().splitlines() or ["tests/lib/laws.py failed"])[0]))
    src = {}
    for r in subprocess.run(_laws + ["--sources"], capture_output=True, text=True).stdout.splitlines():
        if "|" in r:
            src[r.split("|", 1)[0]] = r.split("|", 1)[1]
    spec = os.path.join(root, "docs", "cascade", f"{stage}-{slice_}.md")
    named: set = set()
    if slice_ and os.path.isfile(spec):
        named = {os.path.join(shards, m) for m in
                 re.findall(r"docs/cascade/laws/([\w.-]+\.md)", open(spec, encoding="utf-8", errors="replace").read())}
    summarized: dict = {}
    for line in _decl.stdout.splitlines():
        p = line.split("|")
        if len(p) < 4:
            continue
        s_ = src.get(p[0], env_path)
        if s_ != env_path and s_ not in named:
            in_force = bool(p[2].strip() and p[3].strip())
            any_proven = any_proven or in_force
            summarized.setdefault(s_, []).append(p[0])
            continue
        in_force = bool(p[2].strip() and p[3].strip())
        any_proven = any_proven or in_force
        dsharp.append(f"  {p[0]}  {p[1]}  ->  " + (f"IN FORCE: {p[2]}" if in_force
                      else "NOT IN FORCE (needs a check and a break that fails; STOP and ask)"))

    for f, ids in sorted(summarized.items()):
        ids = sorted(ids, key=lambda x: int(x[1:]))
        span = ids[0] + (f"–{ids[-1]}" if len(ids) > 1 else "")
        dsharp.append(f"  {os.path.relpath(f, root)}: {len(ids)} law{'' if len(ids) == 1 else 's'}, {span} "
                      "(read it when the hop touches it)")
    ctx = [INVARIANTS, f"Current hop: {hop or 'UNSET'} stage {stage or 'UNSET'}"]
    if slice_:
        ctx.append(f"Current slice: {slice_}")
    ctx.append("Domain laws (D#):")
    ctx.extend(dsharp or ["  (none declared)"])
    ctx.append("\nConfirm Current hop is unchanged, then do only that hop.")

    # The plugin updates machine-wide; a repo's tests/ .githooks/ commands come from install.sh. A stale repo half
    # is how a fixed bug appears to still be broken: refresh_or_notice() closes it or says why it could not.
    if drift:
        ctx.append(drift)
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

    # The morning after an unattended run: what was denied, signed, or went red is in the log, not in git.
    recent = decisions_tail(root, 12)
    if recent:
        ctx.append("\nLast decisions this repo recorded (`.cascade/decisions.log`, newest last):\n  "
                   + "\n  ".join(recent))

    if not any_proven and _decl.returncode == 0:   # a FATAL read is not "no law in force" (t67)
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
