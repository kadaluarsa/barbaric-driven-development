#!/usr/bin/env bash
# AC tests for 05b t110-lesson-escalation: tests/patterns.sh marks a signed lesson ESCALATE when its event keeps
# happening after its day, and --propose drafts a brief for a check that refuses the event. tests/lib/escalate.py
# holds the rule and the text. The script reads; it never edits, never signs, never builds.
#   AC1  a fixture of 22 hops and 10 lessons: ESCALATE for 2 after-window events (3 hops and more, whatever the mark,
#        SETTLED too), and for 1 event at a rate not below the before-rate from 10 after-window hops; never for 0
#        events, fewer than 3 hops, a lower rate, 9 hops, or no before hop. The LESSON lines do not change; ESCALATE lines come after them, in id
#        order, before LESSONS:; the last line is still PATTERNS:.
#   AC2  --propose prints one BRIEF line per ESCALATE lesson, a valid brief head after `BRIEF  `, then BRIEFS: k;
#        without --propose there is no BRIEF line; nothing in the fixture changes, 05b-briefs.md and lessons.md
#        included; with no lesson to escalate it prints BRIEFS: 0.
#   AC3  --recall is unchanged by ESCALATE (no ESCALATE text, the same line as before t110, at most 400 bytes) and
#        works with no tests/lib/escalate.py; a full run without the module fails.
#   AC4  escalate() at each boundary; tests/lib/escalate.py imports only __future__ and has no write, process or
#        network call.
#   AC5  USAGE.md B29 names ESCALATE and --propose; release 3.5.12 or later in VERSION, the three manifests, the README
#        release line and CHANGELOG.md, whose section names escalate and T69; T69's shipped-path allowlist names
#        escalate.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOG_SRC BDD_HOOK_HOST PLUGIN_ROOT CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
S="$ROOT/tests/patterns.sh"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TODAY="$(date -u +%Y-%m-%d)"

# ---------- fixture: 22 GENERATE hops, one a day from 2026-02-01; events at 10:00 belong to that day's hop ----------
R="$TMP/r"; mkdir -p "$R/docs/cascade" "$R/.cascade"
git -C "$R" init -q
for d in $(seq 1 22); do
  dd="$(printf '%02d' "$d")"
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s%s\n' "$d" > "$R/docs/cascade/hop-state.md"
  git -C "$R" add -A
  GIT_AUTHOR_DATE="2026-02-${dd}T00:00:00Z" GIT_COMMITTER_DATE="2026-02-${dd}T00:00:00Z" git -C "$R" commit -qm "hop $d"
done
python3 - "$R/.cascade/decisions.log" <<'PY'
import sys
E = {   # actor: the days of its events (one verdict V, one reason each)
    "a1": [1, 18, 19], "a2": [1, 2, 3], "a3": [1, 21, 22], "a4": [5, 20], "a5": [1, 2, 20], "a6": [1, 20],
    "a7": [20], "a8": [10, 11], "a9": [3, 21, 22], "a10": [1, 2],
}
rows = []
for a, days in E.items():
    for i, d in enumerate(days):
        rows.append((f"2026-02-{d:02d}T10:{i:02d}:{len(rows) % 60:02d}Z", a))
rows.sort()
with open(sys.argv[1], "w") as f:
    for ts, a in rows:
        f.write(f"{ts}  {a:<11} V       the event  src=agent\n")
PY
LES="$R/docs/cascade/lessons.md"
cat > "$LES" <<'EOF'
# Lessons

LESSON L1: a1 V "the event" | scope: ANY | since: 2026-02-10 | do: One.
LESSON L2: a2 V "the event" | scope: ANY | since: 2026-02-10 | do: Two.
LESSON L3: a3 V "the event" | scope: GENERATE | since: 2026-02-21 | do: Three.
LESSON L4: a4 V "the event" | scope: ANY | since: 2026-02-13 | do: Four "quoted".
LESSON L5: a5 V "the event" | scope: ANY | since: 2026-02-13 | do: Five.
LESSON L6: a6 V "the event" | scope: ANY | since: 2026-02-14 | do: Six.
LESSON L7: a7 V "the event" | scope: ANY | since: 2026-01-01 | do: Seven.
LESSON L8: a8 V "the event" | scope: ANY | since: 2026-02-10 | do: Eight.
LESSON L9: a9 V "the event" | scope: GENERATE | since: 2026-02-20 | do: Nine.
LESSON L10: a10 V "the event" | scope: ANY | since: 2026-02-20 | do: Ten.
EOF
printf '# Briefs\n\n- s1: [feature] a brief.\n' > "$R/docs/cascade/05b-briefs.md"
git -C "$R" add -A; git -C "$R" commit -qm "lessons and briefs"
run() { bash "$S" --root "$R" "$@" 2>&1; }
out="$(run)"; prop="$(run --propose)"

# ---------- AC1: the marks ----------
ok=1
want_l="LESSON L1  a1 V  before: 1 in 9 hops (0.11/hop)  after: 2 in 13 hops (0.15/hop)  NOT WORKING
LESSON L2  a2 V  before: 3 in 9 hops (0.33/hop)  after: 0 in 13 hops (0.00/hop)  SETTLED
LESSON L3  a3 V  before: 1 in 20 hops (0.05/hop)  after: 2 in 2 hops (1.00/hop)  NEW
LESSON L4  a4 V  before: 1 in 12 hops (0.08/hop)  after: 1 in 10 hops (0.10/hop)  NOT WORKING
LESSON L5  a5 V  before: 2 in 12 hops (0.17/hop)  after: 1 in 10 hops (0.10/hop)  WORKING
LESSON L6  a6 V  before: 1 in 13 hops (0.08/hop)  after: 1 in 9 hops (0.11/hop)  NOT WORKING
LESSON L7  a7 V  before: 0 in 0 hops (-)  after: 1 in 22 hops (0.05/hop)  NEW
LESSON L8  a8 V  before: 0 in 9 hops (0.00/hop)  after: 2 in 13 hops (0.15/hop)  SETTLED
LESSON L9  a9 V  before: 1 in 19 hops (0.05/hop)  after: 2 in 3 hops (0.67/hop)  NOT WORKING
LESSON L10  a10 V  before: 2 in 19 hops (0.11/hop)  after: 0 in 3 hops (0.00/hop)  WORKING"
[[ "$(printf '%s\n' "$out" | grep '^LESSON L' || true)" == "$want_l" ]] \
  || { ok=0; echo "      lesson lines:"; printf '%s\n' "$out" | grep '^LESSON L' | sed 's/^/        /'; }
want_e="ESCALATE L1  a1 V  after: 2 in 13 hops  a prompt line is not enough: tests/patterns.sh --propose drafts a check
ESCALATE L4  a4 V  after: 1 in 10 hops  a prompt line is not enough: tests/patterns.sh --propose drafts a check
ESCALATE L8  a8 V  after: 2 in 13 hops  a prompt line is not enough: tests/patterns.sh --propose drafts a check
ESCALATE L9  a9 V  after: 2 in 3 hops  a prompt line is not enough: tests/patterns.sh --propose drafts a check"
[[ "$(printf '%s\n' "$out" | grep '^ESCALATE' || true)" == "$want_e" ]] \
  || { ok=0; echo "      escalate lines:"; printf '%s\n' "$out" | grep '^ESCALATE' | sed 's/^/        /'; }
# the order: every LESSON line, then every ESCALATE line, then LESSONS:, and PATTERNS: last
shape="$(printf '%s\n' "$out" | grep -E '^(LESSON L|ESCALATE|LESSONS:|PATTERNS:)' | sed -E 's/^(LESSON L|ESCALATE|LESSONS:|PATTERNS:).*/\1/' | uniq | tr '\n' ',')"
[[ "$shape" == "LESSON L,ESCALATE,LESSONS:,PATTERNS:," ]] || { ok=0; echo "      the order of the lesson block: $shape"; }
printf '%s\n' "$out" | grep -qxF 'LESSONS: 10 signed, 0 malformed' || { ok=0; echo "      no 'LESSONS: 10 signed, 0 malformed'"; }
[[ "$(printf '%s\n' "$out" | tail -1)" == "PATTERNS: "* ]] || { ok=0; echo "      the last line is not PATTERNS:"; }
t AC1 "$ok" "ESCALATE for 2 after-window events in 3 or more hops (L1, L9, and L8 though SETTLED) and 1 event at a rate not below the before-rate from 10 hops (L4); not for 0 events (L2, L10), 2 hops (L3), a lower rate (L5), 9 hops (L6) or no before hop (L7); LESSON lines unchanged, ESCALATE after them"

# ---------- AC2: --propose drafts a brief, writes nothing ----------
ok=1
want_b="BRIEF  - lesson-l1-check: [feature] drafted $TODAY by tests/patterns.sh --propose from lesson L1. The event a1 V \"the event\" happened 2 times in 13 hops after 2026-02-10 (1 in 9 hops before), so the prompt line \"One.\" is not enough. Build a check (a hook rule or a test) that refuses this event. Done when a test shows the event is refused. Out of scope: changing or removing lesson L1.
BRIEF  - lesson-l4-check: [feature] drafted $TODAY by tests/patterns.sh --propose from lesson L4. The event a4 V \"the event\" happened 1 times in 10 hops after 2026-02-13 (1 in 12 hops before), so the prompt line \"Four \"quoted\".\" is not enough. Build a check (a hook rule or a test) that refuses this event. Done when a test shows the event is refused. Out of scope: changing or removing lesson L4.
BRIEF  - lesson-l8-check: [feature] drafted $TODAY by tests/patterns.sh --propose from lesson L8. The event a8 V \"the event\" happened 2 times in 13 hops after 2026-02-10 (0 in 9 hops before), so the prompt line \"Eight.\" is not enough. Build a check (a hook rule or a test) that refuses this event. Done when a test shows the event is refused. Out of scope: changing or removing lesson L8.
BRIEF  - lesson-l9-check: [feature] drafted $TODAY by tests/patterns.sh --propose from lesson L9. The event a9 V \"the event\" happened 2 times in 3 hops after 2026-02-20 (1 in 19 hops before), so the prompt line \"Nine.\" is not enough. Build a check (a hook rule or a test) that refuses this event. Done when a test shows the event is refused. Out of scope: changing or removing lesson L9."
[[ "$(printf '%s\n' "$prop" | grep '^BRIEF ' || true)" == "$want_b" ]] \
  || { ok=0; echo "      briefs:"; printf '%s\n' "$prop" | grep '^BRIEF' | cut -c1-160 | sed 's/^/        /'; }
printf '%s\n' "$prop" | grep -qxF 'BRIEFS: 4' || { ok=0; echo "      no 'BRIEFS: 4'"; }
printf '%s\n' "$prop" | grep -qE '^PROPOSALS: [0-9]+$' || { ok=0; echo "      the PROPOSALS: line is gone"; }
heads="$(printf '%s\n' "$prop" | grep '^BRIEF  ' | sed 's/^BRIEF  //' | grep -cE '^- [A-Za-z0-9][A-Za-z0-9._-]*: \[feature\] ' || true)"
[[ "$heads" -eq 4 ]] || { ok=0; echo "      $heads of 4 drafts are a brief head (tests/lib/briefs.py HEAD) after 'BRIEF  '"; }
printf '%s\n' "$out" | grep -qE '^BRIEF' && { ok=0; echo "      BRIEF lines printed without --propose"; }
snap() { ( cd "$R" && find . -type f ! -path ./.git/index -print0 | sort -z | xargs -0 cksum ) 2>/dev/null; }   # .git too
before="$(snap)"; run --propose >/dev/null; run >/dev/null; [[ "$(snap)" == "$before" ]] || { ok=0; echo "      the fixture changed after --propose"; }
[[ -z "$(git -C "$R" status --porcelain)" ]] || { ok=0; echo "      the fixture is not clean: $(git -C "$R" status --porcelain | head -3)"; }
cp "$LES" "$TMP/les.bak"
grep -v '^LESSON L\(1\|4\|8\|9\):' "$TMP/les.bak" > "$LES"
p0="$(run --propose)"
printf '%s\n' "$p0" | grep -qxF 'BRIEFS: 0' || { ok=0; echo "      no 'BRIEFS: 0' with no lesson to escalate"; }
printf '%s\n' "$p0" | grep -qE '^(BRIEF |ESCALATE)' && { ok=0; echo "      a draft or a mark with no lesson to escalate"; }
cp "$TMP/les.bak" "$LES"
t AC2 "$ok" "--propose drafts one brief per ESCALATE lesson (a valid brief head after 'BRIEF  ', then BRIEFS: 4), none without --propose, BRIEFS: 0 when none escalates; the fixture (its git dir too), 05b-briefs.md and lessons.md unchanged"

# ---------- AC3: --recall unchanged, inside D1's budget, no module needed ----------
ok=1
rc="$(run --recall GENERATE)"
want_r="LESSONS THIS HOP: L1 One.; L3 Three.; L9 Nine."
[[ "$rc" == "$want_r" ]] || { ok=0; echo "      --recall GENERATE: $rc"; }
printf '%s\n' "$rc" | grep -q ESCALATE && { ok=0; echo "      the recall line names ESCALATE"; }
(( $(printf '%s\n' "$rc" | wc -c) <= 400 )) || { ok=0; echo "      the recall line is more than 400 bytes"; }
N="$TMP/nolib/tests"; mkdir -p "$N/lib"; cp "$S" "$N/patterns.sh"
r2="$(bash "$N/patterns.sh" --root "$R" --recall GENERATE 2>&1)"; c2=$?
[[ "$c2" -eq 0 && "$r2" == "$want_r" ]] || { ok=0; echo "      --recall without tests/lib/escalate.py: rc=$c2 $r2"; }
bash "$N/patterns.sh" --root "$R" >/dev/null 2>&1 && { ok=0; echo "      a full run without tests/lib/escalate.py passed"; }
cp "$ROOT/tests/lib/escalate.py" "$N/lib/" 2>/dev/null
[[ "$(bash "$N/patterns.sh" --root "$R" 2>&1 | grep '^ESCALATE' || true)" == "$want_e" ]] || { ok=0; echo "      the module is not loaded from the script's own tests/lib"; }
t AC3 "$ok" "--recall is the t107 line (no ESCALATE, at most 400 bytes) and needs no tests/lib/escalate.py; a full run needs it, from the script's own directory"

# ---------- AC4: the rule at each boundary; the module only computes ----------
ok=1
M="$ROOT/tests/lib/escalate.py"
res="$(python3 -B - "$ROOT/tests/lib" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
from escalate import escalate
cases = [  # (b, a, hb, ha, want)
    (1, 2, 9, 3, True), (1, 2, 9, 2, False), (0, 2, 0, 3, True), (1, 1, 9, 3, False), (0, 0, 9, 9, False),
    (5, 9, 5, 9, True), (0, 0, 0, 9, False), (1, 1, 10, 10, True), (1, 1, 10, 9, False), (1, 1, 9, 10, False),
    (0, 1, 0, 10, False), (0, 1, 5, 10, True), (0, 0, 5, 10, False), (2, 1, 20, 10, True), (3, 1, 20, 10, False),
    (9, 2, 1, 3, True), (0, 0, 0, 12, False), (0, 9, 0, 2, False),
]
bad = [c for c in cases if escalate(*c[:4]) is not c[4]]
print("ok" if not bad else "wrong: " + "; ".join(map(str, bad)))
PY
)"
[[ "$res" == "ok" ]] || { ok=0; echo "      escalate(): $res"; }
[[ -f "$M" ]] || { ok=0; echo "      tests/lib/escalate.py does not exist"; }
grep -nE 'open\(|subprocess|socket|urllib|requests|\.write|os\.|shutil|pathlib|exec\(|eval\(|__import__|importlib' "$M" \
  && { ok=0; echo "      tests/lib/escalate.py holds a write, process or network call"; }
grep -nE '^[[:space:]]*(import|from)[[:space:]]' "$M" | grep -vE '^[0-9]+:from __future__ import annotations$' \
  && { ok=0; echo "      tests/lib/escalate.py imports more than __future__"; }
t AC4 "$ok" "escalate() at each boundary: 3 hops, 2 events, 10 hops, equal rates, no before hop, no event; the module imports only __future__ and holds no write, process or network call"

# ---------- AC5: docs and release ----------
ok=1
sec="$(awk '/^### B29\. /{f=1; print; next} /^### /{f=0} f' "$ROOT/USAGE.md")"
[[ -n "$sec" ]] || { ok=0; echo "      USAGE.md has no B29"; }
for w in ESCALATE --propose tests/patterns.sh; do
  printf '%s\n' "$sec" | grep -qF -- "$w" || { ok=0; echo "      USAGE.md B29 does not name $w"; }
done
v="$(tr -d '[:space:]' < "$ROOT/VERSION")"
python3 -B -c 'import sys; a=tuple(map(int, sys.argv[1].split("."))); sys.exit(0 if a >= (3, 5, 12) else 1)' "$v" 2>/dev/null \
  || { ok=0; echo "      VERSION $v is below 3.5.12"; }
for m in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json; do
  grep -qF "\"$v\"" "$ROOT/$m" || { ok=0; echo "      $m does not hold $v"; }
done
grep -qE "^## $v " "$ROOT/CHANGELOG.md" || { ok=0; echo "      CHANGELOG.md has no ## $v"; }
cl="$(awk -v h="## $v " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f' "$ROOT/CHANGELOG.md")"
for w in escalate T69; do printf '%s\n' "$cl" | grep -qF "$w" || { ok=0; echo "      CHANGELOG.md ## $v does not name $w"; }; done
grep -qF "$v" "$ROOT/README.md" || { ok=0; echo "      README.md does not name release $v"; }
grep -qE 'tests/lib/\(.*\|escalate(\||\))' "$ROOT/tests/ac/t69_gradle_tuning.sh" || { ok=0; echo "      T69's shipped-path allowlist does not name escalate"; }
t AC5 "$ok" "USAGE.md B29 names ESCALATE, --propose and tests/patterns.sh; release 3.5.12 or later in VERSION, the three manifests, README.md and CHANGELOG.md (its section names escalate and T69); T69's allowlist names escalate"

exit "$fail"
