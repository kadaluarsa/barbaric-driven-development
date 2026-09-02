#!/usr/bin/env python3
"""PreToolUse(Write|Edit) — deny product writes on a GENERATE hop, and any edit
that would change human-authored <EDIT> tag contents.

Enforces I4 and I15 at the tool call, before the write happens.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

EDIT_BLOCK = re.compile(r"<EDIT>(.*?)</EDIT>", re.S)
DEFAULT_WRITABLE = ("docs/", "evals/", "tests/", ".githooks/", ".claude/", ".github/", ".cursor/", ".windsurf/", ".continue/")


def deny(reason: str) -> None:
    json.dump(
        {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }},
        sys.stdout,
    )
    sys.exit(0)


def repo_root(cwd: str) -> str | None:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=cwd,
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return None


def envelope_field(root: str, key: str) -> str:
    path = os.path.join(root, "docs", "cascade", "envelope.md")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith(key + ":"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return ""


def writable_globs(root: str) -> tuple[str, ...]:
    override = os.path.join(root, "docs", "cascade", "generate-writable.txt")
    try:
        with open(override, encoding="utf-8") as fh:
            pats = [ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")]
        if pats:
            return tuple(pats)
    except OSError:
        pass
    return DEFAULT_WRITABLE


PROTECTED = re.compile(r"^(CURRENT_(HOP|STAGE|SLICE):|D[0-9]+\s*\|)", re.M)


def protected_lines(text: str) -> list[str]:
    return sorted(ln.rstrip() for ln in text.splitlines() if PROTECTED.match(ln))


def projected(tool: str, ti: dict, current: str) -> str | None:
    """Text the file would have after this tool call, or None if unknowable."""
    if tool == "Write":
        return ti.get("content", "")
    edits = ti.get("edits") or [ti]
    text = current
    for e in edits:
        old, new = e.get("old_string"), e.get("new_string", "")
        if old is None:
            return None
        if e.get("replace_all"):
            text = text.replace(old, new)
        elif old in text:
            text = text.replace(old, new, 1)
    return text


def is_product(rel: str, root: str) -> bool:
    if rel.endswith(".md") and "/" not in rel:
        return False
    for pat in writable_globs(root):
        if pat.endswith("/") and rel.startswith(pat):
            return False
        if pat == rel or (pat.startswith("*") and rel.endswith(pat[1:])):
            return False
    return True


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if ev.get("tool_name") not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return 0

    ti = ev.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    root = repo_root(ev.get("cwd") or os.getcwd())
    if not path or not root:
        return 0

    rel = os.path.relpath(os.path.realpath(path), os.path.realpath(root))
    if rel.startswith(".."):
        return 0

    hop = envelope_field(root, "CURRENT_HOP").upper()
    stage = envelope_field(root, "CURRENT_STAGE")

    if hop == "GENERATE" and is_product(rel, root):
        deny(
            f"BLOCKED by cascade hop guard (I4/I15): GENERATE stage {stage} may not write "
            f"product code. '{rel}' is product path.\n"
            "GENERATE produces spec + plan only, then stops at STITCH NEEDED. "
            "Ask the human for 'approved, execute stage {}' first.".format(stage or "N")
        )

    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            current = fh.read()
    except OSError:
        current = ""

    # Hop state and D# laws are human-owned, tags or not. Compute the post-edit text and compare.
    if rel == "docs/cascade/envelope.md" and current:
        after = projected(ev["tool_name"], ti, current)
        if after is not None and protected_lines(current) != protected_lines(after):
            deny("BLOCKED by cascade hop guard (I15): CURRENT_HOP/STAGE/SLICE and D# lines in "
                 "docs/cascade/envelope.md are human-owned. The agent may not flip the hop, start "
                 "the next stage, or change a law's validator. Ask the human to stitch "
                 "(they commit with CASCADE_HUMAN=1).")
    if not current or "<EDIT>" not in current:
        return 0

    spans = [m.span(1) for m in EDIT_BLOCK.finditer(current)]
    msg = (f"BLOCKED by cascade hop guard (I15): '{rel}' has human-authored <EDIT> tags. "
           "The agent must not fill, guess, or delete them. If a required <EDIT> is empty, STOP and ask.")

    if ev["tool_name"] == "Write":
        before = EDIT_BLOCK.findall(current)
        after = EDIT_BLOCK.findall(ti.get("content", ""))
        if any(b not in after for b in before):
            deny(msg)
        return 0

    edits = ti.get("edits") or [ti]
    for e in edits:
        old = e.get("old_string") or ""
        if not old:
            continue
        if "<EDIT>" in old or "</EDIT>" in old:
            deny(msg)
        idx = current.find(old)
        if idx < 0:
            continue
        lo, hi = idx, idx + len(old)
        if any(lo < s_hi and s_lo < hi for s_lo, s_hi in spans):
            deny(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
