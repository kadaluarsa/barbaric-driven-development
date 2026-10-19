#!/usr/bin/env bash
# AC7 for 05b t62-loop-runners: the loop runner's claims, on real Gradle. Opt-in — it needs a JDK, Gradle and
# Maven Central (JUnit), and takes a few minutes per Gradle version. CI runs it in pack-self-check.yml.
#   usage: tests/stress/gradle_runner.sh [gradle-executable ...]     (default: gradle on PATH)
#   CONF_MS=<ms> sets the fixture's simulated configuration time (default 5000; the timing table uses it).
# Per Gradle version, on a two-module JUnit 5 fixture whose build script counts its own configurations:
#   (a) for every probe pattern: the runner's surely set ⊆ Gradle's own selection ⊆ the runner's could set
#   (b) the verdict matrix: every line's verdict equals the line run alone, exact and merged
#   (c) configurations per pass: one per wave (exact), 1 (merged), one per line (alone)
#   (d) the init script moves no task's up-to-date state
#   (e) with --configuration-cache, the second batched pass reuses the entry and still proves its passes
#   (f) the timing table: alone vs exact vs merged, first pass and an unchanged pass
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_LOOP_RUNNER
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
CONF_MS="${CONF_MS:-5000}"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[[ $# -gt 0 ]] || set -- gradle

fixture() {  # fixture <dir> <gradle>
  local d="$1" g="$2" v
  v="$("$g" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1)"
  mkdir -p "$d"/core/src/{main,test}/java/com/x/core "$d"/app/src/{main,test}/java/com/x/app "$d/gradle/wrapper" "$d/docs/cascade" "$d/tests"
  printf "rootProject.name = 'fx'\ninclude 'core', 'app'\n" > "$d/settings.gradle"
  cat > "$d/build.gradle" <<'EOF'
// Counts its own configurations (AC7c) and stands in for a real build's configuration time.
new File(rootDir, 'conf-count.txt') << 'x\n'
def confMs = (System.getenv('CONF_MS') ?: '0') as long
if (confMs > 0) Thread.sleep(confMs)
subprojects {
  apply plugin: 'java'
  repositories { mavenCentral() }
  dependencies {
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.2'
    testRuntimeOnly 'org.junit.platform:junit-platform-launcher'
  }
  tasks.withType(Test).configureEach { useJUnitPlatform() }
}
project(':app') { dependencies { implementation project(':core') } }
EOF
  printf 'package com.x.core;\npublic class Wallet { public static int debit(int b, int a) { return b - a; } }\n' > "$d/core/src/main/java/com/x/core/Wallet.java"
  printf 'package com.x.app;\npublic class Checkout { public static int total(int a) { return com.x.core.Wallet.debit(a, 0); } }\n' > "$d/app/src/main/java/com/x/app/Checkout.java"
  local imp='import org.junit.jupiter.api.*; import static org.junit.jupiter.api.Assertions.*;'
  printf 'package com.x.core;\n%s\nclass BalanceTest { @Test void one() { assertEquals(1, Wallet.debit(2,1)); } @Test void two() { assertEquals(0, Wallet.debit(1,1)); } }\n' "$imp" > "$d/core/src/test/java/com/x/core/BalanceTest.java"
  printf 'package com.x.core;\n%s\nclass LedgerTest { @Test void one() { assertTrue(true); } @Test void two() { assertTrue(true); } @Test @DisplayName("adds two") void addsTwo() { assertTrue(true); } }\n' "$imp" > "$d/core/src/test/java/com/x/core/LedgerTest.java"
  printf 'package com.x.core;\n%s\nclass BalanceSpec { @Test void balanceTest() { assertTrue(true); } @Test void other() { assertTrue(true); } @Nested class Inner { @Test void deep() { assertTrue(true); } } }\n' "$imp" > "$d/core/src/test/java/com/x/core/BalanceSpec.java"
  printf 'package com.x.app;\n%s\nclass CheckoutTest { @Test void ok() { assertEquals(3, Checkout.total(3)); } }\n' "$imp" > "$d/app/src/test/java/com/x/app/CheckoutTest.java"
  printf 'package com.x.app;\n%s\nclass RefundTest { @Test void ok() { assertEquals(3, Checkout.total(3)); } }\n' "$imp" > "$d/app/src/test/java/com/x/app/RefundTest.java"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$g")" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' "$v" > "$d/gradle/wrapper/gradle-wrapper.properties"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/loop.sh" "$d/tests/loop.sh"
  # The evidence that sets VERIFIED must exercise merged mode on the version under test: widen it in this copy.
  python3 - "$d/tests/lib/gradle_runner.py" "$v" <<'PY'
import sys, re
p, v = sys.argv[1], sys.argv[2]
s = open(p).read()
major, minor = v.split(".")[:2]
s = re.sub(r'VERIFIED = \("[^"]*", "[^"]*"\)', f'VERIFIED = ("{major}.{minor}", "{major}.{int(minor) + 1}")', s)
open(p, "w").write(s)
PY
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n' > "$d/docs/cascade/envelope.md"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\nconf-count.txt\n' > "$d/.gitignore"
  ( cd "$d" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
  echo "$v"
}
sign() { printf '<EDIT>\n- LOOP_GRADLE_MERGE: on — locked 2026-10-19 — reason: AC7\n</EDIT>\n' > "$1/docs/cascade/envelope.md"; }
unsign() { printf '# envelope\n' > "$1/docs/cascade/envelope.md"; }
goal() { local d="$1"; shift; { printf 'GOAL_STAGE: 05b\n'; printf 'VALIDATOR: %s\n' "$@"; } > "$d/docs/cascade/goal.md"; }
confs() { wc -l < "$1/conf-count.txt" 2>/dev/null | tr -d ' ' || echo 0; }
loop() {  # loop <dir> [VAR=value...] -> $OUT, $RC, $CONFS (configurations this pass), $SECS
  local d="$1"; shift; local c0 s0
  c0="$(confs "$d")"; s0=$SECONDS
  OUT="$(cd "$d" && env CONF_MS="$LOOP_CONF" "$@" bash tests/loop.sh 2>&1)"; RC=$?
  CONFS=$(( $(confs "$d") - c0 )); SECS=$(( SECONDS - s0 ))
}
verdicts() { grep -E '^(PASS|FAIL)  |^LOOP [0-9]+/[0-9]+$' <<<"$1"; }
same() {  # same <dir> [VAR=value...]
  local d="$1"; shift; local a ra
  loop "$d" BDD_LOOP_RUNNER=shell; a="$(verdicts "$OUT")"; ra=$RC
  loop "$d" "$@"
  [[ "$a" == "$(verdicts "$OUT")" && "$ra" == "$RC" ]] && return 0
  diff <(echo "$a"; echo "rc=$ra") <(verdicts "$OUT"; echo "rc=$RC") | sed 's/^/      /' >&2; return 1
}
edit() { python3 - "$@" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read(); assert old in s, (p, old); open(p, "w").write(s.replace(old, new, 1))
PY
}

LOOP_CONF=0   # only the timing step (c/f) pays the simulated configuration time
for G in "$@"; do
  if ! command -v "$G" >/dev/null 2>&1; then t "AC7[$G]" 0 "no such Gradle executable"; continue; fi
  F="$TMP/fx-$(basename "$G")-$RANDOM"
  V="$(fixture "$F" "$G" | tail -1)"
  echo "== Gradle $V ($G), CONF_MS=$CONF_MS =="
  if ! ( cd "$F" && CONF_MS=0 ./gradlew -q :core:testClasses :app:testClasses >"$TMP/fx-build.log" 2>&1 ); then
    grep -v '^Picked up' "$TMP/fx-build.log" | tail -15 | sed 's/^/    /'
    t "AC7[$V]" 0 "the fixture does not build (JDK, network?)"; continue
  fi

  # (a) patterns: surely ⊆ Gradle ⊆ could, on every test case either module has.
  ok=1
  for p in 'BalanceTest' 'Bal*' 'com.x.core.Bal*' '*Test' 'core.BalanceTest' 'com.x.core.BalanceTest.one' '*BalanceSpec' \
           'com.x.core.BalanceSpec' 'BalanceSpec$Inner' '*Inner' 'com.x.core.LedgerTest' '*RefundTest' 'com.x.app.CheckoutTest'; do
    ( cd "$F" && CONF_MS=0 ./gradlew -q --rerun-tasks :core:test :app:test >/dev/null 2>&1 )
    cp -R "$F/core/build/test-results/test" "$TMP/all-core"; cp -R "$F/app/build/test-results/test" "$TMP/all-app"
    ( cd "$F" && CONF_MS=0 ./gradlew -q --continue :core:test --tests "$p" :app:test --tests "$p" >/dev/null 2>&1 )
    res="$(python3 - "$ROOT/tests/lib" "$p" "$TMP/all-core" "$TMP/all-app" "$F/core/build/test-results/test" "$F/app/build/test-results/test" "$F/conf-count.txt" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
from gradle_runner import junit, surely, could
p = sys.argv[2]
universe = set((c, n) for d in sys.argv[3:5] for c, n, _ in (junit(d) or []))
# A module whose filter matched nothing failed and left no fresh XML; only XML newer than this run counts.
mark = os.path.getmtime(sys.argv[7]) if os.path.exists(sys.argv[7]) else 0
got = set()
for d in sys.argv[5:7]:
    if os.path.isdir(d) and any(os.path.getmtime(os.path.join(d, f)) >= mark for f in os.listdir(d) if f.endswith(".xml")):
        got |= set((c, n) for c, n, _ in (junit(d) or []))
s = {x for x in universe if surely(p, *x)}
c = {x for x in universe if could(p, *x)}
bad = [f"surely-not-run {x}" for x in s - got] + [f"run-but-not-could {x}" for x in got - c]
print("ok" if not bad else "; ".join(bad))
PY
)"
    rm -rf "$TMP/all-core" "$TMP/all-app"
    [[ "$res" == ok ]] || { ok=0; echo "  pattern $p: $res"; }
  done
  t "AC7a[$V]" "$ok" "for every probe pattern, surely ⊆ Gradle's own selection ⊆ could"

  # (c) + (f): configurations and time per pass, four lines on two test tasks (two waves).
  G4=("./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :core:test --tests com.x.core.LedgerTest"
      "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :app:test --tests '*RefundTest'")
  goal "$F" "${G4[@]}"; ok=1; table=""; LOOP_CONF="$CONF_MS"
  for mode in alone exact merged; do
    case "$mode" in alone) env_=(BDD_LOOP_RUNNER=shell); unsign "$F" ;; exact) env_=(); unsign "$F" ;; merged) env_=(); sign "$F" ;; esac
    want=$([[ $mode == alone ]] && echo 4 || { [[ $mode == exact ]] && echo 2 || echo 1; })
    loop "$F" "${env_[@]}"; first=$SECS; c1=$CONFS; r1=$RC
    loop "$F" "${env_[@]}"; second=$SECS; c2=$CONFS
    [[ "$r1" -eq 0 && "$c1" -eq "$want" && "$c2" -eq "$want" ]] || { ok=0; echo "  $mode: rc=$r1, configurations $c1 then $c2 (want $want)"; }
    table="$table$(printf '\n  | %-6s | %3s builds | first pass %4ss | unchanged pass %4ss |' "$mode" "$want" "$first" "$second")"
  done
  unsign "$F"; LOOP_CONF=0
  t "AC7c[$V]" "$ok" "configurations per pass: 4 run alone, 2 in exact mode (2 waves), 1 merged"
  echo "  timing at CONF_MS=$CONF_MS:$table"

  # (b) the verdict matrix, exact and merged.
  ok=1
  case_() {  # case_ <name> <file> <old> <new> <line>...  — apply a source edit, compare, revert
    local name="$1" file="$F/$2" old="$3" new="$4"; shift 4
    [[ -n "$old" ]] && edit "$file" "$old" "$new"
    goal "$F" "$@"
    unsign "$F"; same "$F" || { ok=0; echo "  $name (exact) differs from running each line alone"; }
    sign "$F"; same "$F" || { ok=0; echo "  $name (merged) differs from running each line alone"; }
    unsign "$F"
    [[ -n "$old" ]] && edit "$file" "$new" "$old"
  }
  case_ "all pass" "" "" "" "${G4[@]}"
  case_ "failing test" app/src/test/java/com/x/app/RefundTest.java 'assertEquals(3,' 'assertEquals(4,' "${G4[@]}"
  case_ "failing display-name test" core/src/test/java/com/x/core/LedgerTest.java 'void addsTwo() { assertTrue(true)' 'void addsTwo() { assertTrue(false)' \
    "./gradlew :core:test --tests com.x.core.LedgerTest" "./gradlew :core:test --tests '*BalanceSpec'" "./gradlew :app:test --tests com.x.app.CheckoutTest"
  case_ "compile error" core/src/main/java/com/x/core/Wallet.java 'return b - a;' 'return b - ;' "${G4[@]}"
  case_ "empty filter" "" "" "" "./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :core:test --tests com.x.core.NoSuchTest" \
    "./gradlew :app:test --tests com.x.app.CheckoutTest"
  case_ "filtered next to unfiltered" core/src/test/java/com/x/core/LedgerTest.java 'void one() { assertTrue(true)' 'void one() { assertTrue(false)' \
    "./gradlew :core:test" "./gradlew :core:test --tests com.x.core.NoSuchTest" "./gradlew :core:test --tests com.x.core.BalanceTest" \
    "./gradlew :app:test --tests com.x.app.CheckoutTest"
  case_ "check next to filtered test" app/src/test/java/com/x/app/RefundTest.java 'assertEquals(3,' 'assertEquals(4,' \
    "./gradlew :app:check" "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :core:compileJava"
  t "AC7b[$V]" "$ok" "every line's verdict equals the line run alone, exact and merged (7 cases on real Gradle)"

  # (d) the init script changes no task's up-to-date state.
  goal "$F" "./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :app:test --tests com.x.app.CheckoutTest"
  ( cd "$F" && CONF_MS=0 ./gradlew -q :core:test --tests com.x.core.BalanceTest :app:test --tests com.x.app.CheckoutTest >/dev/null 2>&1 )
  loop "$F"
  ok=1; for task in :core:compileJava :core:test :app:compileJava :app:test; do
    grep -q "^$task	UP-TO-DATE" "$F/.cascade/gradle/outcomes.tsv" || { ok=0; echo "  $task was not UP-TO-DATE after a build without -I: $(grep "^$task	" "$F/.cascade/gradle/outcomes.tsv")"; }
  done
  t "AC7d[$V]" "$ok" "the init script moves no task's up-to-date state"

  # (e) the configuration cache: reused on the second pass, and the passes are still proven.
  goal "$F" "./gradlew --configuration-cache :core:test --tests com.x.core.BalanceTest" "./gradlew --configuration-cache :app:test --tests com.x.app.CheckoutTest"
  loop "$F"; loop "$F"
  ok=1
  grep -qE 'Configuration cache entry reused|Reusing configuration cache' "$F/.cascade/loop/gradle-1-1.log" || { ok=0; echo "  the second pass did not reuse the configuration cache: $(grep -iE 'configuration cache' "$F/.cascade/loop/gradle-1-1.log" | head -2 | tr '\n' ' ')"; }
  grep -q '^loop: 2 lines — 2 proven' <<<"$OUT" && [[ "$CONFS" -eq 0 ]] || { ok=0; echo "  reused entry did not prove its passes ($(grep '^loop:' <<<"$OUT"); $CONFS configurations)"; }
  t "AC7e[$V]" "$ok" "with --configuration-cache the second pass reuses the entry (0 configurations) and still proves its passes"
done

echo
[[ "$fail" -eq 0 ]] && echo "AC7 all PASS" || echo "AC7 FAILED"
exit "$fail"
