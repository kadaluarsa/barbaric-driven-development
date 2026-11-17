#!/usr/bin/env python3
"""The briefs archive (t102). Closed briefs move, verbatim, from docs/cascade/05b-briefs.md to
docs/cascade/05b-briefs-archive.md; readers look in the live file first, then in the archive.

A brief is the line `- <slug>:` at column 0 plus the following lines that start with a space or a tab (a blank or a
column-0 line ends it — recall.py's rule). It is closed when docs/cascade/05b-<slug>.md exists, <slug> is not
CURRENT_SLICE and not an AUTOPILOT entry — or, with no spec, when a continuation line reads `  Absorbed by <other>`
and <other> has a spec.

usage: briefs.py <root> archive | find <slug>
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

LIVE = os.path.join("docs", "cascade", "05b-briefs.md")
ARCHIVE = os.path.join("docs", "cascade", "05b-briefs-archive.md")
HEADER = "# Archived briefs (t102) — closed slices, verbatim\n"
HEAD = re.compile(r"^- ([A-Za-z0-9][A-Za-z0-9._-]*):")
ABSORBED = re.compile(r"^[ \t]+Absorbed by ([A-Za-z0-9][A-Za-z0-9._-]*)")


class Refused(Exception):
    pass


def _read(root: str, rel: str) -> str | None:
    try:
        with open(os.path.join(root, rel), encoding="utf-8", newline="") as fh:
            return fh.read()
    except OSError:
        return None


def blocks(text: str) -> list[tuple[str, int, int]]:
    """[(slug, first, end)] — 0-based line indexes, end exclusive — over text.splitlines(keepends=True)."""
    lines = text.splitlines(keepends=True)
    out, i = [], 0
    while i < len(lines):
        m = HEAD.match(lines[i])
        if not m:
            i += 1
            continue
        j = i + 1
        while j < len(lines) and lines[j].strip() and lines[j][0] in " \t":
            j += 1
        out.append((m.group(1), i, j))
        i = j
    return out


def find(root: str, slug: str) -> tuple[str, int, str] | None:
    """(path, 1-based line, brief text) — the live file first, then the archive; None when neither has it."""
    for rel in (LIVE, ARCHIVE):
        text = _read(root, rel)
        if text is None:
            continue
        lines = text.splitlines(keepends=True)
        for s, a, b in blocks(text):
            if s == slug:
                return rel, a + 1, "".join(lines[a:b])
    return None


def _hop(root: str) -> tuple[str, set[str]]:
    path = os.path.join(root, "docs", "cascade", "hop-state.md")
    if not os.path.exists(path):
        path = os.path.join(root, "docs", "cascade", "envelope.md")
    current, listed = "", set()
    text = _read(root, os.path.relpath(path, root)) or ""
    for line in text.splitlines():
        if line.startswith("CURRENT_SLICE:"):
            current = line.split(":", 1)[1].strip()
        elif line.startswith("AUTOPILOT:"):
            for entry in line.split(":", 1)[1].split(","):
                if entry.strip():
                    listed.add(entry.split()[-1])
    return current, listed


def _spec(root: str, slug: str) -> bool:
    return os.path.isfile(os.path.join(root, "docs", "cascade", f"05b-{slug}.md"))


def closed(root: str, slug: str, body: str, current: str, listed: set[str]) -> bool:
    if slug == current or slug in listed:
        return False
    if _spec(root, slug):
        return True
    for line in body.splitlines()[1:]:
        m = ABSORBED.match(line)
        if m and m.group(1) != slug and _spec(root, m.group(1)):
            return True
    return False


def _dirty(root: str) -> str:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        r = subprocess.run(["git", "status", "--porcelain", "--", LIVE, ARCHIVE], cwd=root, capture_output=True,
                           text=True, timeout=20, env=env)
    except (OSError, subprocess.SubprocessError) as exc:
        return f"git status failed ({exc.__class__.__name__})"
    if r.returncode != 0:
        return "not a git work tree"
    return r.stdout.strip()


def archive(root: str) -> list[str]:
    """Move every closed brief. Returns the moved slugs; raises Refused and changes nothing on a refusal."""
    live = _read(root, LIVE)
    if live is None:
        return []
    dirty = _dirty(root)
    if dirty:
        raise Refused(f"uncommitted changes to the briefs files — commit them first ({dirty.splitlines()[0]})")
    arch = _read(root, ARCHIVE)
    archived = {s for s, _, _ in blocks(arch)} if arch is not None else set()
    both = sorted({s for s, _, _ in blocks(live)} & archived)
    if both:
        raise Refused(f"slug in both files: {', '.join(both)} — a human keeps one")
    current, listed = _hop(root)
    lines = live.splitlines(keepends=True)
    moved, take = [], set()
    for s, a, b in blocks(live):
        if closed(root, s, "".join(lines[a:b]), current, listed):
            moved.append(s)
            take.update(range(a, b))
    if not moved:
        return []
    out = "".join(lines[i] for i in sorted(take))
    if not out.endswith("\n"):
        out += "\n"
    keep = "".join(l for i, l in enumerate(lines) if i not in take)
    base = arch if arch is not None else HEADER
    if base and not base.endswith("\n"):
        base += "\n"
    with open(os.path.join(root, ARCHIVE), "w", encoding="utf-8", newline="") as fh:
        fh.write(base + out)
    with open(os.path.join(root, LIVE), "w", encoding="utf-8", newline="") as fh:
        fh.write(keep)
    return moved


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: briefs.sh archive | find <slug>", file=sys.stderr)
        return 64
    root, cmd = argv[0], argv[1]
    if cmd == "archive" and len(argv) == 2:
        try:
            moved = archive(root)
        except Refused as exc:
            print(f"briefs: refused — {exc}")
            return 1
        print(f"briefs: moved {len(moved)} ({', '.join(moved)})" if moved else "briefs: nothing to move")
        return 0
    if cmd == "find" and len(argv) == 3:
        hit = find(root, argv[2])
        if not hit:
            print(f"briefs: no brief for {argv[2]}")
            return 1
        print(f"{hit[0]}:{hit[1]}")
        return 0
    print("usage: briefs.sh archive | find <slug>", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
