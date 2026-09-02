#!/usr/bin/env python3
"""PreToolUse(Bash) — deny the shell escapes around the ship gate (I15).

Patterns are anchored to command position and heredoc bodies are stripped, so
prose that *mentions* a forbidden command (docs, commit messages, echo) does not
trip the guard. Only running it does.
"""
from __future__ import annotations

import json
import re
import sys

HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")
SPLIT = re.compile(r"[;&|\n]+")

RULES = (
    (re.compile(r"^git\s+push\b(?!.*--dry-run).*\b(main|master)\b"),
     "direct push to main. Ship path is CLEAN 10 + 11 READY -> /barbar merge -> PR -> required checks."),
    (re.compile(r"^git\s+push\b.*\s(-f|--force|--force-with-lease)\b"),
     "force push. Rewriting shared history destroys the evidence trail (I2)."),
    (re.compile(r"^gh\s+pr\s+merge\b"),
     "auto-merge. Merge needs CLEAN stage 10 + READY stage 11 + green D# and a human (I15)."),
    (re.compile(r"^git\s+(commit|push|merge)\b.*--no-verify\b"),
     "--no-verify bypasses the cascade pre-commit/pre-push hooks. That is the bar, not a nuisance."),
    (re.compile(r"^git\s+config\b.*(--unset\b.*core\.hooksPath|core\.hooksPath\s+(?!\.githooks(\s|$))\S)"),
     "re-pointing core.hooksPath disables the cascade git hooks (I18). Reading it, or setting .githooks, is fine."),
)
HUMAN_KEY = re.compile(r"(^|[\s;&|(]|\benv\s+|\bexport\s+)CASCADE_HUMAN=")
ON_MAIN = re.compile(r"^git\s+(checkout|switch)\s+(main|master)\b")
MERGE = re.compile(r"^git\s+merge\b")


def strip_heredocs(cmd: str) -> str:
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = HEREDOC.search(line)
        if m:
            term = m.group(1)
            i += 1
            while i < len(lines) and lines[i].strip() != term:
                i += 1
        i += 1
    return "\n".join(out)


def simple_commands(cmd: str) -> list[str]:
    parts = []
    for raw in SPLIT.split(strip_heredocs(cmd)):
        s = raw.strip().lstrip("({ ").strip()
        s = re.sub(r"^(sudo|time|env|nohup|exec)\s+", "", s)
        s = re.sub(r"^(\w+=\S*\s+)+", "", s)
        if s:
            parts.append(s)
    return parts


def offending(cmd: str) -> str | None:
    on_main = False
    # Setting the human key (outside quoted text) is denied; merely mentioning it is not.
    # Checked on the raw segments: simple_commands() strips leading VAR=value assignments.
    for raw in SPLIT.split(strip_heredocs(cmd)):
        if HUMAN_KEY.search(re.sub(r'"[^"]*"|\'[^\']*\'', "", raw)):
            return "CASCADE_HUMAN is the human's stitch key. The agent never sets it (I15)."
    for s in simple_commands(cmd):
        for pat, why in RULES:
            if pat.search(s):
                return why
        if ON_MAIN.search(s):
            on_main = True
        elif on_main and MERGE.search(s):
            return "merging into main from the shell (I15)."
    return None


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if ev.get("tool_name") != "Bash":
        return 0
    why = offending((ev.get("tool_input") or {}).get("command", ""))
    if why:
        json.dump(
            {"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"BLOCKED by cascade ship guard: {why}",
            }},
            sys.stdout,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
