#!/usr/bin/env python3
"""The progress watchdog (t84): is this hop's loop moving, and did it stay inside its plan?

Read from the tree and the loop's own output — never a model's opinion. The watchdog can only end an autopilot run
early for a human and add a notice; it never changes a loop verdict, a receipt or an edge check.

    watchdog.py <root> --record <stage> <slice> <k> <n> <fingerprint>   FAIL lines on stdin; append one history line
    watchdog.py <root> --check                                          OK | OFF | STALLED <reason>
    watchdog.py <root> --drift <spec doc>                               changed paths the plan's In scope list omits

History: .cascade/loop-history, local and agent-writable. Deleting it can only avoid a stop, never cause an accept.
Every mode exits 0: a watchdog that cannot decide says OK, and the cap and the wall clock still bound the run.
"""
from __future__ import annotations

import fnmatch
import hashlib
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from laws import hopstate_field   # noqa: E402  (sibling: tests/lib ships as one directory)

HISTORY = os.path.join(".cascade", "loop-history")
MAX_LINES = 2000
FIELDS = 8
DEFAULT_PASSES = 3
EXEMPT = ("docs/cascade/goal.md", "docs/cascade/regress.md")
EXEMPT_PREFIX = (".cascade/",)
TICK = re.compile(r"`([^`]+)`")
PATHLIKE = re.compile(r"^[^\s-][^\s]*$")
NAME_EXT = re.compile(r"^(?:[\w.-]*\w\.\w+|\.\w[\w.-]*)$")   # name.ext, or a dotfile such as .gitignore


def clean(v: str) -> str:
    """No tab, CR or LF inside a field: a validator command may hold any of them (C10)."""
    return re.sub(r"[\t\r\n]", " ", v)


def hop_base(root: str) -> str:
    """The commit that opened this hop, or '' — t66's own rule, so both agree on what 'this hop' means."""
    try:
        from affected import hop_base as _hb   # noqa: PLC0415
        sha, _why = _hb(root)
        return sha or ""
    except Exception:   # noqa: BLE001 — no base is a known answer: the watchdog then stops no one (C5)
        return ""


def passes() -> int:
    v = os.environ.get("BDD_WATCHDOG_PASSES", "")
    if not v.isdigit():
        return DEFAULT_PASSES
    return 0 if int(v) == 0 else max(2, int(v))


def record(root: str, stage: str, slice_: str, k: str, n: str, fp: str, fail_lines: list[str]) -> None:
    fails = sorted(clean(l).strip() for l in fail_lines if l.strip())
    digest = hashlib.sha1("\n".join(fails).encode()).hexdigest()[:12] if fails else "-"
    first = (fails[0] if fails else "-")[:120]
    row = [str(int(time.time())), hop_base(root) or "-", stage, slice_, f"{k}/{n}", fp or "-", digest, first]
    path = os.path.join(root, HISTORY)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        lines = []
    lines.append("\t".join(clean(x) or "-" for x in row))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines[-MAX_LINES:]) + "\n")


def history(root: str) -> list[list[str]]:
    try:
        raw = open(os.path.join(root, HISTORY), encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return []
    return [p for p in (l.split("\t") for l in raw) if len(p) == FIELDS]


def kn(cell: str) -> tuple[int, int]:
    try:
        a, b = cell.split("/", 1)
        return int(a), int(b)
    except ValueError:
        return 0, 0


def check(root: str) -> str:
    want = passes()
    if want == 0:
        return "OFF"
    base = hop_base(root)
    if not base:
        return "OK"
    slice_ = hopstate_field(root, "CURRENT_SLICE")
    mine = [p for p in history(root) if p[1] == base and p[3] == slice_]
    if len(mine) < want:
        return "OK"
    last = mine[-want:]
    scores = [kn(p[4]) for p in last]
    if any(k >= n for k, n in scores):
        return "OK"
    k_new, n_new = scores[-1]
    first = last[-1][7]
    tail = f"LOOP {k_new}/{n_new}" + (f", {first}" if first != "-" else "")
    if scores[-1][0] <= scores[0][0] and len({p[6] for p in last}) == 1:
        return f"STALLED no progress over {want} passes of {slice_}: {tail}"
    fps = {p[5] for p in last}
    if len(fps) == 1 and "-" not in fps:
        return f"STALLED no edit between the last {want} passes of {slice_}: {tail}"
    return "OK"


def in_scope(spec: str) -> list[str] | None:
    """Path-shaped backticked tokens under `## In scope this execute` (C8), or None when there is no such list."""
    try:
        text = open(spec, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    m = re.search(r"^## In scope this execute[ \t]*$(.*?)(?=^#{1,2} |\Z)", text, re.M | re.S)
    if not m:
        return None
    out = []
    for tok in TICK.findall(m.group(1)):
        tok = tok.strip()
        if PATHLIKE.match(tok) and ("/" in tok or NAME_EXT.match(tok)):
            out.append(tok)
    return out


def covered(path: str, entries: list[str]) -> bool:
    for e in entries:
        if e.endswith("/") and path.startswith(e):
            return True
        if "*" in e and fnmatch.fnmatch(path, e):
            return True
        if path == e:
            return True
    return False


def drift(root: str, spec: str) -> list[str]:
    entries = in_scope(spec if os.path.isabs(spec) else os.path.join(root, spec))
    if entries is None:
        return []
    base = hop_base(root)
    if not base:
        return []
    try:
        from affected import changed   # noqa: PLC0415
        rows, _why = changed(root, base)
    except Exception:   # noqa: BLE001
        return []
    seen, out = set(), []
    for path, _status in rows or []:
        if path in seen or path in EXEMPT or path.startswith(EXEMPT_PREFIX) or covered(path, entries):
            continue
        seen.add(path)
        out.append(path)
    return out


def main() -> int:
    a = sys.argv[1:]
    if len(a) >= 2 and a[1] == "--check":
        print(check(a[0]))
    elif len(a) == 7 and a[1] == "--record":
        try:
            record(a[0], *a[2:7], sys.stdin.read().splitlines())
        except OSError:
            pass   # best-effort: a failed write never changes the verdict
    elif len(a) == 3 and a[1] == "--drift":
        for p in drift(a[0], a[2]):
            print(p)
    else:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 64
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
