#!/usr/bin/env bash
# AC tests for 05b t69-gradle-tuning: the pack tunes only the Gradle builds it builds itself, never a verdict.
# Gradle is the pack's stub (tests/ac/fixtures/gradlew-stub.py); tests/stress/gradle_tuning.sh makes the same claims
# on real Gradle. docs/cascade/05b-t69-gradle-tuning.md is the contract.
#   AC1   which flags: a batched build gets --configuration-cache unless the user set anything about it anywhere Gradle
#         reads (the line, GRADLE_OPTS, three gradle.properties) or BDD_GRADLE_TUNING=off; a line run alone and a law's
#         own commands get exactly their text; no pack build ever gets a flag on the "never added" list.
#   AC2   a rejection is dropped, remembered while build logic is unchanged, and the verdicts equal every line alone.
#         RED TWIN: a runner that ignores live drop rows pays the rejected build again on the next run.
#   AC3   --offline only when signed AND committed; an offline miss drops it with a reason.
#   AC4   forks reach the law build only from the signed switch, never from an inherited variable.
#   AC5   daemon starts are reported, and a quiet log is "unknown", never zero.
#   AC6   the nightly split: plan, parts and join print what one run prints, for N = 1, 2, 3, 8; zero laws; and every
#         broken set of parts is FATAL. RED TWIN: a join that skips a missing law prints a DSHARP k/n without it.
#   AC8   the release record: the CHANGELOG section that carries t63–t69 and t74 (the version itself is the latest release's AC).
#   AC9   parity: with BDD_GRADLE_TUNING=off, loop.sh and dsharp_strength.sh print what 8d5b269 printed and hand Gradle
#         the same argv; install.sh without --with-nightly ships the same paths; --with-nightly keeps a nightly you have.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR CASCADE_ENVELOPE CASCADE_HUMAN \
      DSHARP_CACHE DSHARP_HARNESS DSHARP_JOBS DSHARP_SERIAL INV_MUTANT BDD_LOOP_RUNNER BDD_GRADLE_TUNING GRADLE_OPTS \
      GRADLE_HOME BDD_LAW_FORKS STUB_DAEMON STUB_COUNT STUB_ENV_LOG STUB_FORKS_LOG
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GRADLE_USER_HOME="$TMP/gradle-home"; mkdir -p "$GRADLE_USER_HOME"   # never the machine's own settings
STUB="$ROOT/tests/ac/fixtures/gradlew-stub.py"
BASELINE=8d5b269     # the last tree before t69
CC=--configuration-cache
CCRE='(^| )--configuration-cache( |$)'   # the stub logs argv without the entry: the flag may open the line

# ---- a Gradle product (the T62 scenario: two modules, four lines in two waves) ------------------------------------
scenario() {  # scenario <dir> [rejectCC] [rejectOffline]
  python3 - "$1/gradle-stub.json" "${2:-0}" "${3:-0}" <<'PY'
import json, sys
core = ["com.x.core.BalanceTest#one()", "com.x.core.LedgerTest#one()"]
s = {"tasks": {":core:compileJava": {},
               ":core:test": {"test": True, "deps": [":core:compileJava"], "tests": core,
                              "mutantFails": {"D1": core[:1]}},
               ":app:compileJava": {},
               ":app:test": {"test": True, "deps": [":core:compileJava"], "tests": ["com.x.app.CheckoutTest#ok()"]}},
     "select": {"com.x.core.BalanceTest": core[:1], "com.x.core.LedgerTest": core[1:],
                "com.x.app.CheckoutTest": ["com.x.app.CheckoutTest#ok()"]},
     "rejectCC": sys.argv[2] == "1", "rejectOffline": sys.argv[3] == "1"}
json.dump(s, open(sys.argv[1], "w"))
PY
}
mkprod() {  # mkprod <dir> [tests dir to install, default this tree's]
  local d="$1" src="${2:-$ROOT/tests}"
  mkdir -p "$d/docs/cascade" "$d/gradle/wrapper"
  rm -rf "$d/tests"; mkdir -p "$d/tests"; cp -R "$src/lib" "$d/tests/lib"
  cp "$src/loop.sh" "$src/dsharp_strength.sh" "$d/tests/"
  find "$d/tests" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  [[ -f "$d/docs/cascade/envelope.md" ]] || printf '# envelope\n' > "$d/docs/cascade/envelope.md"
  printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip\n' > "$d/gradle/wrapper/gradle-wrapper.properties"
  printf "rootProject.name = 'stub'\n" > "$d/settings.gradle"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\n' > "$d/.gitignore"
  [[ -f "$d/gradle-stub.json" ]] || scenario "$d"
  if [[ ! -d "$d/.git" ]]; then ( cd "$d" && git init -q ); fi
  commit "$d"
}
commit() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm fixture >/dev/null 2>&1 || true; }
goal() { local d="$1"; shift; { printf 'GOAL_STAGE: 05b\n'; printf 'VALIDATOR: %s\n' "$@"; } > "$d/docs/cascade/goal.md"; }
G4=("./gradlew :core:test --tests com.x.core.BalanceTest" "./gradlew :core:test --tests com.x.core.LedgerTest"
    "./gradlew :app:test --tests com.x.app.CheckoutTest" "./gradlew :app:test")
loop() {  # loop <dir> [VAR=value…] -> $OUT (stdout), $V (verdict lines + rc), $CALLS (one argv per Gradle call)
  local d="$1"; shift
  rm -rf "$d/.gradle" "$d"/*/build "$d/.cascade/loop"; : > "$TMP/calls"
  OUT="$(cd "$d" && env STUB_COUNT="$TMP/calls" "$@" bash tests/loop.sh 2>&1)"; local rc=$?
  V="$(grep -E '^(PASS|FAIL)  |^LOOP [0-9]' <<<"$OUT"; echo "rc=$rc")"; CALLS="$(cat "$TMP/calls")"
}
batched() { grep -- ' -I ' <<<"$CALLS" || true; }
alone() { grep -v -- ' -I ' <<<"$CALLS" || true; }
envelope() {  # envelope <dir> <line inside EDIT>…
  local d="$1"; shift
  { printf '# envelope\n\n<EDIT>\n'; printf '%s\n' "$@"; printf '</EDIT>\n'; } > "$d/docs/cascade/envelope.md"
}

# ---- AC1  which flags ---------------------------------------------------------------------------------------------
ok=1
P="$TMP/p1"; mkprod "$P"; goal "$P" "${G4[@]}"; commit "$P"
loop "$P"
[[ "$(batched | wc -l | tr -d ' ')" -eq 2 ]] && ! batched | grep -qvE -- "$CCRE" \
  || { ok=0; echo "  default: the two batched builds did not both get $CC:"; batched | sed 's/^/      /'; }
[[ "$V" == *"LOOP 4/4"* ]] || { ok=0; echo "  default: $(tail -2 <<<"$V" | tr '\n' ' ')"; }
grep -q '; tuning: --configuration-cache' <<<"$OUT" || { ok=0; echo "  the loop: line does not name the tuning: $(grep '^loop:' <<<"$OUT")"; }
for never in --no-daemon --daemon --parallel --max-workers -Dorg.gradle.jvmargs -Dorg.gradle.java.home; do
  grep -q -- "$never" <<<"$CALLS" && { ok=0; echo "  a pack build was given $never"; }
done
# Each way the user can say something about the configuration cache: the pack adds nothing.
user_set() {  # user_set <label> <setup command> [VAR=value…]
  local label="$1" setup="$2"; shift 2
  rm -f "$P/gradle.properties" "$GRADLE_USER_HOME/gradle.properties" "$TMP/ghome/gradle.properties"
  eval "$setup"
  loop "$P" "$@"
  local extra; extra="$(batched | grep -cE -- "$CCRE" || true)"
  [[ "$extra" -eq 0 ]] || { ok=0; echo "  $label: the pack still added $CC ($extra build(s))"; }
  [[ "$V" == *"LOOP 4/4"* ]] || { ok=0; echo "  $label: $(tail -2 <<<"$V" | tr '\n' ' ')"; }
}
mkdir -p "$TMP/ghome"
user_set "project gradle.properties =false" "echo org.gradle.configuration-cache=false > '$P/gradle.properties'"
user_set "project gradle.properties =true (nothing to add)" "echo org.gradle.configuration-cache=true > '$P/gradle.properties'"
user_set "project gradle.properties problems=warn" "echo org.gradle.configuration-cache.problems=warn > '$P/gradle.properties'"
user_set "GRADLE_USER_HOME gradle.properties" "echo org.gradle.configuration-cache=false > '$GRADLE_USER_HOME/gradle.properties'"
user_set "GRADLE_HOME gradle.properties" "echo org.gradle.unsafe.configuration-cache=false > '$TMP/ghome/gradle.properties'" GRADLE_HOME="$TMP/ghome"
user_set "GRADLE_OPTS" ":" GRADLE_OPTS=-Dorg.gradle.configuration-cache=false
user_set "BDD_GRADLE_TUNING=off" ":" BDD_GRADLE_TUNING=off
grep -q 'tuning:' <<<"$OUT" && { ok=0; echo "  BDD_GRADLE_TUNING=off still printed a tuning suffix: $(grep '^loop:' <<<"$OUT")"; }
rm -f "$P/gradle.properties" "$GRADLE_USER_HOME/gradle.properties"
for own in "--no-configuration-cache" "-Dorg.gradle.configuration-cache=false" "-Dorg.gradle.configuration-cache.problems=warn" \
           "-D org.gradle.configuration-cache=false" "--system-prop org.gradle.configuration-cache=false"; do
  goal "$P" "./gradlew $own :core:test --tests com.x.core.BalanceTest" "./gradlew $own :app:test --tests com.x.app.CheckoutTest"
  loop "$P"
  [[ "$(batched | grep -cE -- "$CCRE" || true)" -eq 0 ]] || { ok=0; echo "  '$own' on the lines: the pack still added $CC"; }
done
# A line run alone gets exactly its own text: a goal whose Gradle line cannot be batched (one line only).
goal "$P" "./gradlew :core:test --tests com.x.core.BalanceTest"
loop "$P"
[[ "$CALLS" == ":core:test --tests com.x.core.BalanceTest" ]] || { ok=0; echo "  a line run alone was given more than its text: '$CALLS'"; }
# A law's own commands (the two-command path) get exactly their text.
envelope "$P" '### D1 — balance' 'check:  ./gradlew :core:test --tests com.x.core.BalanceTest' \
  'break:  INV_MUTANT=D1 ./gradlew :core:test --tests com.x.core.BalanceTest --rerun'
commit "$P"; : > "$TMP/calls"
DOUT="$(cd "$P" && env STUB_COUNT="$TMP/calls" DSHARP_CACHE=off bash tests/dsharp_strength.sh 2>&1)"
[[ "$(cat "$TMP/calls")" == ":core:test --tests com.x.core.BalanceTest"$'\n'":core:test --tests com.x.core.BalanceTest --rerun" ]] \
  || { ok=0; echo "  a law's own commands were changed:"; sed 's/^/      /' "$TMP/calls"; }
grep -qx 'DSHARP 1/1' <<<"$DOUT" || { ok=0; echo "  the law: $(tail -1 <<<"$DOUT")"; }
t AC1 "$ok" "the batched build gets --configuration-cache unless the user set it anywhere Gradle reads (line, GRADLE_OPTS, three gradle.properties, problems=warn included) or BDD_GRADLE_TUNING=off; a line alone and a law's own commands get exactly their text; no daemon, parallel or JVM flag is ever added"

# ---- AC2  a rejection: dropped, remembered, retried when build logic changes ---------------------------------------
ok=1
P2="$TMP/p2"; mkdir -p "$P2"; scenario "$P2" 1; mkprod "$P2"; goal "$P2" "${G4[@]}"; commit "$P2"
loop "$P2" BDD_LOOP_RUNNER=shell; alone_v="$V"
loop "$P2"
[[ "$V" == "$alone_v" ]] || { ok=0; echo "  verdicts differ from every line alone:"; diff <(echo "$alone_v") <(echo "$V") | sed 's/^/      /'; }
[[ "$(batched | grep -cE -- "$CCRE")" -eq 1 && "$(batched | grep -vcE -- "$CCRE")" -ge 2 ]] \
  || { ok=0; echo "  first run: want one rejected build with $CC, then the waves without it:"; batched | sed 's/^/      /'; }
grep -q "^--configuration-cache	./gradlew	" "$P2/.cascade/gradle/tuning.tsv" 2>/dev/null || { ok=0; echo "  no drop row was written"; }
grep -q 'tuning: --configuration-cache dropped — Configuration cache problems found' "$P2/.cascade/loop/tuning.log" 2>/dev/null \
  || { ok=0; echo "  tuning.log does not name the drop: $(cat "$P2/.cascade/loop/tuning.log" 2>/dev/null)"; }
second() {  # second <dir> -> how many batched builds the next run made with the flag
  rm -rf "$1/.gradle" "$1"/*/build "$1/.cascade/loop"; : > "$TMP/calls"
  ( cd "$1" && env STUB_COUNT="$TMP/calls" bash tests/loop.sh >/dev/null 2>&1 )
  grep -- ' -I ' "$TMP/calls" | grep -cE -- "$CCRE" || true
}
[[ "$(second "$P2")" -eq 0 ]] || { ok=0; echo "  the next run tried the dropped flag again"; }
# RED TWIN: a runner copy that ignores live drop rows tries the flag again on every run.
cp "$P2/tests/lib/gradle_tuning.py" "$TMP/tuning.keep"
python3 - "$P2/tests/lib/gradle_tuning.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "def dropped(root: str, flag: str, entry: str) -> str | None:\n"
assert a in s; open(p, "w").write(s.replace(a, a + "    return None\n", 1))
PY
[[ "$(second "$P2")" -ge 1 ]] || { ok=0; echo "  RED TWIN stayed green: a runner that ignores drop rows did not retry the flag"; }
cp "$TMP/tuning.keep" "$P2/tests/lib/gradle_tuning.py"
# A drop row holds only while build logic is unchanged: edit a tracked build file and the flag is tried again.
printf "rootProject.name = 'stub2'\n" > "$P2/settings.gradle"; commit "$P2"
[[ "$(second "$P2")" -eq 1 ]] || { ok=0; echo "  after a build-logic change the flag was not tried again"; }
# A forged row with another fingerprint removes nothing.
P2b="$TMP/p2b"; mkprod "$P2b"; goal "$P2b" "${G4[@]}"; commit "$P2b"
mkdir -p "$P2b/.cascade/gradle"; printf -- '--configuration-cache\t./gradlew\t0000000000000000\t2026-01-01T00:00:00Z\tforged\n' > "$P2b/.cascade/gradle/tuning.tsv"
[[ "$(second "$P2b")" -eq 2 ]] || { ok=0; echo "  a forged drop row with another fingerprint removed the flag"; }
# An ordinary failure next to "discarded because incompatible task was found" (a build that works with the cache) is
# no rejection; only "discarded with N problem(s)" or a cache error under "What went wrong" is.
rj="$(cd "$ROOT/tests/lib" && python3 -B -c '
import gradle_tuning as g
ok_log = "Configuration cache entry discarded because incompatible task was found: \x27:x\x27.\n\nFAILURE: Build failed with an exception.\n\n* What went wrong:\nExecution failed for task \x27:app:test\x27.\n> There were failing tests.\n\n* Try:\n"
bad_log = "Configuration cache entry discarded with 1 problem.\n\nFAILURE: Build failed with an exception.\n\n* What went wrong:\nExecution failed for task \x27:bad\x27.\n> boom\n\n* Try:\n"
print(g.rejected(ok_log, ["--configuration-cache"]), g.rejected(bad_log, ["--configuration-cache"]) is not None)
')"
[[ "$rj" == "None True" ]] || { ok=0; echo "  rejected() on an incompatible-task notice + failing test / a discarded-with-problems build: $rj"; }
t AC2 "$ok" "a rejected --configuration-cache is dropped with a logged reason, the wave reruns without it and every verdict equals the line alone; the drop holds until build logic changes; a forged row removes nothing; a runner ignoring drop rows retries it (red twin)"

# ---- AC3  --offline: signed and committed, or never ---------------------------------------------------------------
ok=1
P3="$TMP/p3"; mkprod "$P3"; goal "$P3" "${G4[@]}"; commit "$P3"
loop "$P3"; grep -q -- '--offline' <<<"$CALLS" && { ok=0; echo "  unsigned: a build got --offline"; }
envelope "$P3" '- GRADLE_OFFLINE: on — locked 2026-10-22 — reason: AC3'
loop "$P3"; grep -q -- '--offline' <<<"$CALLS" && { ok=0; echo "  signed but not committed: a build got --offline"; }
commit "$P3"
loop "$P3"
[[ "$(batched | grep -c -- '--offline')" -eq 2 ]] || { ok=0; echo "  signed and committed: the batched builds did not get --offline"; }
[[ "$(alone | grep -c -- '--offline' || true)" -eq 0 ]] || { ok=0; echo "  a line run alone got --offline"; }
scenario "$P3" 0 1; commit "$P3"
loop "$P3" BDD_LOOP_RUNNER=shell; alone_v="$V"; loop "$P3"
[[ "$V" == "$alone_v" ]] || { ok=0; echo "  an offline miss changed a verdict"; }
grep -q "^--offline	./gradlew	" "$P3/.cascade/gradle/tuning.tsv" 2>/dev/null || { ok=0; echo "  the offline miss was not dropped"; }
grep -q 'available for offline mode' "$P3/.cascade/loop/tuning.log" 2>/dev/null || { ok=0; echo "  tuning.log does not name the offline miss"; }
t AC3 "$ok" "--offline only when GRADLE_OFFLINE: on is signed and committed, on pack builds only; an offline miss is dropped with its reason and changes no verdict"

# ---- AC4  forks: only the signed switch reaches the law build ------------------------------------------------------
ok=1
P4="$TMP/p4"; mkprod "$P4"
envelope "$P4" '- DSHARP_GRADLE_HARNESS: on — locked 2026-10-22 — reason: AC4' '### D1 — balance' \
  'check:  ./gradlew :core:test --tests com.x.core.BalanceTest' \
  'break:  INV_MUTANT=D1 ./gradlew :core:test --tests com.x.core.BalanceTest --rerun'
commit "$P4"
forks() { : > "$TMP/forks"; ( cd "$P4" && env STUB_FORKS_LOG="$TMP/forks" DSHARP_CACHE=off "$@" bash tests/dsharp_strength.sh >"$TMP/fout" 2>&1 ); cat "$TMP/forks"; }
[[ "$(forks BDD_LAW_FORKS=64)" == "BDD_LAW_FORKS=" ]] || { ok=0; echo "  unsigned: an inherited BDD_LAW_FORKS reached the law build"; }
grep -qx 'DSHARP 1/1' "$TMP/fout" || { ok=0; echo "  unsigned: $(tail -1 "$TMP/fout")"; }
envelope "$P4" '- DSHARP_GRADLE_HARNESS: on — locked 2026-10-22 — reason: AC4' '- DSHARP_GRADLE_FORKS: on — locked 2026-10-22 — reason: AC4' \
  '### D1 — balance' 'check:  ./gradlew :core:test --tests com.x.core.BalanceTest' \
  'break:  INV_MUTANT=D1 ./gradlew :core:test --tests com.x.core.BalanceTest --rerun'
commit "$P4"
want="BDD_LAW_FORKS=$(python3 -c 'import os; print(max(1, (os.cpu_count() or 1) // 2))')"
[[ "$(forks)" == "$want" ]] || { ok=0; echo "  signed: the law build got '$(cat "$TMP/forks")', want '$want'"; }
[[ "$(forks BDD_GRADLE_TUNING=off)" == "BDD_LAW_FORKS=" ]] || { ok=0; echo "  BDD_GRADLE_TUNING=off: forks still reached the law build"; }
t AC4 "$ok" "BDD_LAW_FORKS reaches the law build only from a signed, committed DSHARP_GRADLE_FORKS: on (never inherited, never with tuning off); the check-copy-only rule and the backstop are proven on real Gradle (tests/stress/gradle_tuning.sh)"

# ---- AC5  daemon reporting -----------------------------------------------------------------------------------------
ok=1
goal "$P" "${G4[@]}"; envelope "$P"; commit "$P"
loop "$P" STUB_DAEMON=1
grep -q '; daemon: 2 started (none was running)' <<<"$OUT" || { ok=0; echo "  daemon starts not reported: $(grep '^loop:' <<<"$OUT")"; }
loop "$P"
grep -q 'daemon:' <<<"$OUT" && { ok=0; echo "  no daemon started, yet one is reported: $(grep '^loop:' <<<"$OUT")"; }
goal "$P" "./gradlew -q :core:test --tests com.x.core.BalanceTest" "./gradlew -q :app:test --tests com.x.app.CheckoutTest"
loop "$P"
grep -q '; daemon: unknown (quiet log)' <<<"$OUT" || { ok=0; echo "  a quiet log was not reported unknown: $(grep '^loop:' <<<"$OUT")"; }
t AC5 "$ok" "the loop: line reports daemons the batched builds started, nothing when none did, and 'unknown' — never zero — when the log was quiet"

# ---- AC6  the nightly split ----------------------------------------------------------------------------------------
ok=1
S="$TMP/s6"; mkdir -p "$S/docs/cascade/laws" "$S/tests" "$S/mods"
cp -R "$ROOT/tests/lib" "$S/tests/lib"; cp "$ROOT/tests/dsharp_strength.sh" "$S/tests/"
# A fake gradlew: a test named *Red* fails, a mutant fails unless the test is *Theater*.
cat > "$S/gradlew" <<'EOF'
#!/bin/sh
case "$*" in *Red*) exit 1 ;; esac
if [ -n "$INV_MUTANT" ]; then case "$*" in *Theater*) exit 0 ;; *) exit 1 ;; esac; fi
exit 0
EOF
chmod +x "$S/gradlew"
law() { printf '### %s — %s\ncheck:  %s\nbreak:  %s\n%s\n' "$@"; }
gl() { echo "./gradlew :$1:test --tests $2"; }
LAWS6="$(law D1 'core green' "$(gl core GoodTest)" "INV_MUTANT=D1 $(gl core GoodTest) --rerun" ''
law D2 'core red' "$(gl core RedTest)" "INV_MUTANT=D2 $(gl core RedTest) --rerun" ''
law D3 'app theater' "$(gl app TheaterTest)" "INV_MUTANT=D3 $(gl app TheaterTest) --rerun" ''
law D4 'app unproven' "$(gl app GoodTest)" 'TODO' ''
law D5 'lib green' "$(gl lib GoodTest)" "INV_MUTANT=D5 $(gl lib GoodTest) --rerun" 'reason: NOT_A_TYPE — metadata warning'
law D6 'shell green' 'true' 'false' ''
law D7 'serial a' 'test -f mods/a' 'false' ''
law D8 'serial b' 'test -f mods/a' 'test -f mods/zz' ''
law D9 'retired' 'false' 'false' 'retired: 2026-10-01 — removed — the code is gone'
law D10 'core green two' "$(gl core GoodTwoTest)" "INV_MUTANT=D10 $(gl core GoodTwoTest) --rerun" '')"
touch "$S/mods/a"
printf '# envelope\n\n<EDIT>\n%s\n</EDIT>\n' "$LAWS6" > "$S/docs/cascade/envelope.md"
printf '# lib\n\n<EDIT>\n%s\n</EDIT>\n' "$(law D11 'shard green' "$(gl lib GoodShardTest)" "INV_MUTANT=D11 $(gl lib GoodShardTest) --rerun" '')" > "$S/docs/cascade/laws/lib.md"
( cd "$S" && git init -q && git add -A && git commit -qm init )
single() { ( cd "$S" && env DSHARP_CACHE=off DSHARP_SERIAL="D7 D8" bash tests/dsharp_strength.sh 2>&1 ); echo "rc=$?"; }
split() {  # split <N> -> the join's stdout + rc
  rm -rf "$S/.cascade/nightly"; mkdir -p "$S/.cascade/nightly"
  ( cd "$S" && DSHARP_SERIAL="D7 D8" python3 -B tests/lib/nightly_plan.py "$S" docs/cascade/envelope.md --parts "$1" --out .cascade/nightly/plan.tsv ) > "$TMP/matrix"
  for k in $(python3 -c 'import json,sys; print(" ".join(map(str, json.load(open(sys.argv[1]))["part"])))' "$TMP/matrix"); do
    ( cd "$S" && DSHARP_SERIAL="D7 D8" bash tests/dsharp_strength.sh --part .cascade/nightly/plan.tsv "$k" --out ".cascade/nightly/part-$k" >/dev/null 2>&1 )
  done
  ( cd "$S" && bash tests/dsharp_strength.sh --join .cascade/nightly/plan.tsv .cascade/nightly/part-* 2>&1 ); echo "rc=$?"
}
ONE="$(single)"
grep -q 'DSHARP 7/10' <<<"$ONE" && grep -q '^RETIRED   D9' <<<"$ONE" && grep -q 'reason: "NOT_A_TYPE"' <<<"$ONE" \
  || { ok=0; echo "  the fixture's single run is not the mix this test needs:"; sed 's/^/      /' <<<"$ONE"; }
for N in 1 2 3 8; do
  J="$(split "$N")"
  [[ "$J" == "$ONE" ]] || { ok=0; echo "  N=$N: the join differs from one run:"; diff <(echo "$ONE") <(echo "$J") | sed 's/^/      /'; }
done
# The serial pair lands in one part.
split 3 >/dev/null
[[ "$(awk -F'\t' '$2=="D7"||$2=="D8"{print $3}' "$S/.cascade/nightly/plan.tsv" | sort -u | wc -l | tr -d ' ')" -eq 1 ]] \
  || { ok=0; echo "  DSHARP_SERIAL laws were split across parts"; }
[[ "$(cut -f3 "$S/.cascade/nightly/plan.tsv" | sort -u | wc -l | tr -d ' ')" -eq 3 ]] || { ok=0; echo "  --parts 3 did not give 3 parts"; }
# Zero laws: one empty part, and the join prints what one run prints.
Z="$TMP/z6"; mkdir -p "$Z/docs/cascade" "$Z/tests"; cp -R "$ROOT/tests/lib" "$Z/tests/lib"; cp "$ROOT/tests/dsharp_strength.sh" "$Z/tests/"
printf '# envelope\n' > "$Z/docs/cascade/envelope.md"; ( cd "$Z" && git init -q && git add -A && git commit -qm init )
zm="$(cd "$Z" && python3 -B tests/lib/nightly_plan.py "$Z" docs/cascade/envelope.md --parts 4 --out plan.tsv)"
( cd "$Z" && bash tests/dsharp_strength.sh --part plan.tsv 0 --out p0 >/dev/null 2>&1 )
zj="$(cd "$Z" && bash tests/dsharp_strength.sh --join plan.tsv p0 2>&1; echo "rc=$?")"
zs="$(cd "$Z" && DSHARP_CACHE=off bash tests/dsharp_strength.sh 2>&1; echo "rc=$?")"
[[ "$zm" == '{"part": [0]}' && "$zj" == "$zs" ]] || { ok=0; echo "  zero laws: matrix $zm; join '$zj' vs one run '$zs'"; }
# Every broken set of parts is FATAL, and never prints a score.
fatal() {  # fatal <label> <command that breaks .cascade/nightly>
  split 3 >/dev/null; ( cd "$S/.cascade/nightly" && eval "$2" )
  local j; j="$(cd "$S" && bash tests/dsharp_strength.sh --join .cascade/nightly/plan.tsv .cascade/nightly/part-* 2>&1; echo "rc=$?")"
  grep -q '^FATAL     ' <<<"$j" && grep -q 'rc=1' <<<"$j" && ! grep -q '^DSHARP' <<<"$j" \
    || { ok=0; echo "  $1: not FATAL: $(head -2 <<<"$j" | tr '\n' ' ')"; }
}
fatal "a missing part" 'rm -rf part-1'
fatal "a duplicated result" 'f="$(ls part-0/res.* | head -1)"; cp "$f" part-1/'
fatal "a result in the wrong part" 'f="$(ls part-0/res.* | head -1)"; mv "$f" part-1/'
fatal "a forged status" 'f="$(ls part-0/res.* | head -1)"; echo BLUE > "$f"'
fatal "a law that cannot be GREEN" 'i="$(awk -F"\t" "\$2==\"D4\"{print \$1}" plan.tsv)"; for d in part-*; do [ -f "$d/res.$i" ] && echo GREEN > "$d/res.$i"; done'
fatal "a plan changed after the parts ran" 'printf "\n" >> plan.tsv'
fatal "parts scored from other laws" 'sed -i.bak "s/^laws .*/laws 0000/" part-0/manifest'
fatal "the same part twice" 'cp -R part-0 part-9'
# RED TWIN: a join that skips a law with no result prints a DSHARP k/n without it.
cp "$S/tests/dsharp_strength.sh" "$TMP/dsharp.keep"
python3 - "$S/tests/dsharp_strength.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '[[ "$found" -eq 1 ]] || { bad="law ${ids[$i]} has $found results, not one"; break; }'
assert a in s; open(p, "w").write(s.replace(a, '[[ "$found" -ge 1 ]] || continue', 1))
PY
split 3 >/dev/null; ( cd "$S/.cascade/nightly" && rm -f "$(ls part-0/res.* | head -1)" )
tw="$(cd "$S" && bash tests/dsharp_strength.sh --join .cascade/nightly/plan.tsv .cascade/nightly/part-* 2>&1)"
grep -q '^DSHARP [0-9]*/10$' <<<"$tw" || { ok=0; echo "  RED TWIN stayed green: the weakened join printed no score: $(tail -1 <<<"$tw")"; }
cp "$TMP/dsharp.keep" "$S/tests/dsharp_strength.sh"
t AC6 "$ok" "plan, parts and join print exactly one run's output for N = 1, 2, 3, 8 (GREEN, RED, THEATER, UNPROVEN, RETIRED, a shard, a metadata warning); DSHARP_SERIAL laws share a part; zero laws join to DSHARP 0/0; a missing, duplicated, misplaced or forged result, a changed plan, other laws or a doubled part is FATAL with no score; a join that skips a missing law prints a score (red twin)"

# ---- AC8  the release ----------------------------------------------------------------------------------------------
ok=1
# Since 2.8.0 (t77) the version itself is the latest release's AC; this one keeps the 2.7.0 section honest.
v=2.7.0
python3 - "$ROOT/CHANGELOG.md" "$v" <<'PY' || ok=0
import re, sys
s = open(sys.argv[1]).read(); v = sys.argv[2]
m = re.search(rf"^## {re.escape(v)} — \d{{4}}-\d{{2}}-\d{{2}}\n(.*?)(?=^## \d)", s, re.M | re.S)
bad = []
if not m:
    bad.append(f"no '## {v} — <date>' section")
else:
    body = m.group(1)
    for slug in ("t63-", "t64-", "t65-", "t66-", "t67-", "t68-", "t69-", "t74-"):
        if f"05b {slug}" not in body:
            bad.append(f"no {slug} entry under {v}")
    if "E1" not in body or "| " not in body:
        bad.append("no E1 table")
head = s.split(f"## {v}", 1)[0]
if re.search(r"^## Unreleased\n\s*\S", head, re.M) and "**" in head.split("## Unreleased", 1)[-1]:
    bad.append("entries are still left under ## Unreleased")
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
PY
t AC8 "$ok" "the CHANGELOG's 2.7.0 section holds t63–t69 and t74 and E1's table, and nothing is left under Unreleased"

# ---- AC9  parity with 8d5b269 when tuning is off -------------------------------------------------------------------
ok=1
OLD="$TMP/old"; mkdir -p "$OLD"; git -C "$ROOT" archive "$BASELINE" tests install.sh .github | tar -x -C "$OLD"
P9="$TMP/p9"; mkprod "$P9"; goal "$P9" "${G4[@]}"
envelope "$P9" '### D1 — balance' 'check:  ./gradlew :core:test --tests com.x.core.BalanceTest' \
  'break:  INV_MUTANT=D1 ./gradlew :core:test --tests com.x.core.BalanceTest --rerun'
commit "$P9"
norm() { sed -E 's/\([0-9]+s/(Ns/g; s/ \([0-9]+s, / (Ns, /g'; }
both() {  # both <tests dir> -> loop + dsharp stdout, then every Gradle argv, with the init-script path made neutral
  mkprod "$P9" "$1" >/dev/null; rm -rf "$P9/.cascade"
  loop "$P9" BDD_GRADLE_TUNING=off
  local d; : > "$TMP/calls2"
  d="$(cd "$P9" && env STUB_COUNT="$TMP/calls2" BDD_GRADLE_TUNING=off DSHARP_CACHE=off bash tests/dsharp_strength.sh 2>&1)"
  { echo "$OUT"; echo "$d"; echo "$CALLS"; cat "$TMP/calls2"; } | norm
}
before="$(both "$OLD/tests")"; after="$(both "$ROOT/tests")"
[[ "$before" == "$after" ]] || { ok=0; echo "  BDD_GRADLE_TUNING=off differs from $BASELINE:"; diff <(echo "$before") <(echo "$after") | sed 's/^/      /' | head -20; }
# install.sh without --with-nightly ships the same paths as 8d5b269; --with-nightly keeps a nightly the product has.
inst() {  # inst <pack dir> <target> [flags]
  local src="$1" dst="$2"; shift 2
  mkdir -p "$dst"; ( cd "$dst" && git init -q )
  ( HOME="$TMP/nohome" bash "$src/install.sh" "$@" --no-plugin "$dst" >/dev/null 2>&1 )
  # Leftovers of earlier runs in the pack's own eval fixtures (.cascade/) are no shipped file; t69's two new lib files are.
  ( cd "$dst" && find . -path ./.git -prune -o -type f -print | grep -v '/\.cascade/' \
      | grep -vE '^\./(evals/hops/t82-[^/]+\.md|\.claude/skills/bdd-work/SKILL\.md)$' \
      | grep -vxE '\./tests/lib/(gradle_tuning|nightly_plan|goal_history|regress_lines|carry_out|test_count)\.py|\./tests/(goal|regress)\.sh|\./docs/cascade/(goal|regress)\.template\.md|\./docs/cascade/regress\.md' | sort )
}
OLDPACK="$TMP/oldpack"; mkdir -p "$OLDPACK"; git -C "$ROOT" archive "$BASELINE" | tar -x -C "$OLDPACK"
[[ "$(inst "$OLDPACK" "$TMP/i-old")" == "$(inst "$ROOT" "$TMP/i-new")" ]] \
  || { ok=0; echo "  install.sh ships other paths than $BASELINE:"; diff <(inst "$OLDPACK" "$TMP/i-old2") <(inst "$ROOT" "$TMP/i-new2") | sed 's/^/      /' | head; }
inst "$ROOT" "$TMP/i-n" --with-nightly >/dev/null
nf="$TMP/i-n/.github/workflows/nightly.yml"
[[ -f "$nf" ]] && grep -q 'dsharp_strength.sh --join' "$nf" && ! grep -q '^  pack:' "$nf" && ! grep -q 'tests/enforcement.sh' "$nf" \
  && python3 -c 'import sys,re; s=open(sys.argv[1]).read(); sys.exit(0 if all(f"\n  {j}:\n" in s for j in ("plan","laws","join")) else 1)' "$nf" \
  || { ok=0; echo "  --with-nightly did not ship the product nightly (plan, laws, join; no pack job)"; }
echo "# mine" > "$nf"; inst "$ROOT" "$TMP/i-n" --with-nightly >/dev/null
[[ "$(cat "$nf")" == "# mine" ]] || { ok=0; echo "  --with-nightly overwrote the product's own nightly.yml"; }
t AC9 "$ok" "with BDD_GRADLE_TUNING=off, loop.sh and dsharp_strength.sh print what $BASELINE printed and hand Gradle the same argv; install.sh ships the same paths unless --with-nightly, which adds the product nightly (no pack job) and never overwrites one"

echo
[[ "$fail" -eq 0 ]] && echo "T69 AC all PASS" || echo "T69 AC FAILED"
exit "$fail"
