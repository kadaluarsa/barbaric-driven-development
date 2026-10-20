#!/usr/bin/env bash
# AC4/AC5/E1 for 05b t64-law-harness-jvm: the law harness's claims on real Gradle. Opt-in — it needs a JDK, the
# Gradle distributions to test, and Maven Central (JUnit). CI runs it in pack-self-check.yml.
#   usage: tests/stress/law_harness.sh [--timing N] [gradle-executable ...]   (default: gradle on PATH)
# Per Gradle version, on a five-module JUnit 5 fixture built with that version's wrapper:
#   (a) verdict equality: every law's DSHARP line with the harness on equals the line with DSHARP_HARNESS=off, and
#       the harness proved exactly the laws it should (the plain GREEN ones) from one build
#   (b) a module that does not compile: the harness proves nothing, every verdict is still the per-command one
#   (c) up-to-date state: after a law build, `:core:test` is as up to date as before, and its configuration-cache
#       entry is reused
#   RED TWINS: the init script with its fidelity checks removed proves the `doFirst` and `onlyIf` laws GREEN where
#   their own commands say THEATER; law_harness.py with §4 reduced to "the mutant failed" proves RED laws GREEN.
#   --timing N: E1's table — N GREEN laws scored per-command, per-command with DSHARP_JOBS=4, and by the harness.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR DSHARP_HARNESS DSHARP_JOBS INV_MUTANT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
TIMING=0
[[ "${1:-}" == --timing ]] && { TIMING="$2"; shift 2; }
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[[ $# -gt 0 ]] || set -- gradle

jtest() {  # jtest <dir> <module> <class> <body of the one test>
  mkdir -p "$1/$2/src/test/java/p"
  printf 'package p;\nimport org.junit.jupiter.api.Test;\nimport static org.junit.jupiter.api.Assertions.*;\nclass %s {\n  @Test void law() { %s }\n}\n' "$3" "$4" > "$1/$2/src/test/java/p/$3.java"
}
mutated() { echo "assertNotEquals(\"$1\", System.getenv(\"INV_MUTANT\"));"; }

fixture() {  # fixture <dir> <gradle> <with broken module: 0|1> [extra GREEN laws]
  local d="$1" g="$2" broken="$3" extra="${4:-0}" i mods="'core', 'app', 'odd', 'gated'"
  [[ "$broken" -eq 1 ]] && mods="$mods, 'broken'"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/core" "$d/app" "$d/odd" "$d/gated"   # Gradle 9 will not configure a project with no directory
  printf "rootProject.name = 'fx'\ninclude %s\n" "$mods" > "$d/settings.gradle"
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
project(':app') {
  test {
    systemProperty 'app.prop', 'yes'
    environment 'APP_ENV', 'set'
    jvmArgumentProviders.add({ ['-Dapp.provided=yes'] } as CommandLineArgumentProvider)
    filter { includeTestsMatching 'p.*' }
  }
}
// odd: the build switches its tests into a mode that no longer sees the mutation — only the original does this
project(':odd') { test { doFirst { systemProperty 'odd.strict', 'true' } } }
// gated: the original never runs, so its own commands pass both ways (THEATER); a copy would run
project(':gated') { test { onlyIf { false } } }
EOF
  if [[ "$extra" -eq 0 ]]; then
  jtest "$d" core D1Test "$(mutated D1)"
  jtest "$d" core D2Test "$(mutated D2)"
  jtest "$d" core D3Test 'fail("the product broke D3");'
  jtest "$d" core D4Test 'assertTrue(true);'
  jtest "$d" core D10Test "$(mutated D10)"
  jtest "$d" app D6Test "assertEquals(\"yes\", System.getProperty(\"app.prop\")); assertEquals(\"set\", System.getenv(\"APP_ENV\")); assertEquals(\"yes\", System.getProperty(\"app.provided\")); $(mutated D6)"
  jtest "$d" odd D7Test 'if (!"true".equals(System.getProperty("odd.strict"))) { assertNotEquals("D7", System.getenv("INV_MUTANT")); }'
  jtest "$d" gated D8Test "$(mutated D8)"
  fi
  if [[ "$broken" -eq 1 ]]; then
    mkdir -p "$d/broken/src/main/java/p"; printf 'package p;\nclass Broken { int x = "no"; }\n' > "$d/broken/src/main/java/p/Broken.java"
    jtest "$d" broken D9Test "$(mutated D9)"
  fi
  for ((i = 0; i < extra; i++)); do jtest "$d" core "X${i}Test" "$(mutated "D$((100 + i))")"; done
  ( cd "$d" && "$g" wrapper -q >/dev/null 2>&1 ) || return 1
  mv "$d/gradlew" "$d/gradlew.real"
  printf '#!/bin/sh\necho "$*" >> "%s/invocations.log"\nexec "%s/gradlew.real" "$@"\n' "$d" "$d" > "$d/gradlew"; chmod +x "$d/gradlew"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/dsharp_strength.sh" "$d/tests/"
  law() { printf '### %s — %s\ncheck:  ./gradlew %s --tests %s\nbreak:  INV_MUTANT=%s ./gradlew %s --tests %s%s\n\n' "$1" "$2" "$3" "$4" "$1" "$3" "$4" "${5- --rerun}"; }
  {
    echo "# envelope"; echo; echo "<EDIT>"
    if [[ "$extra" -eq 0 ]]; then
      law D1 "core law one" :core:test 'p.D1Test'
      law D2 "core law two" :core:test 'p.D2Test'
      law D3 "red: the product broke it" :core:test 'p.D3Test'
      law D4 "theater: the test cannot fail" :core:test 'p.D4Test'
      law D5 "no test matches" :core:test 'p.Nope*'
      law D6 "app law with build config" :app:test 'p.D6Test'
      law D7 "doFirst changes the run" :odd:test 'p.D7Test'
      law D8 "onlyIf false skips the task" :gated:test 'p.D8Test'
      [[ "$broken" -eq 1 ]] && law D9 "module does not compile" :broken:test 'p.D9Test'
      law D10 "old shape, no --rerun" :core:test 'p.D10Test' ""
    fi
    for ((i = 0; i < extra; i++)); do law "D$((100 + i))" "timing law $i" :core:test "p.X${i}Test"; done
    echo "</EDIT>"; echo; echo "## Locked decisions"; echo; echo "<EDIT>"; echo "- DSHARP_GRADLE_HARNESS: on — locked 2026-10-20 — reason: stress fixture"; echo "</EDIT>"
  } > "$d/docs/cascade/envelope.md"
  ( cd "$d" && git init -q && printf '.gradle/\nbuild/\n*/build/\n.cascade/\ninvocations.log\n' > .gitignore && git add -A && git commit -qm init )
}
score() {  # score <dir> [env words…]  -> DSHARP lines on stdout; invocations in <dir>/inv.<n>
  local d="$1"; shift
  : > "$d/invocations.log"
  ( cd "$d" && env "$@" bash tests/dsharp_strength.sh 2>/dev/null | grep -E '^(GREEN|RED|THEATER|UNPROVEN|DSHARP)' )
}
inv() { grep -c . "$1/invocations.log" 2>/dev/null | tr -d ' '; }
harness_builds() { grep -c 'bddLaws' "$1/invocations.log" 2>/dev/null | tr -d ' '; }

for g in "$@"; do
  v="$("$g" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1)"
  [[ -n "$v" ]] || { t "AC4[$g]" 0 "no Gradle at $g"; continue; }
  echo "== Gradle $v"
  if [[ "$TIMING" -gt 0 ]]; then
    D="$TMP/timing-$v"; fixture "$D" "$g" 0 "$TIMING" || { t "E1[$v]" 0 "fixture"; continue; }
    ( cd "$D" && ./gradlew.real -q :core:compileTestJava >/dev/null 2>&1 )   # warm the daemon and compile once
    s=$(date +%s); score "$D" DSHARP_HARNESS=off >/dev/null; a=$(( $(date +%s) - s )); ia="$(inv "$D")"
    s=$(date +%s); score "$D" DSHARP_HARNESS=off DSHARP_JOBS=4 >/dev/null; b=$(( $(date +%s) - s )); ib="$(inv "$D")"
    s=$(date +%s); out="$(score "$D")"; c=$(( $(date +%s) - s )); ic="$(inv "$D")"
    rss="$(ps -o rss= -p "$(pgrep -f "GradleDaemon.*${v}" | head -1)" 2>/dev/null | tr -d ' ')"
    echo "E1  Gradle $v, $TIMING GREEN laws: per-command ${a}s ($ia builds) | DSHARP_JOBS=4 ${b}s ($ib builds) | harness ${c}s ($ic builds) | daemon RSS ${rss:-?} KB | $(echo "$out" | tail -1)"
    continue
  fi
  D="$TMP/fx-$v"; fixture "$D" "$g" 0 || { t "AC4[$v]" 0 "the fixture did not build with $g"; continue; }
  off="$(score "$D" DSHARP_HARNESS=off)"; ioff="$(inv "$D")"
  on="$(score "$D")"; ion="$(inv "$D")"; hb="$(harness_builds "$D")"
  ok=1
  [[ "$on" == "$off" ]] || { ok=0; echo "  verdicts differ:"; diff <(echo "$off") <(echo "$on") | sed 's/^/    /'; }
  echo "$off" | grep -q '^GREEN     D1 ' && echo "$off" | grep -q '^RED       D3 ' && echo "$off" | grep -q '^THEATER   D4 ' \
    && echo "$off" | grep -q '^THEATER   D7 ' && echo "$off" | grep -q '^THEATER   D8 ' && echo "$off" | grep -q '^GREEN     D6 ' \
    || { ok=0; echo "  the fixture's per-command verdicts are not the designed ones:"; echo "$off" | sed 's/^/    /'; }
  proven="$(awk -F'\t' '$3=="GREEN"{print $2}' "$D/.cascade/laws/law-harness.tsv" 2>/dev/null | sort | tr '\n' ' ')"
  [[ "$proven" == "D1 D2 D6 " && "$hb" -eq 1 ]] || { ok=0; echo "  the harness proved '$proven' in $hb build(s); want 'D1 D2 D6 ' in 1"; cat "$D/.cascade/laws/law-harness.tsv" 2>/dev/null | sed 's/^/    /'; }
  [[ "$ion" -lt "$ioff" ]] || { ok=0; echo "  harness on made $ion Gradle invocations, off made $ioff"; }
  t "AC4[$v]" "$ok" "Gradle $v: every DSHARP line equals the per-command one; D1, D2, D6 proven GREEN from 1 build; $ion invocations instead of $ioff"

  # RED TWIN (fidelity): the init script without its fidelity checks takes the doFirst and onlyIf laws
  ok=1; cp -R "$D/tests/lib" "$TMP/lib-keep-$v"
  python3 - "$D/tests/lib/law_harness.init.gradle" <<'PY' || ok=0
import sys
p = sys.argv[1]; s = open(p).read()
old = "      if (t.ignoreFailures) why = 'the original ignores failures'"
if old not in s: sys.exit("twin: fidelity block not found")
s = s.replace(old, "      if (false) why = 'twin'\n      else if (true) why = null\n" + old.replace("      if", "      else if", 1))
open(p, "w").write(s)
PY
  tw="$(score "$D")"
  { echo "$tw" | grep -q '^GREEN     D7 ' && echo "$tw" | grep -q '^GREEN     D8 '; } \
    || { ok=0; echo "  red twin (fidelity off) did not turn D7/D8 GREEN — the fidelity check is not what keeps them per-command:"; echo "$tw" | grep -E 'D7|D8' | sed 's/^/    /'; }
  rm -rf "$D/tests/lib"; cp -R "$TMP/lib-keep-$v" "$D/tests/lib"
  # RED TWIN (§4): GREEN whenever the mutant failed
  python3 - "$D/tests/lib/law_harness.py" <<'PY' || ok=0
import sys
p = sys.argv[1]; s = open(p).read()
old = '    lid = law["id"]\n    if elig.get'
if old not in s: sys.exit("twin: proven() not found")
s = s.replace(old, '    lid = law["id"]\n    m0 = outcomes.get(f"{law[\'proj\']}bddLawMutant_{lid}")\n    if m0 and m0[0] == "FAILED":\n        return True, ""\n    if elig.get', 1)
open(p, "w").write(s)
PY
  tw="$(score "$D")"
  echo "$tw" | grep -q '^GREEN     D3 ' || { ok=0; echo "  red twin (§4 reduced) did not turn RED D3 GREEN:"; echo "$tw" | grep D3 | sed 's/^/    /'; }
  rm -rf "$D/tests/lib"; cp -R "$TMP/lib-keep-$v" "$D/tests/lib"
  t "AC4-twins[$v]" "$ok" "Gradle $v: without the fidelity checks D7 (doFirst) and D8 (onlyIf) are proven GREEN against their THEATER; with §4 reduced to 'the mutant failed', RED D3 is proven GREEN"

  # (c) up-to-date state and the user's configuration cache. A fixture whose laws are all the harness's, so the only
  # build between the two plain runs is the law build (a per-command `--tests` run would itself change :core:test).
  ok=1; C="$TMP/fxc-$v"; fixture "$C" "$g" 0 3 || ok=0
  ( cd "$C" && ./gradlew.real -q --configuration-cache :core:test >/dev/null 2>&1; ./gradlew.real --configuration-cache :core:test --console=plain > "$TMP/cc1.log" 2>&1 )
  score "$C" >/dev/null
  [[ "$(awk -F'\t' '$3=="GREEN"' "$C/.cascade/laws/law-harness.tsv" 2>/dev/null | wc -l | tr -d ' ')" -eq 3 && "$(inv "$C")" -eq 1 ]] \
    || { ok=0; echo "  the AC5 fixture's laws were not all proven by one law build ($(inv "$C") invocations)"; }
  ( cd "$C" && ./gradlew.real --configuration-cache :core:test --console=plain > "$TMP/cc2.log" 2>&1 )
  grep -q 'Task :core:test UP-TO-DATE' "$TMP/cc1.log" || { ok=0; echo "  precondition: :core:test was not UP-TO-DATE before the law build"; }
  grep -q 'Task :core:test UP-TO-DATE' "$TMP/cc2.log" || { ok=0; echo "  :core:test was not UP-TO-DATE after a law build"; grep 'Task :core:test' "$TMP/cc2.log" | sed 's/^/    /'; }
  grep -qi 'Reusing configuration cache' "$TMP/cc2.log" || { ok=0; echo "  the user's configuration-cache entry was not reused after a law build"; }
  t "AC5[$v]" "$ok" "Gradle $v: a law build leaves :core:test UP-TO-DATE and the user's configuration-cache entry reused"

  # (b) a module that does not compile: nothing proven, verdicts per-command
  B="$TMP/fxb-$v"; fixture "$B" "$g" 1 || { t "AC4b[$v]" 0 "fixture"; continue; }
  off="$(score "$B" DSHARP_HARNESS=off)"; on="$(score "$B")"
  ok=1
  [[ "$on" == "$off" ]] || { ok=0; echo "  verdicts differ with a broken module:"; diff <(echo "$off") <(echo "$on") | sed 's/^/    /'; }
  echo "$off" | grep -q '^RED       D9 ' || { ok=0; echo "  D9 is not RED per-command"; }
  t "AC4b[$v]" "$ok" "Gradle $v: with a module that does not compile, every DSHARP line still equals the per-command one"
done
exit "$fail"
