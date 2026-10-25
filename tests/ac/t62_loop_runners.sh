#!/usr/bin/env bash
# AC tests for 05b t62-loop-runners: a faster loop for Gradle products that never reports a verdict the line
# run alone would not. Gradle is a stub here (tests/ac/fixtures/gradlew-stub.py), so this runs without a JVM;
# tests/stress/gradle_runner.sh checks the same claims against real Gradle.
#   AC1   exact mode: one build per wave; signed merge: one build, and a second pass is UP-TO-DATE.
#         RED TWIN: BDD_LOOP_RUNNER=shell makes one invocation per line.
#   AC2   every line's verdict equals its verdict run alone (BDD_LOOP_RUNNER=shell), across the matrix.
#         RED TWINS: the runner without surely(i), without the failure-count check, without the D# exclusion,
#         and a runner that prints PASS for every line, must each make a verdict differ.
#   AC3   lines the runner does not prove run through loop.sh's own eval; a crashing or lying-format runner
#         only makes lines run alone.
#   AC3b  only a signed envelope line turns merging on.
#   AC4   shell-only goals: PASS/FAIL/LOOP lines, exit code and receipt equal 2.5.0's loop.sh; FAIL detail capped.
#   AC5   upgrade by install.sh keeps product files; AC5b: the plugin's SessionStart refresh, and every refusal.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_LOOP_RUNNER BDD_PLUGIN_ROOT BDD_AUTO_REFRESH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$ROOT/tests/ac/fixtures/gradlew-stub.py"
OLD_LOOP="$ROOT/tests/ac/fixtures/loop-2.5.0.sh"

# The fixture build, mirroring this hop's real Gradle probe. `select` holds what real Gradle 8.14.3 selected
# for each pattern (recorded in docs/cascade/05b-t62-loop-runners.md §2), not what the runner would compute.
scenario() {  # scenario <dir> [python statements editing `s`]
  python3 - "$1/gradle-stub.json" "${2:-}" <<'PY'
import json, sys
core = ["com.x.core.BalanceTest#one()", "com.x.core.BalanceTest#two()", "com.x.core.LedgerTest#one()",
        "com.x.core.LedgerTest#two()", "com.x.core.BalanceSpec#balanceTest()", "com.x.core.BalanceSpec#other()",
        "com.x.core.BalanceSpec$Inner#deep()", "com.x.core.LedgerTest#adds two"]
s = {"tasks": {
        ":core:compileJava": {},
        ":core:test": {"test": True, "deps": [":core:compileJava"], "tests": core},
        ":app:compileJava": {"deps": [":core:compileJava"]},
        ":app:test": {"test": True, "deps": [":app:compileJava"], "tests": ["com.x.app.CheckoutTest#ok()", "com.x.app.RefundTest#ok()"]},
        ":app:check": {"deps": [":app:test"]}},
     "select": {
        "com.x.core.BalanceTest": core[0:2], "BalanceTest": core[0:2],
        "com.x.core.LedgerTest": core[2:4] + [core[7]],
        "com.x.core.NoSuchTest": [],
        "com.x.core.BalanceSpec": core[4:7], "*BalanceSpec": core[4:7],
        "*Test": [core[4], *core[0:4], "com.x.app.CheckoutTest#ok()", "com.x.app.RefundTest#ok()"],
        "com.x.app.CheckoutTest": ["com.x.app.CheckoutTest#ok()"], "*RefundTest": ["com.x.app.RefundTest#ok()"]}}
T = s["tasks"]
exec(sys.argv[2])
json.dump(s, open(sys.argv[1], "w"), indent=1)
PY
}

mkprod() {  # mkprod <dir> [envelope body]  — a Gradle product with BDD's loop, on an EXECUTE hop
  local d="$1"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/gradle/wrapper"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/loop.sh" "$d/tests/loop.sh"; cp "$OLD_LOOP" "$d/tests/loop-2.5.0.sh"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n\n%s\n' "${2:-}" > "$d/docs/cascade/envelope.md"
  printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip\n' > "$d/gradle/wrapper/gradle-wrapper.properties"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\nbroken\n' > "$d/.gitignore"
  scenario "$d"
  ( cd "$d" && git init -q && git add -A && git commit -qm init )
}
goal() {  # goal <dir> <line>...
  local d="$1"; shift
  { printf 'GOAL_STAGE: 05b\nGOAL_SLICE: x\n'; printf 'VALIDATOR: %s\n' "$@"; } > "$d/docs/cascade/goal.md"
}
reset() { rm -rf "$1/.gradle" "$1"/*/build "$1/build" "$1/.cascade" "$1/broken"; }
loop() {  # loop <dir> [VAR=value...] -> stdout in $OUT, rc in $RC, stub invocations in $CALLS
  local d="$1"; shift
  : > "$TMP/calls"
  OUT="$(cd "$d" && env STUB_COUNT="$TMP/calls" "$@" bash tests/loop.sh 2>&1)"; RC=$?
  CALLS="$(wc -l < "$TMP/calls" | tr -d ' ')"
}
verdicts() { grep -E '^(PASS|FAIL)  |^LOOP [0-9]+/[0-9]+$' <<<"$1"; }
same() {  # same <dir> [VAR=value...] — runner verdicts equal shell verdicts; prints the difference if not
  local d="$1"; shift
  reset "$d"; loop "$d" BDD_LOOP_RUNNER=shell; local a b ra="$RC"; a="$(verdicts "$OUT")"
  reset "$d"; loop "$d" "$@"; b="$(verdicts "$OUT")"
  [[ "$a" == "$b" && "$ra" == "$RC" ]] && return 0
  diff <(echo "$a"; echo "rc=$ra") <(echo "$b"; echo "rc=$RC") | sed 's/^/      /' >&2
  return 1
}
SIGNED='<EDIT>
- LOOP_GRADLE_MERGE: on — locked 2026-10-19 — reason: tests
</EDIT>'
LAW='### D1 — the ledger stays balanced
check:  ./gradlew :core:test --tests com.x.core.LedgerTest
break:  false'

G6=("./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :core:test --tests com.x.core.LedgerTest"
    "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :app:test --tests '*RefundTest'"
    "./gradlew :app:compileJava" "./gradlew :core:compileJava")

# ---- AC1 ----------------------------------------------------------------------------------------------
P="$TMP/ac1"; mkprod "$P"; goal "$P" "${G6[@]}"
ok=1
reset "$P"; loop "$P"
[[ "$RC" -eq 0 && "$CALLS" -eq 2 ]] || { ok=0; echo "  exact mode: rc=$RC, $CALLS builds (want 0, 2)"; }
grep -q '^loop: 6 lines — 6 proven in 2 gradle build' <<<"$OUT" || { ok=0; echo "  no summary line: $(grep '^loop:' <<<"$OUT")"; }
reset "$P"; loop "$P" BDD_LOOP_RUNNER=shell
[[ "$CALLS" -eq 6 ]] || { ok=0; echo "  red twin: shell mode made $CALLS invocations, not 6"; }
P2="$TMP/ac1m"; mkprod "$P2" "$SIGNED"; goal "$P2" "${G6[@]}"
reset "$P2"; loop "$P2"
[[ "$RC" -eq 0 && "$CALLS" -eq 1 ]] || { ok=0; echo "  merged: rc=$RC, $CALLS builds (want 0, 1)"; }
loop "$P2"
[[ "$RC" -eq 0 && "$CALLS" -eq 1 ]] && grep -q $':core:test\tUP-TO-DATE' "$P2/.cascade/gradle/outcomes.tsv" \
  && grep -q $':app:test\tUP-TO-DATE' "$P2/.cascade/gradle/outcomes.tsv" || { ok=0; echo "  merged second pass was not UP-TO-DATE"; }
t AC1 "$ok" "exact: 2 builds for 6 lines in 2 waves; signed merge: 1 build, UP-TO-DATE on the next pass; shell: 6"

# ---- AC2 ----------------------------------------------------------------------------------------------
ok=1
P="$TMP/ac2"; mkprod "$P"; P2="$TMP/ac2m"; mkprod "$P2" "$SIGNED"; P3="$TMP/ac2law"; mkprod "$P3" "$SIGNED
$LAW"
case2() {  # case2 <name> <scenario edit> <line>...  — identical verdicts in exact and in merged mode
  local name="$1" edit="$2"; shift 2
  for d in "$P" "$P2"; do
    scenario "$d" "$edit"; goal "$d" "$@"
    same "$d" || { ok=0; echo "  $name ($(basename "$d")): verdicts differ from running each line alone"; }
  done
}
case2 "all pass" "" "${G6[@]}"
case2 "failing test, unshared task" "T[':app:test']['failing']=['com.x.app.RefundTest#ok()']" "${G6[@]}"
case2 "failing display-name test a *-line could select" "T[':core:test']['failing']=['com.x.core.LedgerTest#adds two']" \
  "./gradlew :core:test --tests com.x.core.LedgerTest" "./gradlew :core:test --tests '*BalanceSpec'" "./gradlew :app:compileJava"
case2 "compile error upstream" "T[':core:compileJava']['fail']=True" "${G6[@]}"
case2 "empty filter next to a match" "" "./gradlew :core:test --tests com.x.core.BalanceTest" \
  "./gradlew :core:test --tests com.x.core.NoSuchTest" "./gradlew :app:test --tests com.x.app.CheckoutTest"
case2 "filtered next to unfiltered, empty" "T[':core:test']['failing']=['com.x.core.LedgerTest#one()']" \
  "./gradlew :core:test" "./gradlew :core:test --tests com.x.core.NoSuchTest" \
  "./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :app:test --tests com.x.app.CheckoutTest"
case2 "test JVM crash" "T[':core:test']['crash']=True" "${G6[@]}"
case2 "ignoreFailures" "T[':app:test']['ignoreFailures']=True; T[':app:test']['failing']=['com.x.app.RefundTest#ok()']" "${G6[@]}"
case2 "failOnNoMatchingTests=false" "T[':core:test']['failOnNoMatchingTests']=False" \
  "./gradlew :core:test --tests com.x.core.NoSuchTest" "./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :app:compileJava"
case2 "unknown task" "" "./gradlew :core:nope" "${G6[@]}"
case2 "build-level failure" "s['buildFailureIf']=':app:test'; T[':core:test']['failing']=['com.x.core.LedgerTest#one()']" \
  "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :core:test --tests com.x.core.LedgerTest" "./gradlew :core:compileJava"
case2 "check next to filtered test" "T[':app:test']['failing']=['com.x.app.RefundTest#ok()']" \
  "./gradlew :app:check" "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :core:compileJava"
case2 "mixed shell and gradle" "" "true" "${G6[@]}" "false"
case2 "two groups" "" "./gradlew -Pa=1 :core:test --tests com.x.core.BalanceTest" "./gradlew -Pa=1 :app:test --tests com.x.app.CheckoutTest" \
  "./gradlew -Pb=2 :core:compileJava" "./gradlew -Pb=2 :app:compileJava"
case2 "shell operator" "" "./gradlew :core:compileJava && true" "${G6[@]}"
case2 "glob that matches a file" "" "./gradlew :core:test --tests gradle-stub*" "${G6[@]}"
# Order: a line may depend on what an earlier one did. Gradle lines after a shell line are batched only after it.
case2 "a shell line breaks the build before Gradle lines" "T[':core:compileJava']['failIfFile']='broken'" \
  "touch broken" "${G6[@]}"
case2 "a shell line checks for no build output yet" "" "test ! -d core/build" "${G6[@]}" "test -d core/build"
case2 "two segments around a shell line" "T[':core:compileJava']['failIfFile']='broken'" \
  "${G6[0]}" "${G6[2]}" "touch broken" "${G6[1]}" "${G6[3]}"
# Shared-JVM side effect: LedgerTest passes only when BalanceTest runs in the same task. Exact mode keeps the
# alone verdict; merged mode may differ for a plain line (the signed trade-off) but never for a law's check.
POLL="s['pollution']={'com.x.core.LedgerTest':'com.x.core.BalanceTest'}"
SIDE=("./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :core:test --tests com.x.core.LedgerTest"
      "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :app:test --tests '*RefundTest'")
scenario "$P" "$POLL"; goal "$P" "${SIDE[@]}"; same "$P" || { ok=0; echo "  shared-JVM side effect changed an exact-mode verdict"; }
scenario "$P3" "$POLL"; goal "$P3" "${SIDE[@]}"; same "$P3" || { ok=0; echo "  shared-JVM side effect changed a law's verdict under merge"; }
t AC2 "$ok" "every line's verdict equals its verdict run alone, exact and merged, across the matrix (19 cases + side effect)"

twin() {  # twin <dir> <python edit of the runner source> -> the fixture's runner, patched
  python3 - "$1/tests/lib/gradle_runner.py" "$2" <<'PY'
import sys
p, edit = sys.argv[1], sys.argv[2]
s = open(p).read()
old, new = edit.split("=>", 1)
assert old in s, "red twin: anchor not found: " + old
open(p, "w").write(s.replace(old, new))
PY
}
ok=1
R="$TMP/rt1"; mkprod "$R" "$SIGNED"; goal "$R" "./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :core:test --tests com.x.core.NoSuchTest" "./gradlew :app:compileJava"
twin "$R" 'if row["fail_none"] and not any(=>if False and not any('
twin "$R" 'if not executed_own(row, fs, self):=>if False:'   # t79 added a second guard on the same case
same "$R" 2>/dev/null && { ok=0; echo "  red twin without surely(i): the empty filter still matched its alone verdict"; }
R="$TMP/rt2"; mkprod "$R"; scenario "$R" "s['buildFailureIf']=':app:test'; T[':core:test']['failing']=['com.x.core.LedgerTest#one()']"
goal "$R" "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :core:test --tests com.x.core.LedgerTest" "./gradlew :core:compileJava"
twin "$R" 'if failure_count(log) != =>if False and failure_count(log) != '
same "$R" 2>/dev/null && { ok=0; echo "  red twin without the failure-count check: the build-level failure went unseen"; }
R="$TMP/rt3"; mkprod "$R" "$SIGNED
$LAW"; scenario "$R" "$POLL"; goal "$R" "${SIDE[@]}"
twin "$R" 'lines[i].strip() in checks]=>False]'
twin "$R" 'rest = [(i, p) for i, p in items if lines[i].strip() not in checks]=>rest = list(items)'
same "$R" 2>/dev/null && { ok=0; echo "  red twin without the D# exclusion: the law's check still ran alone"; }
R="$TMP/rt4"; mkprod "$R"; scenario "$R" "T[':app:test']['failing']=['com.x.app.RefundTest#ok()']"; goal "$R" "${G6[@]}"
printf 'import sys\nfor l in sys.stdin:\n    p = l.split("\\t")\n    if p[0] == "V": print(p[1] + "\\tPASS\\tlie")\n' > "$R/tests/lib/gradle_runner.py"
same "$R" 2>/dev/null && { ok=0; echo "  red twin: a runner that passes every line went unnoticed"; }
t AC2-twins "$ok" "without surely(i), the failure-count check or the D# exclusion, or with a lying runner, a verdict differs"

# ---- AC3 ----------------------------------------------------------------------------------------------
ok=1
P="$TMP/ac3"; mkprod "$P"
goal "$P" "false | true" "cascade_root >/dev/null" "${G6[@]}"
reset "$P"; loop "$P"; new="$(verdicts "$OUT")"
reset "$P"; OUT="$(cd "$P" && bash tests/loop-2.5.0.sh 2>&1)"; old="$(verdicts "$OUT")"
[[ "$new" == "$old" ]] || { ok=0; echo "  pipefail / sourced-function lines differ from 2.5.0"; }
cp "$P/tests/lib/gradle_runner.py" "$TMP/runner.keep"
printf 'raise SystemExit(5)\n' > "$P/tests/lib/gradle_runner.py"
same "$P" || { ok=0; echo "  a crashing runner changed a verdict"; }
printf 'print("garbage")\nprint("99\\tPASS\\tnot sent")\nprint("2\\tFAIL\\tno")\nprint("3\\tpass\\tlower-case")\n' > "$P/tests/lib/gradle_runner.py"
scenario "$P" "T[':core:compileJava']['fail']=True"
same "$P" || { ok=0; echo "  a runner's FAIL, unknown index or garbage was honoured"; }
cp "$TMP/runner.keep" "$P/tests/lib/gradle_runner.py"
t AC3 "$ok" "unproven lines run through loop.sh's own eval (pipefail, sourced helpers); a crashing or garbled runner only makes lines run alone"

# ---- AC3b ---------------------------------------------------------------------------------------------
ok=1
P="$TMP/ac3b"; mkprod "$P"; goal "$P" "${G6[@]}"
envelope() { printf '%s\n' "$2" > "$P/docs/cascade/envelope.md"; [[ "$1" == commit ]] && git -C "$P" commit -qam envelope; return 0; }
builds() {  # builds <label> <want>
  reset "$P"; loop "$P"; [[ "$CALLS" -eq "$2" ]] || { ok=0; echo "  $1: $CALLS builds, want $2"; }
}
reset "$P"; loop "$P" BDD_LOOP_RUNNER=merge; [[ "$CALLS" -eq 2 ]] || { ok=0; echo "  BDD_LOOP_RUNNER=merge merged ($CALLS builds)"; }
envelope commit '# envelope
- LOOP_GRADLE_MERGE: on — unsigned, outside EDIT'; builds "an unsigned line" 2
envelope commit '<EDIT>
- LOOP_GRADLE_MERGE: on — locked {{date}} — reason: {{why}}
</EDIT>'; builds "the template line" 2
envelope no "$SIGNED"; builds "a signed but uncommitted line" 2
envelope commit "$SIGNED"; builds "the signed, committed line" 1
envelope commit '<EDIT>
- LOOP_GRADLE_MERGE: on — locked 2026-10-01 — reason: speed
- LOOP_GRADLE_MERGE: off — locked 2026-10-19 — reason: flaky order
</EDIT>'; builds "on, then a later off" 2
envelope commit '<EDIT>
- LOOP_GRADLE_MERGE: on-hold — reason: undecided
</EDIT>'; builds "on-hold" 2
t AC3b "$ok" "only a committed '- LOOP_GRADLE_MERGE: on' inside <EDIT>, as the last such line, merges; no env var, unsigned, uncommitted, template, later 'off' or 'on-hold' does"

# ---- AC4 ----------------------------------------------------------------------------------------------
ok=1
P="$TMP/ac4"; mkprod "$P" 'D1 | a law | true | false'
cmp_old() {  # cmp_old <label> — new loop.sh vs 2.5.0's on the same tree: contract lines, exit code, receipt
  local a b ra rb ca cb
  reset "$P"; a="$(cd "$P" && bash tests/loop-2.5.0.sh 2>&1)"; ra=$?; ca="$(cat "$P/.cascade/loop-receipt" 2>/dev/null)"
  reset "$P"; b="$(cd "$P" && bash tests/loop.sh 2>&1)"; rb=$?; cb="$(cat "$P/.cascade/loop-receipt" 2>/dev/null)"
  local re='^(PASS|FAIL|WAIVED|LOOP|LOOP REFUSED|not n/n|Hop edge)'
  [[ "$(grep -E "$re" <<<"$a")" == "$(grep -E "$re" <<<"$b")" && "$ra" == "$rb" && "$ca" == "$cb" ]] \
    || { ok=0; echo "  $1: differs from 2.5.0"; diff <(grep -E "$re" <<<"$a"; echo "rc=$ra $ca") <(grep -E "$re" <<<"$b"; echo "rc=$rb $cb") | sed 's/^/      /'; }
}
goal "$P" "true" "true"; cmp_old "law listed, n/n, receipt"
goal "$P" "echo x" "false"; cmp_old "law omitted"
goal "$P" "true" "false"; printf 'WAIVE_DSHARP: D1 waived for this test\n' >> "$P/docs/cascade/goal.md"; cmp_old "waived, one failing"
goal "$P" "true" "true"; printf 'VALIDATOR: true\r\n' >> "$P/docs/cascade/goal.md"; cmp_old "CRLF"
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\n\nD1 | a law | true | false\n' > "$P/docs/cascade/envelope.md"; rm -f "$P/docs/cascade/hop-state.md"
goal "$P" "true" "true"; cmp_old "pre-split envelope"
goal "$P" "python3 -c 'print((\"x\" * 500 + \"\\n\") * 400)'; false" "true"
reset "$P"; out="$(cd "$P" && bash tests/loop.sh 2>&1)"
detail="$(grep -E '^      ' <<<"$out")"
[[ "$(wc -l <<<"$detail")" -le 25 ]] && ! grep -qE '^.{220,}' <<<"$detail" || { ok=0; echo "  FAIL detail not capped: $(wc -l <<<"$detail") lines"; }
t AC4 "$ok" "shell-only goals print the same contract lines, exit code and receipt as 2.5.0; FAIL detail is capped"

# ---- AC5 / AC5b ---------------------------------------------------------------------------------------
# 2.5.0, extracted from the pack's own history: the real old version, not a simulation of it.
if ! git -C "$ROOT" cat-file -e 4e4d6f2 2>/dev/null; then
  t AC5 0 "the pack's history has no 4e4d6f2 (2.5.0) — this AC needs a full clone"
else
OLD="$TMP/pack250"; mkdir -p "$OLD"; git -C "$ROOT" archive 4e4d6f2 | tar -x -C "$OLD"
PLUG="$TMP/plugin"; mkdir -p "$PLUG"   # this working tree, as a plugin would ship it
( cd "$ROOT" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - ) | tar -xf - -C "$PLUG"
printf 'CURRENT_HOP: NONE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$PLUG/docs/cascade/hop-state.md"
NEWV="$(cat "$ROOT/VERSION")"
# Fixture commits skip the fixture's own git hooks: what is under test here is the SessionStart hook.
gc() { git -C "$1" -c core.hooksPath=/dev/null "${@:2}"; }
old_product() {  # old_product <dir> — a plugin-mode product installed by 2.5.0, committed, with one file of its own
  rm -rf "$1"; mkdir -p "$1"; ( cd "$1" && git init -q && echo notes > notes.txt && git add -A && git commit -qm init )
  ( cd "$1" && BDD_PLUGIN_ROOT="$OLD" bash "$OLD/install.sh" --plugin "$1" >/dev/null 2>&1 ) && gc "$1" add -A && gc "$1" commit -qm 'cascade 2.5.0'
}
start() {  # start <dir> [VAR=value...] -> the SessionStart(startup) context in $CTX
  local d="$1"; shift
  CTX="$(printf '{"cwd":"%s","source":"startup","session_id":"s%s"}' "$d" "$RANDOM$RANDOM" \
    | env BDD_PLUGIN_ROOT="$PLUG" "$@" python3 -B "$PLUG/.claude/hooks/preserve.py")"
}
keepsums() { ( cd "$1" && sha256sum docs/cascade/goal.md docs/cascade/envelope.md docs/cascade/hop-state.md ); }

ok=1
U="$TMP/ac5"; old_product "$U"; before="$(keepsums "$U")"
( cd "$U" && BDD_PLUGIN_ROOT="$PLUG" bash "$PLUG/install.sh" --plugin "$U" >/dev/null 2>&1 )
[[ "$(keepsums "$U")" == "$before" ]] || { ok=0; echo "  install.sh changed a product-owned file"; }
grep -qx '.cascade/loop/' "$U/.gitignore" && grep -qx '.cascade/gradle/' "$U/.gitignore" || { ok=0; echo "  .gitignore entries missing"; }
grep -q gradle_runner "$U/tests/loop.sh" && [[ -f "$U/tests/lib/gradle_runner.py" ]] || { ok=0; echo "  new loop.sh/runner not installed"; }
gc "$U" add -A; gc "$U" commit -qm 'cascade: update'
# The product is a Gradle build (the stub), as a real one ignores its own build output.
mkdir -p "$U/gradle/wrapper"; printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$U/gradlew"; chmod +x "$U/gradlew"
printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip\n' > "$U/gradle/wrapper/gradle-wrapper.properties"
scenario "$U"; printf '.gradle/\nbuild/\n*/build/\n' >> "$U/.gitignore"; gc "$U" add -A; gc "$U" commit -qm gradle
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$U/docs/cascade/hop-state.md"
goal "$U" "${G6[@]}" "false"
( cd "$U" && bash tests/loop.sh >/dev/null 2>&1 ); git -C "$U" checkout -q -- docs
[[ -s "$U/.cascade/gradle/outcomes.tsv" ]] || { ok=0; echo "  the loop pass did not batch the Gradle lines"; }
[[ -z "$(git -C "$U" status --porcelain)" ]] || { ok=0; echo "  a loop pass dirtied the tree: $(git -C "$U" status --porcelain | head -2 | tr '\n' ' ')"; }
t AC5 "$ok" "install.sh over a 2.5.0 product keeps goal/envelope/hop-state, adds the ignores and the runner; a pass leaves the tree clean"

ok=1
U="$TMP/ac5b"; old_product "$U"; before="$(keepsums "$U")"
start "$U"
grep -q "BDD REFRESHED" <<<"$CTX" && grep -q "to $NEWV" <<<"$CTX" || { ok=0; echo "  clean idle repo not refreshed: ${CTX:0:200}"; }
grep -q 'CASCADE CONTROL LINE' <<<"$CTX" && { ok=0; echo "  startup re-injected the control line"; }
[[ "$(keepsums "$U")" == "$before" ]] || { ok=0; echo "  refresh changed a product-owned file"; }
[[ "$(sed -n 's/^version //p' "$U/.cascade/manifest")" == "$NEWV" ]] && grep -q gradle_runner "$U/tests/loop.sh" || { ok=0; echo "  refresh did not land $NEWV"; }
( cd "$U" && bash "$PLUG/install.sh" --check . >/dev/null 2>&1 ) || { ok=0; echo "  install.sh --check is not clean after the refresh"; }
start "$U"; [[ -z "$CTX" ]] || { ok=0; echo "  startup printed something with versions in sync"; }
refused() {  # refused <label> <dir> [VAR=value...] — not refreshed, says why, changed nothing
  local d="$2" label="$1"; shift 2
  local snap; snap="$(cd "$d" && git status --porcelain; git rev-parse HEAD; sed -n 1p .cascade/manifest; sha256sum tests/loop.sh)"
  start "$d" "$@"
  grep -q 'BDD VERSION DRIFT' <<<"$CTX" && grep -q 'not refreshed automatically' <<<"$CTX" || { ok=0; echo "  $label: no refusal line: ${CTX:0:160}"; }
  [[ "$snap" == "$(cd "$d" && git status --porcelain; git rev-parse HEAD; sed -n 1p .cascade/manifest; sha256sum tests/loop.sh)" ]] || { ok=0; echo "  $label: files changed"; }
}
U="$TMP/r1"; old_product "$U"; echo mine >> "$U/notes.txt"; refused "dirty tree" "$U"
U="$TMP/r2"; old_product "$U"; printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: y\n' > "$U/docs/cascade/hop-state.md"
gc "$U" commit -qam hop; refused "open hop" "$U"
U="$TMP/r3"; old_product "$U"; echo "# mine" >> "$U/tests/lib/cascade.sh"; gc "$U" commit -qam mine; refused "edited pack file" "$U"
U="$TMP/r4"; old_product "$U"; sed -i 's/^version .*/version 99.0.0/' "$U/.cascade/manifest"; gc "$U" commit -qam newer; refused "plugin older" "$U"
U="$TMP/r5"; old_product "$U"; refused "opt-out" "$U" BDD_AUTO_REFRESH=0
U="$TMP/r6"; old_product "$U"; mkdir -p "$U/.git/cascade-refresh.lock"; refused "lock held" "$U"
U="$TMP/r7"; old_product "$U"; BROKEN="$TMP/broken"; rm -rf "$BROKEN"; cp -R "$PLUG" "$BROKEN"
printf '#!/usr/bin/env bash\n[[ "$1" == --check ]] && exec bash "%s/install.sh" "$@"\necho half > "$2/tests/loop.sh" && echo new > "$2/tests/stray.sh"\nexit 1\n' "$PLUG" > "$BROKEN/install.sh"
CTX="$(printf '{"cwd":"%s","source":"startup","session_id":"b%s"}' "$U" "$RANDOM" | BDD_PLUGIN_ROOT="$BROKEN" python3 -B "$PLUG/.claude/hooks/preserve.py")"
grep -q 'nothing in this repo was changed' <<<"$CTX" && [[ -z "$(git -C "$U" status --porcelain)" ]] \
  && grep -q '^version 2.5.0' "$U/.cascade/manifest" || { ok=0; echo "  a failed install touched the repo: $(git -C "$U" status --porcelain | head -2 | tr '\n' ' ')"; }
# Another session edits the repo while the refresh is being prepared: the edit survives, nothing is applied.
U="$TMP/r9"; old_product "$U"; RACE="$TMP/raceplug"; rm -rf "$RACE"; cp -R "$PLUG" "$RACE"
printf '#!/usr/bin/env bash\n[[ "$1" != --check ]] && echo concurrent >> "%s/notes.txt"\nexec bash "%s/install.sh" "$@"\n' "$U" "$PLUG" > "$RACE/install.sh"
CTX="$(printf '{"cwd":"%s","source":"startup","session_id":"r%s"}' "$U" "$RANDOM" | BDD_PLUGIN_ROOT="$RACE" python3 -B "$PLUG/.claude/hooks/preserve.py")"
grep -q concurrent "$U/notes.txt" && grep -q '^version 2.5.0' "$U/.cascade/manifest" && grep -q 'changed while the refresh' <<<"$CTX" \
  || { ok=0; echo "  a concurrent edit during the refresh: $(grep -c concurrent "$U/notes.txt") edits kept, manifest $(sed -n 1p "$U/.cascade/manifest"), ${CTX:0:120}"; }
CTX="$(printf '{"cwd":"%s","source":"startup"}' "$TMP/ac5b" | python3 -B "$PLUG/.claude/hooks/preserve.py")"
[[ -z "$CTX" ]] || { ok=0; echo "  startup without a plugin printed something (T15)"; }
# Red twin: without the clean-tree checks, a dirty repo gets the refresh mixed into its uncommitted work.
TWIN="$TMP/twinplug"; rm -rf "$TWIN"; cp -R "$PLUG" "$TWIN"
python3 - "$TWIN/.claude/hooks/preserve.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read()
old = 'if _git(root, "status", "--porcelain").stdout.strip():'
assert s.count(old) == 2; open(p, "w").write(s.replace(old, "if False:"))
PY
U="$TMP/r8"; old_product "$U"; echo mine >> "$U/notes.txt"
CTX="$(printf '{"cwd":"%s","source":"startup","session_id":"t%s"}' "$U" "$RANDOM" | BDD_PLUGIN_ROOT="$TWIN" python3 -B "$TWIN/.claude/hooks/preserve.py")"
grep -q '^version 2.5.0' "$U/.cascade/manifest" && { ok=0; echo "  red twin: without the clean-tree checks the dirty repo was still left alone — the checks prove nothing"; }
t AC5b "$ok" "the plugin refreshes a clean idle 2.5.0 repo at startup; refuses when dirty, mid-hop, edited, older, opted out or locked; a failed install or a concurrent edit leaves the repo untouched"
fi

echo
[[ "$fail" -eq 0 ]] && echo "AC t62 all PASS" || echo "AC t62 FAILED"
exit "$fail"
