#!/usr/bin/env bash
# Repeated mistakes across sessions (t104). One session sees only its own part of .cascade/decisions.log; this report
# counts each kind of problem over every session, with evidence a script can check. It reads; it never edits, never
# signs, and no gate reads it. A human decides what, if anything, a pattern should change (USAGE.md §B23).
#
# usage: tests/patterns.sh [--root DIR] [--since YYYY-MM-DD] [--min N]      (default N = 3)
#
#   events   decisions.log lines with src=agent or src=human whose verdict is not PASS, CONTINUE, SIGNED or SIGN?;
#            and commits whose subject starts `send back` or `cascade: send back` (actor git, verdict SENDBACK).
#            src=test lines and lines with no src= field (written before 3.5.5) never count.
#   groups   actor, verdict and the reason: quoted spans become `…`, numbers N (a law id like D3 stays), cut at 120.
#   hops     a hop starts at each commit that changed docs/cascade/hop-state.md, by author time; `-` is before the first.
#
#   PATTERN  stop_guard NOEDGE  seen 4 times in 3 hops
#     reason: GENERATE Nb ended without its edge line
#     evidence: .cascade/decisions.log:37 hop 1a2b3c4 2026-01-03T06:00:00Z  stop_guard  NOEDGE  GENERATE 05b …
#   PATTERNS: k group(s) at --min n from e event(s); t test line(s) and u line(s) with no src= not counted
# Exit 0; 64 on a bad argument.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SINCE=""
MIN=3
usage() { echo "usage: tests/patterns.sh [--root DIR] [--since YYYY-MM-DD] [--min N]" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)  [[ $# -ge 2 && -d "$2" ]] || usage; ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --since) [[ $# -ge 2 ]] || usage; SINCE="$2"; shift 2 ;;
    --min)   [[ $# -ge 2 ]] || usage; MIN="$2"; shift 2 ;;
    *) usage ;;
  esac
done
if ! [[ "$MIN" =~ ^[0-9]+$ ]] || (( 10#$MIN < 1 )); then usage; fi
MIN=$((10#$MIN))
if [[ -n "$SINCE" ]]; then
  [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
  python3 -B -c 'import datetime, sys; datetime.date.fromisoformat(sys.argv[1])' "$SINCE" 2>/dev/null || usage
fi
python3 -B - "$ROOT" "$SINCE" "$MIN" <<'PY'
import calendar, os, re, subprocess, sys, time

root, since, least = sys.argv[1], sys.argv[2], int(sys.argv[3])
FIELD = re.compile(r"  src=([a-z]+)$")          # t103's trailing field (tests/lib/decisions.py FIELD)
NOT_EVENTS = {"PASS", "CONTINUE", "SIGNED", "SIGN?"}
SEND_BACK = re.compile(r"^(cascade: )?send back\b", re.I)


def git(*args: str) -> list[str]:
    try:
        r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return []
    return r.stdout.splitlines() if r.returncode == 0 else []


def day(epoch: int) -> str:
    return time.strftime("%Y-%m-%d", time.gmtime(epoch))


def reason(detail: str) -> str:
    r = re.sub(r"`[^`]*`", "`…`", detail)
    r = re.sub(r"\bD[0-9]+\b|[0-9]+", lambda m: m.group(0) if m.group(0)[0] == "D" else "N", r)
    return re.sub(r" +", " ", r).strip()[:120]


# hops: (author time, short hash), oldest first
hops = []
for row in git("log", "--format=%H %at", "--", "docs/cascade/hop-state.md"):
    h, _, at = row.partition(" ")
    if at.isdigit():
        hops.append((int(at), h[:7]))
hops.sort()


def hop_of(epoch: int) -> str:
    found = "-"
    for at, h in hops:
        if at > epoch:
            break
        found = h
    return found


groups: dict[tuple[str, str, str], list[tuple[int, str, str, str]]] = {}
events = tests = unknown = 0

log = os.path.join(root, ".cascade", "decisions.log")
lines = []
if os.path.isfile(log):
    with open(log, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
for n, raw in enumerate(lines, 1):
    m = FIELD.search(raw)
    src = m.group(1) if m else None
    if src is None:
        unknown += 1
        continue
    if src == "test":
        tests += 1
        continue
    if src not in ("agent", "human"):
        continue
    shown = FIELD.sub("", raw)
    bits = shown.split(None, 3)
    if len(bits) < 3 or bits[2] in NOT_EVENTS:
        continue
    try:
        epoch = calendar.timegm(time.strptime(bits[0], "%Y-%m-%dT%H:%M:%SZ"))
    except ValueError:
        continue
    if since and day(epoch) < since:
        continue
    events += 1
    key = (bits[1], bits[2], reason(bits[3] if len(bits) > 3 else ""))
    groups.setdefault(key, []).append((epoch, f".cascade/decisions.log:{n}", hop_of(epoch), shown))

for row in git("log", "--format=%H %at %s"):
    parts = row.split(" ", 2)
    if len(parts) < 3 or not parts[1].isdigit() or not SEND_BACK.search(parts[2]):
        continue
    epoch, subject = int(parts[1]), parts[2]
    if since and day(epoch) < since:
        continue
    events += 1
    groups.setdefault(("git", "SENDBACK", reason(subject)), []).append(
        (epoch, f"commit {parts[0][:7]}", hop_of(epoch), subject))

printed = 0
for (actor, verdict, why), evs in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    if len(evs) < least:
        continue
    printed += 1
    evs.sort(key=lambda e: e[0])
    n, m = len(evs), len({e[2] for e in evs})
    print(f"PATTERN  {actor} {verdict}  seen {n} time{'' if n == 1 else 's'} in {m} hop{'' if m == 1 else 's'}")
    print(f"  reason: {why}")
    for _, where, hop, text in reversed(evs[-3:]):
        print(f"  evidence: {where} hop {hop} {text}")
print(f"PATTERNS: {printed} group(s) at --min {least} from {events} event(s); "
      f"{tests} test line(s) and {unknown} line(s) with no src= not counted")
PY
