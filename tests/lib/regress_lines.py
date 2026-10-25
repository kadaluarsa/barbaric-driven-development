#!/usr/bin/env python3
"""The regression suite's lines (t78): docs/cascade/regress.md, column-0 `REGRESS: <command>` lines.

usage:
  regress_lines.py dropped BEFORE AFTER     lines of BEFORE missing from AFTER (multiset, whitespace collapsed);
                                            prints each, exit 1 if any — the pre-commit guard
  regress_lines.py suite ROOT work|gate     the lines to run, one `L\\t<line>` each, or `REFUSE\\t<reason>`

`gate` is what the merge gate and CI run: HEAD's lines, plus every line the merge base had that HEAD dropped (a removal
made with --no-verify gains nothing), minus lines the human retired with `- REGRESS_RETIRED: <line> — <reason>` inside
an envelope EDIT block at HEAD. A working copy that differs from HEAD, a shallow clone, or a suite with no base to
compare against is a refusal, never "clean". A tree that is not its own git repository has no history: its working
copy is the suite, as tests/retirements.sh treats it.
"""
import os
import re
import subprocess
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from signed import BLOCK   # noqa: E402  (sibling: tests/lib ships as one directory)

REL = "docs/cascade/regress.md"
RETIRED = re.compile(r"^\s*-\s*REGRESS_RETIRED:\s*(.+?)\s+—\s+\S")


def norm(line: str) -> str:
    return " ".join(line.split())


def parse(text: str) -> list[str]:
    out = []
    for raw in text.replace("\r", "").split("\n"):
        if raw.startswith("REGRESS:"):
            v = raw[len("REGRESS:"):].strip()
            if v:
                out.append(v)
    return out


def dropped(before: str, after: str) -> list[str]:
    """Lines of `before` that `after` no longer holds, counting duplicates."""
    b, a = parse(before), parse(after)
    missing = list((Counter(map(norm, b)) - Counter(map(norm, a))).elements())
    out, left = [], Counter(missing)
    for line in b:
        if left[norm(line)] > 0:
            out.append(line)
            left[norm(line)] -= 1
    return out or missing


def git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, errors="replace")


def show(root: str, rev: str, rel: str) -> str | None:
    r = git(root, "show", f"{rev}:{rel}")
    return r.stdout if r.returncode == 0 else None


def base_of(root: str) -> str:
    """The merge base with the default branch — the same search as tests/retirements.sh."""
    head = git(root, "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD").stdout.strip()
    for b in (head, "main", "master", "trunk", "origin/main", "origin/master"):
        if not b:
            continue
        r = git(root, "merge-base", "HEAD", b)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    return ""


def removed_since_base(root: str, base: str, head_lines: list[str]) -> list[str]:
    return dropped("\n".join("REGRESS: " + l for l in parse(show(root, base, REL) or "")),
                   "\n".join("REGRESS: " + l for l in head_lines))


def retired(root: str) -> set[str]:
    text = show(root, "HEAD", "docs/cascade/envelope.md") or ""
    out = set()
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            m = RETIRED.match(line)
            if m and "{{" not in line:
                out.add(norm(m.group(1)))
    return out


def own_repo(root: str) -> bool:
    top = git(root, "rev-parse", "--show-toplevel").stdout.strip()
    return bool(top) and os.path.realpath(top) == os.path.realpath(root)


def suite(root: str, mode: str) -> tuple[list[str], str]:
    """(lines to run, refusal reason or "")."""
    path = os.path.join(root, REL)
    try:
        work = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        work = None
    if mode != "gate" or not own_repo(root):
        return parse(work or ""), ""
    if git(root, "rev-parse", "--is-shallow-repository").stdout.strip() == "true":
        return [], "a shallow clone cannot show which regression lines were removed — fetch full history (fetch-depth: 0)"
    head = show(root, "HEAD", REL)
    if (work or "") != (head or ""):
        return [], f"{REL} differs from HEAD — commit it first (the gate runs the committed suite)"
    head_lines = parse(head or "")
    base = base_of(root)
    if not base:
        if head is None:
            return [], ""   # no suite and no base: nothing was ever carried here
        return [], "no base to compare against (no main/master/trunk or origin/HEAD)"
    lines = list(head_lines)
    lines += [l for l in removed_since_base(root, base, head_lines)]
    gone = retired(root)
    return [l for l in lines if norm(l) not in gone], ""


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "dropped":
        def read(p):
            try:
                return open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                return ""
        missing = dropped(read(sys.argv[2]), read(sys.argv[3]))
        for m in missing:
            print(m)
        return 1 if missing else 0
    if len(sys.argv) == 4 and sys.argv[1] == "suite":
        lines, why = suite(sys.argv[2], sys.argv[3])
        if why:
            print(f"REFUSE\t{why}")
            return 0
        for l in lines:
            print(f"L\t{l}")
        return 0
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
