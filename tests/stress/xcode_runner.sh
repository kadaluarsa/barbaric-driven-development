#!/usr/bin/env bash
# AC2/AC3/AC6/AC7/E1 for 05b t75-xcode-runner, on real Xcode. Opt-in — it needs Xcode, an iOS simulator runtime and
# xcodegen (brew install xcodegen), and takes several minutes. CI runs it in .github/workflows/xcode-self-check.yml.
#   usage: tests/stress/xcode_runner.sh [--timing]
#   SLOW_PHASE_S=<s>: the fixture's pre-build script phase, standing in for a real app's per-build work (default 5)
# On an app-hosted fixture (an iOS app, a unit-test bundle hosted in it), generated with xcodegen:
#   AC2  every loop verdict equals each line run alone: pass, failing test, a selector that matches nothing, a crash
#   AC3  an edit between two segments rebuilds (the stale binary is never tested); the runner batched (one build for
#        its lines) — so a version outside VERIFIED cannot pass this by running everything alone
#   AC6  signed, a GREEN law is proven by the harness and a RED one keeps its own verdict; DSHARP_HARNESS=off uses none
#   AC7  an INV_MUTANT twin is THEATER with the reason; TEST_RUNNER_INV_MUTANT is GREEN
#   --timing: E1 — 4 lines and 6 laws, tuning off (BDD_LOOP_RUNNER=shell, DSHARP_HARNESS=off) vs on, two passes
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_LOOP_RUNNER DSHARP_HARNESS \
      DSHARP_JOBS INV_MUTANT TEST_RUNNER_INV_MUTANT BDD_XCODE_TIMEOUT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
export SLOW_PHASE_S="${SLOW_PHASE_S:-5}"
TIMING=0; [[ "${1:-}" == --timing ]] && TIMING=1
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
command -v xcodebuild >/dev/null && command -v xcodegen >/dev/null \
  || { echo "FAIL  T75-stress  needs xcodebuild and xcodegen (brew install xcodegen)"; exit 1; }
V0="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9][0-9.]*\).*/\1/p' | head -1)"
# A simulator of its own, created here and deleted on exit: never one that other work on this machine is driving
# (two xcodebuilds on one simulator stall each other — seen while writing this script).
read -r DTYPE RUNTIME < <(xcrun simctl list -j devices available 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
for k in sorted((k for k in d if "iOS" in k), reverse=True):
    for dev in d[k]:
        if dev.get("name", "").startswith("iPhone") and dev.get("deviceTypeIdentifier"):
            print(dev["deviceTypeIdentifier"], k); raise SystemExit
')
[[ -n "${RUNTIME:-}" ]] || { echo "FAIL  T75-stress  no available iPhone simulator type and runtime"; exit 1; }
SIM="$(xcrun simctl create "bdd-t75-stress-$$" "$DTYPE" "$RUNTIME" 2>/dev/null | tail -1)"
[[ "$SIM" =~ ^[0-9A-F-]{36}$ ]] || { echo "FAIL  T75-stress  could not create a simulator ($SIM)"; exit 1; }
trap 'xcrun simctl shutdown "$SIM" >/dev/null 2>&1; xcrun simctl delete "$SIM" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
echo "== Xcode $V0, simulator $SIM, SLOW_PHASE_S=$SLOW_PHASE_S =="

F="$TMP/fx"; mkdir -p "$F/App" "$F/AppTests" "$F/docs/cascade" "$F/tests"
cat > "$F/project.yml" <<'EOF'
name: WalletApp
options: { bundleIdPrefix: dev.bdd.stress, deploymentTarget: { iOS: "17.0" } }
targets:
  WalletApp:
    type: application
    platform: iOS
    sources: [App]
    info: { path: App/Info.plist, properties: { UILaunchScreen: {} } }
    preBuildScripts:
      - name: slow build phase
        script: 'sleep ${SLOW_PHASE_S:-0}'
        basedOnDependencyAnalysis: false
  WalletAppTests:
    type: bundle.unit-test
    platform: iOS
    sources: [AppTests]
    dependencies: [{ target: WalletApp }]
    settings: { TEST_HOST: "$(BUILT_PRODUCTS_DIR)/WalletApp.app/WalletApp", BUNDLE_LOADER: "$(TEST_HOST)", GENERATE_INFOPLIST_FILE: "YES" }
schemes:
  WalletApp:
    build: { targets: { WalletApp: all, WalletAppTests: [test] } }
    test: { targets: [WalletAppTests] }
EOF
cat > "$F/App/App.swift" <<'EOF'
import SwiftUI
public enum Wallet { public static func debit(_ b: Int, _ a: Int) -> Int { b - a } }
@main struct WalletApp: App { var body: some Scene { WindowGroup { Text("wallet") } } }
EOF
law_class() { printf 'final class %s: XCTestCase { func testLaw() { XCTAssertNotEqual(ProcessInfo.processInfo.environment["INV_MUTANT"], "%s") } }\n' "$1" "$2"; }
{ printf 'import XCTest\n@testable import WalletApp\n'
  printf 'final class BalanceTests: XCTestCase { func testDebit() { XCTAssertEqual(Wallet.debit(2, 1), 1) } }\n'
  printf 'final class LedgerTests: XCTestCase { func testA() { XCTAssertTrue(true) } }\n'
  printf 'final class FailTests: XCTestCase { func testFails() { XCTAssertEqual(1, 2) } }\n'
  printf 'final class CrashTests: XCTestCase { func testCrash() { let a: [Int] = []; _ = a[1] } }\n'
  for i in 1 2 3 4 5 6; do law_class "Law${i}Tests" "D$i"; done
} > "$F/AppTests/Tests.swift"
( cd "$F" && xcodegen generate -q ) || { echo "FAIL  T75-stress  xcodegen failed"; exit 1; }
cp -R "$ROOT/tests/lib" "$F/tests/lib"; cp "$ROOT/tests/loop.sh" "$ROOT/tests/dsharp_strength.sh" "$F/tests/"
# The runner verifies its Xcode range; widen it in this copy to the version under test.
python3 - "$F/tests/lib/xcode_runner.py" "$V0" <<'PY'
import re, sys
p, v = sys.argv[1], sys.argv[2]; major, minor = (v.split(".") + ["0"])[:2]
s = open(p).read()
open(p, "w").write(re.sub(r'VERIFIED = \("[^"]*", "[^"]*"\)', f'VERIFIED = ("{major}.{minor}", "{major}.{int(minor) + 1}")', s))
PY
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$F/docs/cascade/hop-state.md"
printf '# envelope\n' > "$F/docs/cascade/envelope.md"
printf '.cascade/\nDerivedData/\n*.xcresult\n' > "$F/.gitignore"
( cd "$F" && git init -q && git add -A && git commit -qm init )
commit() { git -C "$F" add -A >/dev/null 2>&1; git -C "$F" commit -qm fx >/dev/null 2>&1 || true; }
X() { echo "xcodebuild -project WalletApp.xcodeproj -scheme WalletApp -destination 'platform=iOS Simulator,id=$SIM' test $*"; }
goal() { { printf 'GOAL_STAGE: 05b\n'; printf 'VALIDATOR: %s\n' "$@"; } > "$F/docs/cascade/goal.md"; }
loop() { local s0=$SECONDS; OUT="$(cd "$F" && env "$@" bash tests/loop.sh 2>&1)"; local rc=$?
  V="$(grep -E '^(PASS|FAIL)  |^LOOP [0-9]+/[0-9]+$' <<<"$OUT"; echo "rc=$rc")"; SECS=$((SECONDS - s0)); }
# A mismatch is checked once more before it counts: real xcodebuild runs can flake under load (seen in this hop: a
# passing class failed once when run alone, as written, and never again). Only a mismatch that repeats is the
# runner's; a one-off is printed as a flake of the alone path, never passed silently.
same() { local label="$1" a b; rm -rf "$F/.cascade/xcode"; loop BDD_LOOP_RUNNER=shell; a="$V"; rm -rf "$F/.cascade/xcode"; loop
  [[ "$a" == "$V" ]] && return 0
  local first; first="$(diff <(echo "$a") <(echo "$V"))"
  rm -rf "$F/.cascade/xcode"; loop BDD_LOOP_RUNNER=shell; b="$V"; rm -rf "$F/.cascade/xcode"; loop
  if [[ "$b" == "$V" ]]; then
    echo "  $label: FLAKY — one mismatch that did not repeat:"; sed 's/^/      /' <<<"$first"; return 0
  fi
  echo "  $label: differs from every line alone, twice:"; diff <(echo "$b") <(echo "$V") | sed 's/^/      /'; return 1; }

# ---- AC2 ----
ok=1
goal "$(X -only-testing:WalletAppTests/BalanceTests)" "$(X -only-testing:WalletAppTests/LedgerTests)"; same "all pass" || ok=0
grep -q 'proven in 1 xcode build(s)' <<<"$OUT" || { ok=0; echo "  the runner did not batch: $(grep '^loop:' <<<"$OUT")"; }
goal "$(X -only-testing:WalletAppTests/FailTests)" "$(X -only-testing:WalletAppTests/LedgerTests)"; same "failing test" || ok=0
goal "$(X -only-testing:WalletAppTests/NoSuchTests)" "$(X -only-testing:WalletAppTests/LedgerTests)"; same "no-match selector" || ok=0
goal "$(X -only-testing:WalletAppTests/CrashTests)" "$(X -only-testing:WalletAppTests/LedgerTests)"; same "crash" || ok=0
t "AC2[$V0]" "$ok" "every loop verdict equals each line alone on real Xcode (pass, failing test, no-match, crash), and the runner batched"

# ---- AC3 ----
ok=1
goal "$(X -only-testing:WalletAppTests/LedgerTests)" "$(X -only-testing:WalletAppTests/BalanceTests)" \
     "sed -i '' 's/b - a/b + a/' App/App.swift" \
     "$(X -only-testing:WalletAppTests/BalanceTests)" "$(X -only-testing:WalletAppTests/LedgerTests)"
rm -rf "$F/.cascade/xcode"; loop BDD_LOOP_RUNNER=shell; a="$V"; git -C "$F" checkout -q -- App/App.swift
rm -rf "$F/.cascade/xcode"; loop; git -C "$F" checkout -q -- App/App.swift
[[ "$a" == "$V" ]] || { ok=0; echo "  differs from every line alone:"; diff <(echo "$a") <(echo "$V") | sed 's/^/      /'; }
grep -q "^FAIL  $(X -only-testing:WalletAppTests/BalanceTests)" <<<"$V" || { ok=0; echo "  the edited source was not tested (stale binary?)"; }
grep -q 'proven in 2 xcode build(s)' <<<"$OUT" || { ok=0; echo "  want 2 builds (one rebuild after the edit): $(grep '^loop:' <<<"$OUT")"; }
t "AC3[$V0]" "$ok" "an edit between two segments rebuilds before the next line, so the edited source is what is tested; verdicts equal the lines alone"

# ---- AC6 + AC7 ----
ok=1
C1="$(X -only-testing:WalletAppTests/Law1Tests)"; CR="$(X -only-testing:WalletAppTests/FailTests)"
{ printf '# envelope\n\n<EDIT>\n- DSHARP_GRADLE_HARNESS: off\n- DSHARP_XCODE_HARNESS: on — locked 2026-10-23 — reason: stress\n'
  printf '### D1 — green\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D1 %s\n\n' "$C1" "$C1"
  printf '### D2 — red\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D2 %s\n\n' "$CR" "$CR"
  printf '### D3 — bare twin\ncheck:  %s\nbreak:  INV_MUTANT=D3 %s\n</EDIT>\n' "$(X -only-testing:WalletAppTests/Law3Tests)" "$(X -only-testing:WalletAppTests/Law3Tests)"
} > "$F/docs/cascade/envelope.md"; commit
rm -rf "$F/.cascade/xcode" "$F/.cascade/laws"; DS="$(cd "$F" && bash tests/dsharp_strength.sh 2>&1)"
grep -q '^GREEN     D1  green$' <<<"$DS" && grep -q '^RED       D2' <<<"$DS" || { ok=0; echo "  verdicts:"; sed 's/^/      /' <<<"$DS"; }
grep -q $'^0\tD1\tGREEN' "$F/.cascade/laws/xcode-harness.tsv" 2>/dev/null || { ok=0; echo "  the harness did not prove D1: $(cat "$F/.cascade/laws/xcode-harness.tsv" 2>/dev/null)"; }
grep -q '^THEATER   D3  bare twin  — .*write TEST_RUNNER_INV_MUTANT=D3' <<<"$DS" || { ok=0; echo "  D3: $(grep D3 <<<"$DS")"; }
GATE="$(cd "$F" && DSHARP_HARNESS=off bash tests/dsharp_strength.sh 2>&1)"
[[ "$(grep -E '^(GREEN|RED|THEATER)' <<<"$GATE" | cut -c1-14)" == "$(grep -E '^(GREEN|RED|THEATER)' <<<"$DS" | cut -c1-14)" ]] \
  || { ok=0; echo "  the merge gate's path (DSHARP_HARNESS=off) gives other verdicts:"; diff <(echo "$DS") <(echo "$GATE") | sed 's/^/      /'; }
t "AC6/7[$V0]" "$ok" "signed, the harness proves GREEN D1 from one build; RED D2 keeps its verdict; an INV_MUTANT twin is THEATER with the reason; DSHARP_HARNESS=off gives the same verdicts"

# ---- E1 ----
if [[ "$TIMING" -eq 1 ]]; then
  lines=("$(X -only-testing:WalletAppTests/BalanceTests)" "$(X -only-testing:WalletAppTests/LedgerTests)"
         "$(X -only-testing:WalletAppTests/Law1Tests)" "$(X -only-testing:WalletAppTests/Law2Tests)")
  goal "${lines[@]}"
  { printf '# envelope\n\n<EDIT>\n- DSHARP_XCODE_HARNESS: on — locked 2026-10-23 — reason: stress\n'
    for i in 1 2 3 4 5 6; do c="$(X -only-testing:WalletAppTests/Law${i}Tests)"; printf '### D%s — law %s\ncheck:  %s\nbreak:  TEST_RUNNER_INV_MUTANT=D%s %s\n\n' "$i" "$i" "$c" "$i" "$c"; done
    printf '</EDIT>\n'; } > "$F/docs/cascade/envelope.md"; commit
  rm -rf "$F/.cascade/xcode"
  loop BDD_LOOP_RUNNER=shell; l_off1=$SECS; loop BDD_LOOP_RUNNER=shell; l_off2=$SECS; v_off="$V"
  rm -rf "$F/.cascade/xcode"; loop; l_on1=$SECS; loop; l_on2=$SECS; v_on="$V"
  ds() { local s0=$SECONDS; DSO="$(cd "$F" && env "$@" bash tests/dsharp_strength.sh 2>&1)"; echo $((SECONDS - s0)); }
  d_off="$(ds DSHARP_HARNESS=off)"; k_off="$(tail -1 <<<"$DSO")"
  rm -rf "$F/.cascade/xcode"; d_on1="$(ds)"; k_on="$(tail -1 <<<"$DSO")"; d_on2="$(ds)"
  [[ "$v_off" == "$v_on" && "$k_off" == "$k_on" ]] || { fail=1; echo "  E1: verdicts differ (loop: $v_off vs $v_on; laws: $k_off vs $k_on)"; }
  echo "  E1, Xcode $V0, SLOW_PHASE_S=$SLOW_PHASE_S, app-hosted fixture:"
  echo "  | run | before (each call builds) | after (t75) | verdicts |"
  echo "  | loop, 4 lines, first pass | ${l_off1}s | ${l_on1}s | $(tail -2 <<<"$v_on" | head -1) both |"
  echo "  | loop, unchanged pass | ${l_off2}s | ${l_on2}s | same |"
  echo "  | 6 laws (12 commands), harness signed | ${d_off}s | ${d_on1}s, then ${d_on2}s with the build reused | $k_on both |"
fi

echo
[[ "$fail" -eq 0 ]] && echo "T75 stress all PASS" || echo "T75 stress FAILED"
exit "$fail"
