#!/usr/bin/env bash
# AC tests for 05b t75-xcode-runner: consecutive `xcodebuild test` lines share one build per build key, each line in
# its own test process, a PASS only from the result bundle; Xcode laws are proven from one build when signed; nothing
# reaches the merge gate. Xcode is the pack's stub (tests/ac/fixtures/xcodebuild-stub.py, replaying E0/E0b);
# tests/stress/xcode_runner.sh makes the same claims on real Xcode. docs/cascade/05b-t75-xcode-runner.md is the contract.
#   AC1  which lines: the §1 shape is batched; every other shape, a lone line, distinct keys and an unverified Xcode
#        run alone.
#   AC2  every verdict equals the line run alone: pass, failing test, compile error, no-match selector, crash, a class
#        that fails only beside another, a hang.
#   AC3  the fingerprint: a source edit between segments rebuilds; no edit reuses; a build that writes into the tree
#        runs its lines alone. RED TWIN: a runner that reuses without comparing fingerprints passes a stale binary.
#   AC4  PASS only from the result bundle. RED TWIN: a proof that reads only the exit code passes a failed bundle.
#   AC5  never merged: two lines of one key are two test runs, whatever the envelope says.
#   AC6  the harness: unsigned is the two commands; signed proves eligible laws GREEN from one build; RED and THEATER
#        keep their own verdicts; DSHARP_HARNESS=off uses none of it. RED TWIN: a harness that skips the check's proof
#        proves a RED law GREEN.
#   AC7  an unprefixed INV_MUTANT twin is THEATER with the reason; TEST_RUNNER_INV_MUTANT is GREEN.
#   AC8  a hang is killed after BDD_XCODE_TIMEOUT, the host is terminated, and the line runs alone.
#   AC9  parity with d89438e without Xcode lines; "xcode build(s)" wording with them; .cascade/xcode/ is ignored.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR CASCADE_ENVELOPE CASCADE_HUMAN \
      DSHARP_CACHE DSHARP_HARNESS DSHARP_JOBS DSHARP_SERIAL INV_MUTANT TEST_RUNNER_INV_MUTANT BDD_LOOP_RUNNER \
      BDD_GRADLE_TUNING BDD_XCODE_TIMEOUT STUB_COUNT STUB_HANG_S
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$ROOT/tests/ac/fixtures/xcodebuild-stub.py"
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nSTUB_AS=xcodebuild exec python3 -B "%s" "$@"\n' "$STUB" > "$BIN/xcodebuild"
printf '#!/bin/sh\nSTUB_AS=xcrun exec python3 -B "%s" "$@"\n' "$STUB" > "$BIN/xcrun"
chmod +x "$BIN/xcodebuild" "$BIN/xcrun"
export PATH="$BIN:$PATH"
BASELINE=d89438e     # main after 2.7.0, the last tree before t75

X() { echo "xcodebuild -project App.xcodeproj -scheme App -destination 'platform=iOS Simulator,id=SIM1' test $*"; }
scenario() {  # scenario <dir> <python dict literal merged into the default>
  local extra="${2:-}"; [[ -n "$extra" ]] || extra='{}'
  python3 - "$1/xcode-stub.json" "$extra" <<'PY'
import ast, json, sys
s = {"version": "27.0",
     "cases": ["AppTests/BalanceTests/testDebit", "AppTests/BalanceTests/testMutant", "AppTests/LedgerTests/testA",
               "AppTests/AaaTouchTests/testShared", "AppTests/ZzzIsolationTests/testNotTouched",
               "AppTests/FailTests/testFails", "AppTests/CrashTests/testCrash", "AppTests/SleepTests/testSleep"],
     "fail": ["AppTests/FailTests/testFails"],
     "failIfSource": {"AppTests/BalanceTests/testDebit": "src/Wallet.swift:BUG"},
     "mutantFails": {"D1": ["AppTests/BalanceTests/testMutant"]},
     "crash": ["AppTests/CrashTests/testCrash"],
     "hang": ["AppTests/SleepTests/testSleep"],
     "pollutedBy": {"AppTests/ZzzIsolationTests/testNotTouched": "AppTests/AaaTouchTests/testShared"}}
s.update(ast.literal_eval(sys.argv[2]))
json.dump(s, open(sys.argv[1], "w"))
PY
}
mkprod() {  # mkprod <dir> [tests dir]
  local d="$1" src="${2:-$ROOT/tests}"
  mkdir -p "$d/docs/cascade" "$d/src"
  rm -rf "$d/tests"; mkdir -p "$d/tests"; cp -R "$src/lib" "$d/tests/lib"; cp "$src/loop.sh" "$src/dsharp_strength.sh" "$d/tests/"
  find "$d/tests" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  [[ -f "$d/docs/cascade/envelope.md" ]] || printf '# envelope\n' > "$d/docs/cascade/envelope.md"
  [[ -f "$d/src/Wallet.swift" ]] || printf 'func debit() {}\n' > "$d/src/Wallet.swift"
  [[ -f "$d/xcode-stub.json" ]] || scenario "$d"
  printf '.cascade/\nDerivedData/\n' > "$d/.gitignore"
  [[ -d "$d/.git" ]] || ( cd "$d" && git init -q )
  commit "$d"
}
commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm fixture >/dev/null 2>&1 || true; }
goal() { local d="$1"; shift; { printf 'GOAL_STAGE: 05b\n'; printf 'VALIDATOR: %s\n' "$@"; } > "$d/docs/cascade/goal.md"; }
loop() {  # loop <dir> [VAR=value…] -> $OUT, $V (verdicts + rc), $CALLS
  local d="$1"; shift
  rm -rf "$d/.cascade/loop"; : > "$TMP/calls"
  OUT="$(cd "$d" && env STUB_COUNT="$TMP/calls" "$@" bash tests/loop.sh 2>&1)"; local rc=$?
  V="$(grep -E '^(PASS|FAIL)  |^LOOP [0-9]' <<<"$OUT"; echo "rc=$rc")"; CALLS="$(cat "$TMP/calls")"
}
nb() { grep -c "build-for-testing" <<<"$CALLS" | tr -d ' '; }          # builds the runner made
nt() { grep -c "test-without-building" <<<"$CALLS" | tr -d ' '; }      # test runs the runner made
same() {  # same <dir> <label> [VAR=value…]: every verdict equals the lines run alone
  local d="$1" label="$2" a; shift 2
  rm -rf "$d/.cascade/xcode"; loop "$d" BDD_LOOP_RUNNER=shell "$@"; a="$V"
  rm -rf "$d/.cascade/xcode"; loop "$d" "$@"
  [[ "$a" == "$V" ]] && return 0
  echo "  $label: verdicts differ from every line alone:"; diff <(echo "$a") <(echo "$V") | sed 's/^/      /'; return 1
}

# ---- AC1  which lines ----------------------------------------------------------------------------------------------
ok=1
P="$TMP/p1"; mkprod "$P"
goal "$P" "$(X -only-testing:AppTests/BalanceTests/testDebit)" "$(X -only-testing:AppTests/LedgerTests)"
loop "$P"
[[ "$(nb)" -eq 1 && "$(nt)" -eq 2 ]] && grep -q 'LOOP 2/2' <<<"$V" && grep -q 'proven in 1 xcode build(s)' <<<"$OUT" \
  || { ok=0; echo "  two lines of one key: $(nb) build(s), $(nt) test run(s), $(grep '^loop:' <<<"$OUT")"; }
alone_shape() {  # alone_shape <label> <line> <line>: no batched build
  goal "$P" "$2" "$3"; loop "$P"
  [[ "$(nb)" -eq 0 ]] || { ok=0; echo "  $1: the runner built ($(nb)) where both lines must run alone"; }
}
alone_shape "build action" "$(X -only-testing:AppTests/LedgerTests) build" "$(X -only-testing:AppTests/LedgerTests)"
alone_shape "derivedDataPath" "$(X -only-testing:AppTests/LedgerTests -derivedDataPath dd)" "$(X -only-testing:AppTests/BalanceTests)"
alone_shape "resultBundlePath" "$(X -only-testing:AppTests/LedgerTests -resultBundlePath r)" "$(X -only-testing:AppTests/BalanceTests)"
alone_shape "generic destination" "xcodebuild -scheme App -destination generic/platform=iOS test" "xcodebuild -scheme App -destination generic/platform=iOS test"
alone_shape "two destinations" "$(X -destination platform=macOS -only-testing:AppTests/LedgerTests)" "$(X -only-testing:AppTests/BalanceTests)"
alone_shape "shell syntax" "$(X -only-testing:AppTests/LedgerTests) && true" "$(X -only-testing:AppTests/BalanceTests)"
alone_shape "different keys" "$(X -only-testing:AppTests/LedgerTests)" "$(X -configuration Release -only-testing:AppTests/BalanceTests)"
goal "$P" "$(X -only-testing:AppTests/LedgerTests)" "echo hi" "$(X -only-testing:AppTests/BalanceTests)"; loop "$P"
[[ "$(nb)" -eq 0 ]] || { ok=0; echo "  a shell line between two lines still let them share a build ($(nb))"; }
scenario "$P" "{'version': '26.4'}"; commit "$P"
goal "$P" "$(X -only-testing:AppTests/LedgerTests)" "$(X -only-testing:AppTests/BalanceTests)"; loop "$P"
[[ "$(nb)" -eq 0 ]] && grep -q 'LOOP 2/2' <<<"$V" || { ok=0; echo "  an unverified Xcode (26.4) still batched ($(nb))"; }
scenario "$P"; commit "$P"
t AC1 "$ok" "two lines of one build key share one build-for-testing and run as two test-without-building calls; a non-test action, -derivedDataPath, -resultBundlePath, a generic or second destination, shell syntax, different keys, a shell line between them, and an unverified Xcode all run alone"

# ---- AC2  the verdict matrix ---------------------------------------------------------------------------------------
ok=1
P2="$TMP/p2"; mkprod "$P2"
mx() { goal "$P2" "$@"; same "$P2" "$label" || ok=0; }
label="all pass";        mx "$(X -only-testing:AppTests/BalanceTests/testDebit)" "$(X -only-testing:AppTests/LedgerTests)"
label="failing test";    mx "$(X -only-testing:AppTests/FailTests)" "$(X -only-testing:AppTests/LedgerTests)"
label="no-match";        mx "$(X -only-testing:AppTests/NoSuchTests)" "$(X -only-testing:AppTests/LedgerTests)"
label="crash";           mx "$(X -only-testing:AppTests/CrashTests)" "$(X -only-testing:AppTests/LedgerTests)"
label="shared-process";  mx "$(X -only-testing:AppTests/AaaTouchTests)" "$(X -only-testing:AppTests/ZzzIsolationTests)"
label="whole target";    mx "$(X -only-testing:AppTests -skip-testing:AppTests/FailTests -skip-testing:AppTests/CrashTests -skip-testing:AppTests/SleepTests -skip-testing:AppTests/ZzzIsolationTests)" "$(X -only-testing:AppTests/LedgerTests)"
scenario "$P2" "{'compileError': True}"; commit "$P2"
label="compile error";   mx "$(X -only-testing:AppTests/LedgerTests)" "$(X -only-testing:AppTests/BalanceTests)"
scenario "$P2"; commit "$P2"
export STUB_HANG_S=3
label="hang";            mx "$(X -only-testing:AppTests/SleepTests)" "$(X -only-testing:AppTests/LedgerTests)"
unset STUB_HANG_S
t AC2 "$ok" "every line's verdict equals the line run alone: pass, failing test, a selector that matches nothing, a crash, a class that fails only beside another (each line its own process), a whole target with skips, a compile error, a hang"

# ---- AC3  the fingerprint ------------------------------------------------------------------------------------------
ok=1
P3="$TMP/p3"; mkprod "$P3"
G5=("$(X -only-testing:AppTests/LedgerTests)" "$(X -only-testing:AppTests/AaaTouchTests)" "EDIT"
    "$(X -only-testing:AppTests/BalanceTests/testDebit)" "$(X -only-testing:AppTests/LedgerTests)")
g5() { local mid="$1"; goal "$P3" "${G5[0]}" "${G5[1]}" "$mid" "${G5[3]}" "${G5[4]}"; }
g5 "echo BUG >> src/Wallet.swift"
rm -rf "$P3/.cascade/xcode"; loop "$P3" BDD_LOOP_RUNNER=shell; a3="$V"; git -C "$P3" checkout -q -- src/Wallet.swift
rm -rf "$P3/.cascade/xcode"; loop "$P3"; git -C "$P3" checkout -q -- src/Wallet.swift
[[ "$a3" == "$V" ]] || { ok=0; echo "  an edit between segments: verdicts differ from every line alone:"; diff <(echo "$a3") <(echo "$V") | sed 's/^/      /'; }
grep -q "^FAIL  ${G5[3]}" <<<"$V" || { ok=0; echo "  X3 should fail after the edit: $(grep testDebit <<<"$V")"; }
[[ "$(nb)" -eq 2 ]] || { ok=0; echo "  an edit between segments: $(nb) build(s), want 2 (a rebuild before X3)"; }
g5 "true"; rm -rf "$P3/.cascade/xcode"; loop "$P3"
[[ "$(nb)" -eq 1 ]] || { ok=0; echo "  nothing edited between segments: $(nb) build(s), want 1 (reused)"; }
# RED TWIN: reuse a build without comparing fingerprints — X3 passes against the stale binary.
cp "$P3/tests/lib/xcode_runner.py" "$TMP/xr.keep"
python3 - "$P3/tests/lib/xcode_runner.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'return bool(fp) and _read(os.path.join(self.dir, "built")) == f"{fp}\\t{self.stamp}" and os.path.isdir('
assert a in s, "anchor"
open(p, "w").write(s.replace(a, 'return bool(fp) and os.path.exists(os.path.join(self.dir, "built")) and os.path.isdir(', 1))
PY
g5 "echo BUG >> src/Wallet.swift"; rm -rf "$P3/.cascade/xcode"; loop "$P3"
grep -q "^PASS  ${G5[3]}" <<<"$V" || { ok=0; echo "  RED TWIN stayed green: a runner ignoring fingerprints still failed X3: $(grep testDebit <<<"$V")"; }
git -C "$P3" checkout -q -- src/Wallet.swift; cp "$TMP/xr.keep" "$P3/tests/lib/xcode_runner.py"
# A build that writes into the tree: one attempt, its lines alone, the reason logged.
scenario "$P3" "{'buildWrites': 'src/Generated.swift'}"; printf '// gen\n' > "$P3/src/Generated.swift"; commit "$P3"
goal "$P3" "${G5[0]}" "${G5[1]}"; rm -rf "$P3/.cascade/xcode"; loop "$P3"
[[ "$(nb)" -eq 1 ]] && grep -q 'changes the worktree' "$P3/.cascade/loop/xcode-runner.log" 2>/dev/null \
  && grep -q 'LOOP 2/2' <<<"$V" || { ok=0; echo "  a self-modifying build: $(nb) build(s), log: $(cat "$P3/.cascade/loop/xcode-runner.log" 2>/dev/null | head -2)"; }
git -C "$P3" checkout -q -- src/Generated.swift; scenario "$P3"; commit "$P3"
t AC3 "$ok" "an edit between two segments forces a rebuild and the verdicts equal the lines alone; no edit reuses the build; a build that writes into the tree is tried once and its lines run alone, logged; a runner that reuses without comparing fingerprints passes a stale binary (red twin)"

# ---- AC4  PASS only from the result bundle -------------------------------------------------------------------------
ok=1
pr() { ( cd "$1/tests/lib" && python3 -B -c '
import xcode_runner as x
p = {"only": ["AppTests/LedgerTests"], "skip": []}
print(x.proven(0, [("AppTests/LedgerTests/testA", "Failed")], p)[0], x.proven(0, None, p)[0], x.proven(0, [], p)[0],
      x.proven(0, [("AppTests/BalanceTests/testDebit", "Passed")], p)[0], x.proven(None, [("AppTests/LedgerTests/testA", "Passed")], p)[0],
      x.proven(0, [("AppTests/LedgerTests/testA", "Passed")], p)[0])' ); }
[[ "$(pr "$P")" == "False False False False False True" ]] || { ok=0; echo "  proven(): $(pr "$P") (want False ×5, then True)"; }
# RED TWIN: a proof that reads only the exit code.
R4="$TMP/p4"; mkdir -p "$R4"; cp -R "$P/tests" "$R4/tests"
python3 - "$R4/tests/lib/xcode_runner.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'def proven(rc: int | None, cases: list | None, p: dict) -> tuple[bool, str]:\n'
assert a in s
open(p, "w").write(s.replace(a, a + '    return rc == 0, ""\n', 1))
PY
[[ "$(pr "$R4")" == "False False False False False True" ]] && { ok=0; echo "  RED TWIN stayed green: an exit-code-only proof was not caught"; }
t AC4 "$ok" "a line is proven only when its result bundle reads, ran a test case, has no failure and only the line's own cases — never from exit 0 alone; a proof that reads only the exit code passes a failed bundle (red twin)"

# ---- AC5  never merged ---------------------------------------------------------------------------------------------
ok=1
printf '# envelope\n\n<EDIT>\n- LOOP_XCODE_MERGE: on — locked 2026-10-23 — reason: AC5\n</EDIT>\n' > "$P/docs/cascade/envelope.md"; commit "$P"
goal "$P" "$(X -only-testing:AppTests/LedgerTests)" "$(X -only-testing:AppTests/BalanceTests)"; rm -rf "$P/.cascade/xcode"; loop "$P"
[[ "$(nt)" -eq 2 ]] && ! grep "test-without-building" <<<"$CALLS" | grep -q 'LedgerTests.*BalanceTests\|BalanceTests.*LedgerTests' \
  || { ok=0; echo "  two lines were merged into one test run:"; grep test-without-building <<<"$CALLS" | sed 's/^/      /'; }
printf '# envelope\n' > "$P/docs/cascade/envelope.md"; commit "$P"
t AC5 "$ok" "two lines of one key are always two test-without-building calls, each with only its own selectors, even with a signed LOOP_XCODE_MERGE line (no such switch exists)"

# ---- AC6  the harness ----------------------------------------------------------------------------------------------
ok=1
P6="$TMP/p6"; mkprod "$P6"
CHK="$(X -only-testing:AppTests/BalanceTests/testMutant)"
REDC="$(X -only-testing:AppTests/FailTests)"
THC="$(X -only-testing:AppTests/LedgerTests)"
laws6() {  # laws6 [signed] -> envelope with D1 GREEN, D2 RED, D3 THEATER
  { printf '# envelope\n\n<EDIT>\n'
    [[ "${1:-}" == signed ]] && printf -- '- DSHARP_XCODE_HARNESS: on — locked 2026-10-23 — reason: AC6\n'
    printf '### D1 — green\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D1 %s\n\n' "$CHK" "$CHK"
    printf '### D2 — red\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D2 %s\n\n' "$REDC" "$REDC"
    printf '### D3 — theater\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D3 %s\n' "$THC" "$THC"
    printf '</EDIT>\n'; } > "$P6/docs/cascade/envelope.md"; commit "$P6"
}
ds() { : > "$TMP/calls"; DS="$(cd "$P6" && env STUB_COUNT="$TMP/calls" "$@" bash tests/dsharp_strength.sh 2>&1)"; CALLS="$(cat "$TMP/calls")"; }
want6='GREEN     D1  green
RED       D2  red  — validator failed: '"$REDC"'
THEATER   D3  theater  — red twin passed, validator cannot fail: TEST_RUNNER_INV_MUTANT=D3 '"$THC"'
DSHARP 1/3'
laws6; ds
[[ "$(grep -E '^(GREEN|RED|THEATER|DSHARP)' <<<"$DS")" == "$want6" && "$(nb)" -eq 0 ]] \
  || { ok=0; echo "  unsigned: $(nb) harness build(s); verdicts:"; sed 's/^/      /' <<<"$DS"; }
laws6 signed; rm -rf "$P6/.cascade/xcode"; ds
[[ "$(grep -E '^(GREEN|RED|THEATER|DSHARP)' <<<"$DS")" == "$want6" && "$(nb)" -eq 1 ]] \
  || { ok=0; echo "  signed: $(nb) build(s) (want 1); verdicts:"; sed 's/^/      /' <<<"$DS"; }
grep -E ' test -only-testing:AppTests/BalanceTests/testMutant$' <<<"$CALLS" | grep -qv test-without-building \
  && { ok=0; echo "  signed: D1's own check ran too — the harness proved nothing"; }
grep -q "^0	D1	GREEN" "$P6/.cascade/laws/xcode-harness.tsv" 2>/dev/null || { ok=0; echo "  the harness did not prove D1: $(cat "$P6/.cascade/laws/xcode-harness.tsv" 2>/dev/null)"; }
rm -rf "$P6/.cascade/xcode"; ds DSHARP_HARNESS=off
[[ "$(nb)" -eq 0 ]] || { ok=0; echo "  DSHARP_HARNESS=off (the merge gate) still used the harness"; }
# RED TWIN: a harness that skips the check's proof proves RED D2 GREEN (its mutant fails too).
cp "$P6/tests/lib/xcode_harness.py" "$TMP/xh.keep"
python3 - "$P6/tests/lib/xcode_harness.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '        ok, why = xr.proven(rc_c, cases_c, p)\n'
assert a in s
open(p, "w").write(s.replace(a, '        ok, why = True, ""\n', 1))
PY
python3 - "$P6/xcode-stub.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); s["mutantFails"]["D2"] = ["AppTests/FailTests/testFails"]; json.dump(s, open(sys.argv[1], "w"))
PY
commit "$P6"; rm -rf "$P6/.cascade/xcode"; ds
grep -q '^GREEN     D2' <<<"$DS" || { ok=0; echo "  RED TWIN stayed green: a harness without the check's proof did not call RED D2 GREEN"; }
cp "$TMP/xh.keep" "$P6/tests/lib/xcode_harness.py"
t AC6 "$ok" "unsigned, every Xcode law runs its own two commands; signed, eligible D1 is proven GREEN from one build while RED D2 and THEATER D3 keep their own verdicts; DSHARP_HARNESS=off uses none of it; a harness that skips the check's proof calls a RED law GREEN (red twin)"

# ---- AC7  the THEATER reason ---------------------------------------------------------------------------------------
ok=1
{ printf '# envelope\n\n<EDIT>\n### D1 — bare\ncheck:  %s\nbreak:  INV_MUTANT=D1 %s\n\n' "$CHK" "$CHK"
  printf '### D2 — prefixed\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D1 %s\n</EDIT>\n' "$CHK" "$CHK"; } > "$P6/docs/cascade/envelope.md"; commit "$P6"
ds
grep -q '^THEATER   D1  bare  — red twin passed, validator cannot fail: INV_MUTANT=D1 .*  (Xcode passes only TEST_RUNNER_\* variables to tests: write TEST_RUNNER_INV_MUTANT=D1 — USAGE.md §B16)$' <<<"$DS" \
  && grep -q '^GREEN     D2  prefixed$' <<<"$DS" || { ok=0; echo "  verdicts:"; sed 's/^/      /' <<<"$DS"; }
t AC7 "$ok" "a twin written INV_MUTANT=<id> xcodebuild … is THEATER and says Xcode passes only TEST_RUNNER_* variables; TEST_RUNNER_INV_MUTANT=<id> is GREEN"

# ---- AC8  the bound ------------------------------------------------------------------------------------------------
ok=1
goal "$P2" "$(X -only-testing:AppTests/SleepTests)" "$(X -only-testing:AppTests/LedgerTests)"
rm -rf "$P2/.cascade/xcode"; s0=$SECONDS; loop "$P2" BDD_XCODE_TIMEOUT=2 STUB_HANG_S=6; took=$((SECONDS - s0))
grep -q 'simctl terminate SIM1 dev.stub.Host' <<<"$CALLS" || { ok=0; echo "  the test host was not terminated after the timeout"; }
grep -q '0: not proven (timed out)' "$P2/.cascade/loop/xcode-runner.log" 2>/dev/null || { ok=0; echo "  no timeout note: $(cat "$P2/.cascade/loop/xcode-runner.log" 2>/dev/null)"; }
grep -q "^PASS  $(X -only-testing:AppTests/SleepTests)" <<<"$V" || { ok=0; echo "  the timed-out line did not run alone: $(head -2 <<<"$V")"; }
[[ "$took" -lt 20 ]] || { ok=0; echo "  took ${took}s"; }
t AC8 "$ok" "a hung test run is killed after BDD_XCODE_TIMEOUT, the simulator's test host is terminated, nothing is proven, and the line runs alone"

# ---- AC9  parity and wording ---------------------------------------------------------------------------------------
ok=1
OLD="$TMP/old"; mkdir -p "$OLD"; git -C "$ROOT" archive "$BASELINE" tests | tar -x -C "$OLD"
P9="$TMP/p9"; mkprod "$P9"
goal "$P9" "true" "echo two" "test -f src/Wallet.swift"
printf '# envelope\n\n<EDIT>\n### D1 — file\ncheck:  test -f src/Wallet.swift\nbreak:  test -f src/Nope.swift\n</EDIT>\n' > "$P9/docs/cascade/envelope.md"; commit "$P9"
both() { mkprod "$P9" "$1" >/dev/null; rm -rf "$P9/.cascade"
  { (cd "$P9" && bash tests/loop.sh 2>&1); (cd "$P9" && bash tests/dsharp_strength.sh 2>&1)
    (cd "$P9" && BDD_LOOP_RUNNER=shell bash tests/loop.sh 2>&1); } | sed -E 's/\([0-9]+s/(Ns/g'; }
[[ "$(both "$OLD/tests")" == "$(both "$ROOT/tests")" ]] || { ok=0; echo "  without Xcode lines the output differs from $BASELINE:"; diff <(both "$OLD/tests") <(both "$ROOT/tests") | head -10 | sed 's/^/      /'; }
grep -q "'.cascade/xcode/'" "$ROOT/install.sh" && grep -qx '.cascade/xcode/' "$ROOT/.gitignore" \
  || { ok=0; echo "  .cascade/xcode/ is not in install.sh's ignore list or the pack's .gitignore"; }
[[ -z "$(git -C "$P" status --porcelain)" ]] || { ok=0; echo "  a runner run left untracked files: $(git -C "$P" status --porcelain | head -3)"; }
t AC9 "$ok" "with no xcodebuild line and no Xcode law, loop.sh and dsharp_strength.sh print what $BASELINE printed; .cascade/xcode/ is ignored by install.sh and the pack; a run leaves git status clean"

echo
[[ "$fail" -eq 0 ]] && echo "T75 AC all PASS" || echo "T75 AC FAILED"
exit "$fail"
