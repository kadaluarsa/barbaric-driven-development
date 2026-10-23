#!/usr/bin/env bash
# Laws worth a human's second look (t68). Reports; never edits, never retires — retiring is a human-signed D# change
# (USAGE.md §B14).
#
# usage: tests/laws_report.sh [--root DIR] [--years N]     (default N = 3)
#
#   MISSING-PATH  D7       its path: file no longer exists
#   DUPLICATE     D7 D9    identical check: and break: — the same law twice
#   UNEXPLAINED   D7       no reason: line
#   STALE         D7       no commit touched its path: file in N years (a law with no path: is not judged)
#   FAMILY        D7 D8    a shared check: with distinct breaks — information, not a candidate (it runs once)
# Ends `LAWS REPORT: k candidate(s) — …`. Exit 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
YEARS=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --years) YEARS="$2"; shift 2 ;;
    *) echo "usage: tests/laws_report.sh [--root DIR] [--years N]" >&2; exit 64 ;;
  esac
done
[[ "$YEARS" =~ ^[0-9]+$ ]] || { echo "laws_report.sh: --years needs a whole number" >&2; exit 64; }
python3 -B - "$ROOT" "$YEARS" "$HERE/lib" <<'PY'
import os, subprocess, sys, time
root, years, lib = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sys.path.insert(0, lib)
from laws import LawsError, load
try:
    laws = load(os.path.join(root, "docs/cascade/envelope.md"), os.path.join(root, "docs/cascade/laws"))
except LawsError as exc:
    print(f"LAWS REPORT: the laws cannot be read ({exc}) — fix that first"); sys.exit(0)
blank = lambda c: not c or c.strip().lower() in ("todo", "none", "-")
out, info = [], []
for d in laws:
    p = (d.get("path") or "").split(":", 1)[0].strip()
    if p and not os.path.exists(os.path.join(root, p)):
        out.append(f"MISSING-PATH  {d['id']}  path: {p} does not exist")
    if not (d.get("reason") or "").strip():
        out.append(f"UNEXPLAINED   {d['id']}  no reason: line")
    if p and os.path.exists(os.path.join(root, p)):
        r = subprocess.run(["git", "log", "-1", "--format=%ct", "--", p], cwd=root, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            last = int(r.stdout.strip())
            if time.time() - last > years * 365.25 * 86400:
                out.append(f"STALE         {d['id']}  no commit touched {p} since "
                           f"{time.strftime('%Y-%m-%d', time.gmtime(last))} ({years}+ years)")
by_pair, by_check = {}, {}
for d in laws:
    if blank(d.get("check")):
        continue
    by_pair.setdefault((d["check"].strip(), (d.get("break") or "").strip()), []).append(d["id"])
    by_check.setdefault(d["check"].strip(), []).append(d)
for ids in by_pair.values():
    if len(ids) > 1:
        out.append(f"DUPLICATE     {' '.join(ids)}  identical check: and break:")
for members in by_check.values():
    if len({(m.get("break") or "").strip() for m in members}) > 1:
        info.append(f"FAMILY        {' '.join(m['id'] for m in members)}  share one check: (fine — it runs once)")
print("\n".join(out + info) if out or info else "(no candidates)")
print(f"LAWS REPORT: {len(out)} candidate(s) — nothing retired; retiring is a human-signed D# change (USAGE.md)")
PY
exit 0
