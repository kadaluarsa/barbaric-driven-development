#!/usr/bin/env python3
"""The delivery scorecard (t91): one card per slice, computed from the tree — the same bytes whoever runs it.

    scorecard.py <root> [slug] [--full]

Fields: oracle (t89), loop (the fingerprinted receipt, t84 history), review (critique, t90 switch review), drift (t84),
diff, builders (t90), regression (--full only). Each `pass`, `fail …`, `unknown …` or a notice. Verdict: a required
field that fails → SCORECARD fail (exit 1); else one that is unknown → SCORECARD incomplete (exit 2); else pass (0).
A field the tree cannot prove is never `pass`. No timestamps, hosts or ages: identical output for anyone.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from laws import hopstate_field   # noqa: E402  (sibling: tests/lib ships as one directory)

LIB = os.path.dirname(os.path.abspath(__file__))
ROW = re.compile(r"^\|\s*C\d+\s*\|")
DISPO = re.compile(r"^(fixed|rejected|human)\s+\S")


def run(root: str, *cmd: str, timeout: int = 600) -> subprocess.CompletedProcess:
    return subprocess.run(list(cmd), cwd=root, capture_output=True, text=True, timeout=timeout)


def hop(root: str) -> tuple[str, str, str]:
    return (hopstate_field(root, "CURRENT_HOP").upper(), hopstate_field(root, "CURRENT_STAGE") or "05b",
            hopstate_field(root, "CURRENT_SLICE"))


def first_fail(out: str) -> str:
    return next((l.strip() for l in out.splitlines() if l.startswith("FAIL")), out.strip().splitlines()[-1] if out.strip() else "")


def oracle_field(root: str) -> str:
    if run(root, sys.executable, "-B", os.path.join(LIB, "oracle.py"), root, "--due").returncode != 0:
        return "unknown (no oracle)"
    if not os.path.isfile(os.path.join(root, "tests", "oracle.sh")):
        return "fail tests/oracle.sh is missing while the oracle is due (C10)"
    h = hop(root)[0]
    if h == "EXECUTE":
        r = run(root, sys.executable, "-B", os.path.join(LIB, "oracle.py"), root, "--loop")
    elif h == "GENERATE":
        r = run(root, sys.executable, "-B", os.path.join(LIB, "oracle.py"), root)
    else:
        return "unknown (no hop running)"
    return "pass" if r.returncode == 0 else f"fail {first_fail(r.stdout)}"


def fingerprint(root: str) -> str:
    r = run(root, "bash", "-c", '. "$1/tests/lib/cascade.sh" && cascade_worktree_sha "$1"', "_", root)
    return r.stdout.strip()


def loop_field(root: str, slug: str) -> str:
    h, stage, _ = hop(root)
    last = None
    try:
        from affected import hop_base   # noqa: PLC0415
        from watchdog import history    # noqa: PLC0415
        base, _ = hop_base(root)
        mine = [p for p in history(root) if base and p[1] == base and p[3] == slug]
        last = mine[-1][4] if mine else None
    except Exception:  # noqa: BLE001
        pass
    try:
        receipt = open(os.path.join(root, ".cascade", "loop-receipt"), encoding="utf-8").read().split()
    except OSError:
        receipt = []
    if len(receipt) >= 3 and receipt[0].upper() == h and receipt[1] == stage:
        if receipt[2] == fingerprint(root):
            return f"pass (LOOP {last or 'n/n'})"
        return "fail (tree changed since the last n/n pass)"
    if last:
        k, n = last.split("/", 1)
        return f"pass (LOOP {last})" if k == n else f"fail (LOOP {last})"
    return "unknown (no pass recorded)"


def section(text: str, head: str) -> str:
    m = re.search(r"^## " + re.escape(head) + r"[ \t]*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


def review_field(root: str, stage: str, slug: str) -> str:
    crit = None
    try:
        crit = open(os.path.join(root, "docs", "cascade", f"{stage}-{slug}-critique.md"), encoding="utf-8").read()
    except OSError:
        pass
    if crit is not None:
        rows = [l.split("|")[1].strip() for h in ("Brief", "Spec") for l in section(crit, h).splitlines() if ROW.match(l)]
        answers = {}
        for l in section(crit, "Dispositions").splitlines():
            if ROW.match(l):
                c = [x.strip() for x in l.strip().strip("|").split("|")]
                if len(c) >= 2:
                    answers[c[0]] = c[1]
        open_rows = [r for r in rows if not DISPO.match(answers.get(r, ""))]
        if open_rows:
            return f"fail unanswered critique: {', '.join(open_rows)}"
    sw = os.path.join(root, "tests", "switch.sh")
    if os.path.isfile(sw):
        r = run(root, "bash", sw)
        if r.returncode != 0:
            return f"fail switch: {first_fail(r.stdout)}"
    return "pass" if crit is not None else "unknown (no critique)"


def drift_field(root: str, stage: str, slug: str) -> str:
    try:
        from watchdog import drift   # noqa: PLC0415
        paths = drift(root, f"docs/cascade/{stage}-{slug}.md")
    except Exception:  # noqa: BLE001
        return "unknown (drift unavailable)"
    return "pass" if not paths else f"notice {len(paths)} path(s): {', '.join(paths[:5])}"


def diff_field(root: str) -> str:
    try:
        from affected import hop_base   # noqa: PLC0415
        base, _ = hop_base(root)
    except Exception:  # noqa: BLE001
        base = None
    if not base:
        return "unknown (no hop base)"
    st = run(root, "git", "diff", "--shortstat", base).stdout
    files = re.search(r"(\d+) files? changed", st)
    plus = re.search(r"(\d+) insertions?", st)
    minus = re.search(r"(\d+) deletions?", st)
    n = lambda m: m.group(1) if m else "0"   # noqa: E731
    return f"{n(files)} files, +{n(plus)}/-{n(minus)} since {base[:7]}"


def builders_field(root: str) -> str:
    try:
        from builders import builders   # noqa: PLC0415
        bs = builders(root)
    except Exception:  # noqa: BLE001
        bs = []
    return " → ".join(bs) if bs else "unknown (none recorded)"


def regression_field(root: str, full: bool) -> str:
    if not full:
        return "not run (--full)"
    rg = os.path.join(root, "tests", "regress.sh")
    if not os.path.isfile(rg):
        return "unknown (no tests/regress.sh)"
    r = run(root, "bash", rg, timeout=3600)
    return "pass" if r.returncode == 0 else f"fail ({first_fail(r.stdout)})"


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 64
    root, rest = args[0], args[1:]
    full = "--full" in rest
    rest = [a for a in rest if a != "--full"]
    _, stage, cur = hop(root)
    slug = rest[0] if rest else cur
    fields = [("oracle", oracle_field(root), True), ("loop", loop_field(root, slug), True),
              ("review", review_field(root, stage, slug), True), ("drift", drift_field(root, stage, slug), False),
              ("diff", diff_field(root), False), ("builders", builders_field(root), False),
              ("regression", regression_field(root, full), full)]
    for name, value, _ in fields:
        print(f"{name:<11} {value}")
    req = [v for _, v, required in fields if required]
    if any(v.startswith("fail") for v in req):
        print("SCORECARD fail"); return 1
    if any(not v.startswith("pass") for v in req):
        print("SCORECARD incomplete"); return 2
    print("SCORECARD pass"); return 0


if __name__ == "__main__":
    raise SystemExit(main())
