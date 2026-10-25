#!/usr/bin/env bash
# AC tests for 05b t78-carry-out: an accepted slice's tests move to a regression suite that the merge gate and CI
# run; removing a regression line is the human's to sign, and a removal made anyway still runs at the gate.
# "Ran" is counted from the tree (each line appends to a counter file), never from the printed line.
#   AC1  carry-out moves exactly the carried lines (a late '# standing' too), dedups, keeps standing and law lines.
#   AC2  reset carries out first: committed, shallow, unnamed, send-back; refuses an uncommitted goal.
#        RED TWIN: a reset without carry-out leaves regress.md empty.
#   AC3  regress.sh runs each line once: k/n, exit codes, no file / empty file = 0/0.
#   AC4  the gate: HEAD + lines removed since the base − signed retirements; dirty and shallow refused; parity.
#        RED TWIN: a gate that reads only HEAD's lines lets a --no-verify removal through.
#   AC5  protection: removed/edited lines BLOCKED unless signed; file deletion needs the key; adds are free;
#        hop_guard asks / denies / allows. RED TWIN: a guard comparing only line counts lets an edit through.
#   AC6  dropped: named, carried by carry-out, never for a line once committed to regress.md; t77's words.
#   AC7  install seeds regress.md, ships regress.sh and the template, the nightly has a regress job.
#   AC8  parity with a94b26a when nothing is carried, dropped or in the suite.
#   AC9  release: 3.0.0 agreed in three files; CHANGELOG 3.0.0 names t77 and t78; no 2.8.0 heading.
#   AC10 CI: --ci skips '# gate-only' (counted, never passed); the gate runs it; control-line.yml has the job.
#        RED TWIN: a --ci that counts a skipped line as passed reports 2/2.
#   E1   a dream-camera-shaped goal before and after reset.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_LOOP_RUNNER BARBAR_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BASELINE=a94b26a     # t77 accepted, before t78's code
export CNT="$TMP/cnt"
REG=docs/cascade/regress.md

mkprod() {  # mkprod <dir> <current slice> [tests dir] [envelope laws] — a product, no goal, git on main
  local d="$1" slice="$2" tdir="${3:-$ROOT/tests}" laws="${4:-}"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$tdir/lib" "$d/tests/lib"
  for f in loop.sh goal.sh regress.sh sign.sh; do [[ -f "$tdir/$f" ]] && cp "$tdir/$f" "$d/tests/"; done
  for f in goal.template.md regress.template.md; do [[ -f "$ROOT/docs/cascade/$f" ]] && cp "$ROOT/docs/cascade/$f" "$d/docs/cascade/"; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: %s\n' "$slice" > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n\n## Locked decisions\n\n<EDIT>\n</EDIT>\n' "$laws" \
    > "$d/docs/cascade/envelope.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main )
}
goal() {  # goal <dir> <slice or -> <validator…>
  local d="$1" slice="$2"; shift 2
  { echo '# /goal'; echo; echo '```'; echo 'GOAL_STAGE: 05b'
    [[ "$slice" != - ]] && echo "GOAL_SLICE: $slice"
    for v in "$@"; do echo "VALIDATOR: $v"; done; echo '```'; } > "$d/docs/cascade/goal.md"
}
regf() {  # regf <dir> <line…> — write regress.md with the given REGRESS lines under one heading
  local d="$1"; shift
  { echo '# Regression suite'; echo; echo '### fixture'; for l in "$@"; do echo "REGRESS: $l"; done; } > "$d/$REG"
}
commit() { ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm "${2:-c}" ); }
fresh() { rm -rf "$CNT"; mkdir -p "$CNT"; : > "$CNT/ran"; }
ran() { grep -c . "$CNT/ran" | tr -d ' '; }
loop() { local d="$1"; shift; fresh; OUT="$(cd "$d" && bash tests/loop.sh "$@" 2>&1)"; RC=$?; RAN="$(ran)"; }
gsh() { local d="$1"; shift; fresh; OUT="$(cd "$d" && bash tests/goal.sh "$@" 2>&1)"; RC=$?; }
rsh() { local d="$1"; shift; fresh; OUT="$(cd "$d" && bash tests/regress.sh "$@" 2>&1)"; RC=$?; RAN="$(ran)"; }
v() { printf 'echo %s >> "$CNT/ran"' "$1"; }
LINT="$(v lint) # standing"
LAW='### D1 — the fixture law
check:  echo law >> "$CNT/ran"
break:  false'
LAWV='echo law >> "$CNT/ran"'
under() {  # under <file> <heading> <line> — the REGRESS line sits below that heading
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, head, line = sys.argv[1:4]; cur = None
for raw in open(p).read().splitlines():
    if raw.startswith("### "): cur = raw[4:].strip()
    elif raw.startswith("REGRESS:") and raw[len("REGRESS:"):].strip() == line and cur == head: sys.exit(0)
sys.exit(1)
PY
}
nreg() { [[ -f "$1/$REG" ]] && grep -c '^REGRESS:' "$1/$REG" | tr -d ' ' || echo 0; }

# ---- AC1  carry-out ---------------------------------------------------------------------------------------------
ok=1
P="$TMP/p1"; mkprod "$P" B "$ROOT/tests" "$LAW"
goal "$P" A "$(v v1)" "$(v v2)" "$LINT" "$LAWV"; commit "$P" A
goal "$P" B "$(v v1)" "$(v v2)" "$(v v3)" "$LINT" "$LAWV"; commit "$P" B
gsh "$P" carry-out
[[ "$RC" -eq 0 && "$OUT" == *"carried 2 validators to docs/cascade/regress.md (A), 0 already there"* ]] \
  || { ok=0; echo "  carry-out did not say it carried 2 from A (rc $RC): $OUT"; }
under "$P/$REG" A "$(v v1)" && under "$P/$REG" A "$(v v2)" || { ok=0; echo "  v1/v2 are not under '### A' in regress.md"; }
g="$(cat "$P/docs/cascade/goal.md")"
[[ "$g" != *"$(v v1)"* && "$g" == *"$(v v3)"* && "$g" == *"$LINT"* && "$g" == *"VALIDATOR: $LAWV"* ]] \
  || { ok=0; echo "  the goal does not hold exactly v3, the standing line and the law check"; }
loop "$P"; grep -q '^goal: .* earlier slices' <<<"$OUT" && { ok=0; echo "  the loop still prints t77's notice after carry-out"; }
commit "$P" after; gsh "$P" carry-out
[[ "$OUT" == *"carried 0 validators"* && "$(nreg "$P")" -eq 2 ]] || { ok=0; echo "  a second carry-out was not a no-op: $OUT"; }
# a line already in regress.md: removed from the goal, not duplicated
P="$TMP/p1b"; mkprod "$P" B
goal "$P" A "$(v v1)"; commit "$P" A
goal "$P" B "$(v v1)" "$(v v3)"; regf "$P" "$(v v1)"; commit "$P" B
gsh "$P" carry-out
[[ "$OUT" == *"carried 0 validators"*"1 already there"* && "$(nreg "$P")" -eq 1 && "$(grep -c "$(v v1)" "$P/docs/cascade/goal.md")" -eq 0 ]] \
  || { ok=0; echo "  a line already in regress.md was duplicated or left in the goal: $OUT"; }
# a late '# standing' (t77 AC7's shape) is carried
P="$TMP/p1c"; mkprod "$P" B
goal "$P" A "$(v v1)" "$LINT"; commit "$P" A
goal "$P" B "$(v v1) # standing" "$LINT"; commit "$P" B
gsh "$P" carry-out
under "$P/$REG" A "$(v v1) # standing" || { ok=0; echo "  a late-marked standing line was not carried: $OUT"; }
t AC1 "$ok" "carry-out moves exactly the carried lines under their slice, keeps v3, the standing line and the law check, silences t77's notice, is idempotent, does not duplicate, and carries a late '# standing'"

# ---- AC2  reset carries out --------------------------------------------------------------------------------------
ok=1
mk2() { mkprod "$1" B "${2:-$ROOT/tests}"; goal "$1" A "$(v v1)" "$(v v2)" "$(v v3)"; commit "$1" A; }
P="$TMP/p2"; mk2 "$P"; gsh "$P" reset
[[ "$RC" -eq 0 && "$OUT" == *"removed 3 validators (3 carried"* ]] || { ok=0; echo "  reset did not carry 3 out (rc $RC): $OUT"; }
under "$P/$REG" A "$(v v1)" && under "$P/$REG" A "$(v v3)" || { ok=0; echo "  reset did not put A's lines under '### A'"; }
exp="$(sed -E 's/^GOAL_STAGE:.*/GOAL_STAGE: 05b/; s/^GOAL_SLICE:.*/GOAL_SLICE: B/' "$ROOT/docs/cascade/goal.template.md")"
[[ "$(cat "$P/docs/cascade/goal.md")" == "$exp" ]] || { ok=0; echo "  reset did not write the template for B"; }
P="$TMP/p2sh"; mk2 "$P"; SH="$TMP/p2c"; git clone -q --depth 1 "file://$P" "$SH" 2>/dev/null; gsh "$SH" reset
[[ "$RC" -eq 0 && "$(nreg "$SH")" -eq 3 ]] || { ok=0; echo "  reset in a shallow clone did not carry the replaced goal (rc $RC): $OUT"; }
P="$TMP/p2u"; mkprod "$P" B; goal "$P" - "$(v v1)"; commit "$P"; gsh "$P" reset
under "$P/$REG" unattributed "$(v v1)" || { ok=0; echo "  a goal with no GOAL_SLICE was not carried under '### unattributed': $OUT"; }
P="$TMP/p2d"; mk2 "$P"; echo "VALIDATOR: $(v v9)" >> "$P/docs/cascade/goal.md"; before="$(cat "$P/docs/cascade/goal.md")"; gsh "$P" reset
[[ "$RC" -ne 0 && "$OUT" == *"commit the goal first"* && ! -f "$P/$REG" && "$(cat "$P/docs/cascade/goal.md")" == "$before" ]] \
  || { ok=0; echo "  reset of an uncommitted goal was not refused untouched (rc $RC): $OUT"; }
P="$TMP/p2b"; mkprod "$P" B; goal "$P" A "$(v v1)"; commit "$P" A; goal "$P" B "$(v v1)" "$(v v5)"; commit "$P" B; gsh "$P" reset
[[ "$(nreg "$P")" -eq 1 ]] && under "$P/$REG" A "$(v v1)" || { ok=0; echo "  a send-back reset carried this slice's own line: $(cat "$P/$REG" 2>/dev/null)"; }
# red twin: a reset without carry-out
TW="$TMP/twin2"; cp -R "$ROOT/tests" "$TW"
python3 - "$TW/goal.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = '    carry_out_for_reset || exit 1\n'
if old not in s: sys.exit("twin: the reset's carry-out call is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, ""))
PY
P="$TMP/p2t"; mk2 "$P" "$TW"; gsh "$P" reset
[[ "$(nreg "$P")" -eq 0 ]] || { ok=0; echo "  red twin did not go red: a reset without carry-out still filled regress.md"; }
t AC2 "$ok" "reset carries the replaced goal out (committed, shallow clone, no GOAL_SLICE as 'unattributed'), carries only earlier slices' lines on a send-back, refuses an uncommitted goal untouched (red twin: no carry-out, empty suite)"

# ---- AC3  the runner ----------------------------------------------------------------------------------------------
ok=1
P="$TMP/p3"; mkprod "$P" B; regf "$P" "$(v r1)" "$(v r2); false" "$(v r3)"; commit "$P"
rsh "$P"
[[ "$RC" -eq 1 && "$OUT" == *"REGRESS 2/3"* && "$OUT" == *"FAIL  $(v r2); false"* && "$RAN" -eq 3 ]] \
  || { ok=0; echo "  one failing line of three did not give REGRESS 2/3, exit 1, each run once (rc $RC, ran $RAN)"; echo "$OUT" | tail -4 | sed 's/^/      /'; }
regf "$P" "$(v r1)" "$(v r2)" "$(v r3)"; rsh "$P"
[[ "$RC" -eq 0 && "$OUT" == *"REGRESS 3/3"* && "$RAN" -eq 3 ]] || { ok=0; echo "  three passing lines did not give REGRESS 3/3 (rc $RC)"; }
rm -f "$P/$REG"; rsh "$P"; [[ "$RC" -eq 0 && "$OUT" == *"REGRESS 0/0"* ]] || { ok=0; echo "  no regress.md is not REGRESS 0/0: $OUT"; }
: > "$P/$REG"; rsh "$P"; [[ "$RC" -eq 0 && "$OUT" == *"REGRESS 0/0"* ]] || { ok=0; echo "  an empty regress.md is not REGRESS 0/0: $OUT"; }
t AC3 "$ok" "regress.sh: one failing of three is REGRESS 2/3 exit 1 with the line named, all passing 3/3 exit 0, each line run once; no file or an empty file is 0/0"

# ---- AC4  the gate ------------------------------------------------------------------------------------------------
ok=1
mkgate() {  # mkgate <dir> [tests dir] — the farm's ready-product as its own repo on main
  rm -rf "$1"; mkdir -p "$1"; cp -R "$ROOT/evals/fixtures/ready-product/." "$1/"
  printf '.cascade/\n' > "$1/.gitignore"
  ( cd "$1" && git init -q && git symbolic-ref HEAD refs/heads/main )
}
gate() { local d="$1" tdir="${2:-$ROOT/tests}"; fresh; OUT="$(BARBAR_ROOT="$d" bash "$tdir/barbar.sh" gate 2>&1)"; RC=$?; RAN="$(ran)"; }
G="$TMP/g1"; mkgate "$G"; regf "$G" "$(v g1)"; commit "$G"; gate "$G"
[[ "$RC" -eq 0 && "$OUT" == *"ALLOWED"*"REGRESS 1/1"* && "$RAN" -eq 1 ]] || { ok=0; echo "  a passing suite was not ALLOWED with REGRESS 1/1 (rc $RC):"; echo "$OUT" | tail -2 | sed 's/^/      /'; }
regf "$G" "$(v g1)" "$(v g2); false"; commit "$G" red; gate "$G"
[[ "$RC" -ne 0 && "$OUT" == *"REFUSED"*"REGRESS 1/2"* && "$OUT" == *"RG FAIL $(v g2); false"* ]] || { ok=0; echo "  a failing line was not REFUSED and named (rc $RC):"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
( cd "$G" && git checkout -qb slice && sed -i.bak '/false$/d' "$REG" && rm -f "$REG.bak" ) ; commit "$G" "drop it (--no-verify)"
gate "$G"
[[ "$RC" -ne 0 && "$OUT" == *"RG FAIL $(v g2); false"* ]] || { ok=0; echo "  a line removed on the branch was not still run at the gate (rc $RC)"; }
printf '\n## Locked decisions\n\n<EDIT>\n- REGRESS_RETIRED: %s — the fixture retires it\n</EDIT>\n' "$(v g2); false" >> "$G/docs/cascade/envelope.md"
commit "$G" retire; gate "$G"
[[ "$RC" -eq 0 && "$OUT" == *"ALLOWED"*"REGRESS 1/1"* ]] || { ok=0; echo "  a signed REGRESS_RETIRED did not retire the removed line (rc $RC):"; echo "$OUT" | tail -2 | sed 's/^/      /'; }
echo "REGRESS: $(v g3)" >> "$G/$REG"; gate "$G"
[[ "$RC" -ne 0 && "$OUT" == *"REFUSED"* && "$OUT" == *"differs from HEAD"* ]] || { ok=0; echo "  an uncommitted regress.md was not REFUSED (rc $RC)"; }
( cd "$G" && git checkout -q -- "$REG" )
SH="$TMP/g1s"; git clone -q --depth 1 "file://$G" "$SH" 2>/dev/null; gate "$SH"
[[ "$RC" -ne 0 && "$OUT" == *"shallow"* ]] || { ok=0; echo "  a shallow clone was not REFUSED at the gate (rc $RC)"; }
OLD="$TMP/old"; mkdir -p "$OLD"; git -C "$ROOT" archive "$BASELINE" tests | tar -x -C "$OLD"
G2="$TMP/g2"; mkgate "$G2"; commit "$G2"; gate "$G2" "$OLD/tests"; b="$(echo "$OUT" | grep -E 'ALLOWED|REFUSED')"
gate "$G2"; a="$(echo "$OUT" | grep -E 'ALLOWED|REFUSED')"
[[ -n "$a" && "$a" == "$b" ]] || { ok=0; echo "  with no suite the gate line differs from $BASELINE:"; echo "      before: $b"; echo "      after:  $a"; }
NT="$TMP/nors/tests"; mkdir -p "$TMP/nors"; cp -R "$ROOT/tests" "$NT"; rm -f "$NT/regress.sh"; gate "$G2" "$NT"
[[ "$RC" -ne 0 && "$OUT" == *"tests/regress.sh is missing"* && "$OUT" == *"REFUSED"* ]] || { ok=0; echo "  a missing tests/regress.sh was not REFUSED by name (rc $RC)"; }
# red twin: a gate that reads only HEAD's lines
TW="$TMP/twin4/tests"; mkdir -p "$TMP/twin4"; cp -R "$ROOT/tests" "$TW"
python3 - "$TW/lib/regress_lines.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "    lines += [l for l in removed_since_base(root, base, head_lines)]\n"
if old not in s: sys.exit("twin: the base union is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, ""))
PY
G3="$TMP/g3"; mkgate "$G3"; regf "$G3" "$(v g1)" "$(v g2); false"; commit "$G3"
( cd "$G3" && git checkout -qb slice && sed -i.bak '/false$/d' "$REG" && rm -f "$REG.bak" ); commit "$G3" drop
gate "$G3" "$TW"
[[ "$RC" -eq 0 ]] || { ok=0; echo "  red twin did not go red: a HEAD-only gate still refused the --no-verify removal (rc $RC)"; }
t AC4 "$ok" "the gate: ALLOWED with REGRESS 1/1; a failing line REFUSED and named; removed on the branch it still runs; a signed REGRESS_RETIRED retires it; an uncommitted suite and a shallow clone are REFUSED; no suite is byte-identical to $BASELINE; no regress.sh is REFUSED (red twin: HEAD-only gate)"

# ---- AC5  protection ----------------------------------------------------------------------------------------------
ok=1
P="$TMP/p5"; mkprod "$P" B; mkdir -p "$P/.githooks" "$P/.claude"
cp -R "$ROOT/.githooks/." "$P/.githooks/"; cp -R "$ROOT/.claude/hooks" "$P/.claude/hooks"
regf "$P" "$(v k1)" "$(v k2)"; commit "$P"; ( cd "$P" && git config core.hooksPath .githooks )
try() {  # try <dir> <label> [env…] -> $TRY_RC (0 = landed), resets a refused change
  local d="$1"; shift 2
  ( cd "$d" && git add -A && env "$@" git commit -qm try >/dev/null 2>"$TMP/try.err" ); TRY_RC=$?
  [[ "$TRY_RC" -ne 0 ]] && ( cd "$d" && git reset -q --hard HEAD )
  return 0
}
sed -i.bak "/k2/d" "$P/$REG"; rm -f "$P/$REG.bak"; try "$P" remove
[[ "$TRY_RC" -ne 0 ]] && grep -q 'regression line removed or changed' "$TMP/try.err" && grep -qF "$(v k2)" "$TMP/try.err" \
  || { ok=0; echo "  removing a regression line was not BLOCKED by name (rc $TRY_RC)"; cat "$TMP/try.err" | head -3 | sed 's/^/      /'; }
sed -i.bak "s/k2/k2x/" "$P/$REG"; rm -f "$P/$REG.bak"; try "$P" edit
[[ "$TRY_RC" -ne 0 ]] || { ok=0; echo "  editing a regression line was not BLOCKED"; }
sed -i.bak "/k2/d" "$P/$REG"; rm -f "$P/$REG.bak"; ( cd "$P" && bash tests/sign.sh >/dev/null 2>&1 ); try "$P" signed
[[ "$TRY_RC" -eq 0 ]] || { ok=0; echo "  a removal signed with tests/sign.sh did not land"; cat "$TMP/try.err" | head -3 | sed 's/^/      /'; }
rm -f "$P/$REG"; try "$P" delete
[[ "$TRY_RC" -ne 0 ]] || { ok=0; echo "  deleting regress.md was not BLOCKED"; }
rm -f "$P/$REG"; try "$P" delete-key CASCADE_HUMAN=1
[[ "$TRY_RC" -eq 0 ]] || { ok=0; echo "  deleting regress.md with CASCADE_HUMAN=1 did not land"; }
regf "$P" "$(v k1)"; ( cd "$P" && git add -A && CASCADE_HUMAN=1 git commit -qm back >/dev/null 2>&1 )
{ echo; echo '### another'; echo "REGRESS: $(v k3)"; } >> "$P/$REG"; try "$P" add
[[ "$TRY_RC" -eq 0 ]] || { ok=0; echo "  adding a regression line was BLOCKED"; cat "$TMP/try.err" | head -3 | sed 's/^/      /'; }
python3 - "$P/$REG" <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().splitlines(); k1 = [l for l in lines if "k1" in l][0]
lines.remove(k1); lines.append(k1); open(p, "w").write("\n".join(lines) + "\n")
PY
try "$P" move; [[ "$TRY_RC" -eq 0 ]] || { ok=0; echo "  moving a line under another heading was BLOCKED"; }
hg() {  # hg <mode> <new content> -> the hook's decision JSON
  printf '{"tool_name":"Write","cwd":"%s","permission_mode":"%s","tool_input":{"file_path":"%s/%s","content":%s}}' \
    "$P" "$1" "$P" "$REG" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$2")" \
    | CLAUDE_PROJECT_DIR="$P" python3 -B "$P/.claude/hooks/hop_guard.py" 2>/dev/null
}
cur="$(cat "$P/$REG")"; drop="$(grep -v k3 <<<"$cur")"
[[ "$(hg default "$drop")" == *'"ask"'* ]] || { ok=0; echo "  hop_guard did not ask on a Write that drops a line: $(hg default "$drop")"; }
[[ "$(hg bypassPermissions "$drop")" == *'"deny"'* ]] || { ok=0; echo "  hop_guard did not deny a headless drop"; }
j="$(hg default "$cur"$'\n'"REGRESS: $(v k4)")"; [[ -z "$j" ]] || { ok=0; echo "  hop_guard stopped a Write that only adds: $j"; }
# red twin: a guard that compares only line counts
TW="$TMP/twin5.py"; cp "$ROOT/tests/lib/regress_lines.py" "$TW"
python3 - "$TW" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "    missing = list((Counter(map(norm, b)) - Counter(map(norm, a))).elements())\n"
if old not in s: sys.exit("twin: the multiset compare is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "    missing = ['x'] * max(0, len(b) - len(a))\n"))
PY
cp "$TW" "$P/tests/lib/regress_lines.py"; sed -i.bak "s/k3/k3x/" "$P/$REG"; rm -f "$P/$REG.bak"; try "$P" twin
[[ "$TRY_RC" -eq 0 ]] || { ok=0; echo "  red twin did not go red: a count-only guard still blocked an edited line"; }
t AC5 "$ok" "a removed or edited regression line is BLOCKED by name; signed with tests/sign.sh it lands; deleting the file needs CASCADE_HUMAN=1; adding and moving lines land unsigned; hop_guard asks (interactive), denies (headless), allows an add (red twin: count-only guard)"

# ---- AC6  dropped -------------------------------------------------------------------------------------------------
ok=1
P="$TMP/p6"; mkprod "$P" C
goal "$P" B "$(v v1)" "$(v v2)" "$LINT"; commit "$P" B
goal "$P" C "$(v v1)" "$(v vC)"; commit "$P" C; loop "$P"
grep -qF "goal: 1 validators of B's goal are in neither this goal, regress.md nor a law — bash tests/goal.sh carry-out moves them to regress.md (USAGE.md §B17)" <<<"$OUT" \
  || { ok=0; echo "  the dropped line is missing or wrong:"; grep '^goal' <<<"$OUT" | sed 's/^/      /'; }
gsh "$P" carry-out; under "$P/$REG" B "$(v v2)" || { ok=0; echo "  carry-out did not carry the dropped line under '### B': $OUT"; }
commit "$P" carried; loop "$P"; grep -q 'validators of B' <<<"$OUT" && { ok=0; echo "  still dropped after carry-out"; }
grep -q 'lint' "$P/$REG" && { ok=0; echo "  the standing line was carried as dropped"; }
( cd "$P" && sed -i.bak '/v2/d' "$REG" && rm -f "$REG.bak" ); commit "$P" "signed removal"; loop "$P"
grep -q 'validators of B' <<<"$OUT" && { ok=0; echo "  a line once committed to regress.md is reported dropped after its removal"; }
P="$TMP/p6b"; mkprod "$P" B
goal "$P" A "$(v v1)" "$(v v2)" "$(v v3)" "$(v v4)" "$(v v5)" "$(v v6)" "$(v v7)" "$(v v8)" "$(v v9)" "$(v v10)" "$(v v11)"; commit "$P" A
goal "$P" B "$(v v1)" "$(v v2)" "$(v v3)" "$(v v4)" "$(v v5)" "$(v v6)" "$(v v7)" "$(v v8)" "$(v v9)" "$(v v10)" "$(v v11)"; commit "$P" B
loop "$P"
[[ "$OUT" == *"bash tests/goal.sh carry-out"*"or the human signs a higher"* ]] || { ok=0; echo "  t77's cap refusal does not name carry-out first"; echo "$OUT" | head -5 | sed 's/^/      /'; }
P="$TMP/p6c"; mkprod "$P" B; goal "$P" A "$(v v1)"; commit "$P" A; goal "$P" B "$(v v1)" "$(v v2)"; commit "$P" B; loop "$P"
grep -qF "goal: 1 of 2 validators were in earlier slices' goals (A), 0 standing — bash tests/goal.sh carry-out moves the 1 to regress.md (USAGE.md §B17)" <<<"$OUT" \
  || { ok=0; echo "  t77's notice does not name carry-out:"; grep '^goal' <<<"$OUT" | sed 's/^/      /'; }
t AC6 "$ok" "a line of the previous slice's goal in neither goal, regress.md nor a law is named; carry-out carries it under its slice; never the standing line, never a line once committed to regress.md; t77's notice and cap refusal name carry-out"

# ---- AC7  install -------------------------------------------------------------------------------------------------
ok=1
I="$TMP/i7"; mkdir -p "$I"; ( cd "$I" && git init -q ); ( HOME="$TMP/nohome" bash "$ROOT/install.sh" --no-plugin "$I" >/dev/null 2>&1 )
cmp -s "$I/$REG" "$ROOT/docs/cascade/regress.template.md" && [[ -f "$I/tests/regress.sh" && -f "$I/docs/cascade/regress.template.md" ]] \
  || { ok=0; echo "  a fresh install did not seed regress.md from the template, or regress.sh / the template is missing"; }
o="$(cd "$I" && bash tests/regress.sh 2>&1)"; [[ "$o" == *"REGRESS 0/0"* ]] || { ok=0; echo "  the seeded suite is not REGRESS 0/0: $o"; }
I2="$TMP/i7b"; mkdir -p "$I2/docs/cascade"; echo '# mine' > "$I2/$REG"; ( cd "$I2" && git init -q )
( HOME="$TMP/nohome" bash "$ROOT/install.sh" --no-plugin "$I2" >/dev/null 2>&1 )
[[ "$(cat "$I2/$REG")" == '# mine' ]] || { ok=0; echo "  install overwrote an existing regress.md"; }
I3="$TMP/i7c"; mkdir -p "$I3"; ( cd "$I3" && git init -q ); ( HOME="$TMP/nohome" bash "$ROOT/install.sh" --no-plugin --with-nightly "$I3" >/dev/null 2>&1 )
python3 -c 'import sys; s=open(sys.argv[1]).read(); sys.exit(0 if "\n  regress:\n" in s and "bash tests/regress.sh" in s else 1)' "$I3/.github/workflows/nightly.yml" \
  || { ok=0; echo "  --with-nightly did not ship a nightly with a regress job"; }
t AC7 "$ok" "a fresh install seeds regress.md from the template (REGRESS 0/0) and ships regress.sh and the template; an existing regress.md is kept; --with-nightly's nightly has a regress job"

# ---- AC8  parity --------------------------------------------------------------------------------------------------
ok=1
norm() { sed -E 's/\([0-9]+s\)/(Ns)/g; s/ \([0-9]+s, / (Ns, /g'; }
par() {
  local d="$TMP/p8"; mkprod "$d" B "$1" "$LAW"
  goal "$d" B "$(v v1)" "$LAWV"; commit "$d" B1
  goal "$d" B "$(v v1)" "$(v v2)" "$LINT" "$LAWV"; commit "$d" B2
  loop "$d"; echo "$OUT" | norm; echo "rc=$RC ran=$RAN"
}
before="$(par "$OLD/tests")"; after="$(par "$ROOT/tests")"
[[ "$before" == "$after" ]] || { ok=0; echo "  the loop's output differs from $BASELINE:"; diff <(echo "$before") <(echo "$after") | sed 's/^/      /' | head -20; }
t AC8 "$ok" "nothing carried, dropped or in the suite: loop.sh prints what $BASELINE printed, byte for byte (the gate line is AC4's)"

# ---- AC9  release -------------------------------------------------------------------------------------------------
ok=1
V="$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ "$V" == 3.0.0 ]] || { ok=0; echo "  VERSION is $V, not 3.0.0"; }
grep -q "\"version\": \"$V\"" "$ROOT/.claude-plugin/plugin.json" && grep -q "\"version\": \"$V\"" "$ROOT/.claude-plugin/marketplace.json" \
  || { ok=0; echo "  a plugin manifest does not say $V"; }
sec="$(awk '/^## 3\.0\.0 — /{on=1; print; next} /^## [0-9]/{on=0} on' "$ROOT/CHANGELOG.md")"
[[ "$sec" == *t77* && "$sec" == *t78* ]] || { ok=0; echo "  CHANGELOG.md has no '## 3.0.0 — ' section naming t77 and t78"; }
grep -q '^## 2\.8\.0' "$ROOT/CHANGELOG.md" && { ok=0; echo "  CHANGELOG.md still has a 2.8.0 heading (it was never tagged)"; }
o="$(bash "$ROOT/tests/ac/t77_goal_hygiene.sh" 2>&1 | grep '^.... *AC6')"; [[ "$o" == PASS* ]] || { ok=0; echo "  t77's AC6 does not pass on the agreement rule: $o"; }
t AC9 "$ok" "VERSION, plugin.json and marketplace.json agree on 3.0.0; CHANGELOG's 3.0.0 section names t77 and t78 and no 2.8.0 heading is left; t77's AC6 passes"

# ---- AC10  CI -----------------------------------------------------------------------------------------------------
ok=1
P="$TMP/p10"; mkprod "$P" B; regf "$P" "$(v c1)" "$(v c2); false" "$(v c3) # gate-only"; commit "$P"
rsh "$P" --gate --ci
[[ "$RC" -eq 1 && "$OUT" == *"SKIP  gate-only  $(v c3) # gate-only"* && "$OUT" == *"REGRESS 1/2 (1 gate-only, not run here)"* ]] \
  || { ok=0; echo "  --ci did not skip the gate-only line and score 1/2 (rc $RC):"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
regf "$P" "$(v c1)" "$(v c3) # gate-only"; commit "$P" fix; rsh "$P" --gate --ci
[[ "$RC" -eq 0 && "$RAN" -eq 1 ]] || { ok=0; echo "  --ci ran the gate-only line or failed (rc $RC, ran $RAN)"; }
rsh "$P" --gate; [[ "$RC" -eq 0 && "$RAN" -eq 2 && "$OUT" == *"REGRESS 2/2"* ]] || { ok=0; echo "  gate mode did not run the gate-only line (ran $RAN)"; }
python3 - "$ROOT/.github/workflows/control-line.yml" <<'PY' || { ok=0; echo "  control-line.yml has no separate regress job running regress.sh --gate --ci with fetch-depth: 0"; }
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"\n  regress:\n((?:    .*\n|\s*\n)*)", s)
sys.exit(0 if m and "bash tests/regress.sh --gate --ci" in m.group(1) and "fetch-depth: 0" in m.group(1) else 1)
PY
P="$TMP/p10b"; mkprod "$P" B; mkdir -p "$P/.githooks" "$P/.claude"; cp -R "$ROOT/.githooks/." "$P/.githooks/"; cp -R "$ROOT/.claude/hooks" "$P/.claude/hooks"
regf "$P" "$(v c1)"; commit "$P"; ( cd "$P" && git config core.hooksPath .githooks )
python3 - "$P/$REG" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read().splitlines()
open(p, "w").write("\n".join(l + " # gate-only" if l.startswith("REGRESS:") else l for l in s) + "\n")
PY2
try "$P" gate-only
[[ "$TRY_RC" -ne 0 ]] || { ok=0; echo "  adding '# gate-only' to a committed line was not BLOCKED"; }
# red twin: a --ci that counts a skipped line as passed
TW="$TMP/twin10"; cp -R "$ROOT/tests" "$TW"
python3 - "$TW/regress.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = '    echo "SKIP  gate-only  $l"; skipped=$((skipped + 1)); continue\n'
if old not in s: sys.exit("twin: the gate-only skip is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, '    echo "SKIP  gate-only  $l"; k=$((k + 1)); n=$((n + 1)); continue\n'))
PY
P="$TMP/p10t"; mkprod "$P" B "$TW"; regf "$P" "$(v c1)" "$(v c3) # gate-only"; commit "$P"; rsh "$P" --gate --ci
[[ "$OUT" == *"REGRESS 2/2"* ]] || { ok=0; echo "  red twin did not go red: a --ci counting skips as passes did not report 2/2"; }
t AC10 "$ok" "--ci skips '# gate-only' lines (named, counted, never passed) and scores the rest; gate mode runs them; adding the marker to a committed line is BLOCKED; control-line.yml has a separate regress job (red twin: skips counted as passes)"

# ---- E1  cost -----------------------------------------------------------------------------------------------------
P="$TMP/e1"; mkprod "$P" S4
python3 - "$P/docs/cascade/envelope.md" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(s.replace("## Locked decisions\n\n<EDIT>\n", "## Locked decisions\n\n<EDIT>\n- GOAL_CARRY_MAX: 100\n", 1))
PY2
acc=()
for s in S1 S2 S3 S4; do
  for i in $(seq 1 15); do acc+=("sleep 0.2 # $s-$i"); done
  goal "$P" "$s" "${acc[@]}"; commit "$P" "$s"
done
s0=$SECONDS; o="$(cd "$P" && bash tests/loop.sh 2>&1)"; t_before=$((SECONDS - s0))
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: S5\n' > "$P/docs/cascade/hop-state.md"; commit "$P" S5
( cd "$P" && bash tests/goal.sh reset >/dev/null 2>&1 && echo 'VALIDATOR: sleep 0.2 # S5-1' >> docs/cascade/goal.md )
s0=$SECONDS; ( cd "$P" && bash tests/loop.sh >/dev/null 2>&1 ); t_after=$((SECONDS - s0))
s0=$SECONDS; ( cd "$P" && bash tests/regress.sh >/dev/null 2>&1 ); t_reg=$((SECONDS - s0))
echo "E1    a 60-line goal over 4 slices: loop $(grep -c '^PASS' <<<"$o") lines in ${t_before}s before reset; 1 line in ${t_after}s after; the suite holds $(nreg "$P") lines, ${t_reg}s once per merge"

echo
[[ "$fail" -eq 0 ]] && echo "T78 AC all PASS" || echo "T78 AC FAILED"
exit "$fail"
