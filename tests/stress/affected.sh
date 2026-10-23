#!/usr/bin/env bash
# E1/AC8 for 05b t66-affected-laws, on real Gradle. Opt-in: needs a JDK and Maven Central (JUnit). The gate
# (tests/ac/t66_affected_laws.sh) uses the stub; this proves the module map on a real multi-project build and
# measures the cost the selector is meant to remove.
#
#   usage: tests/stress/affected.sh [gradle-executable]     (default: gradle on PATH)
#
# Fixture: :core, :app (depends on :core), :web; 20 Gradle laws (3 core, 2 app, 15 web), one test class each.
# A hop diff in core/ affects 5 laws (core + its dependent app), not web's 15. Measured with a warm daemon:
#   (a) full hop      20 law checks, 20 Gradle invocations
#   (b) affected hop   5 law checks,  5 Gradle invocations
#   (c) the module map alone           1 Gradle invocation
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR AFFECTED_BASE AFFECTED_MUTANT INV_MUTANT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
secs() { python3 -c "print(f'{float($2) - float($1):.2f}')"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
G="${1:-gradle}"

module_for() {
  local n="${1#D}"
  if [[ "$n" -le 3 ]]; then echo ':core'; elif [[ "$n" -le 5 ]]; then echo ':app'; else echo ':web'; fi
}

fixture() {  # fixture <dir> <gradle-executable>
  local d="$1" g="$2" i mod
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/core/src/main/java/p" "$d/app/src/main/java/p" "$d/web/src/main/java/p"
  cat > "$d/settings.gradle" <<'EOF'
rootProject.name = 'affected'
include 'core', 'app', 'web'
EOF
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
  dependencies { implementation project(':core') }
}
EOF
  printf 'package p;\npublic class Core { public static String ok() { return "ok"; } }\n' > "$d/core/src/main/java/p/Core.java"
  printf 'package p;\npublic class App { public static String ok() { return Core.ok(); } }\n' > "$d/app/src/main/java/p/App.java"
  printf 'package p;\npublic class Web { public static String ok() { return "web"; } }\n' > "$d/web/src/main/java/p/Web.java"
  for ((i = 1; i <= 20; i++)); do
    mod="$(module_for "D$i")"
    mkdir -p "$d/${mod#:}/src/test/java/p"
    printf 'package p;\nimport org.junit.jupiter.api.Test;\nimport static org.junit.jupiter.api.Assertions.*;\nclass D%sTest {\n  @Test void law() { assertNotEquals("D%s", System.getenv("INV_MUTANT")); }\n}\n' \
      "$i" "$i" > "$d/${mod#:}/src/test/java/p/D${i}Test.java"
  done
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$g" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\n' > "$d/.gitignore"
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: t66-stress\n' > "$d/docs/cascade/hop-state.md"
  { echo "# envelope"; echo; echo "<EDIT>"
    for ((i = 1; i <= 20; i++)); do
      mod="$(module_for "D$i")"
      printf '### D%s — law %s\ncheck:  ./gradlew %s:test --tests p.D%sTest\nbreak:  INV_MUTANT=D%s ./gradlew %s:test --tests p.D%sTest --rerun\n\n' \
        "$i" "$i" "$mod" "$i" "$i" "$mod" "$i"
    done
    echo "</EDIT>"; } > "$d/docs/cascade/envelope.md"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  cp "$ROOT/tests/affected.sh" "$d/tests/"
  ( cd "$d" && git init -q && git add -A && git commit -qm edge ) || return 1
  return 0
}

run_checks() {  # run_checks <dir> <ids…> -> seconds on stdout (test tasks forced with --rerun)
  local d="$1"; shift
  local start end id mod
  start="$(now)"
  for id in "$@"; do
    mod="$(module_for "$id")"
    ( cd "$d" && ./gradlew -q --console=plain "$mod:test" --tests "p.${id}Test" --rerun >/dev/null 2>&1 ) || return 1
  done
  end="$(now)"; secs "$start" "$end"
}

if ! "$G" --version >/dev/null 2>&1; then
  t E1 0 "no Gradle at $G (pass one, or put gradle on PATH)"
  exit "$fail"
fi
V="$("$G" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1)"
echo "== Gradle ${V:-unknown}"

D="$TMP/affected-${V:-x}"
fixture "$D" "$G" || { t E1 0 "fixture could not be built"; exit "$fail"; }
printf '// hop diff\n' >> "$D/core/src/main/java/p/Core.java"

ok=1
ids="$( cd "$D" && bash tests/affected.sh --list 2>/dev/null )"
[[ "$ids" == $'D1\nD2\nD3\nD4\nD5' ]] || { ok=0; echo "  the selector named '$(echo "$ids" | tr '\n' ' ')'; want D1–D5"; }
rows="$( cd "$D" && BDD_AFFECTED_OUT="$TMP/projects.tsv" ./gradlew -q --no-configuration-cache -I tests/lib/affected.init.gradle bddAffectedProjects >/dev/null 2>&1; grep -c . "$TMP/projects.tsv" 2>/dev/null )"
[[ "${rows:-0}" -eq 3 ]] || { ok=0; echo "  the module map has $rows rows; want 3"; }
grep -q $':app\tapp\t:core' "$TMP/projects.tsv" 2>/dev/null || { ok=0; echo "  the map lost the app -> core dependency"; }

( cd "$D" && ./gradlew -q --console=plain :core:test --tests p.D1Test >/dev/null 2>&1 )   # warm daemon + compile
full="$(run_checks "$D" $(for i in $(seq 1 20); do echo "D$i"; done))" || { ok=0; echo "  the full run failed"; full="?"; }
affected="$(run_checks "$D" D1 D2 D3 D4 D5)" || { ok=0; echo "  the affected run failed"; affected="?"; }
start="$(now)"
( cd "$D" && BDD_AFFECTED_OUT="$TMP/map-only.tsv" ./gradlew -q --no-configuration-cache -I tests/lib/affected.init.gradle bddAffectedProjects >/dev/null 2>&1 ) || { ok=0; echo "  the map-only run failed"; }
map="$(secs "$start" "$(now)")"

printf 'E1  full hop      20 checks  %6ss  20 Gradle invocations\n' "$full"
printf 'E1  affected hop   5 checks  %6ss   5 Gradle invocations\n' "$affected"
printf 'E1  module map         —    %6ss   1 Gradle invocation\n' "$map"
[[ "$full" != "?" && "$affected" != "?" ]] && printf 'E1  saved          %6ss per hop (%s → %s)\n' \
  "$(python3 -c "print(f'{float($full) - float($affected):.2f}')")" "$full" "$affected"

t E1 "$ok" "on real Gradle, a core diff selects D1–D5 (core + dependent app) and not web's 15; the map reads app -> core; E1's full/affected/map costs are above"

exit "$fail"
