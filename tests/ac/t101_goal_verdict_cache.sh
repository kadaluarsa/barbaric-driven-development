#!/usr/bin/env bash
# t101 oracle: tests/loop.sh reuses a goal line's PASS while nothing the line depends on changed; it never reuses a
# FAIL, never decides an autopilot edge from the cache, and keeps the receipt's whole-tree fingerprint.
#   usage: tests/ac/t101_goal_verdict_cache.sh [gradle-executable]
#   Gradle: the argument, else $BDD_T101_GRADLE, else the newest verified Gradle in ~/.gradle/wrapper/dists. A JDK.
#   No verified Gradle is a FAIL, never a skip.
# Fixture: a two-module JUnit 5 cascade repo (:app depends on :core) on an EXECUTE hop. Goal lines:
#   G_CORE  ./gradlew :core:test --tests com.x.core.BalanceTest       keyed by :core (and build logic, toolchain…)
#   G_APP   ./gradlew :app:test --tests com.x.app.CheckoutTest        keyed by :app and :core
#   S_PATH  a shell line that counts its runs; a signed `- LOOP_CACHE_PATHS: tools/ :: <line>` keys it by tools/
#   S_FREE  a shell line that counts its runs; no key: it always runs
#   S_FLIP  a shell line that fails while tools/flip exists; keyed like S_PATH by its own signed line
#   AC1  a docs-only commit: G_CORE, G_APP, S_PATH come from the cache (`(cached)`), S_FREE runs again; LOOP n/n.
#   AC2  an edit under core/: G_CORE and G_APP run again; an edit under app/: only G_APP runs again.
#   AC3  a build-logic edit (build.gradle) runs every Gradle line again; an edit under tools/ (a non-doc file that no
#        module holds) runs S_PATH and every Gradle line again.
#   AC4  a changed pack version (.claude-plugin/plugin.json) or a changed JAVA_TOOL_OPTIONS runs every keyed line again.
#   AC5  a FAIL is never reused: S_FLIP fails, a docs-only commit, it runs again (and still fails).
#   AC6  BDD_LOOP_CACHE=off runs every line; an unsigned or uncommitted LOOP_CACHE_PATHS line keys nothing.
#   AC7  an entry with a wrong key, or a symlinked entry, is a miss; a tree that changes while the loop runs stores
#        nothing.
#   AC8  the receipt after a cached n/n names the whole-tree fingerprint (cascade_worktree_sha).
#   AC10 only a plain Gradle line on one module gets a Gradle key: `./gradlew test` and a :core line with `&& true`
#        run on every pass.
#   AC9  the autopilot gate never reads the cache: an EXECUTE→next edge committed through the real pre-commit hook runs
#        S_PATH again although its entry is fresh, and .cascade/goal-verdicts/ is byte-for-byte the same after it.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_LOOP_RUNNER BDD_LOOP_CACHE \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_AUTOPILOT_LOOP_MINUTES JAVA_TOOL_OPTIONS
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t101.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FAILS=0
ac() { if [[ "$2" -eq 1 ]]; then echo "  ok    $1  $3"; else FAILS=$((FAILS+1)); echo "  FAIL  $1  $3"; fi; }

# ---- which Gradle ----------------------------------------------------------------------------------------------------
read -r VMIN VMAX <<<"$(python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import gradle_runner as g; print(*g.VERIFIED)' "$ROOT/tests/lib")"
in_range() { python3 -B -c 'import sys
k=lambda v: tuple(int(x) for x in (v.split(".")+["0","0"])[:3])
sys.exit(0 if k(sys.argv[2]) <= k(sys.argv[1]) < k(sys.argv[3]) else 1)' "$1" "$VMIN" "$VMAX"; }
G="${1:-${BDD_T101_GRADLE:-}}"
if [[ -z "$G" ]]; then
  best=""
  for g in "$HOME"/.gradle/wrapper/dists/gradle-*-bin/*/gradle-*/bin/gradle; do
    [[ -x "$g" ]] || continue
    v="$(basename "$(dirname "$(dirname "$g")")")"; v="${v#gradle-}"
    in_range "$v" && best="$(printf '%s %s\n%s\n' "$v" "$g" "$best" | sed '/^$/d' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  done
  G="${best#* }"
fi
if [[ -z "$G" || ! -x "$G" ]]; then
  echo "  FAIL  AC*  no verified Gradle ($VMIN to <$VMAX): pass one as an argument or set BDD_T101_GRADLE"; echo; echo "T101 AC FAILED"; exit 1
fi
command -v java >/dev/null || { echo "  FAIL  AC*  no JDK on PATH"; echo; echo "T101 AC FAILED"; exit 1; }
GV="$("$G" --version 2>/dev/null | sed -n 's/^Gradle \([0-9][0-9.]*\).*/\1/p' | head -1)"
echo "== Gradle $GV ($G)"

# ---- the fixture -------------------------------------------------------------------------------------------------------
C="$TMP/counts"; mkdir -p "$C"
G_CORE="./gradlew :core:test --tests com.x.core.BalanceTest"
G_APP="./gradlew :app:test --tests com.x.app.CheckoutTest"
S_PATH="sh -c 'echo x >> $C/path; test -f tools/run.sh'"
S_FREE="sh -c 'echo x >> $C/free; true'"
S_FLIP="sh -c 'echo x >> $C/flip; test ! -f tools/flip'"
D="$TMP/fx"
mkdir -p "$D"/core/src/{main,test}/java/com/x/core "$D"/app/src/{main,test}/java/com/x/app "$D/gradle/wrapper" "$D/docs/cascade" "$D/tests" "$D/tools" "$D/.claude-plugin"
printf "rootProject.name = 'fx'\ninclude 'core', 'app'\n" > "$D/settings.gradle"
cat > "$D/build.gradle" <<'EOF'
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
imp='import org.junit.jupiter.api.*; import static org.junit.jupiter.api.Assertions.*;'
printf 'package com.x.core;\npublic class Wallet { public static int debit(int b, int a) { return b - a; } }\n' > "$D/core/src/main/java/com/x/core/Wallet.java"
printf 'package com.x.app;\npublic class Checkout { public static int total(int a) { return com.x.core.Wallet.debit(a, 0); } }\n' > "$D/app/src/main/java/com/x/app/Checkout.java"
printf 'package com.x.core;\n%s\nclass BalanceTest { @Test void one() { assertEquals(1, Wallet.debit(2,1)); } }\n' "$imp" > "$D/core/src/test/java/com/x/core/BalanceTest.java"
printf 'package com.x.app;\n%s\nclass CheckoutTest { @Test void ok() { assertEquals(3, Checkout.total(3)); } }\n' "$imp" > "$D/app/src/test/java/com/x/app/CheckoutTest.java"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$G" > "$D/gradlew"; chmod +x "$D/gradlew"
printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' "$GV" > "$D/gradle/wrapper/gradle-wrapper.properties"
printf '#!/bin/sh\ntrue\n' > "$D/tools/run.sh"
printf '{"name": "fx", "version": "1.0.0"}\n' > "$D/.claude-plugin/plugin.json"
echo "# notes" > "$D/docs/notes.md"
cp -R "$ROOT/tests/lib" "$D/tests/lib"; cp "$ROOT/tests/loop.sh" "$D/tests/loop.sh"
mkdir -p "$D/.githooks"; cp -R "$ROOT/.githooks/." "$D/.githooks/"
for f in critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$D/tests/"; done
find "$D" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
printf '.cascade/\n.gradle/\nbuild/\n*/build/\n' > "$D/.gitignore"
envelope() {  # envelope <extra lines inside the signed block>
  printf '# envelope\n\n## Locked decisions\n\n<EDIT>\n- LOOP_CACHE_PATHS: tools/ :: %s\n- LOOP_CACHE_PATHS: tools/ :: %s\n%s</EDIT>\n' "$S_PATH" "$S_FLIP" "${1:-}" > "$D/docs/cascade/envelope.md"
}
envelope
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\nAUTOPILOT: 05b a, 05b b\n</EDIT>\n' > "$D/docs/cascade/hop-state.md"
echo '# spec' > "$D/docs/cascade/05b-a.md"
goal() { { echo '```'; echo 'GOAL_STAGE: 05b'; echo 'GOAL_SLICE: a'; for l in "$@"; do echo "VALIDATOR: $l"; done; echo '```'; } > "$D/docs/cascade/goal.md"; }
goal "$G_CORE" "$G_APP" "$S_PATH" "$S_FREE"
commit() { ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm "${1:-edit}" ); }
( cd "$D" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm fixture )
( cd "$D" && ./gradlew -q help >/dev/null 2>&1 ) || true

loop() { ( cd "$D" && env "$@" bash tests/loop.sh </dev/null >"$TMP/out" 2>&1 ); cat "$TMP/out" > "$TMP/last"; }
cached() { grep -qF "PASS  $1  (cached)" "$TMP/last"; }
ran_pass() { grep -qxF "PASS  $1" "$TMP/last"; }
count() { [[ -f "$C/$1" ]] && wc -l < "$C/$1" | tr -d ' ' || echo 0; }
show() { sed 's/^/        | /' "$TMP/last" | tail -12; }

# ---- warm-up: a full pass stores every keyed PASS ------------------------------------------------------------------------
loop; grep -q '^LOOP 4/4' "$TMP/last" || { echo "  setup: the first loop is not 4/4"; show; }

# ---- AC1  docs-only commit --------------------------------------------------------------------------------------------------
ok=1
echo "more" >> "$D/docs/notes.md"; commit docs
f0="$(count free)"; p0="$(count path)"
loop
for l in "$G_CORE" "$G_APP" "$S_PATH"; do cached "$l" || { ok=0; echo "      not cached after a docs-only commit: $l"; }; done
[[ "$(count free)" -eq $((f0 + 1)) ]] || { ok=0; echo "      the unkeyed line did not run again"; }
[[ "$(count path)" -eq "$p0" ]] || { ok=0; echo "      the cached signed-path line ran anyway"; }
grep -q '^LOOP 4/4' "$TMP/last" || { ok=0; echo "      not LOOP 4/4:"; show; }
ac AC1 "$ok" "a docs-only commit reuses the PASS of both Gradle lines and the signed-path line, runs the unkeyed line again, LOOP 4/4"

# ---- AC2  module edits --------------------------------------------------------------------------------------------------------
ok=1
printf '// touched\n' >> "$D/core/src/main/java/com/x/core/Wallet.java"; commit core
loop
for l in "$G_CORE" "$G_APP"; do ran_pass "$l" || { ok=0; echo "      not run again after a :core edit: $l"; }; done
cached "$S_PATH" || { ok=0; echo "      the tools/ line was not cached after a :core edit"; }
printf '// touched\n' >> "$D/app/src/main/java/com/x/app/Checkout.java"; commit app
loop
cached "$G_CORE" || { ok=0; echo "      the :core line was not cached after an :app-only edit"; }
ran_pass "$G_APP" || { ok=0; echo "      the :app line was not run again after an :app edit"; }
ac AC2 "$ok" "a :core edit runs the :core and :app lines again; an :app edit runs only the :app line again"

# ---- AC3  build logic and declared paths -----------------------------------------------------------------------------------------
ok=1
printf '// touched\n' >> "$D/build.gradle"; commit build
loop
for l in "$G_CORE" "$G_APP"; do ran_pass "$l" || { ok=0; echo "      not run again after a build-logic edit: $l"; }; done
p0="$(count path)"
printf '# touched\n' >> "$D/tools/run.sh"; commit tools
loop
[[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      the signed-path line did not run again after a tools/ edit"; }
ran_pass "$G_CORE" || { ok=0; echo "      a tools/ edit (a non-doc file no module holds) did not run the :core line again"; }
ac AC3 "$ok" "a build-logic edit runs every Gradle line again; an edit under tools/ runs the signed-path line and every Gradle line again"

# ---- AC4  pack version and environment -----------------------------------------------------------------------------------------
ok=1
loop   # settle: everything cached
printf '{"name": "fx", "version": "1.0.1"}\n' > "$D/.claude-plugin/plugin.json"; commit pack
p0="$(count path)"; loop
for l in "$G_CORE" "$G_APP"; do ran_pass "$l" || { ok=0; echo "      not run again after a pack version change: $l"; }; done
[[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      the signed-path line did not run again after a pack version change"; }
loop
p0="$(count path)"; loop JAVA_TOOL_OPTIONS=-Dt101=1
for l in "$G_CORE" "$G_APP"; do ran_pass "$l" || { ok=0; echo "      not run again with a new JAVA_TOOL_OPTIONS: $l"; }; done
[[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      the signed-path line did not run again with a new JAVA_TOOL_OPTIONS"; }
ac AC4 "$ok" "a changed pack version or JAVA_TOOL_OPTIONS runs every keyed line again"

# ---- AC5  a FAIL is never reused ---------------------------------------------------------------------------------------------------
ok=1
goal "$G_CORE" "$S_FLIP"; touch "$D/tools/flip"; commit flip
loop; grep -qxF "FAIL  $S_FLIP" "$TMP/last" || { ok=0; echo "      setup: the flip line did not fail"; show; }
x0="$(count flip)"
echo "again" >> "$D/docs/notes.md"; commit docs2
loop
[[ "$(count flip)" -eq $((x0 + 1)) ]] && grep -qxF "FAIL  $S_FLIP" "$TMP/last" || { ok=0; echo "      a failing line was not run again after a docs-only commit"; show; }
rm -f "$D/tools/flip"; commit unflip
goal "$G_CORE" "$G_APP" "$S_PATH" "$S_FREE"; commit goal-back
loop
ac AC5 "$ok" "a FAIL is never reused: the failing line runs again (and fails) after a docs-only commit"

# ---- AC6  switched off, and signatures --------------------------------------------------------------------------------------------
ok=1
loop   # settle
p0="$(count path)"; loop BDD_LOOP_CACHE=off
! grep -q '(cached)' "$TMP/last" && [[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      BDD_LOOP_CACHE=off still reused a verdict"; show; }
# an uncommitted LOOP_CACHE_PATHS line keys nothing: remove the committed lines, add one only in the worktree
printf '# envelope\n\n## Locked decisions\n\n<EDIT>\n</EDIT>\n' > "$D/docs/cascade/envelope.md"; commit unsign
loop   # the shell line now has no key and runs
envelope; p0="$(count path)"; loop
[[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      an uncommitted LOOP_CACHE_PATHS line keyed the shell line"; }
loop; p1="$(count path)"; loop
[[ "$(count path)" -eq $((p1 + 1)) ]] || { ok=0; echo "      an uncommitted LOOP_CACHE_PATHS line keyed the shell line (second pass)"; }
# outside <EDIT>: not a signature either
( cd "$D" && git checkout -q -- docs/cascade/envelope.md )
printf '# envelope\n\n- LOOP_CACHE_PATHS: tools/ :: %s\n\n## Locked decisions\n\n<EDIT>\n</EDIT>\n' "$S_PATH" > "$D/docs/cascade/envelope.md"; commit unsigned-outside
loop; p1="$(count path)"; loop
[[ "$(count path)" -eq $((p1 + 1)) ]] || { ok=0; echo "      a LOOP_CACHE_PATHS line outside <EDIT> keyed the shell line"; }
envelope; commit resign
ac AC6 "$ok" "BDD_LOOP_CACHE=off reuses nothing; a LOOP_CACHE_PATHS line that is uncommitted or outside <EDIT> keys nothing"

# ---- AC7  forged entries and a moving tree --------------------------------------------------------------------------------------------
ok=1
loop; loop   # entries fresh
dir="$D/.cascade/goal-verdicts"
if [[ ! -d "$dir" ]] || [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
  ok=0; echo "      no entries in .cascade/goal-verdicts/ (the cache's directory)"
else
  python3 -B - "$dir" <<'PY'
import json, os, sys
d = sys.argv[1]
for f in os.listdir(d):
    p = os.path.join(d, f)
    if f.endswith(".json") and not os.path.islink(p):
        e = json.load(open(p)); e["key"] = "0" * 64; json.dump(e, open(p, "w"))
PY
  p0="$(count path)"; loop
  [[ "$(count path)" -eq $((p0 + 1)) ]] && ! grep -q '(cached)' "$TMP/last" || { ok=0; echo "      an entry with a wrong key was a hit"; show; }
  loop   # fresh again
  for f in "$dir"/*.json; do mv "$f" "$f.real"; ln -s "$f.real" "$f"; done
  p0="$(count path)"; loop
  [[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      a symlinked entry was a hit"; }
  rm -rf "$dir"
fi
# the tree changes while the loop runs: nothing is stored
goal "$G_CORE" "$S_PATH" "sh -c 'echo moved >> docs/notes.md; echo x >> core/moved.txt; true'"; commit moving
loop; p0="$(count path)"; loop
[[ "$(count path)" -eq $((p0 + 1)) ]] || { ok=0; echo "      a PASS was stored although the tree changed during the loop"; }
( cd "$D" && git checkout -q -- . && rm -f core/moved.txt )
goal "$G_CORE" "$G_APP" "$S_PATH" "$S_FREE"; commit goal-back2
ac AC7 "$ok" "an entry with a wrong key or a symlinked entry is a miss; a tree that changes during the loop stores nothing"

# ---- AC8  the receipt ------------------------------------------------------------------------------------------------------------------
ok=1
loop; loop
grep -q '(cached)' "$TMP/last" && grep -q '^LOOP 4/4' "$TMP/last" || { ok=0; echo "      setup: no cached n/n pass"; show; }
fp="$(cd "$D" && bash -c '. tests/lib/cascade.sh && cascade_worktree_sha "$PWD"')"
[[ -n "$fp" && "$(cat "$D/.cascade/loop-receipt" 2>/dev/null)" == "EXECUTE 05b $fp" ]] || { ok=0; echo "      receipt '$(cat "$D/.cascade/loop-receipt" 2>/dev/null)' does not name '$fp'"; }
ac AC8 "$ok" "after a cached LOOP 4/4 the receipt names the whole-tree fingerprint"

# ---- AC10  lines that get no Gradle key -------------------------------------------------------------------------------------
ok=1
G_ALL="./gradlew test"; G_META="$G_CORE && true"
goal "$G_CORE" "$G_ALL" "$G_META"; commit ac10
loop; loop
echo "ac10" >> "$D/docs/notes.md"; commit docs3
loop
cached "$G_CORE" || { ok=0; echo "      setup: the :core line was not cached"; show; }
for l in "$G_ALL" "$G_META"; do
  grep -qF "PASS  $l  (cached)" "$TMP/last" && { ok=0; echo "      a line with no Gradle key came from the cache: $l"; }
  ran_pass "$l" || { ok=0; echo "      the line did not run and pass: $l"; }
done
goal "$G_CORE" "$G_APP" "$S_PATH" "$S_FREE"; commit goal-back3
ac AC10 "$ok" "\`./gradlew test\` (no module) and a :core line with a shell metacharacter run on every pass"

# ---- AC9  the autopilot gate never reads the cache ---------------------------------------------------------------------------------------
ok=1
loop; loop   # entries fresh
p0="$(count path)"
snap() { ( cd "$D/.cascade/goal-verdicts" 2>/dev/null && ls -la . && cat ./* ) 2>/dev/null | shasum -a 256; }
s0="$(snap)"
( cd "$D" && git config core.hooksPath .githooks \
  && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: b/' docs/cascade/hop-state.md && rm -f docs/cascade/hop-state.md.bak \
  && git add -A && git commit -qm "agent: GENERATE b" </dev/null >"$TMP/edge" 2>&1 ); rc=$?
[[ "$rc" -eq 0 ]] || { ok=0; echo "      the autopilot edge was refused (rc $rc): $(head -4 "$TMP/edge")"; }
[[ "$(count path)" -gt "$p0" ]] || { ok=0; echo "      the autopilot gate reused the cached PASS of the signed-path line"; }
[[ "$(snap)" == "$s0" ]] || { ok=0; echo "      the autopilot gate changed .cascade/goal-verdicts/"; }
ac AC9 "$ok" "an autopilot EXECUTE→next edge through the real pre-commit hook runs the keyed lines again and stores nothing (the gate never touches the cache)"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "T101 AC all PASS"; else echo "T101 AC FAILED ($FAILS)"; fi
exit $(( FAILS > 0 ))
