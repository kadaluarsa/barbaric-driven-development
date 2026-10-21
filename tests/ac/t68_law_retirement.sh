#!/usr/bin/env bash
# AC tests for 05b t68-law-retirement: a human retires a law with a signed, reasoned line; a failing law never leaves
# force inside an open hop; a family on one check runs it once; a report lists candidates and changes nothing.
# "Ran" is counted from the tree (a counter per command), never from the printed line.
#   AC1  a retired law is not scored, not required, not selected, not audited.
#   AC2  an invalid retired: line (bad date, missing or retired target, a cycle) leaves the law in force, named.
#   AC3  a retired id stays taken (t67's duplicate FATAL).
#   AC4  inside an open hop only a GREEN law may leave force — RED, THEATER, UNPROVEN, deletion, the human key, a staged
#        or working-tree NONE are all refused; with no hop running a signed retirement lands; a supersession target
#        cannot be retired under its pointer; a target in a shard is read. RED TWIN: a guard that runs only check:.
#   AC5  the merge gate re-proves it from git after --no-verify. RED TWIN: a backstop that skips the verdict.
#   AC6  retired: is a human-owned line in the envelope and a shard, a duplicate identical line included.
#   AC7  a family's shared check runs once, before any break, JOBS=1 and 4, verdicts as 537c0c0.
#        RED TWIN: a memo that reports pass for every check.
#   AC8  laws_report.sh names each candidate kind, prints FAMILY, exits 0, changes nothing.
#   AC9  no retired: line and no shared check: dsharp is 537c0c0 byte for byte.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HUMAN DSHARP_CACHE DSHARP_HARNESS DSHARP_JOBS DSHARP_SERIAL INV_MUTANT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BASELINE=537c0c0     # the last tree before t68
export CNT="$TMP/cnt"; mkdir -p "$CNT"

lawc() {  # lawc <id> <title> <check> <break> [extra lines]
  printf '### %s — %s\ncheck:  echo %s >> "$CNT/order"; %s\nbreak:  echo %sb >> "$CNT/order"; %s\n%s\n' \
    "$1" "$2" "$1" "$3" "$1" "$4" "${5:-}"
}
LAWS="$(lawc D1 'green one' true false 'reason: REMOVED_GUARD — fixture'
lawc D2 'green two' true false
lawc D3 'green three' true false
lawc D4 'green four' true false
lawc D5 'red' false false
printf '### D6 — family a\ncheck:  echo F >> "$CNT/order"; test -f lib/ok.txt\nbreak:  echo D6b >> "$CNT/order"; false\n\n'
printf '### D7 — family b\ncheck:  echo F >> "$CNT/order"; test -f lib/ok.txt\nbreak:  echo D7b >> "$CNT/order"; false\n\n'
printf '### D8 — family c\ncheck:  echo F >> "$CNT/order"; test -f lib/ok.txt\nbreak:  echo D8b >> "$CNT/order"; false\n\n'
lawc D9 'theater' true true
printf '### D10 — unproven\ncheck:  true\nbreak:  TODO\n\n')"
SHARD="$(lawc D11 'green in a shard' true false)"

mkprod() {  # mkprod <dir> [laws] [hop]
  local d="$1" laws="${2:-$LAWS}" hop="${3:-EXECUTE}"
  mkdir -p "$d/docs/cascade/laws" "$d/tests" "$d/lib" "$d/.claude"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in dsharp_strength audit loop affected sign laws_report retirements; do cp "$ROOT/tests/$f.sh" "$d/tests/"; done
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/.claude/hooks" "$d/.claude/hooks"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  echo ok > "$d/lib/ok.txt"
  printf '.cascade/\n' > "$d/.gitignore"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' "$hop" > "$d/docs/cascade/hop-state.md"
  printf '```\nGOAL_STAGE: 05b\nGOAL_SLICE: x\n```\n' > "$d/docs/cascade/goal.md"
  printf '# envelope\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n\n## Law shards\n\n<EDIT>\n| laws/core.md |\n</EDIT>\n' "$laws" > "$d/docs/cascade/envelope.md"
  printf '# core\n\n<EDIT>\n%s\n</EDIT>\n' "$SHARD" > "$d/docs/cascade/laws/core.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
}
run() {  # run <dir> [VAR=value…] -> $OUT; the command log in $ORDER
  local d="$1"; shift
  rm -rf "$CNT"; mkdir -p "$CNT"; : > "$CNT/order"
  OUT="$(cd "$d" && env "$@" bash tests/dsharp_strength.sh 2>&1)"; ORDER="$(cat "$CNT/order")"
}
ran() { grep -cx "$1" <<<"$ORDER" | tr -d ' '; }
retire() {  # retire <dir> <id> <retired text> — put a retired: line under the law's heading
  python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
d, lid, text = sys.argv[1:4]
for p in ("docs/cascade/envelope.md", "docs/cascade/laws/core.md"):
    f = os.path.join(d, p); s = open(f).read()
    s2 = re.sub(rf"(^### {lid} — .*\n(?:(?:check|break|reason|path|tier):.*\n)*)", lambda m: m.group(1) + f"retired: {text}\n", s, count=1, flags=re.M)
    if s2 != s: open(f, "w").write(s2); break
PY
}
drop() {  # drop <dir> <id> — delete the law's block
  python3 - "$1" "$2" <<'PY'
import os, re, sys
d, lid = sys.argv[1:3]
for p in ("docs/cascade/envelope.md", "docs/cascade/laws/core.md"):
    f = os.path.join(d, p); s = open(f).read()
    s2 = re.sub(rf"^### {lid} — .*\n(?:(?:check|break|reason|path|tier|retired):.*\n)*", "", s, count=1, flags=re.M)
    if s2 != s: open(f, "w").write(s2); break
PY
}
attempt() {  # attempt <dir> <want: blocked|lands> <label> [env…] — sign what is changed, commit, reset if blocked
  local d="$1" want="$2" label="$3"; shift 3
  local rc
  rc="$( cd "$d" && bash tests/sign.sh >/dev/null 2>&1; git add -A && env "$@" git commit -qm "$label" >/dev/null 2>"$TMP/err"; echo $? )"
  if [[ "$want" == blocked ]]; then
    [[ "$rc" -ne 0 ]] || { ok=0; echo "  $label: landed, want BLOCKED"; }
  else
    [[ "$rc" -eq 0 ]] || { ok=0; echo "  $label: blocked, want it to land: $(grep -m1 -E 'BLOCKED|REFUSED' "$TMP/err")"; }
  fi
  ( cd "$d" && { [[ "$rc" -eq 0 ]] || git reset -q --hard HEAD; } )
}

# ---- AC1  a retired law is not scored ----------------------------------------------------------------------------
ok=1
A="$TMP/a1"; mkprod "$A"
retire "$A" D2 "2027-03-01 — superseded by D3"; retire "$A" D4 "2027-03-01 — removed — the wallet API was dropped"
( cd "$A" && git add -A && git -c core.hooksPath=/dev/null commit -qm retire )
run "$A"
echo "$OUT" | grep -q '^RETIRED   D2  green two  — superseded by D3 (2027-03-01)' || { ok=0; echo "  no RETIRED line for D2: $(echo "$OUT" | grep D2)"; }
echo "$OUT" | grep -q '^RETIRED   D4  green four  — removed — the wallet API was dropped (2027-03-01)' || { ok=0; echo "  no RETIRED line for D4"; }
[[ "$(ran D2)$(ran D4)$(ran D2b)$(ran D4b)" == "0000" ]] || { ok=0; echo "  a retired law's commands ran"; }
[[ "$(echo "$OUT" | grep '^DSHARP')" == "DSHARP 6/9" ]] || { ok=0; echo "  want DSHARP 6/9 without D2, D4: $(echo "$OUT" | grep '^DSHARP')"; }
c="$( cd "$A" && python3 -B tests/lib/laws.py docs/cascade/envelope.md --in-force --shards docs/cascade/laws | cut -d'|' -f1 | tr '\n' ' ' )"
[[ "$c" != *"D2 "* && "$c" != *"D4 "* && "$c" == *"D11 "* ]] || { ok=0; echo "  --in-force still lists a retired law: $c"; }
om="$( cd "$A" && bash tests/loop.sh --list 2>/dev/null | sed -n 's/^OMITTED D#: \(D[0-9]*\).*/\1/p' | tr '\n' ' ' )"
[[ "$om" != *"D2 "* && "$om" != *"D4 "* && "$om" == *"D1 "* ]] || { ok=0; echo "  loop requires a retired law: $om"; }
af="$( cd "$A" && bash tests/affected.sh --list 2>/dev/null | tr '\n' ' ' )"
[[ "$af" != *"D2 "* && "$af" != *"D4 "* ]] || { ok=0; echo "  affected.sh lists a retired law: $af"; }
printf '| D2 | x | dsharp | IMPLEMENTED |\n| D1 | x | dsharp | IMPLEMENTED |\n' > "$A/docs/cascade/10-audit.md"
au="$( cd "$A" && bash tests/audit.sh 2>&1 )"
echo "$au" | grep -qE '^RETIRED +D2 .*\(not scored\)' || { ok=0; echo "  audit did not show D2 as RETIRED (not scored)"; }
t AC1 "$ok" "a retired law prints RETIRED with its reason, never runs, is out of DSHARP k/n, --in-force, loop's requirement, affected.sh, and audit's count"

# ---- AC2  invalid retirement stays in force ------------------------------------------------------------------------
ok=1
for case in "D2|2027-02-30 — removed — x|is not a date" "D2|2027-03-01 — superseded by D99|not declared" \
            "D2|2027-03-01 — superseded by D4|retired: line itself" "D2|2027-03-01 — supersede D3|not \""; do
  IFS='|' read -r lid text why <<<"$case"
  B="$TMP/a2-$RANDOM"; mkprod "$B"
  retire "$B" "$lid" "$text"
  [[ "$text" == *"by D4" ]] && retire "$B" D4 "2027-03-01 — removed — gone"
  run "$B"
  echo "$OUT" | grep -q "^WARNING   $lid  retired: — .*$why.*; the law stays in force" || { ok=0; echo "  '$text': no WARNING naming '$why': $(echo "$OUT" | grep WARNING)"; }
  [[ "$(ran "$lid")" -ge 1 ]] || { ok=0; echo "  '$text': $lid was not scored"; }
done
B="$TMP/a2c"; mkprod "$B"; retire "$B" D2 "2027-03-01 — superseded by D3"; retire "$B" D3 "2027-03-01 — superseded by D2"
run "$B"
[[ "$(echo "$OUT" | grep -c '^WARNING   D[23] ')" -eq 2 && "$(ran D2)" -ge 1 && "$(ran D3)" -ge 1 ]] || { ok=0; echo "  a cycle D2->D3->D2 did not keep both in force"; }
t AC2 "$ok" "a bad date, a missing target, a retired target, a malformed line and a cycle each leave the law in force and scored, with a WARNING saying why"

# ---- AC3  the id stays taken ---------------------------------------------------------------------------------------
ok=1
C="$TMP/a3"; mkprod "$C"; retire "$C" D4 "2027-03-01 — removed — gone"
printf '\n<EDIT>\n%s\n</EDIT>\n' "$(lawc D4 'a new law reusing D4' true false)" >> "$C/docs/cascade/envelope.md"
o="$( cd "$C" && python3 -B tests/lib/laws.py docs/cascade/envelope.md --count --shards docs/cascade/laws 2>&1 )"; rc=$?
[[ "$rc" -eq 2 && "$o" == *"FATAL duplicate D4"* ]] || { ok=0; echo "  reusing a retired id was not FATAL: rc $rc $o"; }
t AC3 "$ok" "a new law reusing a retired law's id is t67's duplicate FATAL"

# ---- AC4  leaving force inside an open hop --------------------------------------------------------------------------
ok=1
G="$TMP/a4"; mkprod "$G"
retire "$G" D5 "2027-03-01 — removed — dropped";                 attempt "$G" blocked "retire RED D5 in an open hop"
grep -q 'RETIREMENT REFUSED  D5  red is RED' "$TMP/err" || { ok=0; echo "  the refusal does not name D5 RED: $(cat "$TMP/err" | head -3)"; }
retire "$G" D9 "2027-03-01 — removed — dropped";                 attempt "$G" blocked "retire THEATER D9 in an open hop"
grep -q 'D9  theater is THEATER' "$TMP/err" || { ok=0; echo "  the refusal does not name D9 THEATER"; }
retire "$G" D10 "2027-03-01 — removed — dropped";                attempt "$G" blocked "retire UNPROVEN D10 in an open hop"
grep -q 'D10  unproven is UNPROVEN' "$TMP/err" || { ok=0; echo "  the refusal does not name D10 UNPROVEN"; }
drop "$G" D5;                                                     attempt "$G" blocked "delete RED D5's block in an open hop"
retire "$G" D5 "2027-03-01 — removed — dropped";                 attempt "$G" blocked "retire RED D5 with CASCADE_HUMAN=1" CASCADE_HUMAN=1
retire "$G" D5 "2027-03-01 — removed — dropped"; sed -i.bak 's/^CURRENT_HOP: .*/CURRENT_HOP: NONE/' "$G/docs/cascade/hop-state.md"; rm -f "$G/docs/cascade/hop-state.md.bak"
attempt "$G" blocked "retire RED D5 while staging CURRENT_HOP: NONE"
retire "$G" D5 "2027-03-01 — removed — dropped"
( cd "$G" && bash tests/sign.sh >/dev/null 2>&1; git add docs/cascade/envelope.md && sed -i.bak 's/^CURRENT_HOP: .*/CURRENT_HOP: NONE/' docs/cascade/hop-state.md && rm -f docs/cascade/hop-state.md.bak )
rc="$( cd "$G" && git commit -qm wt-none >/dev/null 2>"$TMP/err"; echo $? )"
[[ "$rc" -ne 0 ]] || { ok=0; echo "  a working-tree-only NONE let RED D5's retirement land"; }
( cd "$G" && git reset -q --hard HEAD )
retire "$G" D5 "2027-03-01 — superseded by D11";                 attempt "$G" blocked "retire RED D5 superseded by D11 (a shard law)"
retire "$G" D1 "2027-03-01 — removed — dropped";                 attempt "$G" lands "retire GREEN D1 in an open hop"
drop "$G" D11;                                                    attempt "$G" lands "delete GREEN D11's block (shard) in an open hop"
# with no hop running, a signed retirement of a failing law lands; a supersession target is protected regardless
N="$TMP/a4n"; mkprod "$N" "$LAWS" NONE
retire "$N" D5 "2027-03-01 — removed — the feature was dropped"; attempt "$N" lands "retire RED D5 with no hop running"
retire "$N" D2 "2027-03-01 — superseded by D3";                  attempt "$N" lands "retire D2 superseded by D3"
retire "$N" D3 "2027-03-01 — removed — gone";                    attempt "$N" blocked "retire D3 while D2 points at it"
grep -q 're-point D2 first' "$TMP/err" || { ok=0; echo "  the supersession refusal does not say to re-point D2"; }
# red twin: a guard that runs only check:
T="$TMP/a4t"; mkprod "$T"
python3 - "$T/tests/lib/retirement_guard.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "    if ok(law[\"break\"]):\n        return \"THEATER\"\n"
if old not in s: sys.exit("twin: the break run is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "", 1))
PY
retire "$T" D9 "2027-03-01 — removed — dropped"
rc="$( cd "$T" && bash tests/sign.sh >/dev/null 2>&1; git add -A && git commit -qm twin >/dev/null 2>&1; echo $? )"
[[ "$rc" -eq 0 ]] || { ok=0; echo "  red twin did not go red: a guard running only check: still blocked THEATER D9"; }
t AC4 "$ok" "in an open hop RED, THEATER and UNPROVEN retirements and a RED deletion are BLOCKED — with the human key, a staged NONE or a working-tree NONE too, and with a shard target; GREEN ones land; with no hop a failing law's signed retirement lands; a supersession target is protected (red twin: check-only guard)"

# ---- AC5  the merge gate re-proves it from git ------------------------------------------------------------------------
ok=1
M="$TMP/a5"; mkprod "$M"
( cd "$M" && git checkout -q -b feature )
retire "$M" D5 "2027-03-01 — removed — dropped"
( cd "$M" && git add -A && git commit -q --no-verify -m "retire RED D5, hook skipped" )
ro="$( cd "$M" && bash tests/retirements.sh 2>&1 )"; rc=$?
[[ "$rc" -ne 0 && "$ro" == *"RETIREMENT REFUSED  D5"* ]] || { ok=0; echo "  retirements.sh missed a --no-verify RED retirement: rc $rc $ro"; }
go="$( cd "$M" && BARBAR_ROOT="$M" bash "$ROOT/tests/barbar.sh" gate 2>&1 )"
[[ "$go" == *"D# RETIREMENT REFUSED  D5"* && "$go" == *"BARBAR merge REFUSED"* && "$go" == *"(=0)"* ]] || { ok=0; echo "  the merge gate did not refuse on the retirement: $(echo "$go" | tail -2)"; }
M2="$TMP/a5b"; mkprod "$M2" "$LAWS" NONE
( cd "$M2" && git checkout -q -b feature )
retire "$M2" D5 "2027-03-01 — removed — dropped"
( cd "$M2" && git add -A && git commit -q --no-verify -m "retire RED D5 with no hop" )
( cd "$M2" && bash tests/retirements.sh >/dev/null 2>&1 ) || { ok=0; echo "  retirements.sh refused a retirement made with no hop running"; }
T="$TMP/a5t"; mkprod "$T"; ( cd "$T" && git checkout -q -b feature )
python3 - "$T/tests/lib/retirement_guard.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "        v = verdict(root, rev, d, tmp)\n"
if old not in s: sys.exit("twin: the verdict call is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "        v = \"GREEN\"\n", 1))
PY
retire "$T" D5 "2027-03-01 — removed — dropped"; ( cd "$T" && git add -A && git commit -q --no-verify -m twin )
( cd "$T" && bash tests/retirements.sh >/dev/null 2>&1 ) || { ok=0; echo "  red twin did not go red: a backstop without the verdict still refused"; }
t AC5 "$ok" "a RED law retired in an open hop with --no-verify is RETIREMENT REFUSED by tests/retirements.sh and the merge gate; with no hop it passes (red twin: no verdict)"

# ---- AC6  retired: is human-owned ----------------------------------------------------------------------------------
ok=1
H="$TMP/a6"; mkprod "$H" "$LAWS" NONE
retire "$H" D1 "2027-03-01 — removed — gone"
rc="$( cd "$H" && git add -A && git commit -qm unsigned >/dev/null 2>"$TMP/err"; echo $? )"; ( cd "$H" && git reset -q --hard HEAD )
[[ "$rc" -ne 0 ]] || { ok=0; echo "  an unsigned retired: line in the envelope landed"; }
retire "$H" D11 "2027-03-01 — removed — gone"
rc="$( cd "$H" && git add -A && git commit -qm unsigned >/dev/null 2>"$TMP/err"; echo $? )"; ( cd "$H" && git reset -q --hard HEAD )
[[ "$rc" -ne 0 ]] || { ok=0; echo "  an unsigned retired: line in a shard landed"; }
retire "$H" D2 "2027-03-01 — superseded by D3"; attempt "$H" lands "first retirement, signed"
retire "$H" D1 "2027-03-01 — superseded by D3"
rc="$( cd "$H" && git add -A && git commit -qm dup >/dev/null 2>"$TMP/err"; echo $? )"; ( cd "$H" && git reset -q --hard HEAD )
[[ "$rc" -ne 0 ]] || { ok=0; echo "  a second, identical retired: line landed unsigned (set comparison)"; }
hg="$(printf '{"tool_name":"Edit","permission_mode":"bypassPermissions","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/laws/core.md","old_string":"### D11 — green in a shard\\n","new_string":"### D11 — green in a shard\\nretired: 2027-03-01 — removed — x\\n"}}' "$H" "$H" \
      | ( cd "$H" && python3 -B .claude/hooks/hop_guard.py 2>/dev/null ) )"
[[ "$hg" == *'"deny"'* ]] || { ok=0; echo "  hop_guard let an agent add retired: to a shard"; }
t AC6 "$ok" "an unsigned retired: line is BLOCKED in the envelope and a shard, a second identical one included; hop_guard denies the agent's edit"

# ---- AC7  a family runs its check once ------------------------------------------------------------------------------
ok=1
F="$TMP/a7"; mkprod "$F"
P="$TMP/a7base"; mkdir -p "$P"; git -C "$ROOT" archive "$BASELINE" tests/lib tests/dsharp_strength.sh | tar -x -C "$P" \
  || { ok=0; echo "  cannot read $BASELINE (fetch full history)"; }
for jobs in 1 4; do
  run "$F" DSHARP_JOBS=$jobs; new="$OUT"
  [[ "$(ran F)" -eq 1 ]] || { ok=0; echo "  JOBS=$jobs: the family's check ran $(ran F) times"; }
  [[ "$(ran D6b)$(ran D7b)$(ran D8b)" == "111" ]] || { ok=0; echo "  JOBS=$jobs: a family break did not run exactly once"; }
  first_break="$(grep -nE '^D[678]b$' <<<"$ORDER" | head -1 | cut -d: -f1)"; f_line="$(grep -nx F <<<"$ORDER" | head -1 | cut -d: -f1)"
  [[ -n "$f_line" && "$f_line" -lt "$first_break" ]] || { ok=0; echo "  JOBS=$jobs: a break ran before the shared check"; }
  base="$( cd "$F" && DSHARP_JOBS=$jobs bash "$P/tests/dsharp_strength.sh" --root "$F" 2>&1 )"
  [[ "$base" == "$new" ]] || { ok=0; echo "  JOBS=$jobs: verdicts differ from $BASELINE:"; diff <(echo "$base") <(echo "$new") | sed 's/^/    /' | head; }
done
rm "$F/lib/ok.txt"; run "$F"
[[ "$(echo "$OUT" | grep -c '^RED       D[678] ')" -eq 3 ]] || { ok=0; echo "  a failing shared check did not make every member RED"; }
T="$TMP/a7t"; mkprod "$T"; rm "$T/lib/ok.txt"
python3 - "$T/tests/dsharp_strength.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '''IFS= read -r rc < "$TMP/chk.$g"; [[ "$rc" -eq 0 ]]; return'''
if old not in s: sys.exit("twin: the memo read is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "return 0", 1))
PY
run "$T"
[[ "$(echo "$OUT" | grep -c '^GREEN     D[678] ')" -ge 1 ]] || { ok=0; echo "  red twin did not go red: a memo that always passes still scored the family RED"; }
t AC7 "$ok" "a family's shared check runs once and before any break (JOBS=1 and 4), each break once, verdicts equal $BASELINE, a failing shared check makes each member RED (red twin: an always-pass memo)"

# ---- AC8  the report -------------------------------------------------------------------------------------------------
ok=1
R="$TMP/a8"
RL="$(lawc D20 'missing path' true false 'reason: REMOVED_GUARD — x
path:   src/gone.py'
lawc D21 'dup a' 'test -f lib/ok.txt' 'test -f lib/no.txt' 'reason: REMOVED_GUARD — x'
lawc D22 'dup b' 'test -f lib/ok.txt' 'test -f lib/no.txt' 'reason: REMOVED_GUARD — x'
lawc D23 'no reason' true false
lawc D24 'stale' true false 'reason: REMOVED_GUARD — x
path:   lib/old.txt'
printf '### D25 — family a\ncheck:  test -f lib/ok.txt\nbreak:  false\nreason: REMOVED_GUARD — x\n\n### D26 — family b\ncheck:  test -f lib/ok.txt\nbreak:  test -f nowhere\nreason: REMOVED_GUARD — x\n')"
mkprod "$R" "$RL" NONE
# D21 and D22 are identical twice over: rewrite their logged commands to one shared string
python3 - "$R/docs/cascade/envelope.md" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'echo D2[12] >> "\$CNT/order"; ', 'echo dup >> "$CNT/order"; ', s)
s = re.sub(r'echo D2[12]b >> "\$CNT/order"; ', 'echo dupb >> "$CNT/order"; ', s)
open(p, "w").write(s)
PY
echo old > "$R/lib/old.txt"
( cd "$R" && git add -A && GIT_AUTHOR_DATE='2015-01-01T00:00:00Z' GIT_COMMITTER_DATE='2015-01-01T00:00:00Z' git -c core.hooksPath=/dev/null commit -qm old )
rep="$( cd "$R" && bash tests/laws_report.sh 2>&1 )"; rc=$?
for want in "MISSING-PATH  D20" "DUPLICATE     D21 D22" "UNEXPLAINED   D23" "STALE         D24" "FAMILY        D25 D26"; do
  grep -q "^$want" <<<"$rep" || { ok=0; echo "  the report does not say '$want'"; }
done
[[ "$rc" -eq 0 && -z "$( cd "$R" && git status --porcelain )" ]] || { ok=0; echo "  the report exited $rc or changed the tree"; }
t AC8 "$ok" "laws_report.sh names a missing path, a duplicate, an unexplained and a stale law, lists a family as information, exits 0 and changes nothing"

# ---- AC9  parity ----------------------------------------------------------------------------------------------------
ok=1
PL="$(lawc D1 'one' true false; lawc D5 'red' false false; lawc D9 'theater' true true; printf '### D10 — unproven\ncheck:  true\nbreak:  TODO\n')"
Q="$TMP/a9"; mkprod "$Q" "$PL"
base="$(bash "$P/tests/dsharp_strength.sh" --root "$Q" 2>&1)"; new="$( cd "$Q" && bash tests/dsharp_strength.sh 2>&1 )"
[[ "$base" == "$new" ]] || { ok=0; echo "  dsharp differs from $BASELINE:"; diff <(echo "$base") <(echo "$new") | sed 's/^/    /' | head; }
t AC9 "$ok" "with no retired: line and no shared check, dsharp equals $BASELINE byte for byte"

exit "$fail"
