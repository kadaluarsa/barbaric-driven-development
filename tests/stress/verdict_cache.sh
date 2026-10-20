#!/usr/bin/env bash
# E2 for 05b t65-verdict-cache, on real Gradle. Opt-in: needs a JDK, JUnit from Maven Central (or the local cache),
# and the 9.1.0 distribution for the wrapper (inside t64's verified range). The gate (tests/ac/t65_verdict_cache.sh)
# uses the stub; this checks what the stub cannot: real verdicts with and without the cache, and the law build's
# Gradle build cache.
#
#   usage: tests/stress/verdict_cache.sh [gradle-executable]     (default: gradle on PATH)
#
#   (a) parity: DSHARP_CACHE=off, a cold run and a warm run give the same verdict per law and the same DSHARP k/n
#   (b) a warm run proves no GREEN law again — not in the law build, not by its own commands; RED and THEATER re-run
#   (c) a one-byte edit in :core re-runs :core's laws and :app's (it depends on :core), not :web's
#   (d) after `clean`, the law build compiles FROM-CACHE and every law copy still executes (the harness proves GREEN)
#   (e) a signed remote cache URL reaches real Gradle through the init script and an unreachable one breaks nothing
#   (f) a project's settings.gradle with `push = true` cannot override the signed URL or `push = false` (red twin,
#       checked once by hand on Gradle 9.7.1: the same block in `beforeSettings` ends with the project's URL and push=true)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR DSHARP_CACHE DSHARP_HARNESS DSHARP_JOBS INV_MUTANT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
secs() { python3 -c "print(f'{float($2) - float($1):.2f}')"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
G="${1:-gradle}"
WRAPPER=9.1.0

jtest() { mkdir -p "$1/$2/src/test/java/p"
  printf 'package p;\nimport org.junit.jupiter.api.Test;\nimport static org.junit.jupiter.api.Assertions.*;\nclass %s {\n  @Test void law() { %s }\n}\n' "$3" "$4" > "$1/$2/src/test/java/p/$3.java"; }
mutated() { echo "assertNotEquals(\"$1\", System.getenv(\"INV_MUTANT\"));"; }
law() { printf '### %s — %s\ncheck:  ./gradlew %s --tests %s\nbreak:  INV_MUTANT=%s ./gradlew %s --tests %s --rerun\n\n' "$1" "$2" "$3" "$4" "$1" "$3" "$4"; }

fixture() {  # fixture <dir> [extra locked line] [salt: makes every class unique, so the local build cache misses]
  local d="$1" extra="${2:-}" salt="${3:-}"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/core/src/main/java/p" "$d/app/src/main/java/p" "$d/web/src/main/java/p"
  printf "rootProject.name = 'vc'\ninclude 'core', 'app', 'web'\n" > "$d/settings.gradle"
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
  printf 'package p;\npublic class Core { public static int one() { return 1; } static final String SALT = "%s"; }\n' "$salt" > "$d/core/src/main/java/p/Core.java"
  printf 'package p;\npublic class App { public static int two() { return Core.one() + 1; } }\n' > "$d/app/src/main/java/p/App.java"
  printf 'package p;\npublic class Web { public static int three() { return 3; } }\n' > "$d/web/src/main/java/p/Web.java"
  jtest "$d" core D1Test "$(mutated D1)"
  jtest "$d" core D2Test "$(mutated D2)"
  jtest "$d" app D3Test "assertEquals(2, App.two()); $(mutated D3)"
  jtest "$d" web D4Test "$(mutated D4)"
  jtest "$d" core D5Test 'fail("the product broke D5");'
  jtest "$d" web D6Test 'assertTrue(true);'
  ( cd "$d" && "$G" wrapper -q --gradle-version "$WRAPPER" >/dev/null 2>&1 ) || return 1
  mv "$d/gradlew" "$d/gradlew.real"
  printf '#!/bin/sh\necho "$*" >> "%s/invocations.log"\nexec "%s/gradlew.real" "$@"\n' "$d" "$d" > "$d/gradlew"; chmod +x "$d/gradlew"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/dsharp_strength.sh" "$d/tests/"
  {
    echo "# envelope"; echo; echo "<EDIT>"
    law D1 "core one" :core:test p.D1Test
    law D2 "core two" :core:test p.D2Test
    law D3 "app, depends on core" :app:test p.D3Test
    law D4 "web" :web:test p.D4Test
    law D5 "red" :core:test p.D5Test
    law D6 "theater" :web:test p.D6Test
    echo "</EDIT>"; echo; echo "## Locked decisions"; echo; echo "<EDIT>"
    echo "- DSHARP_GRADLE_HARNESS: on — locked 2026-10-20 — reason: stress fixture"
    [[ -n "$extra" ]] && echo "$extra"
    echo "</EDIT>"
  } > "$d/docs/cascade/envelope.md"
  ( cd "$d" && printf '.gradle/\nbuild/\n*/build/\n.cascade/\ninvocations.log\n' > .gitignore && git init -q && git add -A && git commit -qm init )
}
score() {  # score <dir> [env words…] -> $OUT (DSHARP lines), $SECS, $INV (invocations)
  local d="$1"; shift; local t0
  : > "$d/invocations.log"; t0="$(now)"
  OUT="$( cd "$d" && env "$@" bash tests/dsharp_strength.sh 2>/dev/null | grep -E '^(GREEN|RED|THEATER|UNPROVEN|DSHARP|CACHE)' )"
  SECS="$(secs "$t0" "$(now)")"; INV="$(cat "$d/invocations.log")"
}
strip() { echo "$1" | sed -E 's/  \(cached\)$//' | grep -v '^CACHE '; }
own_ran() {  # ids whose own check/break ran (not the law build, not --version, not the map)
  echo "$INV" | grep -v -e bddLaws -e bddAffectedProjects -e '^--version' | grep -oE 'p\.D[0-9]+Test' | sed 's/p\.//; s/Test//' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

if ! "$G" --version >/dev/null 2>&1; then t E2 0 "no Gradle at $G (pass one, or put gradle on PATH)"; exit "$fail"; fi
echo "== Gradle $("$G" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1), wrapper $WRAPPER"
D="$TMP/vc"; fixture "$D" || { t E2 0 "fixture could not be built (JDK, JUnit, or the $WRAPPER distribution missing)"; exit "$fail"; }

ok=1
( cd "$D" && ./gradlew -q compileTestJava >/dev/null 2>&1 )   # warm daemon and dependencies, so (a)'s times compare runs
score "$D" DSHARP_CACHE=off; off="$OUT"; t_off="$SECS"
score "$D" DSHARP_CACHE=on;  cold="$OUT"; t_cold="$SECS"; cold_inv="$INV"
score "$D" DSHARP_CACHE=on;  warm="$OUT"; t_warm="$SECS"
[[ "$(echo "$off" | tail -1)" == "DSHARP 4/6" ]] || { ok=0; echo "  the fixture is not 4 GREEN of 6 with the cache off: $(echo "$off" | tail -1)"; }
[[ "$(strip "$cold")" == "$off" ]] || { ok=0; echo "  (a) cold differs from off:"; diff <(echo "$off") <(strip "$cold") | sed 's/^/    /'; }
[[ "$(strip "$warm")" == "$off" ]] || { ok=0; echo "  (a) warm differs from off:"; diff <(echo "$off") <(strip "$warm") | sed 's/^/    /'; }
echo "$cold_inv" | grep bddLaws | grep -q -- '--build-cache' || { ok=0; echo "  (d) the cold law build had no --build-cache"; }
[[ "$(echo "$warm" | grep -c '(cached)')" -eq 4 ]] || { ok=0; echo "  (b) warm cached $(echo "$warm" | grep -c '(cached)') laws, want 4"; }
inplan="$(awk -F'\t' '$2 ~ /^D/{print $2}' "$D/.cascade/laws/law-harness.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')"
[[ -z "$inplan" || "$inplan" == "D5 D6" ]] || { ok=0; echo "  (b) the warm run's law build took '$inplan', want only D5 D6 (RED, THEATER)"; }
[[ "$(own_ran)" == "D5 D6" ]] || { ok=0; echo "  (b) the warm run ran the own commands of '$(own_ran)', want D5 D6 (RED, THEATER)"; }
printf '// one byte\n' >> "$D/core/src/main/java/p/Core.java"
score "$D" DSHARP_CACHE=on; t_edit="$SECS"
cached_after="$(echo "$OUT" | awk '/\(cached\)$/{print $2}' | tr '\n' ' ' | sed 's/ $//')"
[[ "$cached_after" == "D4" ]] || { ok=0; echo "  (c) after a :core edit the cached laws were '$cached_after', want D4 (web) only"; }
t E2a "$ok" "on real Gradle: cache off, cold and warm give the same verdicts; a warm run re-proves only RED and THEATER; a :core edit re-runs :core's and :app's laws and keeps :web's cached"

ok=1
( cd "$D" && ./gradlew -q clean >/dev/null 2>&1 ); rm -rf "$D/.cascade"
score "$D" DSHARP_CACHE=on; t_clean="$SECS"
log="$(cat "$D"/.cascade/laws/laws-*.log 2>/dev/null)"
echo "$log" | grep -qE '> Task :core:compileJava FROM-CACHE' || { ok=0; echo "  (d) :core:compileJava did not come FROM-CACHE after clean: $(echo "$log" | grep compileJava | head -2)"; }
proved="$(awk -F'\t' '$3=="GREEN"{print $2}' "$D/.cascade/laws/law-harness.tsv" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$proved" == "D1 D2 D3 D4" ]] || { ok=0; echo "  (d) the harness proved '$proved' after clean, want D1 D2 D3 D4 (its copies executed)"; }
echo "$log" | grep -E 'bddLaw(Check|Mutant)_' | grep -q 'FROM-CACHE' && { ok=0; echo "  (d) a law copy came FROM-CACHE"; }
[[ "$(strip "$OUT")" == "$off" ]] || { ok=0; echo "  (d) verdicts after clean differ from off"; }
t E2b "$ok" "on real Gradle, after clean the law build compiles FROM-CACHE, every law copy executes (no copy FROM-CACHE), and verdicts are unchanged"

ok=1
R="$TMP/vc-remote"; fixture "$R" '- DSHARP_GRADLE_BUILD_CACHE_URL: https://127.0.0.1:9/cache/' "salt-$$-$(now)" || { ok=0; echo "  remote fixture failed"; }
score "$R" DSHARP_CACHE=on; ron="$OUT"   # first, on a fresh tree: compile is a local miss, so the remote is asked
rlog="$(cat "$R"/.cascade/laws/laws-*.log 2>/dev/null)"
score "$R" DSHARP_CACHE=off; roff="$OUT"
[[ "$(echo "$roff" | tail -1)" == "DSHARP 4/6" ]] || { ok=0; echo "  (e) the remote fixture is not 4 GREEN of 6: $(echo "$roff" | tail -1)"; }
[[ "$(strip "$ron")" == "$roff" ]] || { ok=0; echo "  (e) an unreachable remote cache changed verdicts:"; diff <(echo "$roff") <(strip "$ron") | sed 's/^/    /'; }
echo "$rlog" | grep -qiE 'remote build cache|127\.0\.0\.1:9|HTTP build cache' || { ok=0; echo "  (e) the law build log never mentions the remote cache, so the init block did not apply"; }
echo "  E2c remote evidence: $(echo "$rlog" | grep -iE 'remote build cache|127\.0\.0\.1:9|HTTP build cache' | head -1 | cut -c1-160)"
t E2c "$ok" "on real Gradle, a signed remote cache URL reaches the law build through the init script, and an unreachable one changes no verdict"

ok=1
# (f) the project's settings cannot turn push back on: it sets push = true; after it runs, the init script's block
# must leave the signed URL and push = false. A probe init script registered after ours prints what Gradle holds.
P="$TMP/vc-push"; fixture "$P" '' "push-$$" || { ok=0; echo "  push fixture failed"; }
printf "buildCache { remote(HttpBuildCache) { url = new URI('https://project.example/'); push = true } }\n" >> "$P/settings.gradle"
cat > "$TMP/probe.gradle" <<'EOF'
settingsEvaluated { s -> println "BDD-PROBE url=${s.buildCache.remote.url} push=${s.buildCache.remote.push}" }
EOF
probe="$( cd "$P" && BDD_BUILD_CACHE_URL=https://signed.example/ ./gradlew.real -q --no-configuration-cache \
          -I "$P/tests/lib/law_harness.init.gradle" -I "$TMP/probe.gradle" help 2>&1 | grep 'BDD-PROBE' )"
[[ "$probe" == "BDD-PROBE url=https://signed.example/ push=false" ]] || { ok=0; echo "  the project's settings overrode the signed remote: '$probe'"; }
probe0="$( cd "$P" && ./gradlew.real -q --no-configuration-cache -I "$P/tests/lib/law_harness.init.gradle" -I "$TMP/probe.gradle" help 2>&1 | grep 'BDD-PROBE' )"
[[ "$probe0" == "BDD-PROBE url=https://project.example/ push=true" ]] || { ok=0; echo "  with no signed URL the project's own cache was changed: '$probe0'"; }
t E2d "$ok" "on real Gradle, a project's settings.gradle with push = true cannot override the signed URL or push = false; with no signed URL its own remote is untouched"

printf 'E2  cache off            %6ss\n' "$t_off"
printf 'E2  cold (cache on)      %6ss\n' "$t_cold"
printf 'E2  warm, unchanged      %6ss\n' "$t_warm"
printf 'E2  :core edit           %6ss\n' "$t_edit"
printf 'E2  after clean          %6ss  (compile FROM-CACHE)\n' "$t_clean"
exit "$fail"
