#!/usr/bin/env bash
# AC tests for 05b t109-oracle-strength — THE ORACLE for this slice, written at GENERATE before any implementation and
# pinned in docs/cascade/05b-t109-oracle-strength.oracle. EXECUTE builds against it and does not edit it.
# Scratch repos with the real hooks wired: slice `a`, a product file app.py and a script tools/limit.sh changed on
# EXECUTE, an oracle tests/ac/a.sh (strong) or tests/ac/weak.sh (one assertion removed).
#   AC1  a strong oracle kills every mutant: MUTANTS 14/14 killed, exit 0, one MUTANT line per mutant (id, file:line, op).
#   AC2  RED TWIN: an oracle with one assertion removed lets a mutant survive: exit 1, the survivor named with its id.
#   AC3  a survivor is answered only by `| <id> | equivalent <reason> |` in docs/cascade/05b-a-mutants.md.
#   AC4  mutants come only from lines this hop added (not the base, not .md, not docs/); the same tree gives the same
#        bytes; MUTANTS_MAX keeps the lowest ids.
#   AC5  binding: the GENERATE gate needs `run: bash tests/mutants.sh` once the tree ships it; on EXECUTE a survivor
#        keeps the loop from n/n, a strong oracle reaches it.
#   AC6  the operators: comparison, boolean, and/or, not, statement deletion (py) and -gt, &&, ||, deletion (sh); the
#        working tree is unchanged after a run.
#   AC7  edges: nothing to mutate is 0/0 and green; not EXECUTE 05b is n/a; an oracle that fails unmutated is red; a
#        mutant that hangs is killed (timeout); no mutant run starts the mutants again.
#   AC8  USAGE.md B28; release 3.5.11 or later; the fixture run stays under 120 s.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT \
      BDD_MUTANT_RUN MUTANTS_MAX MUTANTS_TIMEOUT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell BDD_LOOP_CACHE=off
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
START=$(date +%s)
HS=docs/cascade/hop-state.md
MAN=docs/cascade/05b-a.oracle
ANS=docs/cascade/05b-a-mutants.md

# the oracle checks, one assertion per line; weak.sh is a.sh without the fee(100) check
CHECKS='assert app.fee(100) == 2
assert app.fee(99) == 1
assert app.allowed(10, 11, False) is False
assert app.allowed(10, 10, False) is True
assert app.allowed(10, 11, True) is True
assert app.allowed(10, 9, False) is True'
oracle_file() {  # oracle_file <path> <checks>
  { printf '#!/usr/bin/env bash\nset -e\ncd "$(dirname "$0")/../.."\npython3 - <<'"'"'PY'"'"'\nimport app\n%s\nPY\n' "$2"
    printf '[[ "$(bash tools/limit.sh 6)" == high ]]\n[[ "$(bash tools/limit.sh 5)" == low ]]\n'; } > "$1"
}

# mk <dir> <oracle: a|weak> [runs…] — GENERATE: base app.py + oracle pinned; then the human's GENERATE→EXECUTE
mk() {
  local d="$1" o="$2"; shift 2; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests/ac"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh oracle.sh critique.sh diverge.sh mutants.sh; do cp "$ROOT/tests/$f" "$d/tests/" 2>/dev/null; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n__pycache__/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\n\n</EDIT>\n' > "$d/$HS"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  echo '# spec' > "$d/docs/cascade/05b-a.md"
  printf 'def fee(amount):\n    return 0\n\n\ndef legacy(x):\n    return x == 1\n' > "$d/app.py"
  printf '# readme\n' > "$d/README.md"
  oracle_file "$d/tests/ac/a.sh" "$CHECKS"
  oracle_file "$d/tests/ac/weak.sh" "$(printf '%s\n' "$CHECKS" | grep -v 'fee(100)')"
  local runs=() r; for r in "$@"; do runs+=(--run "$r"); done
  [[ ${#runs[@]} -gt 0 ]] || runs=(--run "bash tests/ac/$o.sh" --run "bash tests/mutants.sh")
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A \
      && git -c core.hooksPath=/dev/null commit -qm init \
      && bash tests/oracle.sh --write "${runs[@]}" "tests/ac/$o.sh" >/dev/null 2>&1 \
      && git add -A && git -c core.hooksPath=/dev/null commit -qm pin \
      && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: EXECUTE/' "$HS" && rm -f "$HS.bak" \
      && git add -A && git -c core.hooksPath=/dev/null commit -qm exec && git config core.hooksPath .githooks )
}
build() {  # build <dir> — the EXECUTE change: app.py and tools/limit.sh (untracked), a README line and docs/gen.py with an operator
  printf 'def fee(amount):\n    if amount >= 100:\n        return 2\n    return 1\n\n\ndef legacy(x):\n    return x == 1\n\n\ndef allowed(balance, amount, vip):\n    if not vip and amount > balance:\n        return False\n    return True\n' > "$1/app.py"
  mkdir -p "$1/tools"; printf '#!/usr/bin/env bash\n[[ "$1" -gt 5 ]] && echo high || echo low\n' > "$1/tools/limit.sh"
  echo 'a == b' >> "$1/README.md"
  mkdir -p "$1/docs"; printf 'ok = 1 == 1\n' > "$1/docs/gen.py"   # under docs/: never mutated
}
goal() {  # goal <dir> <validator>…
  local d="$1"; shift
  { printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\n'; local v; for v in "$@"; do printf 'VALIDATOR: %s\n' "$v"; done
    printf '```\n'; } > "$d/docs/cascade/goal.md"
}
mut() { (cd "$1" && shift && env "$@" bash tests/mutants.sh 2>&1); }
nlines() { printf '%s\n' "$1" | grep -c "^MUTANT  " || true; }
surv() { printf '%s\n' "$1" | sed -n 's/^FAIL  survivor \([0-9a-f]\{8\}\):.*/\1/p'; }

# ---- AC1 a strong oracle kills every mutant ------------------------------------------------------------------------
D="$TMP/strong"; mk "$D" a; build "$D"
o1="$(mut "$D")"; r1=$?
ok=1
[[ $r1 -eq 0 && "$o1" == *"MUTANTS 14/14 killed"* && "$(nlines "$o1")" == 14 ]] || ok=0
printf '%s\n' "$o1" | grep "^MUTANT  " | grep -qvE '^MUTANT  [0-9a-f]{8}  KILLED +(app\.py|tools/limit\.sh):[0-9]+  [a-z-]+  `' && ok=0
t AC1 "$ok" "a strong oracle kills every mutant: MUTANTS 14/14 killed, exit 0, each MUTANT line has an 8-hex id, KILLED, file:line and the operator"
[[ $ok -eq 1 ]] || printf '%s\n' "$o1" | sed 's/^/      | /' | head -30

# ---- AC2 RED TWIN: one assertion removed lets a mutant survive -----------------------------------------------------
W="$TMP/weak"; mk "$W" weak; build "$W"
o2="$(mut "$W")"; r2=$?
sid="$(surv "$o2")"
ok=1
[[ $r2 -ne 0 && "$(printf '%s\n' "$sid" | grep -c .)" == 1 && "$o2" == *"MUTANTS 13/14 killed"* ]] || ok=0
printf '%s\n' "$o2" | grep -qE "^MUTANT  $sid  SURVIVED +app\.py:3  delete  \`return 2\`" || ok=0
[[ "$o2" == *"| $sid | equivalent <reason> |"* && "$o2" == *"docs/cascade/05b-a-mutants.md"* ]] || ok=0
t AC2 "$ok" "red twin: without the fee(100) assertion, deleting 'return 2' survives — exit 1, MUTANTS 13/14 killed, the survivor named with its id and how to answer it"
[[ $ok -eq 1 ]] || printf '%s\n' "$o2" | sed 's/^/      | /' | head -30

# ---- AC3 answering a survivor --------------------------------------------------------------------------------------
ok=1
printf '| %s | equivalent |\n' "$sid" > "$W/$ANS"
o="$(mut "$W")"; [[ $? -ne 0 ]] || ok=0                                         # no reason: not an answer
printf '| deadbeef | equivalent fee(100) is not specified |\n' > "$W/$ANS"
o="$(mut "$W")"; [[ $? -ne 0 ]] || ok=0                                         # another id: not an answer
printf '| %s | killed by review |\n' "$sid" > "$W/$ANS"
o="$(mut "$W")"; [[ $? -ne 0 ]] || ok=0                                         # not the word equivalent
printf '# mutants\n\n| id | answer |\n|---|---|\n| %s | equivalent fee(100) is not in the spec |\n' "$sid" > "$W/$ANS"
o3="$(mut "$W")"; r3=$?
[[ $r3 -eq 0 && "$o3" == *"MUTANTS 13/14 killed, 1 answered equivalent"* ]] || ok=0
rm -f "$W/$ANS"
t AC3 "$ok" "a survivor is answered only by '| <id> | equivalent <reason> |' in $ANS: an empty reason, another id or another word stay red; the row turns it green and the count says so"

# ---- AC4 only this hop's lines; deterministic; MUTANTS_MAX ---------------------------------------------------------
ok=1
o4="$(mut "$D")"
[[ "$o4" == "$o1" ]] || ok=0                                                     # same tree, same bytes
printf '%s\n' "$o1" | grep -qE '^MUTANT .*(README\.md|docs/|app\.py:5 |app\.py:6 |app\.py:7 |app\.py:8 )' && ok=0   # base lines and .md never
printf '%s\n' "$o1" | grep -q 'legacy\|x == 1' && ok=0
ids="$(printf '%s\n' "$o1" | grep '^MUTANT  ' | awk '{print $2}' | sort | head -5 | tr '\n' ' ')"
o5="$(mut "$D" MUTANTS_MAX=5)"; r5=$?
got="$(printf '%s\n' "$o5" | grep '^MUTANT  ' | awk '{print $2}' | sort | tr '\n' ' ')"
[[ $r5 -eq 0 && "$(nlines "$o5")" == 5 && "$got" == "$ids" && "$o5" == *"MUTANTS 5/5 killed (the 5 lowest ids of 14)"* ]] || ok=0
[[ "$(mut "$D" MUTANTS_MAX=5)" == "$o5" ]] || ok=0
t AC4 "$ok" "mutants come only from lines added since the hop opened (no base line, no .md); the same tree prints the same bytes; MUTANTS_MAX=5 judges the 5 lowest ids, the same on every run"

# ---- AC5 binding: the GENERATE gate and the loop -------------------------------------------------------------------
ok=1
G="$TMP/gen"; mk "$G" a "bash tests/ac/a.sh"
( cd "$G" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' "$HS" && rm -f "$HS.bak" )
og="$(cd "$G" && bash tests/oracle.sh 2>&1)"; rg=$?
[[ $rg -ne 0 && "$og" == *"run: bash tests/mutants.sh"* ]] || ok=0
( cd "$G" && bash tests/oracle.sh --write --run "bash tests/ac/a.sh" --run "bash tests/mutants.sh" tests/ac/a.sh >/dev/null 2>&1 )
og2="$(cd "$G" && bash tests/oracle.sh 2>&1)"; rg2=$?
[[ $rg2 -eq 0 && "$og2" == *"the manifest runs the mutants"* ]] || ok=0
goal "$W" "bash tests/ac/weak.sh" "bash tests/mutants.sh"
ol="$(cd "$W" && bash tests/loop.sh 2>&1)"; rl=$?
[[ $rl -ne 0 && "$ol" == *"FAIL  bash tests/mutants.sh"* && "$ol" != *"LOOP 2/2"* ]] || ok=0
goal "$D" "bash tests/ac/a.sh" "bash tests/mutants.sh"
ol2="$(cd "$D" && bash tests/loop.sh 2>&1)"; rl2=$?
[[ $rl2 -eq 0 && "$ol2" == *"LOOP 2/2"* ]] || ok=0
t AC5 "$ok" "binding: with tests/mutants.sh in the tree the GENERATE gate is red until the manifest runs it; on EXECUTE a survivor keeps the loop from n/n and a strong oracle reaches LOOP 2/2"
[[ $ok -eq 1 ]] || { printf '%s\n' "$og" "$ol" | sed 's/^/      | /' | tail -20; }

# ---- AC6 the operators; the tree is untouched ----------------------------------------------------------------------
ok=1
ops_py="$(printf '%s\n' "$o1" | awk '$4 ~ /^app\.py/ {print $5}' | sort -u | tr '\n' ' ')"
ops_sh="$(printf '%s\n' "$o1" | awk '$4 ~ /^tools/ {print $5}' | sort -u | tr '\n' ' ')"
[[ "$ops_py" == "and-or delete drop-not false-true ge-lt gt-le true-false " ]] || ok=0
[[ "$ops_sh" == "and-or delete gt-le or-and " ]] || ok=0
before="$(cd "$D" && git status --porcelain && shasum app.py tools/limit.sh README.md)"
mut "$D" >/dev/null
after="$(cd "$D" && git status --porcelain && shasum app.py tools/limit.sh README.md)"
[[ "$before" == "$after" ]] || ok=0
t AC6 "$ok" "operators: py ge-lt, gt-le, and-or, drop-not, true/false, delete; sh gt-le, and-or, or-and, delete; the working tree is byte-identical after the run (py: $ops_py| sh: $ops_sh)"

# ---- AC7 edges -----------------------------------------------------------------------------------------------------
ok=1
E="$TMP/docs"; mk "$E" a; echo 'only docs == here' >> "$E/README.md"
o="$(mut "$E")"; [[ $? -eq 0 && "$o" == *"MUTANTS 0/0 killed"*"nothing to mutate"* ]] || ok=0
( cd "$E" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' "$HS" && rm -f "$HS.bak" )
o="$(mut "$E")"; [[ $? -eq 0 && "$o" == *"MUTANTS n/a"* ]] || ok=0
B="$TMP/broken"; mk "$B" a; build "$B"; printf 'def fee(amount):\n    return 5\n' > "$B/app.py"
o="$(mut "$B")"; [[ $? -ne 0 && "$o" == *"fails on the unmutated tree"* ]] || ok=0
H="$TMP/hang"; mk "$H" a "bash tests/ac/a.sh"
printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/../.."\npython3 -c "import app,time\nif app.fee(100) != 2: time.sleep(60)"\nbash tests/ac/a.sh\n' > "$H/tests/ac/slow.sh"
( cd "$H" && git add tests/ac/slow.sh && git -c core.hooksPath=/dev/null commit -qm slow )
python3 - "$H/$MAN" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read().replace("run: bash tests/ac/a.sh", "run: bash tests/ac/slow.sh"); open(p, "w").write(s)
PY
( cd "$H" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' "$HS" && git add -A && git -c core.hooksPath=/dev/null commit -qm regen \
    && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: EXECUTE/' "$HS" && rm -f "$HS.bak" && git add -A && git -c core.hooksPath=/dev/null commit -qm exec2 )
build "$H"
o="$(mut "$H" MUTANTS_TIMEOUT=3)"
printf '%s\n' "$o" | grep -qE '^MUTANT  [0-9a-f]{8}  KILLED \(timeout\) +app\.py:2  ge-lt' || ok=0
o="$(mut "$D" BDD_MUTANT_RUN=1)"; [[ $? -eq 0 && "$o" == *"MUTANTS n/a"*"inside a mutant run"* ]] || ok=0
t AC7 "$ok" "edges: a docs-only build is 0/0 and green; GENERATE is n/a; an oracle that fails unmutated is red; a mutant that hangs is KILLED (timeout); inside a mutant run the mutants do not start again"

# ---- AC8 docs, release, time ---------------------------------------------------------------------------------------
ok=1
grep -q '^### B28\.' "$ROOT/USAGE.md" && sed -n '/^### B28\./,/^### B29\./p' "$ROOT/USAGE.md" | grep -q 'tests/mutants.sh' \
  && sed -n '/^### B28\./,/^### B29\./p' "$ROOT/USAGE.md" | grep -q 'equivalent' || ok=0
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
assert tuple(int(x) for x in v.split(".")) >= (3, 5, 11), v
for f, k in ((".claude-plugin/plugin.json", None), (".codex-plugin/plugin.json", None)):
    assert json.load(open(os.path.join(r, f)))["version"] == v, f
m = json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))
assert all(p["version"] == v for p in m["plugins"]), "marketplace"
assert "## 3.5.11" in open(os.path.join(r, "CHANGELOG.md")).read()
assert "3.5.11" in open(os.path.join(r, "README.md")).read()
PY
el=$(( $(date +%s) - START )); [[ $el -lt 120 ]] || ok=0
t AC8 "$ok" "USAGE.md B28 names tests/mutants.sh and 'equivalent'; VERSION 3.5.11 or later and equal in the three manifests; CHANGELOG.md and README.md show 3.5.11; the run took ${el}s (< 120 s)"

echo
if [[ $fail -eq 0 ]]; then echo "T109 AC all PASS"; else echo "T109 AC FAILED"; exit 1; fi
