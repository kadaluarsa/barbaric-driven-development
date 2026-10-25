#!/usr/bin/env python3
"""Move a goal's lines to the regression suite (t78). Called by tests/goal.sh; never removes a regression line.

usage: carry_out.py ROOT carry|reset CURRENT_SLICE   (stdin: one in-force law check per line)

carry  the current goal's carried lines (t77's rule, a late '# standing' included) leave goal.md; they and the
       previous slice's dropped lines are appended to docs/cascade/regress.md under `### <origin slice>`.
reset  the goal is about to be replaced. If it is this slice's own (a send-back re-run), as `carry`; otherwise
       every validator in it that is not standing and not a law check, under `### <its GOAL_SLICE>` (or
       `### unattributed`), plus the previous slice's dropped lines. Needs no history for the goal's own lines.

Prints `goal: carried <n> validators to docs/cascade/regress.md (<slices>), <k> already there` and, last, a line
`CARRIED <n>` for the caller. A line already in the suite (whitespace collapsed) is not added again.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import goal_history as gh   # noqa: E402  (sibling: tests/lib ships as one directory)

GOAL = "docs/cascade/goal.md"
SUITE = "docs/cascade/regress.md"
TEMPLATE = "docs/cascade/regress.template.md"


def read(path: str) -> str | None:
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None


def append(text: str, groups: list[tuple[str, list[str]]]) -> str:
    """Add each group's lines under its `### heading`, creating the heading at the end when absent."""
    lines = text.rstrip("\n").split("\n") if text.strip() else []
    for head, add in groups:
        if not add:
            continue
        hdr = f"### {head}"
        if hdr in lines:
            i = lines.index(hdr) + 1
            while i < len(lines) and not lines[i].startswith("### ") and not lines[i].startswith("## "):
                i += 1
            while i > 0 and lines[i - 1].strip() == "":
                i -= 1
            lines[i:i] = [f"REGRESS: {l}" for l in add]
        else:
            if lines and lines[-1].strip():
                lines.append("")
            lines += [hdr] + [f"REGRESS: {l}" for l in add]
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 4 or sys.argv[2] not in ("carry", "reset"):
        print(__doc__, file=sys.stderr)
        return 64
    root, mode, current = sys.argv[1:4]
    laws = {gh.norm(l) for l in sys.stdin.read().splitlines() if l.strip()}
    goal_path, suite_path = os.path.join(root, GOAL), os.path.join(root, SUITE)
    goal_text = read(goal_path) or ""
    gslice, gvals = gh.parse(goal_text)
    a = gh.analyze(root, goal_path, current, laws)
    own = bool(current) and gslice == current
    if mode == "reset" and not own:
        take = [(gslice or "unattributed", v) for v in gvals
                if not gh.entry(v)[1] and gh.entry(v)[0] not in laws]
    else:
        take = list(a["carried"]) if a else []
    take += [(a["prev"], v) for v in a["dropped"]] if a else []
    if a is None and mode == "carry":
        print("goal: history unreadable — carried nothing (carry-out needs the goal's git history)")
        print("CARRIED 0")
        return 0

    suite = read(suite_path)
    if suite is None:
        suite = read(os.path.join(root, TEMPLATE)) or "# Regression suite\n"
    have = {gh.norm(l) for l in gh_regress(suite)}
    groups: dict[str, list[str]] = {}
    order, n, already = [], 0, 0
    for origin, v in take:
        k = gh.norm(v)
        if k in have:
            already += 1
            continue
        have.add(k)
        if origin not in groups:
            groups[origin] = []
            order.append(origin)
        groups[origin].append(v)
        n += 1
    if n:
        os.makedirs(os.path.dirname(suite_path), exist_ok=True)
        with open(suite_path, "w", encoding="utf-8") as fh:
            fh.write(append(suite, [(o, groups[o]) for o in order]))

    if mode == "carry" and a and a["carried"]:
        gone = {v for _o, v in a["carried"]}
        kept = []
        for raw in goal_text.split("\n"):
            r = raw.rstrip("\r")
            if r.startswith("VALIDATOR:") and r[len("VALIDATOR:"):].strip() in gone:
                continue
            kept.append(raw)
        with open(goal_path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(kept))

    shown = ", ".join(order[:3]) + (", …" if len(order) > 3 else "")
    print(f"goal: carried {n} validators to {SUITE}{f' ({shown})' if shown else ''}, {already} already there")
    print(f"CARRIED {n}")
    return 0


def gh_regress(text: str) -> list[str]:
    out = []
    for raw in text.replace("\r", "").split("\n"):
        if raw.startswith("REGRESS:") and raw[len("REGRESS:"):].strip():
            out.append(raw[len("REGRESS:"):].strip())
    return out


if __name__ == "__main__":
    raise SystemExit(main())
