#!/usr/bin/env python3
"""One home for the helpers every cascade hook needs.

Why here and not tests/lib: both wirings execute these exact files — standalone runs
`$CLAUDE_PROJECT_DIR/.claude/hooks/X.py`, the plugin runs `$BDD_PLUGIN_ROOT/.claude/hooks/X.py` — so a
sibling module is importable with no path work in either mode. `tests/lib` is not viable: seam.py and
preserve.py also run in repos that never installed BDD, where `<root>/tests/lib` does not exist. That is
why every import from tests/lib in this directory is wrapped in try/except with a fallback.

Why at all: five copies of "where does hop state live", four of the logger, three of the dedupe. That is
the defect consolidated in 1.2.2 — six law parsers drifting until a placeholder counted as a law —
reintroduced by hand hours later. seam.py carried the proof: `if "seam.py" == "preserve.py"`, a
constant-false comparison left by copy-paste.

One deliberate duplicate remains: `hopstate()` here and `hopstate_path()` in tests/lib/laws.py. They sit on
either side of the availability boundary above and cannot import each other. Change one, change both.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time

SEEN_TTL = 3600


# --- git ----------------------------------------------------------------------------------------------

def repo_root(cwd: str) -> str | None:
    try:
        return subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd,
                              capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return None


def git_dir(root: str) -> str | None:
    """The real git dir. `--git-dir` prints a path relative to the repo root, not to our cwd, and in a
    worktree it resolves to a directory elsewhere — assuming `<root>/.git` once aborted commits (T45)."""
    try:
        d = subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root,
                           capture_output=True, text=True, check=True).stdout.strip()
        return os.path.realpath(d if os.path.isabs(d) else os.path.join(root, d))
    except Exception:
        return None


# --- judge each event once ----------------------------------------------------------------------------
# Project-level and plugin-level hooks may both be wired; the same call must not be judged twice.

def _seen(root: str, marker: str) -> bool:
    try:
        gd = git_dir(root)
        if not gd:
            return False
        d = os.path.join(gd, "cascade-seen")
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, marker)
        if os.path.exists(path):
            return True
        open(path, "w").close()
        cutoff = time.time() - SEEN_TTL
        for f in os.listdir(d):
            fp = os.path.join(d, f)
            if os.path.getmtime(fp) < cutoff:
                os.unlink(fp)
        return False
    except Exception:
        return False


def already_handled(ev: dict, root: str, name: str) -> bool:
    """Same tool call, seen before. `name` keeps the marker per-hook — two hooks must both get a turn."""
    tid = ev.get("tool_use_id")
    if not tid or not root:
        return False
    return _seen(root, f"{name}-{str(tid)[:120]}")


def already_event(ev: dict, root: str, name: str, field: str = "prompt_id") -> bool:
    """Same prompt or session event, seen before."""
    key = ev.get(field)
    if not key or not root:
        return False
    composite = f'{key}-{ev.get("hook_event_name", "")}-{ev.get("source", "")}'
    return _seen(root, f"{name}-{composite[:120]}")


# --- the run log --------------------------------------------------------------------------------------
# Lives in tests/lib (Layer 1, always in the product), so these are the try/except'd calls.

def log(root: str, actor: str, verdict: str, detail: str) -> None:
    try:
        sys.path.insert(0, os.path.join(root, "tests", "lib"))
        from decisions import record   # noqa: PLC0415
        record(root, actor, verdict, detail)
    except Exception:
        pass


def decisions_tail(root: str, n: int = 12) -> list[str]:
    try:
        sys.path.insert(0, os.path.join(root, "tests", "lib"))
        from decisions import tail   # noqa: PLC0415
        return [ln for ln in tail(root, n).splitlines() if ln.strip()]
    except Exception:
        return []


# --- hop state ----------------------------------------------------------------------------------------

def hopstate(root: str) -> str:
    """CURRENT_HOP/STAGE/SLICE and AUTOPILOT. Repos from before the 1.6.0 split keep them in the envelope.
    Twin of tests/lib/laws.py:hopstate_path — see the module docstring."""
    h = os.path.join(root, "docs", "cascade", "hop-state.md")
    return h if os.path.exists(h) else os.path.join(root, "docs", "cascade", "envelope.md")


def hopstate_field(root: str, key: str) -> str:
    try:
        with open(hopstate(root), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith(key + ":"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return ""


# --- failing safely -----------------------------------------------------------------------------------

def ask(name: str, reason: str) -> None:
    """A PreToolUse verdict of last resort: never allow, make a human decide."""
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
                                      "permissionDecisionReason": f"cascade guard {name} {reason}"}}, sys.stdout)


def guarded(main, name: str) -> int:
    """A guard that crashes must not fail open. Surface it as 'ask' so a human sees it (I18)."""
    try:
        if os.environ.get("CASCADE_HOOK_SELFTEST_RAISE"):
            raise RuntimeError("selftest")
        return main()
    except Exception as exc:
        ask(name, f"failed ({exc!r}); refusing to fail open — a human must decide.")
        return 0
