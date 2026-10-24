#!/usr/bin/env python3
"""What a goal carries over from earlier slices' goals, and the cap on it (t77).

usage: goal_history.py ROOT GOAL CURRENT_SLICE ENVELOPE [--versions]   (stdin: one in-force law check per line)

A goal is one hop's definition of done. This reads docs/cascade/goal.md's history in ONE `git log -p` process and
compares it with the current goal file:

  * a current validator is CARRIED when an earlier version whose GOAL_SLICE names another slice held it;
  * it is STANDING when it ends with the shell comment `# standing` (it runs unchanged) — unless an earlier slice's
    goal held it unmarked in a version that marked other lines standing: a marker added to get under the cap;
  * an in-force law's check is neither: I13 requires it in every goal.

Lines are compared after collapsing whitespace and dropping the marker; a reworded or folded line is not matched (an
under-count, never a guess). Prints, tab-separated:

  U                                    history cannot be read (no git, a shallow clone): no notice, no cap
  N  <carried> <total> <standing> <slices>   otherwise; <slices> are the oldest origins first, at most 3, then "…"
  C  <cap>                             the cap: a signed, committed GOAL_CARRY_MAX, else 10

Never prints a verdict: tests/loop.sh decides what the numbers mean.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from signed import BLOCK   # noqa: E402  (sibling: tests/lib ships as one directory)

DEFAULT_CAP = 10
MAX_VERSIONS = 200
MARK = re.compile(r"\s+#\s*standing\s*$")
CAP = re.compile(r"^\s*(?:-\s*)?GOAL_CARRY_MAX:\s*(\d+)\s*$")
SEP = "\x00t77-commit\x00"


def norm(line: str) -> str:
    return " ".join(line.split())


def parse(text: str) -> tuple[str, list[str]]:
    """(the last column-0 GOAL_SLICE, the column-0 VALIDATOR lines) — the rule tests/loop.sh reads by."""
    slice_, vals = "", []
    for raw in text.replace("\r", "").split("\n"):
        if raw.startswith("GOAL_SLICE:"):
            slice_ = raw[len("GOAL_SLICE:"):].strip()
        elif raw.startswith("VALIDATOR:"):
            v = raw[len("VALIDATOR:"):].strip()
            if v:
                vals.append(v)
    if (slice_.startswith("<") and slice_.endswith(">")) or "{{" in slice_:
        slice_ = ""
    return slice_, vals


def entry(v: str) -> tuple[str, bool]:
    """(the comparison key, marked standing)."""
    marked = bool(MARK.search(v))
    return norm(MARK.sub("", v)) if marked else norm(v), marked


def versions(root: str, rel: str) -> list[tuple[str, list[str]]] | None:
    """Every committed version of the goal, newest first, as (slice, validators); None = history unreadable."""
    shallow = subprocess.run(["git", "rev-parse", "--is-shallow-repository"], cwd=root, capture_output=True, text=True)
    if shallow.returncode != 0 or shallow.stdout.strip() != "false":
        return None
    log = subprocess.run(["git", "log", f"-{MAX_VERSIONS}", "-p", "--no-color", "--no-ext-diff", "--no-renames",
                          "-U999999", "--format=%x00t77-commit%x00%H", "--", rel],
                         cwd=root, capture_output=True, text=True, errors="replace")
    if log.returncode != 0:
        return None
    out = []
    for chunk in log.stdout.split(SEP)[1:]:
        body, hunk, deleted = [], False, False
        for line in chunk.split("\n"):
            if line.startswith("@@"):
                hunk = True
            elif line.startswith("+++ /dev/null"):
                deleted = True
            elif hunk and line[:1] in (" ", "+"):
                body.append(line[1:])
        if not hunk:
            continue   # a merge (no patch) or a mode change: no version of its own
        out.append(parse("" if deleted else "\n".join(body)))
    return out


def cap(root: str, envelope: str) -> int:
    """The last GOAL_CARRY_MAX inside <EDIT>, when HEAD's envelope and the working copy both say the same."""
    def decided(text: str):
        last = None
        for block in BLOCK.findall(text):
            for line in block.splitlines():
                m = CAP.match(line)
                if m and "{{" not in line:
                    last = int(m.group(1))
        return last
    try:
        work = open(envelope, encoding="utf-8", errors="replace").read()
    except OSError:
        return DEFAULT_CAP
    rel = os.path.relpath(os.path.realpath(envelope), os.path.realpath(root))
    if rel.startswith(".."):
        rel = "docs/cascade/envelope.md"   # an autopilot pre-edge copy: the committed one is still this repo's
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=root, capture_output=True, text=True)
    a, b = decided(work), decided(head.stdout if head.returncode == 0 else "")
    return a if a is not None and a == b else DEFAULT_CAP


def late_marker(key: str, older: list[tuple[str, list[str]]]) -> bool:
    """An earlier slice's goal held the line unmarked while marking others: the marker came after the fact."""
    for _slice, vals in older:
        entries = [entry(v) for v in vals]
        if any(m for _k, m in entries) and any(k == key and not m for k, m in entries):
            return True
    return False


def main() -> int:
    if len(sys.argv) < 5:
        return 64
    root, goal, current, envelope = sys.argv[1:5]
    rel = os.path.relpath(os.path.realpath(goal), os.path.realpath(root))
    hist = versions(root, rel)
    if len(sys.argv) > 5 and sys.argv[5] == "--versions":
        print(len(hist) if hist is not None else "unreadable")
        return 0
    if hist is None:
        print("U")
        return 0
    try:
        _, vals = parse(open(goal, encoding="utf-8", errors="replace").read())
    except OSError:
        vals = []
    laws = {norm(line) for line in sys.stdin.read().splitlines() if line.strip()}
    older = [(s, v) for s, v in hist if s and s != current]   # earlier slices' goals, newest first
    carried, standing, origins = 0, 0, []
    for v in vals:
        key, marked = entry(v)
        if key in laws:
            continue
        holders = [s for s, vs in older if key in {entry(x)[0] for x in vs}]
        if marked:
            if late_marker(key, older):
                carried += 1
                origins.append(holders[-1])
                continue
            standing += 1
            continue
        if holders:
            carried += 1
            origins.append(holders[-1])   # the oldest version in log order
    names = []
    for s, _v in reversed(older):
        if s in origins and s not in names:
            names.append(s)
    shown = ", ".join(names[:3]) + (", …" if len(names) > 3 else "")
    print(f"N\t{carried}\t{len(vals)}\t{standing}\t{shown}")
    print(f"C\t{cap(root, envelope)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
