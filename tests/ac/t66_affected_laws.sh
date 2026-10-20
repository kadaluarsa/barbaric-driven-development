#!/usr/bin/env bash
# AC tests for 05b t66-affected-laws: a hop runs the laws its diff can break, and never fewer. Gradle is the stub
# (tests/ac/fixtures/gradlew-stub.py, `projects` + `bddAffectedProjects`), so this runs without a JVM;
# tests/stress/affected.sh checks the module map on real Gradle and measures E1.
#   AC1  a diff in core/ requires D-core and D-app (its dependent), prints D-web `not affected`, and
#        `affected.sh --list` names exactly that set; the hop's LOOP k/n excludes D-web.
#   AC3  an affected law omitted from /goal is FAIL; an unaffected one is `not affected` and passes.
#        RED TWIN 1: a copy of affected.py that drops D-app makes the AC's required-set check go red.
#        RED TWIN 2: a copy of loop.sh that treats every omission as not affected makes the FAIL check go red.
#   AC2  each fail-closed trigger in the spec, one at a time, is the full set with a reason; the full set still
#        requires an omitted law.
#   AC4  selection cannot reach the merge gate: dsharp and `barbar.sh gate` run every check and twin (2N
#        invocations), print no `not affected`, and ignore AFFECTED_BASE/AFFECTED_MUTANT.
#   AC5  the nightly workflow exists, is scheduled, runs the full scripts, and its command scores every law.
#   AC6  path:, the :symbol suffix, a rename out of a module, an unmapped law, and CASCADE_ENVELOPE.
#   AC7  the base is the hop, not the branch: a two-hop fixture sees only hop 2's diff; --base is report-only.
#   AC8  measured on real Gradle by tests/stress/affected.sh (reported in EXECUTE and CHANGELOG); skipped here.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      AFFECTED_BASE AFFECTED_MUTANT STUB_AFFECTED_FAIL DSHARP_HARNESS DSHARP_JOBS INV_MUTANT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export DSHARP_CACHE=off   # t65: these assertions are about uncached scoring (exact counts on repeat runs)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$ROOT/tests/ac/fixtures/gradlew-stub.py"

LAWS="$(cat <<'EOF'
### D1 — core file
path: core/x.txt
check:  test -f core/x.txt
break:  test -f core/missing.txt

### D2 — app file
path: app/y.txt
check:  test -f app/y.txt
break:  test -f app/missing.txt

### D3 — web file
path: web/z.txt
check:  test -f web/z.txt
break:  test -f web/missing.txt

### D4 — core module
check:  ./gradlew :core:test --tests p.D4Test
break:  INV_MUTANT=D4 ./gradlew :core:test --tests p.D4Test --rerun

### D5 — app module
check:  ./gradlew :app:test --tests p.D5Test
break:  INV_MUTANT=D5 ./gradlew :app:test --tests p.D5Test --rerun

### D6 — web module
check:  ./gradlew :web:test --tests p.D6Test
break:  INV_MUTANT=D6 ./gradlew :web:test --tests p.D6Test --rerun
EOF
)"

GRADLE_LAWS="$(cat <<'EOF'
### D1 — core module
check:  ./gradlew :core:test --tests p.D1Test
break:  INV_MUTANT=D1 ./gradlew :core:test --tests p.D1Test --rerun

### D2 — core module two
check:  ./gradlew :core:test --tests p.D2Test
break:  INV_MUTANT=D2 ./gradlew :core:test --tests p.D2Test --rerun

### D3 — app module
check:  ./gradlew :app:test --tests p.D3Test
break:  INV_MUTANT=D3 ./gradlew :app:test --tests p.D3Test --rerun

### D4 — web module
check:  ./gradlew :web:test --tests p.D4Test
break:  INV_MUTANT=D4 ./gradlew :web:test --tests p.D4Test --rerun
EOF
)"

check_for() {  # the /goal lines, i.e. the law's own check
  case "$1" in
    D1) if [[ "${2:-}" == gradle ]]; then echo './gradlew :core:test --tests p.D1Test'; else echo 'test -f core/x.txt'; fi ;;
    D2) if [[ "${2:-}" == gradle ]]; then echo './gradlew :core:test --tests p.D2Test'; else echo 'test -f app/y.txt'; fi ;;
    D3) if [[ "${2:-}" == gradle ]]; then echo './gradlew :app:test --tests p.D3Test'; else echo 'test -f web/z.txt'; fi ;;
    D4) if [[ "${2:-}" == gradle ]]; then echo './gradlew :web:test --tests p.D4Test'; else echo './gradlew :core:test --tests p.D4Test'; fi ;;
    D5) echo './gradlew :app:test --tests p.D5Test' ;;
    D6) echo './gradlew :web:test --tests p.D6Test' ;;
    D7) echo 'test -f nowhere' ;;
    D8) echo 'test -f core/x' ;;
    D9) echo 'test -f web/z.txt' ;;
  esac
}

scenario() {  # scenario <dir> [gradle] — the stub's world: :core, :app (:core), :web
  local d="$1" flavour="${2:-}"
  if [[ "$flavour" == gradle ]]; then
    cat > "$d/gradle-stub.json" <<'EOF'
{"tasks": {
  ":core:test": {"test": true, "tests": ["p.D1Test#law", "p.D2Test#law"],
                 "mutantFails": {"D1": ["p.D1Test#law"], "D2": ["p.D2Test#law"]}},
  ":app:test": {"test": true, "tests": ["p.D3Test#law"], "mutantFails": {"D3": ["p.D3Test#law"]}},
  ":web:test": {"test": true, "tests": ["p.D4Test#law"], "mutantFails": {"D4": ["p.D4Test#law"]}}
 },
 "select": {"p.D1Test": ["p.D1Test#law"], "p.D2Test": ["p.D2Test#law"],
            "p.D3Test": ["p.D3Test#law"], "p.D4Test": ["p.D4Test#law"]},
 "projects": {":core": {"dir": "core", "deps": []},
              ":app": {"dir": "app", "deps": [":core"]},
              ":web": {"dir": "web", "deps": []}}
}
EOF
    return
  fi
  cat > "$d/gradle-stub.json" <<'EOF'
{"tasks": {
  ":core:test": {"test": true, "tests": ["p.D4Test#law"], "mutantFails": {"D4": ["p.D4Test#law"]}},
  ":app:test": {"test": true, "tests": ["p.D5Test#law"], "mutantFails": {"D5": ["p.D5Test#law"]}},
  ":web:test": {"test": true, "tests": ["p.D6Test#law"], "mutantFails": {"D6": ["p.D6Test#law"]}}
 },
 "select": {"p.D4Test": ["p.D4Test#law"], "p.D5Test": ["p.D5Test#law"], "p.D6Test": ["p.D6Test#law"]},
 "projects": {":core": {"dir": "core", "deps": []},
              ":app": {"dir": "app", "deps": [":core"]},
              ":web": {"dir": "web", "deps": []}}
}
EOF
}

mkprod() {  # mkprod <dir> <laws> [nohop] [mutator] [locked line] [gradle flavour]
  local d="$1" laws="$2" mode="${3:-head}" mut="${4:-}" locked="${5:-}" flavour="${6:-}"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/gradle/wrapper" "$d/core" "$d/app" "$d/web"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  cp "$ROOT/tests/affected.sh" "$ROOT/tests/loop.sh" "$ROOT/tests/dsharp_strength.sh" "$ROOT/tests/audit.sh" "$d/tests/"
  printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip\n' > "$d/gradle/wrapper/gradle-wrapper.properties"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\n' > "$d/.gitignore"
  printf '| FR-1 | x | path: gradlew test: true | IMPLEMENTED |\n' > "$d/docs/cascade/10-audit.md"
  printf 'core\n' > "$d/core/x.txt"; printf 'app\n' > "$d/app/y.txt"; printf 'web\n' > "$d/web/z.txt"
  { printf '# envelope\n\n<EDIT>\n%s\n</EDIT>\n\n## Locked decisions\n\n<EDIT>\n' "$laws"
    [[ -n "$locked" ]] && printf '%s\n' "$locked"
    printf '</EDIT>\n'; } > "$d/docs/cascade/envelope.md"
  scenario "$d" "$flavour"
  [[ "$mode" != nohop ]] && printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: t66-fixture\n' > "$d/docs/cascade/hop-state.md"
  if [[ -n "$mut" ]]; then "$mut" "$d" || return 1; fi
  ( cd "$d" && git init -q && git add -A && git commit -qm edge ) || return 1
  [[ "$mode" == nohop ]] && printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: t66-fixture\n' > "$d/docs/cascade/hop-state.md"
  return 0
}

goal() {  # goal <dir> <id...> — writes /goal with those law checks plus one always-true validator
  local d="$1"; shift
  { printf 'GOAL_STAGE: 05b\nGOAL_SLICE: t66-fixture\n'
    local id; for id in "$@"; do printf 'VALIDATOR: %s\n' "$(check_for "$id" "${FLAVOUR:-}")"; done
    printf 'VALIDATOR: true\n'; } > "$d/docs/cascade/goal.md"
}

list_of() { ( cd "$1" && bash tests/affected.sh --list 2>/dev/null ); }
has() { printf '%s\n' "$1" | grep -qx "$2"; }
full_of() { ( cd "$1" && bash tests/affected.sh 2>/dev/null | head -1 ); }
loop_run() { ( cd "$1" && bash tests/loop.sh 2>&1 ); }

required() {  # required <dir> <id> — is it in the set the hop must run?
  has "$(list_of "$1")" "$2"
}

omission_fails() {  # omission_fails <dir> — a goal that omits D5 must make the loop fail on D5
  local d="$1" out
  goal "$d" D1 D4
  out="$(loop_run "$d")"
  [[ $? -ne 0 ]] || return 1
  printf '%s\n' "$out" | grep -q 'in-force D# omitted from /goal: D5'
}

patch_drop_d5() {  # red twin 1: the selector forgets the dependent module's law
  python3 - "$1/tests/lib/affected.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '                if own in cl:\n'
if old not in s:
    sys.exit("twin: the module-closure branch moved — update the red twin with the code")
open(p, "w").write(s.replace(old, '                if own in cl and d["id"] != "D5":\n', 1))
PY
}

patch_loop_always_not() {  # red twin 2: every omitted law is called not affected
  python3 - "$1/tests/loop.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '0) if law_not_affected "$id"; then'
if old not in s:
    sys.exit("twin: the omission branch moved — update the red twin with the code")
open(p, "w").write(s.replace(old, '0) if true; then', 1))
PY
}

# ---- AC1 + AC3  one module's diff, omission, and the two red twins --------------------------------------------
ok=1
A="$TMP/a1"; mkprod "$A" "$LAWS" || ok=0
printf 'core changed\n' > "$A/core/x.txt"
want=$'D1\nD4\nD5'
got="$(list_of "$A")"
[[ "$got" == "$want" ]] || { ok=0; echo "  --list was '$(echo "$got" | tr '\n' ' ')'; want D1 D4 D5"; }
required "$A" D5 || { ok=0; echo "  D5 (the dependent module's law) is not required"; }
required "$A" D2 && { ok=0; echo "  D2 (an app file, not in the diff) is required"; }
goal "$A" D1 D4 D5
out="$(loop_run "$A")"
echo "$out" | grep -q '^LOOP 4/4$' || { ok=0; echo "  the hop is not LOOP 4/4:"; echo "$out" | tail -8 | sed 's/^/    /'; }
for id in D2 D3 D6; do
  echo "$out" | grep -q "^not affected  $id " || { ok=0; echo "  D$id is not printed not affected"; }
done
omission_fails "$A" || { ok=0; echo "  omitting affected D5 did not fail the loop on D5"; }
# RED TWIN 1: the same required-set check, on a selector that drops D5.
A1="$TMP/a1-twin"; mkprod "$A1" "$LAWS" "" patch_drop_d5 || ok=0
printf 'core changed\n' > "$A1/core/x.txt"
required "$A1" D5 && { ok=0; echo "  red twin 1 did not drop D5, so the required-set check proves nothing"; }
# RED TWIN 2: the same omission check, on a loop that calls every omission not affected.
A2="$TMP/a1-twin2"; mkprod "$A2" "$LAWS" "" patch_loop_always_not || ok=0
printf 'core changed\n' > "$A2/core/x.txt"
omission_fails "$A2" && { ok=0; echo "  red twin 2 still failed the loop, so the omission check proves nothing"; }
t AC1 "$ok" "a core diff requires D1 (path), D4 (module) and D5 (dependent module), prints D2/D3/D6 not affected, and LOOP 4/4 excludes them"
t AC3 "$ok" "an affected law omitted from /goal FAILs; an unaffected one is not affected and passes; a selector that drops the dependent law fails AC1's required-set check, and a loop that hides omissions fails the omission check"

# ---- AC2  fail closed -------------------------------------------------------------------------------------------
ok=1
full_reason() {  # full_reason <dir> [env…]
  local d="$1"; shift
  ( cd "$d" && env "$@" bash tests/affected.sh 2>/dev/null | head -1 )
}
full_requires_all() {  # full_requires_all <dir> [env…] — every law is in --list and the first line says full
  local d="$1"; shift
  local first; first="$(full_reason "$d" "$@")"
  [[ "$first" == AFFECTED\ full\ —* ]] || { echo "  not full: $first"; return 1; }
  local ids; ids="$( cd "$d" && env "$@" bash tests/affected.sh --list 2>/dev/null )"
  local id; for id in D1 D2 D3 D4 D5 D6; do has "$ids" "$id" || { echo "  full set lacks $id"; return 1; }; done
}

# 1 no hop-open commit
F="$TMP/a2-nohop"; mkprod "$F" "$LAWS" nohop || ok=0
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  no hop-open commit"; }
# 1b hop-state mismatch (the commit opened a different slice)
F="$TMP/a2-mismatch"; mkprod "$F" "$LAWS" || ok=0
printf 'core changed\n' > "$F/core/x.txt"
sed -i.bak 's/t66-fixture/t66-other/' "$F/docs/cascade/hop-state.md"
full_requires_all "$F" || { ok=0; echo "  hop-state mismatch"; }
# 2 build logic
F="$TMP/a2-build"; mkprod "$F" "$LAWS" || ok=0
printf 'rootProject.name = "x"\n' > "$F/settings.gradle"
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  build logic"; }
# 3 signed shared module; and the same line unsigned declares nothing
F="$TMP/a2-shared"; mkprod "$F" "$LAWS" "" "" '- AFFECTED_SHARED_MODULES: :core' || ok=0
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  signed shared module"; }
F="$TMP/a2-shared-unsigned"; mkprod "$F" "$LAWS" "" "" '- AFFECTED_SHARED_MODULES: {{ core }}' || ok=0
printf 'core changed\n' > "$F/core/x.txt"
[[ "$(list_of "$F")" == "$want" ]] || { ok=0; echo "  an unsigned shared line changed the set: $(list_of "$F" | tr '\n' ' ')"; }
# 4 map failure
F="$TMP/a2-mapfail"; mkprod "$F" "$LAWS" || ok=0
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" STUB_AFFECTED_FAIL=1 || { ok=0; echo "  map failure"; }
# 5 a law naming a module the map does not contain
F="$TMP/a2-nomodule"; mkprod "$F" "$LAWS" || ok=0
printf '\n### D7 — no such module\ncheck:  ./gradlew :nope:test --tests p.D7Test\nbreak:  INV_MUTANT=D7 ./gradlew :nope:test --tests p.D7Test\n' >> "$F/docs/cascade/envelope.md"
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  missing module"; }
# 6 an unmapped changed file
F="$TMP/a2-unmapped"; mkprod "$F" "$LAWS" || ok=0
mkdir -p "$F/misc"; printf 'x\n' > "$F/misc/x.txt"
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  unmapped file"; }
# 7 an unmapped law (neither path nor module)
F="$TMP/a2-unmappedlaw"; mkprod "$F" "$LAWS" || ok=0
printf '\n### D7 — no map at all\ncheck:  test -f nowhere\nbreak:  test -f missing\n' >> "$F/docs/cascade/envelope.md"
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  unmapped law"; }
# 8 a Gradle check that cannot be parsed into one module
F="$TMP/a2-unparseable"; mkprod "$F" "$LAWS" || ok=0
printf '\n### D7 — a bare task\ncheck:  ./gradlew test --tests p.D7Test\nbreak:  INV_MUTANT=D7 ./gradlew test --tests p.D7Test\n' >> "$F/docs/cascade/envelope.md"
printf 'core changed\n' > "$F/core/x.txt"
full_requires_all "$F" || { ok=0; echo "  unparseable selector"; }
# the full set still requires an omitted law
F="$TMP/a2-full-requires"; mkprod "$F" "$LAWS" || ok=0
printf 'rootProject.name = "x"\n' > "$F/settings.gradle"
printf 'core changed\n' > "$F/core/x.txt"
goal "$F" D1 D4 D5
out="$(loop_run "$F")"
[[ $? -ne 0 ]] && printf '%s\n' "$out" | grep -q 'in-force D# omitted from /goal: D6' \
  || { ok=0; echo "  the full set did not require an omitted law (D6)"; }
t AC2 "$ok" "no hop commit, hop mismatch, build logic, a shared module, map failure, an unknown module, an unmapped file, an unmapped law and an unparseable selector each give AFFECTED full with a reason and every law; the full set still FAILs an omitted law"

# ---- AC4  selection cannot reach the merge gate ------------------------------------------------------------------
ok=1
G="$TMP/a4"; mkprod "$G" "$GRADLE_LAWS" "" "" "" gradle || ok=0
printf 'core changed\n' > "$G/core/x.txt"
: > "$TMP/calls"
d_out="$( cd "$G" && env STUB_COUNT="$TMP/calls" bash tests/dsharp_strength.sh 2>&1 )"
d_calls="$(grep -c . "$TMP/calls")"
[[ "$(printf '%s\n' "$d_out" | tail -1)" == "DSHARP 4/4" ]] || { ok=0; echo "  dsharp: $(printf '%s\n' "$d_out" | tail -1)"; }
[[ "$d_calls" -eq 8 ]] || { ok=0; echo "  dsharp made $d_calls invocations; want 8 (4 checks + 4 twins)"; }
printf '%s\n' "$d_out" | grep -q 'not affected' && { ok=0; echo "  dsharp printed not affected"; }
: > "$TMP/calls"
( cd "$G" && env STUB_COUNT="$TMP/calls" BARBAR_ROOT="$G" bash "$ROOT/tests/barbar.sh" gate >/dev/null 2>&1 )
g_calls="$(grep -c . "$TMP/calls")"
[[ "$g_calls" -eq 16 ]] || { ok=0; echo "  barbar gate made $g_calls invocations; want 16 (audit 8 + gate 8)"; }
: > "$TMP/calls"
d_out2="$( cd "$G" && env STUB_COUNT="$TMP/calls" AFFECTED_BASE=HEAD AFFECTED_MUTANT=D1 STUB_AFFECTED_FAIL=1 bash tests/dsharp_strength.sh 2>&1 )"
[[ "$(printf '%s\n' "$d_out2" | tail -1)" == "DSHARP 4/4" && "$(grep -c . "$TMP/calls")" -eq 8 ]] \
  || { ok=0; echo "  AFFECTED_* changed the gate: $(printf '%s\n' "$d_out2" | tail -1), $(grep -c . "$TMP/calls") invocations"; }
grep -q 'AFFECTED_BASE\|AFFECTED_MUTANT\|affected\.py\|affected\.sh' "$ROOT/tests/dsharp_strength.sh" "$ROOT/tests/audit.sh" \
  && { ok=0; echo "  a full-run script reads the selector"; }
t AC4 "$ok" "with a narrowed diff present, dsharp and barbar gate run every check and twin (8 and 16 invocations), print no not affected, and AFFECTED_BASE/AFFECTED_MUTANT change nothing"

# ---- AC5  nightly -------------------------------------------------------------------------------------------------
ok=1
WF="$ROOT/.github/workflows/nightly.yml"
[[ -f "$WF" ]] || { ok=0; echo "  no .github/workflows/nightly.yml"; }
if [[ -f "$WF" ]]; then
  grep -q '^on:' "$WF" && grep -q 'schedule:' "$WF" && grep -q 'cron:' "$WF" || { ok=0; echo "  the workflow is not scheduled"; }
  grep -q 'tests/enforcement.sh' "$WF" || { ok=0; echo "  the workflow does not run tests/enforcement.sh"; }
  grep -q 'tests/dsharp_strength.sh' "$WF" || { ok=0; echo "  the workflow does not run tests/dsharp_strength.sh"; }
  grep -q 'tests/stress/affected.sh' "$WF" || { ok=0; echo "  the workflow does not run tests/stress/affected.sh"; }
fi
: > "$TMP/calls"
w_out="$( cd "$G" && env STUB_COUNT="$TMP/calls" bash tests/dsharp_strength.sh 2>&1 )"
[[ "$(printf '%s\n' "$w_out" | tail -1)" == "DSHARP 4/4" && "$(grep -c . "$TMP/calls")" -eq 8 ]] \
  || { ok=0; echo "  the workflow's command did not score every law"; }
t AC5 "$ok" "nightly.yml exists, runs on a schedule, and runs enforcement, dsharp and the affected stress; its dsharp command scores every law's check and twin"

# ---- AC6  mapping edges ------------------------------------------------------------------------------------------
ok=1
# path: core/x (no extension) is affected by an edit to core/x and not by web/y
add_x_y() { printf 'x\n' > "$1/core/x"; printf 'web y\n' > "$1/web/y"; }
F="$TMP/a6-path"; mkprod "$F" '### D8 — extensionless
path: core/x
check:  test -f core/x
break:  test -f core/missing

### D3 — web y
path: web/y
check:  test -f web/y
break:  test -f web/missing
' "" add_x_y || ok=0
printf 'core changed\n' > "$F/core/x"
required "$F" D8 || { ok=0; echo "  path: core/x did not map core/x"; }
required "$F" D3 && { ok=0; echo "  a core edit marked the web law D3 affected"; }
( cd "$F" && git checkout -q -- core/x ) && printf 'web changed\n' > "$F/web/y"
required "$F" D3 || { ok=0; echo "  the web edit did not map web/y"; }
required "$F" D8 && { ok=0; echo "  a web edit marked the core law D8 affected"; }
# :symbol is stripped, exactly as dsharp_strength.sh does
F="$TMP/a6-symbol"; mkprod "$F" '### D8 — with a symbol
path: core/x:withdraw()
check:  test -f core/x
break:  test -f core/missing
' "" add_x_y || ok=0
printf 'core changed\n' > "$F/core/x"
required "$F" D8 || { ok=0; echo "  path: core/x:withdraw() did not map core/x"; }
# a rename out of core affects the old module's laws and the new module's
F="$TMP/a6-rename"; mkprod "$F" "$LAWS" || ok=0
( cd "$F" && git mv core/x.txt web/x.txt ) || ok=0
ids="$(list_of "$F")"
has "$ids" D1 || { ok=0; echo "  the rename did not keep D1 (the old path)"; }
has "$ids" D4 || { ok=0; echo "  the rename did not keep D4 (the old module)"; }
has "$ids" D6 || { ok=0; echo "  the rename did not affect D6 (the new module)"; }
# CASCADE_ENVELOPE is the laws' envelope, not the host's
F="$TMP/a6-env"; mkprod "$F" "$LAWS" || ok=0
printf '### D9 — only core/x\npath: core/x.txt\ncheck:  test -f core/x.txt\nbreak:  test -f core/missing\n' > "$F/env-b.md"
printf 'core changed\n' > "$F/core/x.txt"
ids="$( cd "$F" && CASCADE_ENVELOPE="$F/env-b.md" bash tests/affected.sh --list 2>/dev/null )"
[[ "$ids" == "D9" ]] || { ok=0; echo "  CASCADE_ENVELOPE did not read the fixture envelope: $(echo "$ids" | tr '\n' ' ')"; }
t AC6 "$ok" "path: (with and without :symbol) maps a file, a rename out of a module affects both modules, and CASCADE_ENVELOPE selects the fixture's laws"

# ---- AC7  the base is the hop, not the branch ---------------------------------------------------------------------
ok=1
F="$TMP/a7"; mkprod "$F" "$LAWS" || ok=0
( cd "$F" && printf 'core changed\n' > core/x.txt && git add -A && git commit -qm "hop 1 work" ) || ok=0
( cd "$F" && printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: t66-hop2\n' > docs/cascade/hop-state.md \
  && git add docs/cascade/hop-state.md && git commit -qm "open hop 2" ) || ok=0
E1="$( cd "$F" && git rev-parse HEAD~2 )"
printf 'web changed\n' > "$F/web/z.txt"
ids="$(list_of "$F")"
[[ "$(printf '%s\n' "$ids" | sort | tr '\n' ' ')" == "D3 D6 " ]] || { ok=0; echo "  hop 2 saw '$(echo "$ids" | tr '\n' ' ')'; want D3 D6 (hop 1's core work is before the edge)"; }
ids_old="$( cd "$F" && bash tests/affected.sh --base "$E1" --list 2>/dev/null )"
has "$ids_old" D5 || { ok=0; echo "  --base E1 did not include the previous hop's core law (report-only base is broken)"; }
goal "$F" D3 D6
out="$( cd "$F" && env AFFECTED_BASE="$E1" bash tests/loop.sh 2>&1 )"
echo "$out" | grep -q '^LOOP 3/3$' || { ok=0; echo "  loop read AFFECTED_BASE instead of the hop-open commit:"; echo "$out" | tail -8 | sed 's/^/    /'; }
t AC7 "$ok" "at hop 2 the selector sees only web (D3, D6) and not hop 1's core work; --base E1 is report-only; the loop ignores AFFECTED_BASE"

# ---- AC8  measured ------------------------------------------------------------------------------------------------
echo "SKIP  AC8  measured on real Gradle by tests/stress/affected.sh (E1 goes in the EXECUTE report and CHANGELOG)"

exit "$fail"
