#!/usr/bin/env bash
# AC tests for 05b t77-goal-hygiene: a goal is one hop's definition of done. A goal written for another slice is
# refused; validators carried over from earlier slices' goals are counted on every pass and refused above a cap;
# one helper resets the goal; new installs start from a template that runs nothing.
# "Ran" is counted from the tree (each validator appends to a counter file), never from the printed line.
#   AC1  GOAL_SLICE names another slice: LOOP REFUSED naming both and the helper, exit 3, nothing ran. Equal, absent
#        and the <slice slug> placeholder run as before.
#   AC2  the notice: "2 of 5 … (A), 1 standing"; no earlier slice, no notice. RED TWIN: counting law checks says 3.
#   AC3  goal.sh reset writes the template for this hop and says what it removed; one validator added runs to 1/1;
#        goal.sh show runs nothing.
#   AC4  install seeds goal.md from the template (no validator) and keeps an existing goal.md.
#        RED TWIN: seeding from the pack's goal.md ships its live validators.
#   AC5  a goal for this slice with nothing carried prints what the pre-t77 loop printed, byte for byte.
#   AC6  2.8.0 in VERSION, plugin.json and marketplace.json; CHANGELOG has the 2.8.0 section with t77.
#   AC7  the cap: 11 carried > 10 refused before anything runs; a committed, signed GOAL_CARRY_MAX: 11 runs; signed
#        in the working copy only or as a {{…}} line, refused; a late '# standing' still counts; a marker in a goal
#        that predates the convention does not; a shallow clone says the cap was not checked.
#        RED TWIN: a counter without the late-marker guard runs with 11 carried.
#   E1   goal_history.py on this repo's own history: wall time, reported.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_LOOP_RUNNER
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BASELINE=f984625     # the last tree before t77's code (tests/ and install.sh equal to main's)
export CNT="$TMP/cnt"

mkprod() {  # mkprod <dir> <current slice> [tests dir] [envelope body] — a product with no goal yet
  local d="$1" slice="$2" tdir="${3:-$ROOT/tests}" laws="${4:-}"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$tdir/lib" "$d/tests/lib"; cp "$tdir/loop.sh" "$d/tests/"
  [[ -f "$tdir/goal.sh" ]] && cp "$tdir/goal.sh" "$d/tests/"
  [[ -f "$ROOT/docs/cascade/goal.template.md" ]] && cp "$ROOT/docs/cascade/goal.template.md" "$d/docs/cascade/"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: %s\n' "$slice" > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n\n## Locked decisions\n\n<EDIT>\n</EDIT>\n' "$laws" \
    > "$d/docs/cascade/envelope.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main )
}
goal() {  # goal <dir> <slice or -> <validator…> — write the goal (slice "-" = no GOAL_SLICE line)
  local d="$1" slice="$2"; shift 2
  { echo '# /goal'; echo; echo '```'; echo 'GOAL_STAGE: 05b'
    [[ "$slice" != - ]] && echo "GOAL_SLICE: $slice"
    for v in "$@"; do echo "VALIDATOR: $v"; done; echo '```'; } > "$d/docs/cascade/goal.md"
}
commit() { ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm "${2:-c}" ); }
loop() {  # loop <dir> [args…] -> $OUT, $RC, $RAN (validators that ran)
  local d="$1"; shift
  rm -rf "$CNT"; mkdir -p "$CNT"; : > "$CNT/ran"
  OUT="$(cd "$d" && bash tests/loop.sh "$@" 2>&1)"; RC=$?
  RAN="$(grep -c . "$CNT/ran" | tr -d ' ')"
}
v() { printf 'echo %s >> "$CNT/ran"' "$1"; }                     # a validator that leaves a mark
vs() { local o=(); for i in $(seq "$1" "$2"); do o+=("$(v "v$i")"); done; printf '%s\n' "${o[@]}"; }
LINT="$(v lint) # standing"
LAW='### D1 — the fixture law
check:  echo law >> "$CNT/ran"
break:  false'
LAWV='echo law >> "$CNT/ran"'

# ---- AC1  a goal for another slice ------------------------------------------------------------------------------
ok=1
P="$TMP/p1"; mkprod "$P" new; goal "$P" old "$(v a)"; commit "$P"
loop "$P"
[[ "$RC" -eq 3 && "$OUT" == *"LOOP REFUSED: docs/cascade/goal.md is for slice old, this hop is new"* \
   && "$OUT" == *"bash tests/goal.sh reset"* && "$RAN" -eq 0 ]] \
  || { ok=0; echo "  another slice's goal was not refused before anything ran (rc $RC, ran $RAN):"; echo "$OUT" | head -5 | sed 's/^/      /'; }
for s in new - '<slice slug>'; do
  goal "$P" "$s" "$(v a)"; loop "$P"
  [[ "$RC" -eq 0 && "$RAN" -eq 1 && "$OUT" != *"is for slice"* ]] \
    || { ok=0; echo "  GOAL_SLICE '$s' did not run as before (rc $RC, ran $RAN)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
done
t AC1 "$ok" "a goal naming another slice is refused (both named, the helper named, exit 3, nothing ran); the same slice, no GOAL_SLICE and the placeholder run as before"

# ---- AC2  the notice ------------------------------------------------------------------------------------------------
ok=1
mk2() {  # mk2 <dir> [goal_history.py to use] — A's goal, then B's
  mkprod "$1" B "$ROOT/tests" "$LAW"
  [[ -n "${2:-}" ]] && cp "$2" "$1/tests/lib/goal_history.py"
  goal "$1" A "$(v v1)" "$(v v2)" "$LINT" "$LAWV"; commit "$1" A
  goal "$1" B "$(v v1)" "$(v v2)" "$(v v3)" "$LINT" "$LAWV"; commit "$1" B
}
P="$TMP/p2"; mk2 "$P"; loop "$P"
want="goal: 2 of 5 validators were in earlier slices' goals (A), 1 standing — move the 2 to the project's CI or a law (USAGE.md §B16)"
[[ "$RC" -eq 0 && "$RAN" -eq 5 ]] && grep -qxF "$want" <<<"$OUT" \
  || { ok=0; echo "  the notice is not '$want' (rc $RC, ran $RAN):"; grep '^goal' <<<"$OUT" | sed 's/^/      /'; }
P="$TMP/p2b"; mkprod "$P" B "$ROOT/tests" "$LAW"
goal "$P" B "$(v v1)" "$(v v2)" "$LINT" "$LAWV"; commit "$P"; loop "$P"
[[ "$RC" -eq 0 ]] && ! grep -q '^goal:' <<<"$OUT" || { ok=0; echo "  a goal with no earlier slice printed a notice:"; grep '^goal' <<<"$OUT" | sed 's/^/      /'; }
# red twin: a counter that treats a law's check as an ordinary line
TW="$TMP/twin2.py"; cp "$ROOT/tests/lib/goal_history.py" "$TW"
python3 - "$TW" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "        if key in laws:\n"
if old not in s: sys.exit("twin: the law exclusion is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "        if False:\n"))
PY
P="$TMP/p2t"; mk2 "$P" "$TW"; loop "$P"
grep -q "^goal: 3 of 5 validators" <<<"$OUT" || { ok=0; echo "  red twin did not go red: a counter of law checks did not report 3"; grep '^goal' <<<"$OUT" | sed 's/^/      /'; }
t AC2 "$ok" "the notice counts carried lines and names their slice, apart from standing lines and law checks; silent with no earlier slice (red twin: counting law checks reports 3)"

# ---- AC3  the helper ------------------------------------------------------------------------------------------------
ok=1
P="$TMP/p3"; mkprod "$P" new; goal "$P" old "$(v a)" "$(v b)" "$(v c)"; commit "$P"
out="$(cd "$P" && bash tests/goal.sh reset 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"removed 3 validators"* ]] || { ok=0; echo "  goal.sh reset did not say it removed 3 (rc $rc): $out"; }
exp="$(sed -E 's/^GOAL_STAGE:.*/GOAL_STAGE: 05b/; s/^GOAL_SLICE:.*/GOAL_SLICE: new/' "$ROOT/docs/cascade/goal.template.md")"
[[ "$(cat "$P/docs/cascade/goal.md")" == "$exp" ]] || { ok=0; echo "  the reset goal is not the template with this hop's stage and slice"; }
loop "$P"
[[ "$RC" -eq 3 && "$OUT" != *"is for slice"* && "$OUT" == *"no VALIDATOR lines"* && "$RAN" -eq 0 ]] \
  || { ok=0; echo "  a reset goal was refused for its slice, or ran something (rc $RC):"; echo "$OUT" | head -3 | sed 's/^/      /'; }
echo "VALIDATOR: $(v x)" >> "$P/docs/cascade/goal.md"; loop "$P"
[[ "$RC" -eq 0 && "$RAN" -eq 1 && "$OUT" == *"LOOP 1/1"* ]] || { ok=0; echo "  one validator on a reset goal did not run to LOOP 1/1 (rc $RC)"; }
goal "$P" old "$(v a)"; rm -rf "$CNT"; mkdir -p "$CNT"; : > "$CNT/ran"
out="$(cd "$P" && bash tests/goal.sh show 2>&1)"
[[ "$out" == *"is for slice old, this hop is new"* && "$(grep -c . "$CNT/ran")" -eq 0 ]] \
  || { ok=0; echo "  goal.sh show did not name the slice mismatch, or ran a validator: $out"; }
t AC3 "$ok" "goal.sh reset writes the template with this hop's stage and slice and says it removed 3; the loop refuses it only for having no validator; one added runs to LOOP 1/1; goal.sh show names a mismatch and runs nothing"

# ---- AC4  install -----------------------------------------------------------------------------------------------------
ok=1
inst() {  # inst <pack dir> <target>
  mkdir -p "$2"; ( cd "$2" && git init -q )
  ( HOME="$TMP/nohome" bash "$1/install.sh" --no-plugin "$2" >/dev/null 2>&1 )
}
I="$TMP/i4"; inst "$ROOT" "$I"
cmp -s "$I/docs/cascade/goal.md" "$ROOT/docs/cascade/goal.template.md" && [[ -f "$I/docs/cascade/goal.template.md" ]] \
  || { ok=0; echo "  a fresh install's goal.md is not the template, or goal.template.md is missing"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$I/docs/cascade/hop-state.md"
lst="$(cd "$I" && bash tests/loop.sh --list 2>&1)"
grep -qxF 'validator: <none>' <<<"$lst" || { ok=0; echo "  loop.sh --list lists validators on a fresh install:"; grep validator <<<"$lst" | sed 's/^/      /'; }
I2="$TMP/i4b"; mkdir -p "$I2/docs/cascade"; echo '# mine' > "$I2/docs/cascade/goal.md"; inst "$ROOT" "$I2"
[[ "$(cat "$I2/docs/cascade/goal.md")" == '# mine' ]] || { ok=0; echo "  install overwrote an existing goal.md"; }
# red twin: an install.sh that seeds from the pack's own goal.md
TP="$TMP/twinpack"; mkdir -p "$TP"
( cd "$ROOT" && tar --exclude=.git --exclude=.cascade -cf - . ) | tar -xf - -C "$TP"
python3 - "$TP/install.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "seed docs/cascade/goal.md docs/cascade/goal.template.md"
if old not in s: sys.exit("twin: the goal seed is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "seed docs/cascade/goal.md docs/cascade/goal.md"))
PY
I3="$TMP/i4t"; inst "$TP" "$I3"
[[ "$(grep -c '^VALIDATOR:' "$I3/docs/cascade/goal.md")" -gt 0 ]] \
  || { ok=0; echo "  red twin did not go red: seeding from goal.md shipped no live validator"; }
t AC4 "$ok" "a fresh install gets goal.md equal to goal.template.md, and loop.sh --list lists no validator from it; an existing goal.md is kept (red twin: seeding from goal.md ships the pack's live validators)"

# ---- AC5  parity with the pre-t77 loop ----------------------------------------------------------------------------
ok=1
OLD="$TMP/old"; mkdir -p "$OLD"; git -C "$ROOT" archive "$BASELINE" tests | tar -x -C "$OLD"
norm() { sed -E 's/\([0-9]+s\)/(Ns)/g; s/ \([0-9]+s, / (Ns, /g'; }
par() {  # par <tests dir> — the same product, history and goal, run by that loop
  local d="$TMP/p5"; mkprod "$d" B "$1" "$LAW"
  goal "$d" B "$(v v1)" "$LAWV"; commit "$d" B1
  goal "$d" B "$(v v1)" "$(v v2)" "$LINT" "$LAWV"; commit "$d" B2
  loop "$d"; echo "$OUT" | norm; echo "rc=$RC ran=$RAN"
}
before="$(par "$OLD/tests")"; after="$(par "$ROOT/tests")"
[[ "$before" == "$after" ]] || { ok=0; echo "  the loop's output differs from $BASELINE:"; diff <(echo "$before") <(echo "$after") | sed 's/^/      /' | head -20; }
t AC5 "$ok" "a goal for this slice with nothing carried: loop.sh prints what $BASELINE printed, byte for byte (seconds normalised)"

# ---- AC6  release ---------------------------------------------------------------------------------------------------
ok=1
[[ "$(tr -d '[:space:]' < "$ROOT/VERSION")" == 2.8.0 ]] || { ok=0; echo "  VERSION is not 2.8.0"; }
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  python3 - "$ROOT/$j" <<'PY' || { ok=0; echo "  $j does not read 2.8.0"; }
import json, sys
d = json.load(open(sys.argv[1]))
vs = [d.get("version")] + [p.get("version") for p in d.get("plugins", [])] + [d.get("metadata", {}).get("version")]
vs = [v for v in vs if v]
sys.exit(0 if vs and all(v == "2.8.0" for v in vs) else 1)
PY
done
sec="$(awk '/^## 2\.8\.0 — /{on=1; print; next} /^## /{on=0} on' "$ROOT/CHANGELOG.md")"
[[ -n "$sec" && "$sec" == *t77* ]] || { ok=0; echo "  CHANGELOG.md has no '## 2.8.0 — ' section naming t77"; }
t AC6 "$ok" "VERSION, plugin.json and marketplace.json read exactly 2.8.0; CHANGELOG.md has the 2.8.0 section with t77"

# ---- AC7  the cap ---------------------------------------------------------------------------------------------------
ok=1
A11=(); while IFS= read -r l; do A11+=("$l"); done < <(vs 1 11)
A10=(); while IFS= read -r l; do A10+=("$l"); done < <(vs 1 10)
mk7() {  # mk7 <dir> [goal_history.py] — A: v1–v11, B: v1–v12
  mkprod "$1" B
  [[ -n "${2:-}" ]] && cp "$2" "$1/tests/lib/goal_history.py"
  goal "$1" A "${A11[@]}"; commit "$1" A
  goal "$1" B "${A11[@]}" "$(v v12)"; commit "$1" B
}
P="$TMP/p7"; mk7 "$P"; loop "$P"
[[ "$RC" -eq 3 && "$RAN" -eq 0 && "$OUT" == *"LOOP REFUSED: 11 validators were in earlier slices' goals (A), the cap is 10"* \
   && "$OUT" == *"GOAL_CARRY_MAX"* ]] \
  || { ok=0; echo "  11 carried over a cap of 10 was not refused before anything ran (rc $RC, ran $RAN):"; echo "$OUT" | head -4 | sed 's/^/      /'; }
sign() {  # sign <dir> <line> <commit: yes|no>
  python3 - "$1/docs/cascade/envelope.md" "$2" <<'PY'
import sys
p, line = sys.argv[1:3]; s = open(p).read()
open(p, "w").write(s.replace("## Locked decisions\n\n<EDIT>\n", "## Locked decisions\n\n<EDIT>\n" + line + "\n", 1))
PY
  [[ "$3" == yes ]] && commit "$1" sign
}
P="$TMP/p7s"; mk7 "$P"; sign "$P" '- GOAL_CARRY_MAX: 11' yes; loop "$P"
[[ "$RC" -eq 0 && "$RAN" -eq 12 && "$OUT" == *"LOOP 12/12"* ]] || { ok=0; echo "  a committed, signed GOAL_CARRY_MAX: 11 did not let 11 carried run (rc $RC)"; echo "$OUT" | head -3 | sed 's/^/      /'; }
P="$TMP/p7w"; mk7 "$P"; sign "$P" '- GOAL_CARRY_MAX: 11' no; loop "$P"
[[ "$RC" -eq 3 && "$OUT" == *"the cap is 10"* ]] || { ok=0; echo "  a cap signed only in the working copy was honoured (rc $RC)"; }
P="$TMP/p7p"; mk7 "$P"; sign "$P" '- GOAL_CARRY_MAX: 11  {{the cap you sign}}' yes; loop "$P"
[[ "$RC" -eq 3 && "$OUT" == *"the cap is 10"* ]] || { ok=0; echo "  a {{…}} cap line was honoured (rc $RC)"; }
late() {  # late <dir> [goal_history.py] — A: v1–v11 + standing lint; B marks v11 standing after the fact
  mkprod "$1" B
  [[ -n "${2:-}" ]] && cp "$2" "$1/tests/lib/goal_history.py"
  goal "$1" A "${A11[@]}" "$LINT"; commit "$1" A
  goal "$1" B "${A10[@]}" "$(v v11) # standing" "$LINT" "$(v v12)"; commit "$1" B
}
P="$TMP/p7l"; late "$P"; loop "$P"
[[ "$RC" -eq 3 && "$OUT" == *"LOOP REFUSED: 11 validators"* ]] || { ok=0; echo "  a '# standing' added after the fact got under the cap (rc $RC):"; echo "$OUT" | head -3 | sed 's/^/      /'; }
P="$TMP/p7n"; mkprod "$P" B
goal "$P" A "${A10[@]}" "$(v lint)"; commit "$P" A
goal "$P" B "${A10[@]}" "$LINT" "$(v v12)"; commit "$P" B; loop "$P"
[[ "$RC" -eq 0 && "$RAN" -eq 12 ]] && grep -q "^goal: 10 of 12 validators were in earlier slices' goals (A), 1 standing" <<<"$OUT" \
  || { ok=0; echo "  a marker in a goal that predates the convention was counted as carried (rc $RC):"; grep '^goal\|REFUSED' <<<"$OUT" | sed 's/^/      /'; }
SH="$TMP/p7c"; git clone -q --depth 1 "file://$TMP/p7" "$SH" 2>/dev/null; loop "$SH"
[[ "$OUT" == *"goal: history unreadable, carry cap not checked"* && "$OUT" != *"the cap is"* && "$RAN" -eq 12 ]] \
  || { ok=0; echo "  a shallow clone did not say the cap was not checked (rc $RC, ran $RAN):"; grep '^goal\|REFUSED' <<<"$OUT" | sed 's/^/      /'; }
# red twin: a counter without the late-marker guard
TW="$TMP/twin7.py"; cp "$ROOT/tests/lib/goal_history.py" "$TW"
python3 - "$TW" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "            if late_marker(key, older):\n"
if old not in s: sys.exit("twin: the late-marker guard is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "            if False:\n"))
PY
P="$TMP/p7t"; late "$P" "$TW"; loop "$P"
[[ "$RC" -eq 0 ]] || { ok=0; echo "  red twin did not go red: without the guard the late marker was still refused (rc $RC)"; }
t AC7 "$ok" "11 carried over the default cap of 10 is refused before anything runs; a committed, signed GOAL_CARRY_MAX: 11 runs; working-copy-only and {{…}} caps are ignored; a late '# standing' still counts, a marker that predates the convention does not; a shallow clone says the cap was not checked (red twin: no late-marker guard)"

# ---- E1  cost ---------------------------------------------------------------------------------------------------------
s0="$(python3 -c 'import time; print(time.time())')"
vers="$(python3 -B "$ROOT/tests/lib/goal_history.py" "$ROOT" "$ROOT/docs/cascade/goal.md" __none__ "$ROOT/docs/cascade/envelope.md" --versions </dev/null 2>/dev/null)"
s1="$(python3 -c 'import time; print(time.time())')"
echo "E1    goal_history.py on this repo: ${vers:-?} goal versions read in $(python3 -c "print(f'{$s1-$s0:.2f}')")s"

echo
[[ "$fail" -eq 0 ]] && echo "T77 AC all PASS" || echo "T77 AC FAILED"
exit "$fail"
