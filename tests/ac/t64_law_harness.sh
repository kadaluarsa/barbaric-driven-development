#!/usr/bin/env bash
# AC tests for 05b t64-law-harness-jvm: Gradle laws proven GREEN from one build instead of two per law, with every
# non-GREEN verdict still the law's own two commands. Gradle is the stub (tests/ac/fixtures/gradlew-stub.py), so
# this runs without a JVM; tests/stress/law_harness.sh checks the same claims on real Gradle (AC4, AC5, E1).
#   AC1   6 eligible laws, two modules: one law build, DSHARP lines equal to DSHARP_HARNESS=off.
#         RED TWINS: unsigned, and signed only in the working tree, each make 12 invocations.
#   AC1b  a mutant that leaks into the check copy makes the harness prove nothing; verdicts unchanged.
#         RED TWIN: without §4's check conditions, the leak goes unnoticed (laws proven with a failed check copy).
#   AC2   RED, THEATER and no-matching-tests laws are scored by their own two commands, with that verdict.
#         RED TWIN: a harness that calls GREEN whenever the mutant failed makes the RED law GREEN.
#   AC3   each eligibility rule sends its law to the per-command path; exactly the others are proven.
#   AC5   a law build leaves the original test task's up-to-date state as it was.
#   AC6   the merge gate (tests/barbar.sh gate) never starts a law build, even with the switch signed.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR DSHARP_HARNESS DSHARP_JOBS INV_MUTANT STUB_LAW_LEAK
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export DSHARP_CACHE=off   # t65: these assertions are about uncached scoring (exact invocation counts)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$ROOT/tests/ac/fixtures/gradlew-stub.py"

SIGN='- DSHARP_GRADLE_HARNESS: on — locked 2026-10-20 — reason: AC fixture'
law() {  # law <id> <selector> <pattern> [break suffix, default " --rerun"]
  printf '### %s — law %s\ncheck:  ./gradlew %s --tests %s\nbreak:  INV_MUTANT=%s ./gradlew %s --tests %s%s\n\n' \
    "$1" "$1" "$2" "$3" "$1" "$2" "$3" "${4- --rerun}"
}
scenario() {  # the stub's world: two modules, each test reads INV_MUTANT for its own law unless it is THEATER
  cat > "$1/gradle-stub.json" <<'EOF'
{"tasks": {
  ":core:compileTestJava": {},
  ":app:compileTestJava": {},
  ":odd:compileTestJava": {},
  ":core:test": {"test": true, "deps": [":core:compileTestJava"],
    "tests": ["p.D1Test#law", "p.D2Test#law", "p.D3Test#law", "p.D4Test#law", "p.D13Test#law"],
    "failing": ["p.D3Test#law"],
    "mutantFails": {"D1": ["p.D1Test#law"], "D2": ["p.D2Test#law"], "D3": ["p.D3Test#law"], "D13": ["p.D13Test#law"],
                    "D20": ["p.D1Test#law"], "D21": ["p.D2Test#law"], "D22": ["p.D2Test#law"], "D23": ["p.D1Test#law"], "D24": ["p.D1Test#law"]}},
  ":app:test": {"test": true, "deps": [":app:compileTestJava"],
    "tests": ["p.D6Test#law", "p.D11Test#law", "p.D12Test#law"],
    "mutantFails": {"D6": ["p.D6Test#law"], "D11": ["p.D11Test#law"], "D12": ["p.D12Test#law"]}},
  ":odd:test": {"test": true, "deps": [":odd:compileTestJava"], "tests": ["p.D7Test#law"],
    "fidelity": "the original has 1 extra action(s) (doFirst/doLast)", "mutantFails": {"D7": ["p.D7Test#law"]}}
 },
 "select": {"p.D1Test": ["p.D1Test#law"], "p.D2Test": ["p.D2Test#law"], "p.D3Test": ["p.D3Test#law"],
            "p.D4Test": ["p.D4Test#law"], "p.D13Test": ["p.D13Test#law"], "p.D6Test": ["p.D6Test#law"],
            "p.D11Test": ["p.D11Test#law"], "p.D12Test": ["p.D12Test#law"], "p.D7Test": ["p.D7Test#law"], "p.Nope*": []}}
EOF
}
mkprod() {  # mkprod <dir> <laws> [signed: head|work|none] [wrapper version]
  local d="$1" sign="${3:-head}"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/gradle/wrapper"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/dsharp_strength.sh" "$ROOT/tests/audit.sh" "$d/tests/"
  printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' "${4:-8.14.3}" > "$d/gradle/wrapper/gradle-wrapper.properties"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\n' > "$d/.gitignore"
  printf 'CURRENT_HOP: NONE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  printf '| FR-1 | x | path: gradlew test: true | IMPLEMENTED |\n' > "$d/docs/cascade/10-audit.md"
  { printf '# envelope\n\n<EDIT>\n%s\n</EDIT>\n\n## Locked decisions\n\n<EDIT>\n' "$2"
    [[ "$sign" == head ]] && echo "$SIGN"
    printf '</EDIT>\n'; } > "$d/docs/cascade/envelope.md"
  scenario "$d"
  ( cd "$d" && git init -q && git add -A && git commit -qm init )
  if [[ "$sign" == work ]]; then   # signed in the working tree only, never committed
    python3 - "$d/docs/cascade/envelope.md" "$SIGN" <<'PY'
import sys
p, line = sys.argv[1:3]; s = open(p).read()
open(p, "w").write(s.replace("## Locked decisions\n\n<EDIT>\n", "## Locked decisions\n\n<EDIT>\n" + line + "\n"))
PY
  fi
}
score() {  # score <dir> [VAR=value…] -> DSHARP lines in $OUT, stub invocations in $CALLS, law builds in $LB
  local d="$1"; shift
  rm -rf "$d/.gradle" "$d/.cascade"; : > "$TMP/calls"
  OUT="$(cd "$d" && env STUB_COUNT="$TMP/calls" "$@" bash tests/dsharp_strength.sh 2>&1 | grep -E '^(GREEN|RED|THEATER|UNPROVEN|DSHARP|FATAL)')"
  CALLS="$(grep -c . "$TMP/calls" | tr -d ' ')"; LB="$(grep -c 'bddLaws' "$TMP/calls" | tr -d ' ')"
}
proved() { awk -F'\t' '$3=="GREEN"{print $2}' "$1/.cascade/laws/law-harness.tsv" 2>/dev/null | sort | tr '\n' ' '; }
why() { awk -F'\t' -v id="$2" '$2==id{print $3}' "$1/.cascade/laws/law-harness.tsv" 2>/dev/null; }
patch_proven_mutant_only() {  # the §4 red twin: GREEN whenever the mutant failed
  python3 - "$1/tests/lib/law_harness.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '    lid = law["id"]\n    if elig.get'
if old not in s: sys.exit("twin: proven() not found — update the red twin with the code")
s = s.replace(old, '    lid = law["id"]\n    m0 = outcomes.get(f"{law[\'proj\']}bddLawMutant_{lid}")\n    if m0 and m0[0] == "FAILED":\n        return True, ""\n    if elig.get', 1)
open(p, "w").write(s)
PY
}

GREENS="$(law D1 :core:test p.D1Test; law D2 :core:test p.D2Test; law D13 :core:test p.D13Test; law D6 :app:test p.D6Test; law D11 :app:test p.D11Test; law D12 :app:test p.D12Test)"

# ---- AC1  one law build ---------------------------------------------------------------------------------------
ok=1
A="$TMP/a1"; mkprod "$A" "$GREENS"
score "$A" DSHARP_HARNESS=off; off="$OUT"; coff="$CALLS"
score "$A"; on="$OUT"; con="$CALLS"; lb="$LB"
[[ "$on" == "$off" ]] || { ok=0; echo "  verdicts differ:"; diff <(echo "$off") <(echo "$on") | sed 's/^/    /'; }
[[ "$(echo "$off" | tail -1)" == "DSHARP 6/6" ]] || { ok=0; echo "  the fixture is not 6 GREEN laws per-command: $(echo "$off" | tail -1)"; }
[[ "$con" -eq 1 && "$lb" -eq 1 && "$coff" -eq 12 ]] || { ok=0; echo "  harness on made $con invocations ($lb law builds), off made $coff; want 1 and 12"; }
[[ "$(proved "$A")" == "D1 D11 D12 D13 D2 D6 " ]] || { ok=0; echo "  proven: '$(proved "$A")'"; }
A2="$TMP/a1-unsigned"; mkprod "$A2" "$GREENS" none; score "$A2"
[[ "$CALLS" -eq 12 && "$LB" -eq 0 ]] || { ok=0; echo "  red twin: unsigned, the run made $CALLS invocations ($LB law builds)"; }
A3="$TMP/a1-work"; mkprod "$A3" "$GREENS" work; score "$A3"
[[ "$CALLS" -eq 12 && "$LB" -eq 0 ]] || { ok=0; echo "  red twin: signed only in the working tree, the run made $CALLS invocations ($LB law builds)"; }
t AC1 "$ok" "6 eligible laws over two modules are proven GREEN from 1 law build (12 invocations off); DSHARP lines identical; unsigned or uncommitted, no law build runs"

# ---- AC1b  a leaked mutant -------------------------------------------------------------------------------------
ok=1
score "$A" STUB_LAW_LEAK=1; leak="$OUT"
[[ "$leak" == "$off" ]] || { ok=0; echo "  with a leaked mutant the verdicts changed:"; diff <(echo "$off") <(echo "$leak") | sed 's/^/    /'; }
[[ -z "$(proved "$A")" && "$CALLS" -eq 13 ]] || { ok=0; echo "  with a leaked mutant the harness proved '$(proved "$A")' ($CALLS invocations; want none proven, 1 + 12)"; }
grep -q 'check copy FAILED' "$A/.cascade/laws/law-harness.tsv" || { ok=0; echo "  the notes do not say the check copy failed"; }
B="$TMP/a1b-twin"; mkprod "$B" "$GREENS"; patch_proven_mutant_only "$B" || ok=0
score "$B" STUB_LAW_LEAK=1
[[ "$(proved "$B")" == "D1 D11 D12 D13 D2 D6 " ]] || { ok=0; echo "  red twin: without §4's check conditions the leak should go unnoticed, but proven='$(proved "$B")'"; }
t AC1b "$ok" "a mutant that leaks into the check copy makes every check copy fail, so the harness proves nothing and the verdicts stay the per-command ones; without §4's check conditions the leak would pass unnoticed"

# ---- AC2  only GREEN is the harness's ----------------------------------------------------------------------------
ok=1
MIXED="$(law D1 :core:test p.D1Test; law D3 :core:test p.D3Test; law D4 :core:test p.D4Test; law D5 :core:test 'p.Nope*'; law D6 :app:test p.D6Test)"
M="$TMP/a2"; mkprod "$M" "$MIXED"
score "$M" DSHARP_HARNESS=off; off="$OUT"; coff="$CALLS"
score "$M"; on="$OUT"; con="$CALLS"
[[ "$on" == "$off" ]] || { ok=0; echo "  verdicts differ:"; diff <(echo "$off") <(echo "$on") | sed 's/^/    /'; }
echo "$off" | grep -q '^RED       D3 ' && echo "$off" | grep -q '^THEATER   D4 ' && echo "$off" | grep -q '^RED       D5 ' \
  || { ok=0; echo "  the fixture's per-command verdicts are not RED D3 / THEATER D4 / RED D5:"; echo "$off" | sed 's/^/    /'; }
[[ "$(proved "$M")" == "D1 D6 " ]] || { ok=0; echo "  proven: '$(proved "$M")' (want D1 D6)"; }
# D3, D4, D5 run their own two commands: 6 per-command invocations + 1 law build (D3 RED stops after check: 5)
[[ "$con" -eq $((1 + 4)) ]] || { ok=0; echo "  $con invocations with the harness; want 1 law build + 4 per-command (D3 check, D4 check+break, D5 check)"; }
T2="$TMP/a2-twin"; mkprod "$T2" "$MIXED"; patch_proven_mutant_only "$T2" || ok=0
score "$T2"
echo "$OUT" | grep -q '^GREEN     D3 ' || { ok=0; echo "  red twin: GREEN-whenever-the-mutant-failed did not make RED D3 GREEN, so AC2 proves nothing"; }
t AC2 "$ok" "RED, THEATER and no-matching-tests laws are scored by their own two commands with that verdict; a harness that trusts the mutant alone would call RED D3 GREEN"

# ---- AC3  eligibility ---------------------------------------------------------------------------------------------
ok=1
ELIG="$(law D1 :core:test p.D1Test)"
ELIG+=$'\n\n'"$(printf '### D20 — globals with -P\ncheck:  ./gradlew -Pfoo=1 :core:test --tests p.D1Test\nbreak:  INV_MUTANT=D20 ./gradlew -Pfoo=1 :core:test --tests p.D1Test --rerun\n\n')"
ELIG+=$'\n\n'"$(law D21 :core:test p.D2Test "")"
ELIG+=$'\n\n'"$(printf '### D22 — break names another law\ncheck:  ./gradlew :core:test --tests p.D2Test\nbreak:  INV_MUTANT=D2 ./gradlew :core:test --tests p.D2Test --rerun\n\n')"
ELIG+=$'\n\n'"$(printf '### D23 — two selectors\ncheck:  ./gradlew :core:test :app:test --tests p.D6Test\nbreak:  INV_MUTANT=D23 ./gradlew :core:test :app:test --tests p.D6Test --rerun\n\n')"
ELIG+=$'\n\n'"$(printf '### D24 — unqualified selector\ncheck:  ./gradlew test --tests p.D1Test\nbreak:  INV_MUTANT=D24 ./gradlew test --tests p.D1Test --rerun\n\n')"
ELIG+=$'\n\n'"$(law D7 :odd:test p.D7Test)"
E="$TMP/a3"; mkprod "$E" "$ELIG"
score "$E" DSHARP_HARNESS=off; off="$OUT"; score "$E"; on="$OUT"
[[ "$on" == "$off" ]] || { ok=0; echo "  verdicts differ:"; diff <(echo "$off") <(echo "$on") | sed 's/^/    /'; }
[[ "$(proved "$E")" == "D1 " ]] || { ok=0; echo "  proven: '$(proved "$E")' (want only D1)"; }
for pair in "D20|-D/-P" "D21|--rerun" "D22|INV_MUTANT=D22" "D23|more than one task" "D24|without a project path" "D7|extra action"; do
  id="${pair%%|*}"; want="${pair#*|}"
  why "$E" "$id" | grep -qF -- "$want" || { ok=0; echo "  $id was not refused for '$want': $(why "$E" "$id")"; }
done
V="$TMP/a3-version"; mkprod "$V" "$(law D1 :core:test p.D1Test)" head 7.6; score "$V"
[[ "$LB" -eq 0 && -z "$(proved "$V")" ]] && why "$V" D1 | grep -q 'not a verified Gradle version' \
  || { ok=0; echo "  an unverified wrapper (7.6) still got a law build ($LB) or no reason: $(why "$V" D1)"; }
t AC3 "$ok" "-P in globals, a break: without --rerun or naming another id, two selectors, an unqualified selector, a copy the build would not reproduce, and an unverified Gradle each send the law to its own two commands; only the plain law is proven"

# ---- AC5  the original task's up-to-date state ----------------------------------------------------------------------
ok=1
U="$TMP/a5"; mkprod "$U" "$GREENS"
( cd "$U" && ./gradlew :app:test >/dev/null 2>&1 )
before="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(":app:test"))' "$U/.gradle/stub-state.json")"
: > "$TMP/calls"; ( cd "$U" && env STUB_COUNT="$TMP/calls" bash tests/dsharp_strength.sh >/dev/null 2>&1 )
after="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(":app:test"))' "$U/.gradle/stub-state.json")"
[[ -n "$before" && "$before" != None && "$before" == "$after" ]] || { ok=0; echo "  :app:test's up-to-date state changed: '$before' -> '$after'"; }
grep -q 'bddLaws' "$TMP/calls" || { ok=0; echo "  no law build ran, so this checked nothing"; }
t AC5 "$ok" "a law build leaves the original :app:test exactly as up to date as it was"

# ---- AC6  the merge gate never uses the harness -----------------------------------------------------------------------
ok=1
G="$TMP/a6"; mkprod "$G" "$GREENS"
: > "$TMP/calls"
( cd "$G" && env STUB_COUNT="$TMP/calls" BARBAR_ROOT="$G" bash "$ROOT/tests/barbar.sh" gate >/dev/null 2>&1 )
lb="$(grep -c 'bddLaws' "$TMP/calls" | tr -d ' ')"; calls="$(grep -c . "$TMP/calls" | tr -d ' ')"
[[ "$lb" -eq 0 && "$calls" -eq 24 ]] || { ok=0; echo "  the merge gate made $calls invocations ($lb law builds); want 24 per-command (audit.sh's 12 + the gate's 12) and none"; }
grep -q 'export DSHARP_HARNESS=off' "$ROOT/tests/barbar.sh" || { ok=0; echo "  tests/barbar.sh does not export DSHARP_HARNESS=off"; }
t AC6 "$ok" "the merge gate scores every law with its own two commands — through audit.sh and its own check — even with the switch signed"

exit "$fail"
