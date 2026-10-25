#!/usr/bin/env bash
# AC tests for 05b t79-zero-test-guard: a test runner that exited 0 having executed no test is a FAIL / RED.
# Stub runners replay what real Gradle 8.14.3 and Xcode 27 left behind in E0 (docs/cascade/05b-t79-zero-test-guard.md):
#   ./gradlew  copies .stub/<scenario>/ into the tree (XML + binary/, as a run that executed; nothing, as up-to-date)
#   xcodebuild writes a result bundle (summary.json, tests.json) and a log; xcrun xcresulttool prints the bundle's JSON
#   AC1  Gradle: a misspelled filter, one bad filter of two, all skipped, @Nested, subproject-only bare task, up-to-date
#   AC2  Xcode: bundle 0 / all skipped / 2 executed / a target with none; log 0 / all skipped / 4; Swift Testing 0; none
#   AC3  parity: a shell-only goal prints what c8886b0 printed; a mixed goal counts `not inspected`
#   AC4  the t62 runner proves a line only with an executed case of its own. RED TWIN: without it both are proven.
#   AC5  the regression suite: REGRESS 0/1, ran no tests
#   AC6  laws: zero-test check RED; the count is the check's, not the twin's; a family; DSHARP_JOBS>1 skips the default
#        DerivedData scan. RED TWIN: a reader that says `ran 1` for every Gradle run lets AC1's misspelling pass.
#   AC7  .cascade/regress/ ignored (pack + install), nothing under it tracked; test_count.py is a verdict-cache scorer
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_LOOP_RUNNER BARBAR_ROOT DSHARP_JOBS
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BASELINE=c8886b0     # t79's spec, before its code
export BDD_DERIVED_DATA="$TMP/DerivedData"

mkprod() {  # mkprod <dir> [tests dir] [laws] — a product with stub runners, git on main
  local d="$1" tdir="${2:-$ROOT/tests}" laws="${3:-}"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests" "$d/bin" "$d/.stub"
  cp -R "$tdir/lib" "$d/tests/lib"; for f in loop.sh regress.sh dsharp_strength.sh; do [[ -f "$tdir/$f" ]] && cp "$tdir/$f" "$d/tests/"; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n.stub/\nbin/\n**/build/\n' > "$d/.gitignore"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: B\n' > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n' "$laws" > "$d/docs/cascade/envelope.md"
  cat > "$d/gradlew" <<'SH'
#!/usr/bin/env bash
# stub: replay .stub/<scenario> (a run that executed replaces each task's results directory, as Gradle does)
sc="$(cat .stub/current 2>/dev/null)"; [[ -n "$sc" && -d ".stub/$sc" ]] || exit 0
( cd ".stub/$sc" && find . -type d -path '*/build/test-results/*' -prune -print ) | while IFS= read -r dd; do rm -rf "$dd"; done
( cd ".stub/$sc" && find . -type f ) | while IFS= read -r f; do mkdir -p "$(dirname "$f")"; cp ".stub/$sc/$f" "$f"; done
[[ -f ".stub/$sc.rc" ]] && exit "$(cat ".stub/$sc.rc")"
exit 0
SH
  cat > "$d/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
# stub: write the scenario's result bundle where xcodebuild would, and its log
sc="$(cat .stub/current 2>/dev/null)"; dest=""
while [[ $# -gt 0 ]]; do [[ "$1" == -resultBundlePath ]] && dest="$2"; shift; done
[[ -z "$dest" ]] && dest="$BDD_DERIVED_DATA/App-xyz/Logs/Test/Test-App-$RANDOM.xcresult"
if [[ -d ".stub/$sc/bundle" ]]; then rm -rf "$dest"; mkdir -p "$dest"; cp ".stub/$sc/bundle/"* "$dest/"; fi
[[ -f ".stub/$sc/out.txt" ]] && cat ".stub/$sc/out.txt"
exit 0
SH
  cat > "$d/bin/xcrun" <<'SH'
#!/usr/bin/env bash
# stub: xcrun xcresulttool get test-results summary|tests --path B
[[ "$1 $2 $3" == "xcresulttool get test-results" ]] || exit 1
kind="$4"; shift 4; [[ "$1" == --path ]] && cat "$2/$kind.json"
SH
  chmod +x "$d/gradlew" "$d/bin/xcodebuild" "$d/bin/xcrun"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main )
}
xml() {  # xml <scenario dir> <module path or .> <task> <class> <name>[:skipped] … — one fresh results directory
  local sd="$1" mod="$2" task="$3"; shift 3
  local dir="$sd/$mod/build/test-results/$task"; mkdir -p "$dir/binary"; echo bin > "$dir/binary/results.bin"
  [[ $# -eq 0 ]] && return 0
  local cls="$1"; shift
  { echo "<testsuite name=\"$cls\">"
    for c in "$@"; do
      if [[ "$c" == *:skipped ]]; then echo "  <testcase classname=\"$cls\" name=\"${c%:skipped}\"><skipped/></testcase>"
      else echo "  <testcase classname=\"$cls\" name=\"$c\"/>"; fi
    done; echo "</testsuite>"; } > "$dir/TEST-$cls.xml"
}
scen() { mkdir -p "$1/.stub/$2"; echo "$2" > "$1/.stub/current"; echo "$1/.stub/$2"; }
goal() { local d="$1"; shift; { echo '```'; echo 'GOAL_STAGE: 05b'; echo 'GOAL_SLICE: B'; for v in "$@"; do echo "VALIDATOR: $v"; done; echo '```'; } > "$d/docs/cascade/goal.md"; }
commit() { ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm "${2:-c}" ); }
loop() { local d="$1"; shift; OUT="$(cd "$d" && PATH="$d/bin:$PATH" bash tests/loop.sh "$@" 2>&1)"; RC=$?; }
tc() { local d="$1" start="$2"; shift 2; ( cd "$d" && PATH="$d/bin:$PATH" python3 -B tests/lib/test_count.py "$d" "$start" "${LOG:-/dev/null}" "$*" ); }
now() { python3 -c 'import time; print(time.time())'; }
G1='./gradlew :core:test --tests com.x.FoTest -q'

# ---- AC1  Gradle -------------------------------------------------------------------------------------------------
ok=1
P="$TMP/p1"; mkprod "$P"; goal "$P" "$G1"; commit "$P"
s="$(scen "$P" typo)"; xml "$s" core test com.x.FooTest a; loop "$P"
[[ "$RC" -ne 0 && "$OUT" == *"FAIL  $G1"* && "$OUT" == *"ran no tests"* && "$OUT" == *"LOOP 0/1"* ]] \
  || { ok=0; echo "  a misspelled filter in a run that executed was not FAIL ran no tests (rc $RC):"; echo "$OUT" | tail -4 | sed 's/^/      /'; }
goal "$P" './gradlew :core:test --tests com.x.FooTest -q'; loop "$P"
[[ "$RC" -eq 0 && "$OUT" == *"LOOP 1/1"* ]] || { ok=0; echo "  the right filter did not PASS (rc $RC)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
goal "$P" './gradlew :core:test --tests com.x.FooTest --tests com.x.BaTest -q'; s="$(scen "$P" two)"; xml "$s" core test com.x.FooTest a; loop "$P"
[[ "$RC" -ne 0 && "$OUT" == *"filter matched no executed test: com.x.BaTest"* ]] || { ok=0; echo "  one bad filter of two was not named (rc $RC)"; }
goal "$P" './gradlew :core:test --tests com.x.FooTest -q'; s="$(scen "$P" skip)"; xml "$s" core test com.x.FooTest a:skipped b:skipped; loop "$P"
[[ "$RC" -ne 0 && "$OUT" == *"ran no tests"* ]] || { ok=0; echo "  an all-skipped run was not FAIL (rc $RC)"; }
s="$(scen "$P" nested)"; xml "$s" core test 'com.x.FooTest$Inner' a; loop "$P"
[[ "$RC" -eq 0 ]] || { ok=0; echo "  a @Nested case under its outer class filter did not PASS (rc $RC)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
goal "$P" './gradlew test -q'; s="$(scen "$P" sub)"; xml "$s" lib/feature test com.x.SubTest a; loop "$P"
[[ "$RC" -eq 0 ]] || { ok=0; echo "  a bare test task with results only in a subproject did not PASS (rc $RC)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
s="$(scen "$P" noop)"; sleep 1; loop "$P"
[[ "$RC" -eq 0 && "$OUT" == *"1 not inspected"* ]] || { ok=0; echo "  an up-to-date task (results older than the run) was not PASS + not inspected (rc $RC)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
goal "$P" "$G1"; s="$(scen "$P" lenient)"; xml "$s" core test; loop "$P"
[[ "$RC" -ne 0 && "$OUT" == *"ran no tests"* ]] || { ok=0; echo "  a lenient typo (fresh binary results, no XML — E0b) was not FAIL (rc $RC)"; }
t AC1 "$ok" "Gradle: a misspelled filter, one bad filter of two, an all-skipped run and a lenient typo FAIL ran no tests; the right filter, a @Nested case and a subproject-only bare task PASS; an up-to-date task PASSes as not inspected"

# ---- AC2  Xcode ---------------------------------------------------------------------------------------------------
ok=1
P="$TMP/p2"; mkprod "$P"
X1='xcodebuild test -scheme App -destination "platform=macOS" -only-testing:AppTests/FooTests -quiet'
X2='xcodebuild test -scheme App -resultBundlePath out/r.xcresult -only-testing:AppTests/FooTests -only-testing:AppTests/BarTests -quiet'
bundle() {  # bundle <scenario dir> <total> <skipped> [target/suite:result …]
  local sd="$1" total="$2" skipped="$3"; shift 3; mkdir -p "$sd/bundle"
  printf '{"result":"%s","totalTestCount":%s,"skippedTests":%s}\n' "$([[ $total -gt 0 ]] && echo Passed || echo unknown)" "$total" "$skipped" > "$sd/bundle/summary.json"
  python3 - "$sd/bundle/tests.json" "$@" <<'PY'
import json, sys
out, specs = sys.argv[1], sys.argv[2:]
bundles = {}
for s in specs:
    path, result = s.rsplit(":", 1); tgt, suite = path.split("/")
    b = bundles.setdefault(tgt, {"nodeType": "Unit test bundle", "name": tgt, "children": []})
    b["children"].append({"nodeType": "Test Suite", "name": suite, "children": [
        {"nodeType": "Test Case", "name": "testA()", "result": result, "nodeIdentifier": f"{suite}/testA()"}]})
json.dump({"testNodes": [{"nodeType": "Test Plan", "name": "App", "children": list(bundles.values())}]}, open(out, "w"))
PY
}
case2() {  # case2 <label> <want: pass|fail> <line> — run the loop on one Xcode line
  goal "$P" "$3"; loop "$P"
  if [[ "$2" == pass ]]; then [[ "$RC" -eq 0 ]] || { ok=0; echo "  $1: want PASS (rc $RC)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
  else [[ "$RC" -ne 0 && "$OUT" == *"ran no tests"* ]] || { ok=0; echo "  $1: want FAIL ran no tests (rc $RC)"; echo "$OUT" | tail -3 | sed 's/^/      /'; }; fi
}
s="$(scen "$P" b0)"; bundle "$s" 0 0; case2 "bundle, 0 executed" fail "$X1"
s="$(scen "$P" bskip)"; bundle "$s" 3 3 AppTests/FooTests:Skipped; case2 "bundle, all skipped" fail "$X1"
s="$(scen "$P" b2)"; bundle "$s" 2 0 AppTests/FooTests:Passed; case2 "bundle, 2 executed" pass "$X1"
s="$(scen "$P" btgt)"; bundle "$s" 1 0 AppTests/FooTests:Passed; case2 "-resultBundlePath, one target with none" fail "$X2"
[[ "$OUT" == *"AppTests/BarTests"* ]] || { ok=0; echo "  the empty -only-testing target was not named"; }
s="$(scen "$P" btgt2)"; bundle "$s" 2 0 AppTests/FooTests:Passed AppTests/BarTests:Failed; case2 "-resultBundlePath, both targets ran" pass "$X2"
s="$(scen "$P" l0)"; echo "Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds" > "$s/out.txt"; case2 "log, Executed 0" fail "$X1"
s="$(scen "$P" lskip)"; echo "Executed 3 tests, with 3 tests skipped and 0 failures (0 unexpected) in 0.01 (0.02) seconds" > "$s/out.txt"; case2 "log, all skipped" fail "$X1"
s="$(scen "$P" l4)"; echo "Executed 4 tests, with 0 failures (0 unexpected) in 0.01 (0.02) seconds" > "$s/out.txt"; case2 "log, Executed 4" pass "$X1"
s="$(scen "$P" st0)"; echo "✔ Test run with 0 tests passed after 0.001 seconds." > "$s/out.txt"; case2 "Swift Testing, 0" fail "$X1"
s="$(scen "$P" none)"; echo "Testing started" > "$s/out.txt"; goal "$P" "$X1" 'true'; loop "$P"
[[ "$RC" -eq 0 && "$OUT" == *"2 not inspected"* ]] || { ok=0; echo "  no bundle and no count line: not PASS + not inspected (rc $RC)"; echo "$OUT" | tail -2 | sed 's/^/      /'; }
t AC2 "$ok" "Xcode: a bundle with 0 executed, all skipped, or an -only-testing target with none FAIL; 2 executed and both targets PASS; the log's Executed 0, all-skipped and Swift Testing 0 FAIL, Executed 4 PASSes; no count is not inspected"

# ---- AC3  parity ----------------------------------------------------------------------------------------------------
ok=1
OLD="$TMP/old"; mkdir -p "$OLD"; git -C "$ROOT" archive "$BASELINE" tests | tar -x -C "$OLD"
norm() { sed -E 's/\([0-9]+s\)/(Ns)/g; s/ \([0-9]+s, / (Ns, /g'; }
par() { local d="$TMP/p3"; mkprod "$d" "$1"; goal "$d" 'true' 'echo hi'; commit "$d"; loop "$d"; echo "$OUT" | norm; echo "rc=$RC"; }
before="$(par "$OLD/tests")"; after="$(par "$ROOT/tests")"
[[ "$before" == "$after" ]] || { ok=0; echo "  a shell-only goal prints differently from $BASELINE:"; diff <(echo "$before") <(echo "$after") | sed 's/^/      /' | head; }
P="$TMP/p3m"; mkprod "$P"; goal "$P" './gradlew :core:test --tests com.x.FooTest -q' 'true'; commit "$P"
s="$(scen "$P" ok)"; xml "$s" core test com.x.FooTest a; loop "$P"
[[ "$RC" -eq 0 && "$OUT" == *"; 1 not inspected"* ]] || { ok=0; echo "  a mixed goal did not count the shell line as not inspected:"; echo "$OUT" | tail -3 | sed 's/^/      /'; }
t AC3 "$ok" "a shell-only goal prints what $BASELINE printed (no not-inspected text); a goal with a Gradle line counts the shell line as not inspected"

# ---- AC4  the t62 runner's proof -------------------------------------------------------------------------------------
ok=1
proof() {  # proof <gradle_runner.py dir> -> "A B" proven flags for two lines sharing one build
  python3 - "$1" "$TMP/p4" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); import gradle_runner as g
from collections import OrderedDict
root = sys.argv[2]
def results(task, cases):
    d = os.path.join(root, "core", "build", "test-results", task); os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "TEST-x.xml"), "w") as f:
        f.write("<testsuite>" + "".join(f'<testcase classname="{c}" name="{n}"/>' for c, n in cases) + "</testsuite>")
    return d
row = lambda d: {"deps": [], "fin": [], "test": True, "xml": d, "ignore": False, "fail_none": True}
graph = {":core:testA": row(results("testA", [("com.x.FooTest", "a")])),
         ":core:testB": row(results("testB", [("com.x.Other", "z")]))}
fa, fb = frozenset({"com.x.FooTest"}), frozenset({"com.x.BarTest"})
sels = OrderedDict([(":core:testA", fa), (":core:testB", fb)])
b = g.Build(sels, {":core:testA": ("SUCCESS", ""), ":core:testB": ("SUCCESS", "")}, graph)
print(int(b.proven({"sels": [(":core:testA", fa)]})), int(b.proven({"sels": [(":core:testB", fb)]})))
PY
}
r="$(proof "$ROOT/tests/lib")"; [[ "$r" == "1 0" ]] || { ok=0; echo "  the runner proved '$r' (want '1 0': the line whose filter executed nothing is not proven)"; }
TW="$TMP/twin4"; cp -R "$ROOT/tests/lib" "$TW"
python3 - "$TW/gradle_runner.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "                if not executed_own(row, fs, self):\n"
if old not in s: sys.exit("twin: the executed-case requirement is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "                if False:\n", 1))
PY
rm -rf "$TMP/p4"; r="$(proof "$TW")"; [[ "$r" == "1 1" ]] || { ok=0; echo "  red twin did not go red: without the requirement the runner proved '$r'"; }
t AC4 "$ok" "the batched runner proves a line only when its own filter executed a case in the shared build; the other line runs alone (red twin: both proven)"

# ---- AC5  the regression suite ----------------------------------------------------------------------------------------
ok=1
P="$TMP/p5"; mkprod "$P"; printf '# suite\n\n### A\nREGRESS: %s\n' "$G1" > "$P/docs/cascade/regress.md"; commit "$P"
s="$(scen "$P" typo)"; xml "$s" core test com.x.FooTest a
o="$(cd "$P" && PATH="$P/bin:$PATH" bash tests/regress.sh 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$o" == *"REGRESS 0/1"* && "$o" == *"ran no tests"* ]] || { ok=0; echo "  the suite did not FAIL a zero-test line (rc $rc): $o"; }
t AC5 "$ok" "a zero-test REGRESS line is REGRESS 0/1 with ran no tests"

# ---- AC6  laws ------------------------------------------------------------------------------------------------------
ok=1
law() { printf '### %s — %s\ncheck:  %s\nbreak:  %s\n\n' "$1" "$2" "$3" "$4"; }
P="$TMP/p6"; mkprod "$P" "$ROOT/tests" "$(law D1 'zero' "$G1" 'false')"; commit "$P"
s="$(scen "$P" typo)"; xml "$s" core test com.x.FooTest a
o="$(cd "$P" && PATH="$P/bin:$PATH" bash tests/dsharp_strength.sh 2>&1)"
[[ "$o" == *"RED"*"D1"*"ran no tests"* ]] || { ok=0; echo "  a zero-test law check was not RED ran no tests: $(echo "$o" | head -2)"; }
P="$TMP/p6g"; mkprod "$P" "$ROOT/tests" "$(law D1 'one' './gradlew :core:test --tests com.x.FooTest -q' 'false')"; commit "$P"
s="$(scen "$P" ok)"; xml "$s" core test com.x.FooTest a
o="$(cd "$P" && PATH="$P/bin:$PATH" bash tests/dsharp_strength.sh 2>&1)"; [[ "$o" == *"GREEN"*"D1"* ]] || { ok=0; echo "  a law whose check ran one test was not GREEN: $(echo "$o" | head -2)"; }
P="$TMP/p6t"; mkprod "$P" "$ROOT/tests" "$(law D1 'twin writes' "$G1" 'echo good > .stub/current; ./gradlew; false')"; commit "$P"
s="$(scen "$P" typo)"; xml "$s" core test com.x.FooTest a; s2="$(scen "$P" good)"; xml "$s2" core test com.x.FoTest a; echo typo > "$P/.stub/current"
o="$(cd "$P" && PATH="$P/bin:$PATH" bash tests/dsharp_strength.sh 2>&1)"; [[ "$o" == *"RED"*"ran no tests"* ]] || { ok=0; echo "  the count was taken after the twin, not the check: $(echo "$o" | head -1)"; }
P="$TMP/p6f"; mkprod "$P" "$ROOT/tests" "$(law D1 'fam a' "$G1" 'false'; law D2 'fam b' "$G1" 'true; false')"; commit "$P"
s="$(scen "$P" typo)"; xml "$s" core test com.x.FooTest a
o="$(cd "$P" && PATH="$P/bin:$PATH" bash tests/dsharp_strength.sh 2>&1)"
[[ "$(grep -c '^RED.*ran no tests' <<<"$o")" -eq 2 ]] || { ok=0; echo "  a family on one zero-test check was not RED twice: $o"; }
P="$TMP/p6j"; mkprod "$P"; s="$(scen "$P" b2)"; bundle "$s" 2 0 AppTests/FooTests:Passed
st="$(now)"; ( cd "$P" && PATH="$P/bin:$PATH" xcodebuild test -scheme App >/dev/null )
r1="$(tc "$P" "$st" "$X1")"; r2="$(DSHARP_JOBS=4 tc "$P" "$st" "$X1")"
[[ "$r1" == "ran 2" && "$r2" == uninspected* ]] || { ok=0; echo "  DSHARP_JOBS=4 still scanned the default DerivedData ('$r1' / '$r2')"; }
TW="$TMP/twin6"; cp -R "$ROOT/tests/lib" "$TW"
python3 - "$TW/test_count.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "        return gradle_verdict(root, start, cmd, toks)\n"
if old not in s: sys.exit("twin: the Gradle verdict call is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, '        return "ran 1"\n'))
PY
P="$TMP/p6r"; mkprod "$P"; cp "$TW/test_count.py" "$P/tests/lib/test_count.py"; goal "$P" "$G1"; commit "$P"
s="$(scen "$P" typo)"; xml "$s" core test com.x.FooTest a; loop "$P"
[[ "$RC" -eq 0 ]] || { ok=0; echo "  red twin did not go red: a reader saying 'ran 1' still failed the misspelling"; }
t AC6 "$ok" "a zero-test law check is RED ran no tests, one executed test GREEN; the count is the check's, not the twin's; a family on one zero-test check is RED twice; DSHARP_JOBS>1 skips the default DerivedData scan (red twin: a reader that always says ran 1)"

# ---- AC7  t78's ignored logs, the cache scorer ------------------------------------------------------------------------
ok=1
grep -qxF '.cascade/regress/' "$ROOT/.gitignore" || { ok=0; echo "  .cascade/regress/ is not in the pack's .gitignore"; }
grep -q "'.cascade/regress/'" "$ROOT/install.sh" || { ok=0; echo "  install.sh does not gitignore .cascade/regress/"; }
I="$TMP/i7"; mkdir -p "$I"; ( cd "$I" && git init -q ); ( HOME="$TMP/nohome" bash "$ROOT/install.sh" --no-plugin "$I" >/dev/null 2>&1 )
grep -qxF '.cascade/regress/' "$I/.gitignore" || { ok=0; echo "  a fresh install's .gitignore lacks .cascade/regress/"; }
[[ -z "$(git -C "$ROOT" ls-files .cascade/regress)" ]] || { ok=0; echo "  files under .cascade/regress/ are still tracked: $(git -C "$ROOT" ls-files .cascade/regress | tr '\n' ' ')"; }
grep -q '"test_count.py"' "$ROOT/tests/lib/verdict_cache.py" || { ok=0; echo "  test_count.py is not among the verdict cache's SCORERS"; }
t AC7 "$ok" ".cascade/regress/ is ignored by the pack and by install.sh, nothing under it is tracked; test_count.py is a verdict-cache scorer"

echo
[[ "$fail" -eq 0 ]] && echo "T79 AC all PASS" || echo "T79 AC FAILED"
exit "$fail"
