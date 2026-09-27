#!/usr/bin/env python3
"""Shared helpers for the spec-edge gates (t57 critique.py, t58 diverge.py).

Both gates ask the same two questions of a cascade document: what does section X say, and what did the
file say in the commit that first added it. One implementation, so the two gates cannot drift apart.
"""
from __future__ import annotations

import re
import subprocess


def section(text: str, heading: str) -> str | None:
    """Body of `## heading` up to the next `## `, or None when the heading is absent."""
    m = re.search(rf"^##\s+{re.escape(heading)}\s*$(.*?)(?=^##\s|\Z)", text, re.M | re.S)
    return m.group(1) if m else None


def git(root: str, *args: str) -> tuple[int, str]:
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return r.returncode, r.stdout


def at_head(root: str, rel: str) -> str | None:
    """The file as committed at HEAD, or None when git does not track it there."""
    rc, out = git(root, "show", f"HEAD:{rel}")
    return out if rc == 0 else None


def adding_commit(root: str, rel: str) -> tuple[str, str | None]:
    """(sha, text) of the commit that first added `rel` in reachable history; ('', None) if none."""
    rc, sha = git(root, "log", "--diff-filter=A", "--format=%H", "-1", "--", rel)
    sha = sha.strip()
    if rc != 0 or not sha:
        return "", None
    _, text = git(root, "show", f"{sha}:{rel}")
    return sha, text
