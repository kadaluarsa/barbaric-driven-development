#!/usr/bin/env bash
# t100 oracle: plain Gradle lines on one test task are proven from ONE Gradle build — one Test-task copy per line,
# each with the line's own filter — and every line's verdict equals its verdict run alone. Real Gradle and a JDK.
#   usage: tests/ac/t100_isolated_gradle_merge.sh [gradle-executable ...]
#   Gradle: the arguments, else $BDD_T100_GRADLE (space-separated), else the oldest and newest verified Gradle in
#   ~/.gradle/wrapper/dists. No verified Gradle found is a FAIL, never a skip. JUnit comes from Maven Central or
#   the local Gradle cache.
# Per Gradle version, on a two-module JUnit 5 fixture that is a cascade repo on an EXECUTE hop:
#   AC0  the fixture discriminates: its claim pair FAILS when the two classes share a JVM, and PASSES with
#        forkEvery = 1 (one JVM per class) — so a runner that isolated classes would turn a FAIL into a PASS.
#   AC1  every line's verdict with the default loop equals its verdict with BDD_LOOP_RUNNER=shell (alone): the claim
#        pair, a failing class, an all-@Disabled class (t79), a filter that matches nothing, a D# check line, a
#        line on another module, and passing lines.
#   AC2  the passing lines on :core:test with different --tests filters, the D# check line included, are proven
#        from one Gradle build; the loop says so on its `loop:` line.
#   AC3  a second pass on the unchanged tree still proves them from one build, and gives the same verdicts.
#   AC4  BDD_LOOP_RUNNER=shell batches nothing (`N lines ran alone`), as before.
#   AC5  no copy task leaks into the user's build: `gradle tasks --all` in the fixture lists no bddLaw*/bddLoop* task,
#        and the loop changes no file outside the build directories and .cascade/.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_LOOP_RUNNER BDD_GRADLE_TUNING \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t100.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ac() { if [[ "$2" -eq 1 ]]; then echo "  ok    $1  $3"; else FAILS=$((FAILS+1)); echo "  FAIL  $1  $3"; fi; }

# ---- which Gradle --------------------------------------------------------------------------------------------------
verified_range() { python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import gradle_runner as g; print(*g.VERIFIED)' "$ROOT/tests/lib"; }
read -r VMIN VMAX <<<"$(verified_range)"
gversion() { "$1" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1; }
in_range() { python3 -B -c 'import sys
k=lambda v: tuple(int(x) for x in v.split(".")[:3]+["0"]*(3-len(v.split("."))))
sys.exit(0 if k(sys.argv[2]) <= k(sys.argv[1]) < k(sys.argv[3]) else 1)' "$1" "$VMIN" "$VMAX"; }
GRADLES=()
if [[ $# -gt 0 ]]; then GRADLES=("$@")
elif [[ -n "${BDD_T100_GRADLE:-}" ]]; then read -r -a GRADLES <<<"$BDD_T100_GRADLE"
else
  found=()
  for g in "$HOME"/.gradle/wrapper/dists/gradle-*-bin/*/gradle-*/bin/gradle; do
    [[ -x "$g" ]] || continue
    v="$(basename "$(dirname "$(dirname "$g")")")"; v="${v#gradle-}"
    in_range "$v" && found+=("$v $g")
  done
  if [[ ${#found[@]} -gt 0 ]]; then
    sorted="$(printf '%s\n' "${found[@]}" | sort -t. -k1,1n -k2,2n -k3,3n | awk '!seen[$1]++')"
    GRADLES+=("$(head -1 <<<"$sorted" | cut -d' ' -f2-)")
    last="$(tail -1 <<<"$sorted" | cut -d' ' -f2-)"; [[ "$last" != "${GRADLES[0]}" ]] && GRADLES+=("$last")
  fi
fi
if [[ ${#GRADLES[@]} -eq 0 ]]; then
  echo "  FAIL  AC*  no verified Gradle ($VMIN to <$VMAX) found: pass one as an argument or set BDD_T100_GRADLE"
  echo; echo "T100 AC FAILED"; exit 1
fi
command -v java >/dev/null || { echo "  FAIL  AC*  no JDK on PATH"; echo; echo "T100 AC FAILED"; exit 1; }

# ---- the fixture ----------------------------------------------------------------------------------------------------
L_CLAIM="./gradlew :core:test --tests com.x.core.ClaimA --tests com.x.core.ClaimB"
L_BAL="./gradlew :core:test --tests com.x.core.BalanceTest"
L_FAIL="./gradlew :core:test --tests com.x.core.FailingTest"
L_SKIP="./gradlew :core:test --tests com.x.core.SkippedTest"
L_NONE="./gradlew :core:test --tests com.x.core.NoSuchTest"
L_LAW="./gradlew :core:test --tests com.x.core.LedgerTest"
L_ONE="./gradlew :core:test --tests com.x.core.ClaimA"
L_APP="./gradlew :app:test --tests com.x.app.CheckoutTest"
LINES=("$L_BAL" "$L_LAW" "$L_ONE" "$L_CLAIM" "$L_FAIL" "$L_SKIP" "$L_NONE" "$L_APP")
SAME_TASK_PASSING=("$L_BAL" "$L_LAW" "$L_ONE")

fixture() {  # fixture <dir> <gradle>
  local d="$1" g="$2" v
  v="$(gversion "$g")"
  mkdir -p "$d"/core/src/{main,test}/java/com/x/core "$d"/app/src/{main,test}/java/com/x/app "$d/gradle/wrapper" "$d/docs/cascade" "$d/tests"
  printf "rootProject.name = 'fx'\ninclude 'core', 'app'\n" > "$d/settings.gradle"
  cat > "$d/build.gradle" <<'EOF'
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
  local imp='import org.junit.jupiter.api.*; import static org.junit.jupiter.api.Assertions.*;'
  printf 'package com.x.core;\npublic class Wallet { public static int debit(int b, int a) { return b - a; } }\n' > "$d/core/src/main/java/com/x/core/Wallet.java"
  printf 'package com.x.app;\npublic class Checkout { public static int total(int a) { return com.x.core.Wallet.debit(a, 0); } }\n' > "$d/app/src/main/java/com/x/app/Checkout.java"
  # The claim pair: each class claims a JVM-wide system property once. In one JVM the second class fails, whatever
  # the order; in separate JVMs both pass. Alone, the line's two classes share one JVM.
  for c in ClaimA ClaimB; do
    printf 'package com.x.core;\n%s\nclass %s { @BeforeAll static void claim() { String o = System.getProperty("bdd.claim"); System.setProperty("bdd.claim", "%s"); assertNull(o, "JVM already claimed by " + o); } @Test void ok() { assertTrue(true); } }\n' "$imp" "$c" "$c" > "$d/core/src/test/java/com/x/core/$c.java"
  done
  printf 'package com.x.core;\n%s\nclass BalanceTest { @Test void one() { assertEquals(1, Wallet.debit(2,1)); } }\n' "$imp" > "$d/core/src/test/java/com/x/core/BalanceTest.java"
  printf 'package com.x.core;\n%s\nclass LedgerTest { @Test void one() { assertTrue(true); } }\n' "$imp" > "$d/core/src/test/java/com/x/core/LedgerTest.java"
  printf 'package com.x.core;\n%s\nclass FailingTest { @Test void bad() { assertEquals(2, Wallet.debit(2,1)); } }\n' "$imp" > "$d/core/src/test/java/com/x/core/FailingTest.java"
  printf 'package com.x.core;\n%s\nclass SkippedTest { @Test @Disabled void off() { assertTrue(true); } }\n' "$imp" > "$d/core/src/test/java/com/x/core/SkippedTest.java"
  printf 'package com.x.app;\n%s\nclass CheckoutTest { @Test void ok() { assertEquals(3, Checkout.total(3)); } }\n' "$imp" > "$d/app/src/test/java/com/x/app/CheckoutTest.java"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$g" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' "$v" > "$d/gradle/wrapper/gradle-wrapper.properties"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  cp "$ROOT/tests/loop.sh" "$d/tests/loop.sh"   # loop.sh only, as tests/stress does: no oracle gate for the fixture's slice
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\nconf-count.txt\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\n<EDIT>\n### D1 — the ledger holds\ncheck:  %s\nbreak:  false\n</EDIT>\n' "$L_LAW" > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: fx\n\n<EDIT>\nAUTOPILOT: \n</EDIT>\n' > "$d/docs/cascade/hop-state.md"
  { echo '```'; echo 'GOAL_STAGE: 05b'; echo 'GOAL_SLICE: fx'; for l in "${LINES[@]}"; do echo "VALIDATOR: $l"; done; echo '```'; } > "$d/docs/cascade/goal.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm fixture )
}
# verdicts <loop output>: one "PASS|FAIL<TAB>line" per goal line, sorted by line text.
verdicts() { python3 -B -c '
import sys
lines = [l.rstrip("\n") for l in open(sys.argv[1]) if l.strip()]
out = []
for want in sys.argv[2:]:
    v = [l[:4] for l in lines if l[:4] in ("PASS", "FAIL") and l[6:].split("  ")[0].strip() == want]
    out.append(f"{v[0] if len(v) == 1 else ("?" + str(len(v)))}\t{want}")
print("\n".join(sorted(out)))' "$1" "${LINES[@]}"; }
summary() { grep -m1 '^loop: ' "$1" || echo "(no loop: line)"; }
expected() {  # the verdict each line has alone, by construction of the fixture
  local l
  for l in "${LINES[@]}"; do
    if [[ "$l" == "$L_BAL" || "$l" == "$L_LAW" || "$l" == "$L_ONE" || "$l" == "$L_APP" ]]; then printf 'PASS\t%s\n' "$l"
    else printf 'FAIL\t%s\n' "$l"; fi
  done
}

for G in "${GRADLES[@]}"; do
  V="$(gversion "$G")"
  echo "== Gradle $V ($G)"
  D="$TMP/fx-$V"; fixture "$D" "$G"
  ( cd "$D" && ./gradlew -q --no-daemon help >/dev/null 2>&1 ) || true   # warm the dependency cache once

  # AC0  the fixture discriminates
  ok=1
  ( cd "$D" && ./gradlew :core:test --tests com.x.core.ClaimA --tests com.x.core.ClaimB >"$TMP/ac0a-$V.log" 2>&1 ); a=$?
  printf 'allprojects { tasks.withType(Test).configureEach { forkEvery = 1 } }\n' > "$TMP/fork1.gradle"
  ( cd "$D" && ./gradlew -I "$TMP/fork1.gradle" :core:test --rerun-tasks --tests com.x.core.ClaimA --tests com.x.core.ClaimB >"$TMP/ac0b-$V.log" 2>&1 ); b=$?
  [[ "$a" -ne 0 ]] || { ok=0; echo "      the claim pair passed in one JVM — the fixture cannot catch class isolation"; }
  [[ "$b" -eq 0 ]] || { ok=0; echo "      the claim pair failed with forkEvery = 1 — the fixture is broken: $(grep -m2 -E 'FAILED|rror' "$TMP/ac0b-$V.log")"; }
  ( cd "$D" && git clean -qfdx -e .gradle >/dev/null 2>&1 )
  ac "AC0" "$ok" "Gradle $V: the claim pair fails in one JVM and passes with forkEvery = 1"

  # alone verdicts, then the default loop twice
  ( cd "$D" && BDD_LOOP_RUNNER=shell bash tests/loop.sh </dev/null >"$TMP/alone-$V.txt" 2>&1 )
  ( cd "$D" && bash tests/loop.sh </dev/null >"$TMP/batch1-$V.txt" 2>&1 )
  ( cd "$D" && bash tests/loop.sh </dev/null >"$TMP/batch2-$V.txt" 2>&1 )
  VA="$(verdicts "$TMP/alone-$V.txt")"; V1="$(verdicts "$TMP/batch1-$V.txt")"; V2="$(verdicts "$TMP/batch2-$V.txt")"

  # AC1  verdicts equal alone; and the alone verdicts are the expected ones (else the comparison proves little)
  ok=1
  want="$(expected | sort)"
  [[ "$VA" == "$want" ]] || { ok=0; echo "      alone verdicts are not the expected ones:"; diff <(echo "$want") <(echo "$VA") | sed 's/^/        /'; tail -15 "$TMP/alone-$V.txt" | sed 's/^/        | /'; }
  [[ "$V1" == "$VA" ]] || { ok=0; echo "      batched verdicts differ from alone:"; diff <(echo "$VA") <(echo "$V1") | sed 's/^/        /'; }
  ac "AC1" "$ok" "Gradle $V: every line's verdict equals alone (claim pair, failing, all-skipped, no-match, D#, other module, passing)"

  # AC2  the same-task passing lines, the D# line included, are proven from one build
  ok=1
  s1="$(summary "$TMP/batch1-$V.txt")"
  n_same=${#SAME_TASK_PASSING[@]}
  python3 -B - "$s1" "$n_same" <<'PY' || { ok=0; echo "      loop line: $s1"; }
import re, sys
s, need = sys.argv[1], int(sys.argv[2])
m = re.search(r"(\d+) proven in (\d+) gradle build", s)
sys.exit(0 if m and int(m.group(1)) >= need and int(m.group(2)) == 1 else 1)
PY
  for l in "${SAME_TASK_PASSING[@]}"; do
    grep -qF "PASS  $l" "$TMP/batch1-$V.txt" || { ok=0; echo "      not PASS in the batched loop: $l"; }
  done
  grep -q '^LOOP ' "$TMP/batch1-$V.txt" || { ok=0; echo "      the batched loop printed no LOOP line"; tail -5 "$TMP/batch1-$V.txt" | sed 's/^/        /'; }
  ac "AC2" "$ok" "Gradle $V: the $n_same passing :core:test lines with different filters (D# included) are proven from one Gradle build"

  # AC3  an unchanged second pass
  ok=1
  s2="$(summary "$TMP/batch2-$V.txt")"
  python3 -B - "$s2" "$n_same" <<'PY' || { ok=0; echo "      second pass loop line: $s2"; }
import re, sys
s, need = sys.argv[1], int(sys.argv[2])
m = re.search(r"(\d+) proven in (\d+) gradle build", s)
sys.exit(0 if m and int(m.group(1)) >= need and int(m.group(2)) == 1 else 1)
PY
  [[ "$V2" == "$VA" ]] || { ok=0; echo "      second-pass verdicts differ from alone"; diff <(echo "$VA") <(echo "$V2") | sed 's/^/        /'; }
  ac "AC3" "$ok" "Gradle $V: a second pass on the unchanged tree proves them from one build, with the same verdicts"

  # AC4  shell batches nothing
  ok=1
  sa="$(summary "$TMP/alone-$V.txt")"
  [[ "$sa" == *"${#LINES[@]} lines ran alone"* && "$sa" != *proven* ]] || { ok=0; echo "      shell loop line: $sa"; }
  ac "AC4" "$ok" "Gradle $V: BDD_LOOP_RUNNER=shell runs every line alone"

  # AC5  nothing leaks into the user's build
  ok=1
  ( cd "$D" && ./gradlew -q tasks --all >"$TMP/tasks-$V.txt" 2>&1 )
  ! grep -qiE 'bddLaw|bddLoop' "$TMP/tasks-$V.txt" || { ok=0; echo "      a copy task is visible in the user's own build"; }
  ( cd "$D" && git status --porcelain --untracked-files=all | grep -vE '^\?\? (\.cascade/|\.gradle/|core/build/|app/build/|build/)' ) | grep -q . \
    && { ok=0; echo "      the loop left tracked or unexpected files: $(cd "$D" && git status --porcelain | head -3 | tr '\n' ' ')"; }
  ac "AC5" "$ok" "Gradle $V: no copy task in the user's own build, and no file outside build dirs and .cascade/ changed"
done

echo
if [[ "$FAILS" -eq 0 ]]; then echo "T100 AC all PASS"; else echo "T100 AC FAILED ($FAILS)"; fi
exit $(( FAILS > 0 ))
