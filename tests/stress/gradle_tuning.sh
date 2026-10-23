#!/usr/bin/env bash
# AC4/AC5/AC7/E1 for 05b t69-gradle-tuning, on real Gradle. Opt-in — it needs a JDK, the Gradle distributions to test
# and JUnit from Maven Central (or the local cache), and takes several minutes per version.
#   usage: tests/stress/gradle_tuning.sh [--timing] [gradle-executable ...]   (default: gradle on PATH)
#   CONF_MS=<ms>: the fixture's simulated configuration time for --timing (default 5000, as t62 measured)
# Per Gradle version, on a two-module JUnit 5 fixture:
#   AC7  every loop verdict with tuning on equals tuning off equals each line alone: all pass, a failing test, a compile
#        error, a module whose build logic rejects the configuration cache (dropped, logged), and two tests in two modules
#        that bind one fixed port (the cache runs their tasks at once: the batched build fails and the lines run alone).
#   AC4  forks, signed: the check copy runs in more than one JVM and the mutant copy in one; a law whose classes fail only
#        when they share a JVM is GREEN by the signed harness and RED with DSHARP_HARNESS=off (the merge gate's path).
#        RED TWIN: forks on the mutant prove a THEATER law GREEN (its classes race on one file).
#   AC5  one loop run starts at most one daemon and names it; an immediate second run starts none.
#   --timing: E1 — loop pass 1 / unchanged pass 2 (tuning off, on), farm with 20 laws (forks unsigned, signed), nightly
#        single run vs 3 parts + join.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_LOOP_RUNNER BDD_GRADLE_TUNING \
      DSHARP_HARNESS DSHARP_JOBS DSHARP_SERIAL INV_MUTANT GRADLE_OPTS BDD_LAW_FORKS
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off      # every comparison is between two live runs on one tree
CONF_MS="${CONF_MS:-5000}"
TIMING=0; [[ "${1:-}" == --timing ]] && { TIMING=1; shift; }
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[[ $# -gt 0 ]] || set -- gradle

jt() {  # jt <dir> <module> <class> <body>
  mkdir -p "$1/$2/src/test/java/p"
  printf 'package p;\nimport org.junit.jupiter.api.Test;\nimport static org.junit.jupiter.api.Assertions.*;\nclass %s {\n  @Test void t() throws Exception { %s }\n}\n' "$3" "$4" > "$1/$2/src/test/java/p/$3.java"
}
fixture() {  # fixture <dir> <gradle> -> prints the version
  local d="$1" g="$2" v
  v="$("$g" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1)"
  mkdir -p "$d/gradle/wrapper" "$d/docs/cascade" "$d/tests"
  printf "rootProject.name = 'fx'\ninclude 'core', 'app'\n" > "$d/settings.gradle"
  cat > "$d/build.gradle" <<'EOF'
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
EOF
  printf 'org.gradle.jvmargs=-Xmx%sm\norg.gradle.daemon.idletimeout=120000\n' "$(( 600 + RANDOM % 900 ))" > "$d/gradle.properties"   # a daemon of its own, gone 2 min after
  jt "$d" core BalanceTest 'assertEquals(1, 2 - 1);'
  jt "$d" core LedgerTest 'assertTrue(true);'
  jt "$d" app CheckoutTest 'assertTrue(true);'
  jt "$d" app RefundTest 'assertTrue(true);'
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$g")" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' "$v" > "$d/gradle/wrapper/gradle-wrapper.properties"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/loop.sh" "$ROOT/tests/dsharp_strength.sh" "$d/tests/"
  # The runner and the harness verify their Gradle range; widen it in this copy to the version under test.
  python3 - "$d/tests/lib/gradle_runner.py" "$v" <<'PY'
import re, sys
p, v = sys.argv[1], sys.argv[2]; major, minor = v.split(".")[:2]
s = open(p).read()
open(p, "w").write(re.sub(r'VERIFIED = \("[^"]*", "[^"]*"\)', f'VERIFIED = ("{major}.{minor}", "{major}.{int(minor) + 1}")', s))
PY
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n' > "$d/docs/cascade/envelope.md"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\nconf-count.txt\npids/\n' > "$d/.gitignore"
  ( cd "$d" && git init -q && git add -A && git commit -qm init )
  echo "$v"
}
commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm fx >/dev/null 2>&1 || true; }
goal() { local d="$1"; shift; { printf 'GOAL_STAGE: 05b\n'; printf 'VALIDATOR: %s\n' "$@"; } > "$d/docs/cascade/goal.md"; }
loop() {  # loop <dir> [VAR=value…] -> $OUT, $V (verdicts + rc), $SECS
  local d="$1"; shift; local s0=$SECONDS
  OUT="$(cd "$d" && env "$@" bash tests/loop.sh 2>&1)"; local rc=$?
  V="$(grep -E '^(PASS|FAIL)  |^LOOP [0-9]+/[0-9]+$' <<<"$OUT"; echo "rc=$rc")"; SECS=$(( SECONDS - s0 ))
}
same3() {  # same3 <dir> <label>: alone == tuning off == tuning on, each from clean build outputs so every test runs
  local d="$1" a off on
  rm -rf "$d"/*/build; loop "$d" BDD_LOOP_RUNNER=shell; a="$V"
  rm -rf "$d"/*/build; loop "$d" BDD_GRADLE_TUNING=off; off="$V"
  rm -rf "$d"/*/build; loop "$d"; on="$V"
  [[ "$a" == "$off" && "$a" == "$on" ]] && return 0
  echo "  $2: alone / off / on differ:"; paste <(echo "$a") <(echo "$off") <(echo "$on") | sed 's/^/      /'; return 1
}
envelope() { local d="$1"; shift; { printf '# envelope\n\n<EDIT>\n'; printf '%s\n' "$@"; printf '</EDIT>\n'; } > "$d/docs/cascade/envelope.md"; }
edit() { python3 - "$@" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read(); assert old in s, (p, old); open(p, "w").write(s.replace(old, new, 1))
PY
}

G4=("./gradlew :core:test --tests p.BalanceTest" "./gradlew :core:test --tests p.LedgerTest"
    "./gradlew :app:test --tests p.CheckoutTest" "./gradlew :app:test --tests p.RefundTest")

for G in "$@"; do
  command -v "$G" >/dev/null 2>&1 || { t "T69[$G]" 0 "no such Gradle executable"; continue; }
  F="$TMP/fx-$RANDOM"; V0="$(fixture "$F" "$G" | tail -1)"
  echo "== Gradle $V0 ($G) =="
  if ! ( cd "$F" && ./gradlew -q :core:testClasses :app:testClasses >"$TMP/b.log" 2>&1 ); then
    tail -15 "$TMP/b.log" | sed 's/^/    /'; t "T69[$V0]" 0 "the fixture does not build (JDK, network?)"; continue
  fi

  # ---- AC5 daemon (first, so this fixture's own daemon is not yet running) ----
  goal "$F" "${G4[@]}"; commit "$F"
  # A heap size no running daemon has makes them all incompatible, so the next build must start one — without stopping
  # anybody else's daemons. (A new -D value does not: a daemon applies system properties per build.)
  printf 'org.gradle.jvmargs=-Xmx%sm -XX:MaxMetaspaceSize=%sm\norg.gradle.daemon.idletimeout=120000\n' "$(( 600 + RANDOM % 900 ))" "$(( 300 + RANDOM % 600 ))" > "$F/gradle.properties"; commit "$F"
  loop "$F"; first="$(grep '^loop:' <<<"$OUT")"
  loop "$F"; second="$(grep '^loop:' <<<"$OUT")"
  ok=1
  [[ "$first" == *"daemon: 1 started"* ]] || { ok=0; echo "  first run: $first"; }
  [[ "$second" != *"daemon:"* ]] || { ok=0; echo "  second run started a daemon: $second"; }
  t "AC5[$V0]" "$ok" "one loop run starts one daemon and says so; the next run starts none"

  # ---- AC7 verdict matrix ----
  ok=1
  same3 "$F" "all pass" || ok=0
  edit "$F/app/src/test/java/p/RefundTest.java" 'assertTrue(true)' 'assertTrue(false)'; same3 "$F" "failing test" || ok=0
  edit "$F/app/src/test/java/p/RefundTest.java" 'assertTrue(false)' 'assertTrue(true)'
  printf 'package p; class Broken { int x = ; }\n' > "$F/core/src/test/java/p/Broken.java"; same3 "$F" "compile error" || ok=0
  rm "$F/core/src/test/java/p/Broken.java"
  # A module whose build logic the configuration cache rejects.
  printf "tasks.named('test') { doLast { println \"ran \" + project.name } }\n" > "$F/app/build.gradle"; commit "$F"
  rm -rf "$F/.cascade/gradle/tuning.tsv"
  same3 "$F" "cache-incompatible module" || ok=0
  grep -q '^--configuration-cache	' "$F/.cascade/gradle/tuning.tsv" 2>/dev/null || { ok=0; echo "  the rejection was not dropped"; }
  grep -q 'tuning: --configuration-cache dropped' "$F/.cascade/loop/tuning.log" 2>/dev/null || { ok=0; echo "  the drop was not logged"; }
  rm "$F/app/build.gradle"; commit "$F"
  # Two tests in two modules on one fixed port: concurrent under the cache, so the batched build fails and they run alone.
  port=$(( 40000 + RANDOM % 20000 ))
  jt "$F" core PortTest "try (java.net.ServerSocket s = new java.net.ServerSocket($port)) { Thread.sleep(3000); }"
  jt "$F" app PortTest "try (java.net.ServerSocket s = new java.net.ServerSocket($port)) { Thread.sleep(3000); }"
  goal "$F" "./gradlew :core:test --tests p.PortTest" "./gradlew :app:test --tests p.PortTest"; commit "$F"
  same3 "$F" "one port, two modules" || ok=0
  echo "  port pair, tuning on: $(grep '^loop:' <<<"$OUT")"
  rm "$F/core/src/test/java/p/PortTest.java" "$F/app/src/test/java/p/PortTest.java"; goal "$F" "${G4[@]}"; commit "$F"
  t "AC7[$V0]" "$ok" "every verdict with tuning on equals tuning off equals each line alone (pass, failing test, compile error, a cache-incompatible module dropped and logged, a port shared by two modules)"

  # ---- AC4 forks ----
  ok=1
  rec='java.nio.file.Files.createDirectories(java.nio.file.Paths.get(System.getProperty("user.dir"), "..", "pids")); java.nio.file.Files.writeString(java.nio.file.Paths.get(System.getProperty("user.dir"), "..", "pids", (System.getenv("INV_MUTANT") == null ? "check" : "mutant") + "-" + ProcessHandle.current().pid() + "-" + getClass().getSimpleName()), "");'
  for c in A B C; do jt "$F" core "Fork${c}Test" "$rec Thread.sleep(500); assertNotEquals(\"D1\", System.getenv(\"INV_MUTANT\"));"; done
  # D2's classes fail only when they share one JVM: each asserts the other has not run in it yet.
  for c in A B; do jt "$F" core "Pol${c}Test" 'assertNull(System.getProperty("bdd.pol")); System.setProperty("bdd.pol", "1"); assertNotEquals("D2", System.getenv("INV_MUTANT"));'; done
  # D3 is THEATER (its test ignores the mutant), and its two classes race on one file when they run at once.
  for c in A B; do jt "$F" core "Race${c}Test" "java.nio.file.Path f = java.nio.file.Paths.get(System.getProperty(\"user.dir\"), \"..\", \"race.txt\"); java.nio.file.Files.writeString(f, \"$c\"); Thread.sleep(2500); assertEquals(\"$c\", java.nio.file.Files.readString(f));"; done
  printf 'race.txt\n' >> "$F/.gitignore"
  LAWS4=('### D1 — forks seen' 'check:  ./gradlew :core:test --tests p.Fork*' 'break:  INV_MUTANT=D1 ./gradlew :core:test --tests p.Fork* --rerun'
         '### D2 — shared JVM breaks it' 'check:  ./gradlew :core:test --tests p.Pol*' 'break:  INV_MUTANT=D2 ./gradlew :core:test --tests p.Pol* --rerun'
         '### D3 — theater, racy' 'check:  ./gradlew :core:test --tests p.Race*' 'break:  INV_MUTANT=D3 ./gradlew :core:test --tests p.Race* --rerun')
  HARN='- DSHARP_GRADLE_HARNESS: on — locked 2026-10-22 — reason: stress'
  FORKS='- DSHARP_GRADLE_FORKS: on — locked 2026-10-22 — reason: stress'
  score() { rm -rf "$F/pids"; ( cd "$F" && env "$@" bash tests/dsharp_strength.sh 2>&1 ) | grep -E '^(GREEN|RED|THEATER|UNPROVEN) '; }
  envelope "$F" "$HARN" "${LAWS4[@]}"; commit "$F"
  unsigned="$(score)"; up="$(ls "$F/pids" 2>/dev/null | sed -n 's/^check-\([0-9]*\)-ForkA.*/\1/p;s/^check-\([0-9]*\)-ForkB.*/\1/p;s/^check-\([0-9]*\)-ForkC.*/\1/p' | sort -u | wc -l | tr -d ' ')"
  envelope "$F" "$HARN" "$FORKS" "${LAWS4[@]}"; commit "$F"
  signed="$(score)"
  cp_="$(ls "$F/pids" | grep '^check-' | grep -c Fork | tr -d ' ')"
  cpids="$(ls "$F/pids" | sed -n 's/^check-\([0-9]*\)-Fork.*/\1/p' | sort -u | wc -l | tr -d ' ')"
  mpids="$(ls "$F/pids" | sed -n 's/^mutant-\([0-9]*\)-Fork.*/\1/p' | sort -u | wc -l | tr -d ' ')"
  [[ "$up" -le 1 ]] || { ok=0; echo "  unsigned: the check copy ran in $up JVMs"; }
  [[ "$cpids" -gt 1 && "$mpids" -eq 1 ]] || { ok=0; echo "  signed: check copy in $cpids JVMs (want >1), mutant in $mpids (want 1) [$cp_ check records]"; }
  gate="$(score DSHARP_HARNESS=off)"
  grep -q '^GREEN     D2' <<<"$signed" && grep -q '^RED       D2' <<<"$gate" \
    || { ok=0; echo "  D2 (fails only in a shared JVM): signed harness '$(grep D2 <<<"$signed")', gate path '$(grep D2 <<<"$gate")'"; }
  grep -q '^THEATER   D3' <<<"$signed" || { ok=0; echo "  D3 with the real harness: $(grep D3 <<<"$signed")"; }
  # RED TWIN: forks on the mutant copy instead of the check copy.
  cp "$F/tests/lib/law_harness.init.gradle" "$TMP/init.keep"
  python3 - "$F/tests/lib/law_harness.init.gradle" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("(kind == 'check' && lawForks > 0)", "(kind == 'mutant' && lawForks > 0)", 1)
lines = [l for l in s.split("\n") if "m.maxParallelForks != t.maxParallelForks" not in l]
s = "\n".join(lines)
s = s.replace("else if (c.maxParallelForks != (lawForks > 0 ? Math.max(t.maxParallelForks, lawForks) : t.maxParallelForks))", "else if (false)", 1)
s = s.replace("      else if (false)\n        why = ", "      else if (false) why = ", 1)
open(p, "w").write(s)
PY
  twin="$(score)"
  grep -q '^GREEN     D3' <<<"$twin" || { ok=0; echo "  RED TWIN stayed green: forks on the mutant did not prove THEATER D3 GREEN ($(grep D3 <<<"$twin"))"; }
  cp "$TMP/init.keep" "$F/tests/lib/law_harness.init.gradle"
  t "AC4[$V0]" "$ok" "signed forks reach the check copy only (several JVMs) and never the mutant (one JVM); a shared-JVM failure is GREEN by the signed harness and RED on the gate's path; forks on the mutant prove a racy THEATER law GREEN (red twin)"
  rm -f "$F"/core/src/test/java/p/{Fork,Pol,Race}*Test.java; envelope "$F"; commit "$F"

  # ---- E1 ----
  if [[ "$TIMING" -eq 1 ]]; then
    goal "$F" "${G4[@]}"; commit "$F"
    row=""
    for mode in off on; do
      env_=(); [[ "$mode" == off ]] && env_=(BDD_GRADLE_TUNING=off)
      rm -rf "$F/.gradle/configuration-cache"
      loop "$F" CONF_MS="$CONF_MS" ${env_[@]+"${env_[@]}"}; p1=$SECS
      loop "$F" CONF_MS="$CONF_MS" ${env_[@]+"${env_[@]}"}; p2=$SECS
      row="$row$(printf '\n  | loop, 4 lines in 2 waves | tuning %-3s | pass 1 %3ss | unchanged pass %3ss |' "$mode" "$p1" "$p2")"
    done
    laws=("$HARN")
    for i in $(seq 1 20); do
      m=core; [[ "$i" -gt 10 ]] && m=app
      jt "$F" "$m" "Law${i}Test" "assertNotEquals(\"D$i\", System.getenv(\"INV_MUTANT\"));"
      laws+=("### D$i — law $i" "check:  ./gradlew :$m:test --tests p.Law${i}Test" "break:  INV_MUTANT=D$i ./gradlew :$m:test --tests p.Law${i}Test --rerun")
    done
    envelope "$F" "${laws[@]}"; commit "$F"
    farm() { local s0=$SECONDS; ( cd "$F" && env CONF_MS="$CONF_MS" "$@" bash tests/dsharp_strength.sh >"$TMP/farm" 2>&1 ); echo $(( SECONDS - s0 )); }
    f_off="$(farm BDD_GRADLE_TUNING=off)"; k_off="$(tail -1 "$TMP/farm")"
    f_on="$(farm)"; k_on="$(tail -1 "$TMP/farm")"
    envelope "$F" "${laws[@]:0:1}" "$FORKS" "${laws[@]:1}"; commit "$F"
    f_fk="$(farm)"; k_fk="$(tail -1 "$TMP/farm")"
    envelope "$F" "${laws[@]}"; commit "$F"
    row="$row$(printf '\n  | farm, 20 laws, harness signed | tuning off | %3ss | %s |' "$f_off" "$k_off")"
    row="$row$(printf '\n  | farm, 20 laws, harness signed | tuning on  | %3ss | %s |' "$f_on" "$k_on")"
    row="$row$(printf '\n  | farm, 20 laws, harness signed | + forks signed | %3ss | %s |' "$f_fk" "$k_fk")"
    s0=$SECONDS; ( cd "$F" && CONF_MS="$CONF_MS" bash tests/dsharp_strength.sh >/dev/null 2>&1 ); single=$(( SECONDS - s0 ))
    ( cd "$F" && python3 -B tests/lib/nightly_plan.py "$F" docs/cascade/envelope.md --parts 3 --out "$TMP/plan.tsv" >/dev/null )
    slowest=0
    for k in $(cut -f3 "$TMP/plan.tsv" | sort -u); do
      s0=$SECONDS; ( cd "$F" && CONF_MS="$CONF_MS" bash tests/dsharp_strength.sh --part "$TMP/plan.tsv" "$k" --out "$TMP/part-$k" >/dev/null 2>&1 )
      took=$(( SECONDS - s0 )); [[ "$took" -gt "$slowest" ]] && slowest=$took
    done
    s0=$SECONDS; jout="$( cd "$F" && bash tests/dsharp_strength.sh --join "$TMP/plan.tsv" "$TMP"/part-* 2>&1 | tail -1 )"; jt_=$(( SECONDS - s0 ))
    row="$row$(printf '\n  | nightly, 20 laws | one runner | %3ss | parts: %s (slowest part %ss + join %ss), %s |' "$single" "$(cut -f3 "$TMP/plan.tsv" | sort -u | wc -l | tr -d ' ')" "$slowest" "$jt_" "$jout")"
    echo "  E1 at CONF_MS=$CONF_MS, Gradle $V0, $(sysctl -n hw.ncpu 2>/dev/null || nproc) CPUs:$row"
  fi
done

echo
[[ "$fail" -eq 0 ]] && echo "T69 stress all PASS" || echo "T69 stress FAILED"
exit "$fail"
