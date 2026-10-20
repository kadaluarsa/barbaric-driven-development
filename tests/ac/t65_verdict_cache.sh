#!/usr/bin/env bash
# AC tests for 05b t65-verdict-cache: a law's GREEN is reused only when nothing it declares has changed, and no merge
# decision ever reads it. Gradle is the stub (tests/ac/fixtures/gradlew-stub.py), so this runs without a JVM;
# tests/stress/verdict_cache.sh checks the build-cache half on real Gradle (E2). "Ran" is counted from the tree (a
# counter per shell law, the stub's argv log per Gradle law), never from the printed line.
#   AC1   a warm run scores D1–D5 and D9 from the cache, re-runs RED/THEATER, same verdicts and DSHARP k/n.
#   AC2   a one-byte edit re-runs exactly the laws that declare it (module closure included).
#         RED TWIN: a key without the module closure leaves :app's law cached after a :core edit.
#   AC3   every fail-closed trigger re-runs every law; a docs edit re-runs none.
#   AC4   forged entries are ignored. RED TWIN: a cache that skips the key comparison takes a forged entry.
#   AC5   only GREEN is stored, and only when the worktree did not change during the run.
#         RED TWINS: storing THEATER, and storing without the fingerprint re-check.
#   AC6   the merge gate and the nightly never read the cache (a correctly keyed GREEN for a RED law changes nothing).
#   AC7   parity with the pre-t65 script (219baef): byte-identical with the cache off; identical modulo `(cached)` on.
#   AC8   readers: audit marks a cached row, the k/n readers see the same score, the fingerprint is cascade_worktree_sha's.
#   AC9   --build-cache only on the harness's own law build; a remote URL only when signed, committed and https.
#   AC10  E1: cold, warm and one-module-edit runs measured on 20 laws (E2 is tests/stress/verdict_cache.sh).
#   AC11  the t56/t64/t66 ACs' `export DSHARP_CACHE=off` is load-bearing; a DSHARP 0/0 run is inert.
#   AC12  install.sh makes an installed repo ignore .cascade/verdicts/.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      DSHARP_CACHE DSHARP_HARNESS DSHARP_JOBS DSHARP_SERIAL DSHARP_MUTANT INV_MUTANT STUB_COUNT STUB_AFFECTED_FAIL \
      STUB_VERSION_FAIL STUB_ENV_LOG STUB_LAW_LEAK BDD_BUILD_CACHE_URL CASCADE_ENVELOPE
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$ROOT/tests/ac/fixtures/gradlew-stub.py"
BASELINE=219baef     # the last dsharp_strength.sh before t65
export CNT="$TMP/cnt"; mkdir -p "$CNT"

LAWS="$(cat <<'EOF'
### D1 — core module
check:  ./gradlew :core:test --tests p.D1Test
break:  INV_MUTANT=D1 ./gradlew :core:test --tests p.D1Test --rerun

### D2 — app module, depends on core
check:  ./gradlew :app:test --tests p.D2Test
break:  INV_MUTANT=D2 ./gradlew :app:test --tests p.D2Test --rerun

### D3 — web module
check:  ./gradlew :web:test --tests p.D3Test
break:  INV_MUTANT=D3 ./gradlew :web:test --tests p.D3Test --rerun

### D4 — a file
check:  echo x >> "$CNT/D4"; grep -q ok lib/a.txt
break:  echo x >> "$CNT/D4"; grep -q nope lib/a.txt
reason: REMOVED_GUARD — fixture
path:   lib/a.txt

### D5 — a file with a symbol
check:  echo x >> "$CNT/D5"; grep -q ok lib/b.txt
break:  echo x >> "$CNT/D5"; grep -q nope lib/b.txt
reason: REMOVED_GUARD — fixture
path:   lib/b.txt:run

### D6 — red
check:  echo x >> "$CNT/D6"; false
break:  true

### D7 — theater
check:  echo x >> "$CNT/D7"; true
break:  echo x >> "$CNT/D7"; true

### D8 — unproven
check:  true
break:  TODO

### D9 — unmapped green
check:  echo x >> "$CNT/D9"; true
break:  echo x >> "$CNT/D9"; false
EOF
)"
GREENS="D1 D2 D3 D4 D5 D9"

scenario() {
  cat > "$1/gradle-stub.json" <<'EOF'
{"tasks": {
  ":core:test": {"test": true, "tests": ["p.D1Test#law"], "mutantFails": {"D1": ["p.D1Test#law"]}},
  ":app:test": {"test": true, "tests": ["p.D2Test#law"], "mutantFails": {"D2": ["p.D2Test#law"]}},
  ":web:test": {"test": true, "tests": ["p.D3Test#law"], "mutantFails": {"D3": ["p.D3Test#law"]}}
 },
 "select": {"p.D1Test": ["p.D1Test#law"], "p.D2Test": ["p.D2Test#law"], "p.D3Test": ["p.D3Test#law"]},
 "projects": {":core": {"dir": "core", "deps": []},
              ":app": {"dir": "app", "deps": [":core"]},
              ":web": {"dir": "web", "deps": []}}
}
EOF
}
mkprod() {  # mkprod <dir> [laws] [locked lines]
  local d="$1" laws="${2:-$LAWS}" locked="${3:-}"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/gradle/wrapper" "$d/core/src" "$d/app/src" "$d/web/src" "$d/lib" "$d/scripts"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/dsharp_strength.sh" "$ROOT/tests/audit.sh" "$d/tests/"
  find "$d/tests/lib" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip\n' > "$d/gradle/wrapper/gradle-wrapper.properties"
  printf '.cascade/\n.gradle/\nbuild/\n*/build/\ngradle-stub-version.txt\n' > "$d/.gitignore"
  echo 'class Core {}' > "$d/core/src/Core.java"; echo 'class App {}' > "$d/app/src/App.java"
  echo 'class Web {}' > "$d/web/src/Web.java"; printf 'ok\n' > "$d/lib/a.txt"; printf 'ok\ndef run\n' > "$d/lib/b.txt"
  echo 'print(1)' > "$d/scripts/tool.py"; echo '# notes' > "$d/docs/notes.md"
  printf 'CURRENT_HOP: NONE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  { for id in D1 D2 D3 D4 D5 D6 D7 D8 D9; do printf '| %s | law | dsharp | IMPLEMENTED |\n' "$id"; done; } > "$d/docs/cascade/10-audit.md"
  printf '# envelope\n\n<EDIT>\n%s\n</EDIT>\n\n## Locked decisions\n\n<EDIT>\n%s\n</EDIT>\n' "$laws" "$locked" > "$d/docs/cascade/envelope.md"
  scenario "$d"
  ( cd "$d" && git init -q && git add -A && git commit -qm init )
}
run() {  # run <dir> [VAR=value…] -> $OUT (everything), $RAN (ids whose commands ran), $CACHED (ids printed cached)
  local d="$1"; shift
  rm -rf "$CNT"; mkdir -p "$CNT"; : > "$TMP/calls"
  OUT="$(cd "$d" && env STUB_COUNT="$TMP/calls" "$@" bash tests/dsharp_strength.sh 2>&1)"
  RAN=""
  local id
  for id in D1 D2 D3 D4 D5 D6 D7 D8 D9; do
    case "$id" in
      D1|D2|D3) grep -q -- "--tests p.${id}Test" "$TMP/calls" && RAN="$RAN $id" ;;
      *) [[ -s "$CNT/$id" ]] && RAN="$RAN $id" ;;
    esac
  done
  RAN="${RAN# }"
  CACHED="$(echo "$OUT" | awk '/^GREEN .*  \(cached\)$/{print $2}' | tr '\n' ' ' | sed 's/ $//')"
}
verdicts() { echo "$1" | grep -E '^(GREEN|RED|THEATER|UNPROVEN|DSHARP|FATAL|WARNING|METADATA)' | sed -E 's/  \(cached\)$//'; }
expect_ran() {  # expect_ran <label> <want>
  [[ "$RAN" == "$2" ]] || { ok=0; echo "  $1: ran '$RAN', want '$2'"; }
}
warm() { run "$1" DSHARP_CACHE=on; }

# ---- AC1  warm run ----------------------------------------------------------------------------------------------
ok=1
A="$TMP/a1"; mkprod "$A"
run "$A" DSHARP_CACHE=on; cold="$OUT"
expect_ran "cold" "D1 D2 D3 D4 D5 D6 D7 D9"
run "$A" DSHARP_CACHE=on; hot="$OUT"
expect_ran "warm" "D6 D7"
[[ "$CACHED" == "$GREENS" ]] || { ok=0; echo "  warm cached '$CACHED', want '$GREENS'"; }
[[ "$(verdicts "$cold")" == "$(verdicts "$hot")" ]] || { ok=0; echo "  verdicts differ:"; diff <(verdicts "$cold") <(verdicts "$hot") | sed 's/^/    /'; }
grep -q -- '--tests' "$TMP/calls" && { ok=0; echo "  the warm run started a law build: $(grep -- '--tests' "$TMP/calls" | head -1)"; }
echo "$hot" | grep -qx 'CACHE     6 hit, 3 run' || { ok=0; echo "  no 'CACHE 6 hit, 3 run' line: $(echo "$hot" | grep '^CACHE')"; }
[[ "$(echo "$cold" | grep '^DSHARP')" == "DSHARP 6/9" ]] || { ok=0; echo "  the fixture is not 6 GREEN of 9: $(echo "$cold" | grep '^DSHARP')"; }
t AC1 "$ok" "a warm run scores every GREEN law from the cache with no law command, re-runs RED and THEATER, and prints the same verdicts and DSHARP k/n"

# ---- AC2  exactly the dependents ----------------------------------------------------------------------------------
ok=1
A="$TMP/a2"; mkprod "$A"; warm "$A"
echo 'class Core { int x; }' > "$A/core/src/Core.java"; run "$A" DSHARP_CACHE=on; expect_ran "core edit" "D1 D2 D6 D7 D9"
echo 'class Web { int x; }' > "$A/web/src/Web.java";  run "$A" DSHARP_CACHE=on; expect_ran "web edit" "D3 D6 D7 D9"
printf 'ok \n' > "$A/lib/a.txt";                       run "$A" DSHARP_CACHE=on; expect_ran "lib/a.txt edit" "D4 D6 D7 D9"
printf 'ok\ndef run \n' > "$A/lib/b.txt";              run "$A" DSHARP_CACHE=on; expect_ran "lib/b.txt edit (path with :symbol)" "D5 D6 D7 D9"
# red twin: the key without the module closure — :app's law stays cached after a :core edit
T="$TMP/a2t"; mkprod "$T"
python3 - "$T/tests/lib/verdict_cache.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "            mods, why = closure(mod, projects)\n"
if old not in s: sys.exit("twin: closure() call not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "            mods, why = {mod}, \"\"\n", 1))
PY
warm "$T"; echo 'class Core { int x; }' > "$T/core/src/Core.java"; run "$T" DSHARP_CACHE=on
[[ "$RAN" == "D1 D6 D7 D9" ]] || { ok=0; echo "  red twin did not go red: without the closure the core edit ran '$RAN' (want D2 left cached)"; }
t AC2 "$ok" "a one-byte edit re-runs exactly the laws that declare it — the module, its dependents, a path:, a path:symbol (red twin: no closure leaves :app's law cached)"

# ---- AC3  fail closed ---------------------------------------------------------------------------------------------
ok=1
ALL="D1 D2 D3 D4 D5 D6 D7 D9"
A="$TMP/a3"; mkprod "$A"
warm "$A"; echo 'include "core"' > "$A/settings.gradle";        run "$A" DSHARP_CACHE=on; expect_ran "settings.gradle" "$ALL"
warm "$A"; echo 'print(2)' > "$A/scripts/tool.py";               run "$A" DSHARP_CACHE=on; expect_ran "an unowned file" "$ALL"
warm "$A"; echo '# x' >> "$A/tests/lib/laws.py";                   run "$A" DSHARP_CACHE=on; expect_ran "a scoring file" "$ALL"
warm "$A"; echo 'Gradle 9.9 (stub)' > "$A/gradle-stub-version.txt"; run "$A" DSHARP_CACHE=on; expect_ran "a new toolchain" "$ALL"
warm "$A"; mkdir -p "$A/.cascade"; echo 'version 9.9.9' > "$A/.cascade/manifest"; rm -f "$A/.claude-plugin/plugin.json"
run "$A" DSHARP_CACHE=on; expect_ran "a new pack version" "$ALL"
warm "$A"; run "$A" DSHARP_CACHE=on INV_MUTANT=D1;               expect_ran "INV_MUTANT exported" "$ALL"
warm "$A"; run "$A" DSHARP_CACHE=on STUB_AFFECTED_FAIL=1;        expect_ran "the module map fails after a warm run" "$ALL"
echo "$OUT" | grep -q '^CACHE     off — the module map build failed' || { ok=0; echo "  no 'CACHE off' reason for the map failure: $(echo "$OUT" | grep '^CACHE')"; }
warm "$A"; run "$A" DSHARP_CACHE=on STUB_VERSION_FAIL=1;         expect_ran "--version fails" "$ALL"
echo "$OUT" | grep -q '^CACHE     off — ./gradlew --version failed' || { ok=0; echo "  no 'CACHE off' reason for --version: $(echo "$OUT" | grep '^CACHE')"; }
warm "$A"; echo '# more' >> "$A/docs/notes.md";                  run "$A" DSHARP_CACHE=on; expect_ran "a docs edit" "D6 D7"
warm "$A"; echo 'class Core { int y; }' > "$A/core/src/Core.java"; run "$A" DSHARP_CACHE=on; expect_ran "an edit any unmapped law sees" "D1 D2 D6 D7 D9"
# a shared module, signed: an edit in it re-runs every law; the same line unsigned declares nothing
S="$TMP/a3s"; mkprod "$S" "$LAWS" '- AFFECTED_SHARED_MODULES: :web'
warm "$S"; echo 'class Web { int z; }' > "$S/web/src/Web.java"; run "$S" DSHARP_CACHE=on; expect_ran "a signed shared module" "$ALL"
U="$TMP/a3u"; mkprod "$U"; printf '\n- AFFECTED_SHARED_MODULES: :web\n' >> "$U/docs/cascade/envelope.md"
warm "$U"; echo 'class Web { int z; }' > "$U/web/src/Web.java"; run "$U" DSHARP_CACHE=on; expect_ran "an unsigned shared module" "D3 D6 D7 D9"
# not a git worktree
N="$TMP/a3n"; mkprod "$N"; warm "$N"; rm -rf "$N/.git"; run "$N" DSHARP_CACHE=on; expect_ran "no git" "$ALL"
echo "$OUT" | grep -q '^CACHE     off — not a git worktree' || { ok=0; echo "  no 'CACHE off' for a non-git tree: $(echo "$OUT" | grep '^CACHE')"; }
t AC3 "$ok" "every fail-closed trigger re-runs every law (build logic, an unowned file, a scoring file, toolchain, pack version, INV_MUTANT, map and --version failure, a signed shared module, no git); a docs edit re-runs none"

# ---- AC4  forged entries ------------------------------------------------------------------------------------------
ok=1
A="$TMP/a4"; mkprod "$A"; warm "$A"
V="$A/.cascade/verdicts"
real="$(cat "$V/D4.json")"
forge() {  # forge <label> <python expression that writes V/D4.json from `e`, the real entry>
  python3 - "$V" "$2" <<'PY'
import json, os, sys
v, expr = sys.argv[1], sys.argv[2]
e = json.load(open(os.path.join(v, "D4.json")))
exec(expr)
PY
  run "$A" DSHARP_CACHE=on
  [[ " $RAN " == *" D4 "* ]] || { ok=0; echo "  forged entry ($1) was taken: D4 did not run"; }
  printf '%s' "$real" > "$V/D4.json"
}
forge "another law's entry"  'import shutil; shutil.copy(os.path.join(v, "D5.json"), os.path.join(v, "D4.json"))'
forge "an old key"           'e["key"] = "0" * 64; json.dump(e, open(os.path.join(v, "D4.json"), "w"))'
forge "verdict RED"          'e["verdict"] = "RED"; json.dump(e, open(os.path.join(v, "D4.json"), "w"))'
forge "verdict 'GREEN '"     'e["verdict"] = "GREEN "; json.dump(e, open(os.path.join(v, "D4.json"), "w"))'
forge "bad JSON"             'open(os.path.join(v, "D4.json"), "w").write("{\"schema\": ")'
forge "schema 2"             'e["schema"] = "bdd-verdict-cache/2"; json.dump(e, open(os.path.join(v, "D4.json"), "w"))'
forge "a symlink"            'json.dump(e, open(os.path.join(v, "real.json"), "w")); os.remove(os.path.join(v, "D4.json")); os.symlink(os.path.join(v, "real.json"), os.path.join(v, "D4.json"))'
rm -f "$V/real.json"
# red twin: a cache that skips the key comparison takes the forged old key
T="$TMP/a4t"; mkprod "$T"
python3 - "$T/tests/lib/verdict_cache.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '    if entry.get("key") != key:\n        return False\n'
if old not in s: sys.exit("twin: key comparison not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "", 1))
PY
warm "$T"
python3 - "$T/.cascade/verdicts/D4.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1])); e["key"] = "0" * 64; json.dump(e, open(sys.argv[1], "w"))
PY
printf 'ok \n' > "$T/lib/a.txt"; run "$T" DSHARP_CACHE=on
[[ " $RAN " != *" D4 "* ]] || { ok=0; echo "  red twin did not go red: without the key comparison D4 still ran"; }
t AC4 "$ok" "a forged entry — another law's, an old key, RED, 'GREEN ', bad JSON, another schema, a symlink — is ignored and the law runs (red twin: no key comparison takes it)"

# ---- AC5  only GREEN, only on an unchanged worktree ---------------------------------------------------------------
ok=1
A="$TMP/a5"; mkprod "$A"; warm "$A"
stored="$(ls "$A/.cascade/verdicts" | sed 's/\.json$//' | sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$stored" == "D1 D2 D3 D4 D5 D9" ]] || { ok=0; echo "  stored '$stored', want the GREEN laws only"; }
GEN="$(printf '%s\n\n### D10 — writes a tracked file\ncheck:  echo run >> scripts/gen.txt; true\nbreak:  false\n' "$LAWS")"
W="$TMP/a5w"; mkprod "$W" "$GEN"; echo 0 > "$W/scripts/gen.txt"; ( cd "$W" && git add -A && git commit -qm gen )
run "$W" DSHARP_CACHE=on
[[ ! -d "$W/.cascade/verdicts" || -z "$(ls "$W/.cascade/verdicts")" ]] || { ok=0; echo "  a run that changed the worktree stored: $(ls "$W/.cascade/verdicts" | tr '\n' ' ')"; }
echo "$OUT" | grep -q '^CACHE     not stored — the worktree changed while the laws ran' || { ok=0; echo "  no 'not stored' line"; }
# red twin 1: a dsharp that also stores THEATER
T="$TMP/a5t"; mkprod "$T"
python3 - "$T/tests/dsharp_strength.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '[[ "$status" == GREEN ]] && printf'
if old not in s: sys.exit("twin: the store filter is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, '[[ "$status" == GREEN || "$status" == THEATER ]] && printf', 1))
PY
warm "$T"
[[ -f "$T/.cascade/verdicts/D7.json" ]] || { ok=0; echo "  red twin 1 did not go red: a THEATER-storing dsharp stored no D7"; }
# red twin 2: a store that skips the fingerprint re-check
T2="$TMP/a5t2"; mkprod "$T2" "$GEN"; echo 0 > "$T2/scripts/gen.txt"; ( cd "$T2" && git add -A && git commit -qm gen )
python3 - "$T2/tests/lib/verdict_cache.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "    if f2 != f1:\n"
if old not in s: sys.exit("twin: the fingerprint re-check is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "    if False:\n", 1))
PY
run "$T2" DSHARP_CACHE=on
[[ -n "$(ls "$T2/.cascade/verdicts" 2>/dev/null)" ]] || { ok=0; echo "  red twin 2 did not go red: without the re-check nothing was stored either"; }
t AC5 "$ok" "only GREEN laws are stored, and nothing when the worktree changed during the run (red twins: storing THEATER; no fingerprint re-check)"

# ---- AC6  the merge gate and the nightly never read it ------------------------------------------------------------
ok=1
G="$TMP/a6"; mkprod "$G"
cat > "$TMP/plant.py" <<'PY'
import os, subprocess, sys
g = sys.argv[1]
rows = []
for i, line in enumerate(sys.stdin.read().splitlines()):
    p = [x.strip() for x in line.split("|")]
    chk = "" if p[2] in ("TODO", "none", "") else p[2]; brk = "" if p[3] in ("TODO", "none", "") else p[3]
    if chk and brk:
        rows.append(f"L\t{i}\t{p[0]}\t{chk}\t{brk}\t{p[5]}")
r = subprocess.run(["python3", "-B", "tests/lib/verdict_cache.py", "keys", g, os.path.join(g, "docs/cascade/envelope.md"),
                    os.path.join(g, ".cascade/verdicts")], cwd=g, input="\n".join(rows) + "\n", capture_output=True, text=True)
idx = {l.split("\t")[1]: l.split("\t")[2] for l in rows}
for line in r.stdout.splitlines():
    k = line.split("\t")
    if k[0] == "K" and idx.get(k[1]) == "D6":
        os.makedirs(os.path.join(g, ".cascade/verdicts"), exist_ok=True)
        open(os.path.join(g, ".cascade/verdicts/D6.json"), "w").write(
            '{"schema": "bdd-verdict-cache/1", "id": "D6", "key": "%s", "verdict": "GREEN", "at": "x"}' % k[2])
PY
plant() {  # a correctly keyed GREEN for D6 (the RED law), from the library's own key function
  ( cd "$G" && python3 -B tests/lib/laws.py docs/cascade/envelope.md --declared ) | python3 "$TMP/plant.py" "$G"
}
plant
run "$G" DSHARP_CACHE=on
[[ " $CACHED " == *" D6 "* ]] || { ok=0; echo "  the planted entry is not a real hit, so this AC would prove nothing: $(echo "$OUT" | grep D6)"; }
plant; run "$G" DSHARP_CACHE=off
echo "$OUT" | grep -q '^RED       D6' || { ok=0; echo "  DSHARP_CACHE=off did not score D6 RED"; }
echo "$OUT" | grep -q '^CACHE' && { ok=0; echo "  DSHARP_CACHE=off printed a CACHE line"; }
plant; run "$G" DSHARP_CACHE=bogus
echo "$OUT" | grep -q '^RED       D6' || { ok=0; echo "  DSHARP_CACHE=bogus took the cache"; }
gate() {  # gate -> $GOUT and the per-law counters in $GCNT
  rm -rf "$CNT"; mkdir -p "$CNT"; : > "$TMP/calls"
  GOUT="$(cd "$G" && env STUB_COUNT="$TMP/calls" BARBAR_ROOT="$G" bash "$ROOT/tests/barbar.sh" gate 2>&1)"
  GCNT="$(for id in D4 D5 D6 D7 D9; do printf '%s=%s ' "$id" "$(wc -l < "$CNT/$id" 2>/dev/null | tr -d ' ' || echo 0)"; done; \
          for id in D1 D2 D3; do printf '%s=%s ' "$id" "$(grep -c -- "--tests p.${id}Test" "$TMP/calls" | tr -d ' ')"; done)"
}
warm "$G"; plant; gate; with="$GCNT"; gout="$GOUT"
rm -rf "$G/.cascade/verdicts"; gate; without="$GCNT"
[[ "$with" == "$without" ]] || { ok=0; echo "  the gate ran different commands with a cache present: '$with' vs '$without'"; }
echo "$gout" | grep -q 'BARBAR merge REFUSED' || { ok=0; echo "  the gate did not refuse"; }
echo "$gout" | grep -q 'RED       D6' || { ok=0; echo "  the gate did not name RED D6"; }
echo "$gout" | grep -q '(cached)' && { ok=0; echo "  the gate printed a cached verdict"; }
[[ "$with" == *"D4=4"* ]] || { ok=0; echo "  the gate did not run D4's two commands in audit and itself: $with"; }
NY="$ROOT/.github/workflows/nightly.yml"
python3 - "$NY" <<'PY' || { ok=0; echo "  nightly.yml: DSHARP_CACHE is not off on the dsharp step only"; }
import re, sys
s = open(sys.argv[1]).read()
steps = re.split(r"\n      - ", s)
d = [x for x in steps if "run: bash tests/dsharp_strength.sh" in x]
e = [x for x in steps if "run: bash tests/enforcement.sh" in x]
job_env = re.search(r"\n    env:\n(?:      .*\n)*?      DSHARP_CACHE", s)
sys.exit(0 if d and re.search(r"DSHARP_CACHE:\s*'?off'?", d[0]) and e and "DSHARP_CACHE" not in e[0] and not job_env else 1)
PY
t AC6 "$ok" "a correctly keyed GREEN planted for a RED law changes nothing at the merge gate (same commands, RED, REFUSED) or with DSHARP_CACHE off/bogus; the nightly's dsharp step is off and its enforcement step is not handed it"

# ---- AC7  parity with the pre-t65 script --------------------------------------------------------------------------
ok=1
A="$TMP/a7"; mkprod "$A"
git -C "$ROOT" show "$BASELINE:tests/dsharp_strength.sh" > "$A/tests/dsharp_base.sh" 2>/dev/null \
  || { ok=0; echo "  cannot read the baseline $BASELINE (a shallow clone?)"; }
base() { ( cd "$A" && env "$@" bash tests/dsharp_base.sh 2>&1 ); }
strip() { echo "$1" | sed -E 's/  \(cached\)$//' | grep -v '^CACHE '; }
for jobs in 1 4; do
  rm -rf "$A/.cascade"
  b="$(base DSHARP_JOBS=$jobs)"; rb=$?
  run "$A" DSHARP_JOBS=$jobs DSHARP_CACHE=off; off="$OUT"
  [[ "$b" == "$off" ]] || { ok=0; echo "  JOBS=$jobs: cache off is not byte-identical to $BASELINE:"; diff <(echo "$b") <(echo "$off") | sed 's/^/    /' | head; }
  run "$A" DSHARP_JOBS=$jobs DSHARP_CACHE=on; cold="$OUT"; ( cd "$A" && DSHARP_JOBS=$jobs DSHARP_CACHE=on bash tests/dsharp_strength.sh >/dev/null 2>&1 ); rc=$?
  run "$A" DSHARP_JOBS=$jobs DSHARP_CACHE=on; hot="$OUT"
  [[ "$(strip "$cold")" == "$b" ]] || { ok=0; echo "  JOBS=$jobs: a cold run differs from $BASELINE beyond (cached)/CACHE:"; diff <(echo "$b") <(strip "$cold") | sed 's/^/    /' | head; }
  [[ "$(strip "$hot")" == "$b" ]] || { ok=0; echo "  JOBS=$jobs: a warm run differs from $BASELINE beyond (cached)/CACHE:"; diff <(echo "$b") <(strip "$hot") | sed 's/^/    /' | head; }
  [[ "$rb" -eq "$rc" ]] || { ok=0; echo "  JOBS=$jobs: exit $rc, baseline $rb"; }
done
P="$TMP/a7p"; mkdir -p "$P/tests"; cp -R "$ROOT/tests/lib" "$P/tests/lib"
git -C "$ROOT" show "$BASELINE:tests/dsharp_strength.sh" > "$P/tests/dsharp_strength.sh"
pb="$(bash "$P/tests/dsharp_strength.sh" --root "$ROOT" 2>&1)"; pn="$(DSHARP_CACHE=on bash "$ROOT/tests/dsharp_strength.sh" --root "$ROOT" 2>&1)"
[[ "$pb" == "$pn" ]] || { ok=0; echo "  the pack repo (DSHARP 0/0) is not byte-identical with the cache on"; }
t AC7 "$ok" "against $BASELINE: DSHARP_CACHE=off is byte-identical, cold and warm runs identical but for (cached) and the CACHE line, same exit code, JOBS=1 and JOBS=4, and a 0/0 repo unchanged"

# ---- AC8  readers -------------------------------------------------------------------------------------------------
ok=1
A="$TMP/a8"; mkprod "$A"; warm "$A"
au="$(cd "$A" && DSHARP_CACHE=on bash tests/audit.sh 2>&1)"
echo "$au" | grep -E '^IMPLEMENTED +D4 ' | grep -q '(D# GREEN (cached))' || { ok=0; echo "  audit does not mark a cached D# row: $(echo "$au" | grep ' D4 ')"; }
echo "$au" | grep -E '^VIOLATED +D6 ' | grep -q '(D# RED)' || { ok=0; echo "  audit's RED row changed: $(echo "$au" | grep ' D6 ')"; }
run "$A" DSHARP_CACHE=on
[[ "$(echo "$OUT" | grep -oE 'DSHARP [0-9]+/[0-9]+' | tail -1)" == "DSHARP 6/9" ]] || { ok=0; echo "  doctor's DSHARP k/n reader sees another score"; }
echo "$OUT" | grep -E '^GREEN' | while IFS= read -r l; do [[ "${l:0:8}" == "GREEN   " ]] || echo bad; done | grep -q bad && { ok=0; echo "  sign_ok's l[:8] reader breaks"; }
fp() { ( cd "$1" && python3 -B tests/lib/verdict_cache.py fingerprint "$1" ); }
sh_fp() { bash -c '. "$1/tests/lib/cascade.sh"; cascade_worktree_sha "$1"' _ "$1"; }
[[ -n "$(fp "$A")" && "$(fp "$A")" == "$(sh_fp "$A")" ]] || { ok=0; echo "  clean: python '$(fp "$A")' vs cascade_worktree_sha '$(sh_fp "$A")'"; }
echo dirty >> "$A/core/src/Core.java"; echo new > "$A/scripts/new.py"
[[ "$(fp "$A")" == "$(sh_fp "$A")" ]] || { ok=0; echo "  dirty: python '$(fp "$A")' vs cascade_worktree_sha '$(sh_fp "$A")'"; }
t AC8 "$ok" "audit marks a cached D# row and keeps RED rows; the DSHARP k/n and sign-hook readers parse a cached line; the cache's fingerprint equals cascade_worktree_sha, clean and dirty"

# ---- AC9  the build cache on the harness's own law build ----------------------------------------------------------
ok=1
HLAWS="$(printf '### D1 — core\ncheck:  ./gradlew :core:test --tests p.D1Test\nbreak:  INV_MUTANT=D1 ./gradlew :core:test --tests p.D1Test --rerun\n\n### D2 — app\ncheck:  ./gradlew :app:test --tests p.D2Test\nbreak:  INV_MUTANT=D2 ./gradlew :app:test --tests p.D2Test --rerun\n')"
SIGNED='- DSHARP_GRADLE_HARNESS: on — locked 2026-10-20 — reason: AC fixture'
hrun() {  # hrun <dir> [VAR=value…] -> $LAWB (the law build's argv), $LAWE (its env log), $OWN (each law's own commands)
  local d="$1"; shift
  rm -rf "$d/.cascade" "$d/.gradle"; : > "$TMP/calls"; : > "$TMP/envlog"
  ( cd "$d" && env STUB_COUNT="$TMP/calls" STUB_ENV_LOG="$TMP/envlog" "$@" bash tests/dsharp_strength.sh >/dev/null 2>&1 )
  LAWB="$(grep 'bddLaws' "$TMP/calls")"; LAWE="$(cat "$TMP/envlog")"; OWN="$(grep -- '--tests' "$TMP/calls" | grep -v bddLaws)"
}
H="$TMP/a9"; mkprod "$H" "$HLAWS" "$(printf '%s\n- DSHARP_GRADLE_BUILD_CACHE_URL: https://cache.example/' "$SIGNED")"
hrun "$H" DSHARP_CACHE=on
[[ "$LAWB" == *"--build-cache"* ]] || { ok=0; echo "  cache on: the law build has no --build-cache: '$LAWB'"; }
[[ "$LAWE" == "BDD_BUILD_CACHE_URL=https://cache.example/" ]] || { ok=0; echo "  a signed https URL did not reach the law build: '$LAWE'"; }
hrun "$H" DSHARP_CACHE=off
[[ -n "$LAWB" && "$LAWB" != *"--build-cache"* ]] || { ok=0; echo "  cache off: the law build has --build-cache (or did not run): '$LAWB'"; }
[[ "$LAWE" == "BDD_BUILD_CACHE_URL=" ]] || { ok=0; echo "  cache off: the URL still reached the law build: '$LAWE'"; }
hrun "$H" DSHARP_CACHE=on DSHARP_HARNESS=off
echo "$OWN" | grep -q -- '--build-cache' && { ok=0; echo "  a law's own command was given --build-cache"; }
[[ -n "$OWN" ]] || { ok=0; echo "  the laws' own commands did not run with the harness off"; }
H2="$TMP/a9b"; mkprod "$H2" "$HLAWS" "$SIGNED"; printf '\n- DSHARP_GRADLE_BUILD_CACHE_URL: https://cache.example/\n' >> "$H2/docs/cascade/envelope.md"
( cd "$H2" && git commit -qam unsigned )
hrun "$H2" DSHARP_CACHE=on BDD_BUILD_CACHE_URL=https://inherited.example/
[[ "$LAWE" == "BDD_BUILD_CACHE_URL=" ]] || { ok=0; echo "  an unsigned or inherited URL reached the law build: '$LAWE'"; }
H3="$TMP/a9c"; mkprod "$H3" "$HLAWS" "$(printf '%s\n- DSHARP_GRADLE_BUILD_CACHE_URL: http://cache.example/' "$SIGNED")"
hrun "$H3" DSHARP_CACHE=on
[[ "$LAWE" == "BDD_BUILD_CACHE_URL=" ]] || { ok=0; echo "  a plain-http URL reached the law build: '$LAWE'"; }
grep -q 'push = false' "$ROOT/tests/lib/law_harness.init.gradle" || { ok=0; echo "  the init script's remote cache is not read-only"; }
grep -q 'c.outputs.cacheIf { false }' "$ROOT/tests/lib/law_harness.init.gradle" || { ok=0; echo "  t64's law copies are no longer cacheIf { false }"; }
t AC9 "$ok" "--build-cache only on the harness's law build and only with the cache on; a law's own command is never changed; a remote URL only when signed, committed and https, read-only; law copies stay uncacheable"

# ---- AC10  E1, measured ------------------------------------------------------------------------------------------
ok=1
E1LAWS="$(for i in $(seq 1 20); do
  if [[ "$i" -le 3 ]]; then m=core; elif [[ "$i" -le 5 ]]; then m=app; else m=web; fi
  printf '### D%s — law %s\ncheck:  ./gradlew :%s:test --tests p.D%sTest\nbreak:  INV_MUTANT=D%s ./gradlew :%s:test --tests p.D%sTest --rerun\n\n' "$i" "$i" "$m" "$i" "$i" "$m" "$i"
done)"
E="$TMP/e1"; mkprod "$E" "$E1LAWS"
python3 - "$E/gradle-stub.json" <<'PY'
import json, sys
mods = {m: [] for m in ("core", "app", "web")}
for i in range(1, 21):
    mods["core" if i <= 3 else "app" if i <= 5 else "web"].append(i)
tasks = {f":{m}:test": {"test": True, "tests": [f"p.D{i}Test#law" for i in ids],
                        "mutantFails": {f"D{i}": [f"p.D{i}Test#law"] for i in ids}} for m, ids in mods.items()}
sel = {f"p.D{i}Test": [f"p.D{i}Test#law"] for i in range(1, 21)}
json.dump({"tasks": tasks, "select": sel, "projects": {":core": {"dir": "core", "deps": []},
          ":app": {"dir": "app", "deps": [":core"]}, ":web": {"dir": "web", "deps": []}}}, open(sys.argv[1], "w"))
PY
( cd "$E" && git add -A && git commit -qm e1 )
now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
measure() {  # measure <label>
  local t0 t1; : > "$TMP/calls"; t0="$(now)"
  ( cd "$E" && STUB_COUNT="$TMP/calls" DSHARP_CACHE=on bash tests/dsharp_strength.sh >/dev/null 2>&1 ); t1="$(now)"
  printf '  E1  %-22s %6.2fs  %3s law commands  %s other Gradle calls\n' "$1" "$(python3 -c "print($t1 - $t0)")" \
    "$(grep -c -- '--tests' "$TMP/calls" | tr -d ' ')" "$(grep -vc -- '--tests' "$TMP/calls" | tr -d ' ')"
  E1N="$(grep -c -- '--tests' "$TMP/calls" | tr -d ' ')"
}
measure "cold (20 laws)";     [[ "$E1N" -eq 40 ]] || { ok=0; echo "  cold ran $E1N law commands, want 40"; }
measure "warm, unchanged";    [[ "$E1N" -eq 0 ]]  || { ok=0; echo "  warm ran $E1N law commands, want 0"; }
echo 'class Core { int e; }' > "$E/core/src/Core.java"
measure "core edit (D1-D5)";  [[ "$E1N" -eq 10 ]] || { ok=0; echo "  a core edit ran $E1N law commands, want 10 (core + app)"; }
t AC10 "$ok" "E1: 20 laws over three modules — cold 40 law commands, warm 0, a core edit 10 (its laws and its dependent's); times above"

# ---- AC11  the existing ACs and a 0/0 repo ------------------------------------------------------------------------
ok=1
for ac in t56_dsharp_parallel t64_law_harness t66_affected_laws; do
  grep -qx 'export DSHARP_CACHE=off.*' "$ROOT/tests/ac/$ac.sh" || { ok=0; echo "  $ac.sh has no 'export DSHARP_CACHE=off'"; }
done
# load-bearing: without the line, t64's exact invocation counts go red (the cheapest of the three to re-run)
X="$TMP/a11"; mkdir -p "$X/tests/ac/fixtures"; cp -R "$ROOT/tests/lib" "$X/tests/lib"
cp "$ROOT/tests/dsharp_strength.sh" "$ROOT/tests/audit.sh" "$ROOT/tests/barbar.sh" "$X/tests/" 2>/dev/null
cp "$ROOT/tests/ac/fixtures/gradlew-stub.py" "$X/tests/ac/fixtures/"
grep -v '^export DSHARP_CACHE=off' "$ROOT/tests/ac/t64_law_harness.sh" > "$X/tests/ac/t64_law_harness.sh"
if bash "$X/tests/ac/t64_law_harness.sh" >"$TMP/t64-nocache.out" 2>&1; then
  ok=0; echo "  t64's AC passes without 'export DSHARP_CACHE=off' — the line would not be load-bearing"
fi
before="$(ls -A "$ROOT/.cascade/verdicts" 2>/dev/null | wc -l | tr -d ' ')"
out0="$(DSHARP_CACHE=on bash "$ROOT/tests/dsharp_strength.sh" --root "$ROOT" 2>&1)"
echo "$out0" | grep -q '^CACHE' && { ok=0; echo "  a DSHARP 0/0 run printed a CACHE line"; }
[[ "$(ls -A "$ROOT/.cascade/verdicts" 2>/dev/null | wc -l | tr -d ' ')" == "$before" ]] || { ok=0; echo "  a DSHARP 0/0 run wrote a verdict file"; }
t AC11 "$ok" "the t56/t64/t66 ACs export DSHARP_CACHE=off and t64's goes red without it; a DSHARP 0/0 run prints no CACHE line and writes nothing"

# ---- AC12  installed repos ignore the store -----------------------------------------------------------------------
ok=1
I="$TMP/a12"; mkdir -p "$I"; ( cd "$I" && git init -q )
bash "$ROOT/install.sh" "$I" >"$TMP/install.out" 2>&1 || { ok=0; echo "  install.sh failed: $(tail -3 "$TMP/install.out")"; }
grep -qxF '.cascade/verdicts/' "$I/.gitignore" 2>/dev/null || { ok=0; echo "  the installed .gitignore does not ignore .cascade/verdicts/"; }
mkdir -p "$I/.cascade/verdicts"; echo '{}' > "$I/.cascade/verdicts/D1.json"
( cd "$I" && git status --porcelain --untracked-files=all ) | grep -q 'verdicts' && { ok=0; echo "  git status shows a verdict entry"; }
t AC12 "$ok" "install.sh makes an installed repo ignore .cascade/verdicts/, so an entry never shows in git status"

exit "$fail"
