#!/usr/bin/env bash
# Repeated mistakes across sessions (t104), and lessons that answer them (t106). One session sees only its own part of
# .cascade/decisions.log; this report counts each kind of problem over every session, with evidence a script can
# check, and measures each human-signed lesson. It reads; it never edits, never signs, and no gate reads it. A human
# decides what, if anything, a pattern should change (USAGE.md §B23, §B24).
#
# usage: tests/patterns.sh [--root DIR] [--since YYYY-MM-DD] [--min N] [--propose]      (default N = 3)
#
#   events   decisions.log lines with src=agent or src=human whose verdict is not PASS, CONTINUE, SIGNED or SIGN?;
#            and commits whose subject starts `send back` or `cascade: send back` (actor git, verdict SENDBACK).
#            src=test lines and lines with no src= field (written before 3.5.5) never count.
#   groups   actor, verdict and the reason: quoted spans become `…`, numbers N (a law id like D3 stays), cut at 120.
#   hops     a hop starts at a hop-state.md commit that opens GENERATE or EXECUTE on a new (hop, stage, slice), by
#            author time; NONE ends it; `-` is no hop (before the first, or while none runs).
#   lessons  docs/cascade/lessons.md, one human-signed line each (pre-commit and hop_guard guard them):
#              LESSON L1: <actor> <verdict> "<reason prefix>" | scope: <hop class|ANY> | since: <day> | do: <sentence>
#            each is measured per hop of its scope before and after its day: NO MATCH, SETTLED, NOT WORKING,
#            WORKING or NEW. --propose drafts a lesson line for each printed group no lesson covers (stdout only).
#
#   PATTERN  stop_guard NOEDGE  seen 4 times in 3 hops
#     reason: GENERATE Nb ended without its edge line
#     evidence: .cascade/decisions.log:37 hop 1a2b3c4 2026-01-03T06:00:00Z  stop_guard  NOEDGE  GENERATE 05b …
#   LESSON L1  stop_guard NOEDGE  before: 6 in 3 hops (2.00/hop)  after: 1 in 6 hops (0.17/hop)  SETTLED
#   LESSONS: 1 signed, 0 malformed
#   PATTERNS: k group(s) at --min n from e event(s); t test line(s) and u line(s) with no src= not counted
# Exit 0; 64 on a bad argument.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SINCE=""
MIN=3
PROPOSE=0
usage() { echo "usage: tests/patterns.sh [--root DIR] [--since YYYY-MM-DD] [--min N] [--propose]" >&2; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)    [[ $# -ge 2 && -d "$2" ]] || usage; ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --since)   [[ $# -ge 2 ]] || usage; SINCE="$2"; shift 2 ;;
    --min)     [[ $# -ge 2 ]] || usage; MIN="$2"; shift 2 ;;
    --propose) PROPOSE=1; shift ;;
    *) usage ;;
  esac
done
if ! [[ "$MIN" =~ ^[0-9]+$ ]] || (( 10#$MIN < 1 )); then usage; fi
MIN=$((10#$MIN))
if [[ -n "$SINCE" ]]; then
  [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
  python3 -B -c 'import datetime, sys; datetime.date.fromisoformat(sys.argv[1])' "$SINCE" 2>/dev/null || usage
fi
python3 -B - "$ROOT" "$SINCE" "$MIN" "$PROPOSE" <<'PY'
import calendar, datetime, os, re, subprocess, sys, time

root, since, least, propose = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1"
FIELD = re.compile(r"  src=([a-z]+)$")          # t103's trailing field (tests/lib/decisions.py FIELD)
NOT_EVENTS = {"PASS", "CONTINUE", "SIGNED", "SIGN?"}
SEND_BACK = re.compile(r"^(cascade: )?send back\b", re.I)
HOP_STATE = "docs/cascade/hop-state.md"
# the hop classes of .claude/hooks/seam.py hop_class (its DESIGN / AUDIT / PRR stage sets)
DESIGN, AUDIT, PRR = {"01", "02", "03", "04"}, {"10"}, {"11"}
SCOPES = ("ANY", "GENERATE", "EXECUTE-BUILD", "EXECUTE-DESIGN", "EXECUTE-AUDIT", "EXECUTE-PRR")


def git(*args: str) -> list[str]:
    try:
        r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return []
    return r.stdout.splitlines() if r.returncode == 0 else []


def day(epoch: int) -> str:
    return time.strftime("%Y-%m-%d", time.gmtime(epoch))


def reason(detail: str) -> str:
    r = re.sub(r"`[^`]*`", "`…`", detail)
    r = re.sub(r"\bD[0-9]+\b|[0-9]+", lambda m: m.group(0) if m.group(0)[0] == "D" else "N", r)
    return re.sub(r" +", " ", r).strip()[:120]


def hop_class(hop: str, stage: str) -> str:
    if hop == "GENERATE":
        return "GENERATE"
    st = stage.split()[0] if stage else ""
    return ("EXECUTE-DESIGN" if st in DESIGN else "EXECUTE-AUDIT" if st in AUDIT
            else "EXECUTE-PRR" if st in PRR else "EXECUTE-BUILD")


# ---- hops: real edges. One `git log -p` in history order carries the triple forward; author time places it. ----
state = {"CURRENT_HOP": "", "CURRENT_STAGE": "", "CURRENT_SLICE": ""}
versions = []   # (author time, short hash, (hop, stage, slice)) per hop-state commit, in history order
head = None
for line in git("log", "--reverse", "--format=\x01%H %at", "-p", "--unified=0", "--", HOP_STATE):
    if line.startswith("\x01"):
        if head:
            versions.append((head[1], head[0], (state["CURRENT_HOP"].upper(), state["CURRENT_STAGE"], state["CURRENT_SLICE"])))
        h, _, at = line[1:].partition(" ")
        head = (h[:7], int(at) if at.isdigit() else 0)
        continue
    m = re.match(r"^\+(CURRENT_HOP|CURRENT_STAGE|CURRENT_SLICE):[ \t]*(.*?)\s*$", line)
    if m:
        state[m.group(1)] = m.group(2)
if head:
    versions.append((head[1], head[0], (state["CURRENT_HOP"].upper(), state["CURRENT_STAGE"], state["CURRENT_SLICE"])))
marks = []      # (author time, short hash or None for an end, class)
prev, running = None, False
for at, h, trip in versions:
    if trip[0] in ("GENERATE", "EXECUTE"):
        if trip != prev:
            marks.append((at, h, hop_class(trip[0], trip[1])))
            running = True
    elif running:
        marks.append((at, None, None))
        running = False
    prev = trip
marks.sort(key=lambda m: m[0])
hops = [(at, h, c) for at, h, c in marks if h]


def hop_of(epoch: int) -> str:
    found = "-"
    for at, h, _ in marks:
        if at > epoch:
            break
        found = h or "-"
    return found


# ---- events ----
Item = tuple[int, str, str, str]   # (time, where, hop, text)
groups: dict[tuple[str, str, str], list[Item]] = {}   # what the report prints (--since applied)
every: dict[tuple[str, str, str], list[Item]] = {}    # what lessons measure (no --since)
events = tests = unknown = 0


def add(key: tuple[str, str, str], item: Item) -> None:
    global events
    every.setdefault(key, []).append(item)
    if since and day(item[0]) < since:
        return
    events += 1
    groups.setdefault(key, []).append(item)


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
    add((bits[1], bits[2], reason(bits[3] if len(bits) > 3 else "")),
        (epoch, f".cascade/decisions.log:{n}", hop_of(epoch), shown))

for row in git("log", "--format=%H %at %s"):
    parts = row.split(" ", 2)
    if len(parts) < 3 or not parts[1].isdigit() or not SEND_BACK.search(parts[2]):
        continue
    epoch, subject = int(parts[1]), parts[2]
    add(("git", "SENDBACK", reason(subject)), (epoch, f"commit {parts[0][:7]}", hop_of(epoch), subject))

# ---- lessons ----
LINE = re.compile(r'^LESSON L([0-9]+): (\S+) (\S+) "([^"]{1,120})" \| scope: (\S+) \| since: ([0-9]{4}-[0-9]{2}-[0-9]{2})'
                  r' \| do: (.+)$')
lessons, malformed, lesson_lines, top = [], [], 0, 0
lp = os.path.join(root, "docs", "cascade", "lessons.md")
if os.path.isfile(lp):
    seen: set[str] = set()
    with open(lp, encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f.read().splitlines(), 1):
            if not raw.startswith("LESSON "):
                continue
            lesson_lines += 1
            mid = re.match(r"^LESSON L([0-9]+):", raw)
            if mid:
                top = max(top, int(mid.group(1)))
            m = LINE.match(raw)
            why = ""
            if not m:
                why = 'not the form LESSON L<n>: <actor> <verdict> "<prefix>" | scope: <s> | since: <day> | do: <sentence>'
            else:
                lid, actor, verdict, prefix, scope, on, do = m.groups()
                try:
                    datetime.date.fromisoformat(on)
                except ValueError:
                    why = f"since: {on} is not a calendar day"
                if not why and scope not in SCOPES:
                    why = f"scope: {scope} is not one of {', '.join(SCOPES)}"
                if not why and do.startswith("TODO"):
                    why = "do: is still TODO"
                if not why and len(do) > 160:
                    why = f"do: is {len(do)} characters, more than 160"
                if not why and lid in seen:
                    why = f"L{lid} is already used above"
            if why:
                malformed.append(f"LESSON ?  malformed: docs/cascade/lessons.md:{n} — {why}")
                continue
            seen.add(lid)
            lessons.append((int(lid), actor, verdict, prefix, scope, on))


def covers(lesson, key) -> bool:
    return lesson[1] == key[0] and lesson[2] == key[1] and key[2].replace('"', "'").startswith(lesson[3])


# ---- output ----
printed, shown_keys = 0, []
for key, evs in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    if len(evs) < least:
        continue
    printed += 1
    shown_keys.append(key)
    evs.sort(key=lambda e: e[0])
    n, m = len(evs), len({e[2] for e in evs})
    print(f"PATTERN  {key[0]} {key[1]}  seen {n} time{'' if n == 1 else 's'} in {m} hop{'' if m == 1 else 's'}")
    print(f"  reason: {key[2]}")
    for _, where, hop, text in reversed(evs[-3:]):
        print(f"  evidence: {where} hop {hop} {text}")

if propose:
    k = 0
    today = time.strftime("%Y-%m-%d", time.gmtime())
    for key in shown_keys:
        if any(covers(l, key) for l in lessons):
            continue
        top += 1
        k += 1
        prefix = key[2].replace('"', "'")[:60].rstrip()
        print(f'PROPOSE  LESSON L{top}: {key[0]} {key[1]} "{prefix}" | scope: ANY | since: {today}'
              " | do: TODO — one imperative sentence")
    print(f"PROPOSALS: {k}")


def hops_word(x: int) -> str:
    return "hop" if x == 1 else "hops"


def rate(e: int, h: int) -> str:
    return f"({e / h:.2f}/hop)" if h else "(-)"


if lesson_lines:
    for line in malformed:
        print(line)
    for lid, actor, verdict, prefix, scope, on in sorted(lessons):
        lesson = (lid, actor, verdict, prefix, scope, on)
        start = calendar.timegm(time.strptime(on, "%Y-%m-%d"))
        mine = [(at, h) for at, h, c in hops if scope == "ANY" or c == scope]
        before = [h for at, h in mine if at < start]
        after = [h for at, h in mine if at >= start]
        evs = [e for key, es in every.items() if covers(lesson, key) for e in es if e[2] in before or e[2] in after]
        b = sum(1 for e in evs if e[2] in before)
        a = len(evs) - b
        hb, ha = len(before), len(after)
        if b == 0 and a == 0:
            mark = "NO MATCH"
        elif ha >= 5 and not any(e[2] in after[-5:] for e in evs):
            mark = "SETTLED"
        elif hb and ha >= 3 and a / ha >= b / hb:
            mark = "NOT WORKING"
        elif hb and ha >= 3:
            mark = "WORKING"
        else:
            mark = "NEW"
        print(f"LESSON L{lid}  {actor} {verdict}  before: {b} in {hb} {hops_word(hb)} {rate(b, hb)}"
              f"  after: {a} in {ha} {hops_word(ha)} {rate(a, ha)}  {mark}")
    print(f"LESSONS: {len(lessons)} signed, {len(malformed)} malformed")

print(f"PATTERNS: {printed} group(s) at --min {least} from {events} event(s); "
      f"{tests} test line(s) and {unknown} line(s) with no src= not counted")
PY
