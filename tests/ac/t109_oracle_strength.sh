#!/usr/bin/env bash
# AC tests for 05b t109-oracle-strength — THE ORACLE for this slice, written at GENERATE before any implementation and
# pinned in docs/cascade/05b-t109-oracle-strength.oracle. EXECUTE builds against it and does not edit it.
# Scratch repos with the real git hooks wired: slice `a`, a product file app.py and a script tools/limit.sh changed on
# EXECUTE, an ignored input .venv/marker the oracle needs (mutants run in place), an oracle tests/ac/a.sh (strong) or
# tests/ac/weak.sh (one assertion removed). v2, after the critic (C1–C10) and the human's decisions of 2026-11-18.
#   AC1  a strong oracle kills every mutant: MUTANTS 14/14 killed, exit 0, one MUTANT line per mutant (id, file:line, op).
#   AC2  RED TWIN: an oracle with one assertion removed lets a mutant survive: exit 1, the survivor named with its id.
#   AC3  a survivor is answered only by a committed, human-signed `| <id> | equivalent <reason> |` row: an uncommitted
#        row, an agent commit (refused by pre-commit), an empty reason, another id or another word stay red.
#   AC4  only lines this hop added (not the base, not .md, not docs/); the same tree gives the same bytes; ids do not
#        move with line numbers; MUTANTS_MAX counts only when signed and committed (the environment is ignored).
#   AC5  binding: the GENERATE gate needs exactly `run: bash tests/mutants.sh` once the tree ships it (`|| true` and an
#        env prefix are red; a signed `- MUTANTS: off` lifts it); on EXECUTE a survivor keeps the loop from n/n.
#   AC6  the operators (py and sh); in place: the tree is byte-identical after a run, ignored inputs stay, and a run
#        that was killed is put back by the next run.
#   AC7  edges: 0/0 when nothing to mutate; n/a off EXECUTE 05b; signed MUTANTS off and ORACLE off; an oracle red
#        unmutated; a hanging mutant KILLED (timeout); BDD_MUTANT_RUN is exported and stops recursion; a held lock is
#        red; docstrings, heredocs, quotes and comments are never mutated.
#   AC8  USAGE.md B28; release 3.5.11 or later; the fixture run stays under 240 s.
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
ENV=docs/cascade/envelope.md
ANS=docs/cascade/05b-a-mutants.md

# the oracle checks, one assertion per line; weak.sh is a.sh without the fee(100) check
CHECKS='assert app.fee(100) == 2
assert app.fee(99) == 1
assert app.allowed(10, 11, False) is False
assert app.allowed(10, 10, False) is True
assert app.allowed(10, 11, True) is True
assert app.allowed(10, 9, False) is True'
oracle_file() {  # oracle_file <path> <checks> — needs the ignored .venv/marker: a clone without it would fail
  { printf '#!/usr/bin/env bash\nset -e\ncd "$(dirname "$0")/../.."\n[[ -f .venv/marker ]]\n'
    printf 'python3 - <<'"'"'PY'"'"'\nimport app\n%s\nPY\n' "$2"
    printf '[[ "$(bash tools/limit.sh 6)" == high ]]\n[[ "$(bash tools/limit.sh 5)" == low ]]\n'; } > "$1"
}
envelope() {  # envelope <dir> [signed line…] — the <EDIT> block holds the signed lines
  local d="$1"; shift
  { printf '# envelope\n\n## Laws\n\nnone\n\n<EDIT>\n'; local l; for l in "$@"; do printf '%s\n' "$l"; done
    printf '</EDIT>\n'; } > "$d/$ENV"
}
setup_commit() { ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm "${2:-setup}" ); }

# mk <dir> <oracle: a|weak> [runs…] — GENERATE: base app.py + oracle pinned; then the human's GENERATE→EXECUTE
mk() {
  local d="$1" o="$2"; shift 2; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests/ac" "$d/.venv"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh oracle.sh critique.sh diverge.sh mutants.sh; do cp "$ROOT/tests/$f" "$d/tests/" 2>/dev/null; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n__pycache__/\n.venv/\n' > "$d/.gitignore"; echo ok > "$d/.venv/marker"
  envelope "$d" ${SIGNED:+"$SIGNED"}
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
build() {  # build <dir> — the EXECUTE change: app.py, tools/limit.sh (untracked), README.md and docs/gen.py
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
mut() { local d="$1"; shift; (cd "$d" && env "$@" bash tests/mutants.sh 2>&1); }
nlines() { printf '%s\n' "$1" | grep -c "^MUTANT  " || true; }
ids() { printf '%s\n' "$1" | grep '^MUTANT  ' | awk '{print $2}' | sort | tr '\n' ' '; }
surv() { printf '%s\n' "$1" | sed -n 's/^FAIL  survivor \([0-9a-f]\{8\}\):.*/\1/p'; }
gen() { ( cd "$1" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' "$HS" && rm -f "$HS.bak" ); }

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
[[ "$o2" == *"| $sid | equivalent <reason> |"* && "$o2" == *"$ANS"* ]] || ok=0
t AC2 "$ok" "red twin: without the fee(100) assertion, deleting 'return 2' survives — exit 1, MUTANTS 13/14 killed, the survivor named with its id and how to answer it"
[[ $ok -eq 1 ]] || printf '%s\n' "$o2" | sed 's/^/      | /' | head -30

# ---- AC3 a survivor is answered only by a committed, human-signed row ----------------------------------------------
ok=1
row() { printf '# mutants\n\n| id | answer |\n|---|---|\n| %s | %s |\n' "$1" "$2" > "$W/$ANS"; }
row "$sid" "equivalent fee(100) is not in the spec"
o="$(mut "$W")"; [[ $? -ne 0 ]] || { ok=0; echo "      an uncommitted row answered the survivor"; }
( cd "$W" && git add "$ANS" && env -u CASCADE_HUMAN git commit -qm "agent answers" >"$TMP/pc.out" 2>&1 ); rc=$?
[[ $rc -ne 0 ]] || { ok=0; echo "      pre-commit let an agent commit an equivalent row"; }
grep -q "05b-a-mutants.md" "$TMP/pc.out" || { ok=0; echo "      the refusal does not name the file: $(head -2 "$TMP/pc.out")"; }
o="$(mut "$W")"; [[ $? -ne 0 ]] || { ok=0; echo "      a refused row answered the survivor"; }
( cd "$W" && git add "$ANS" && CASCADE_HUMAN=1 git commit -qm "human signs" >/dev/null 2>&1 ) || { ok=0; echo "      the human key did not commit the row"; }
o3="$(mut "$W")"; r3=$?
[[ $r3 -eq 0 && "$o3" == *"MUTANTS 13/14 killed, 1 answered equivalent"* ]] || { ok=0; echo "      the signed row did not answer: $(tail -1 <<<"$o3")"; }
for bad in "equivalent" "killed by review" ; do
  row "$sid" "$bad"; ( cd "$W" && git add "$ANS" && CASCADE_HUMAN=1 git commit -qm "human: $bad" >/dev/null 2>&1 )
  o="$(mut "$W")"; [[ $? -ne 0 ]] || { ok=0; echo "      '| id | $bad |' answered the survivor"; }
done
row deadbeef "equivalent fee(100) is not in the spec"; ( cd "$W" && git add "$ANS" && CASCADE_HUMAN=1 git commit -qm "human: other id" >/dev/null 2>&1 )
o="$(mut "$W")"; [[ $? -ne 0 ]] || { ok=0; echo "      a row for another id answered the survivor"; }
( cd "$W" && git rm -q "$ANS" && CASCADE_HUMAN=1 git commit -qm "human: no rows" >/dev/null 2>&1 )
t AC3 "$ok" "a survivor is answered only by a committed, human-signed '| <id> | equivalent <reason> |' row in $ANS: uncommitted, an agent commit (refused, naming the file), no reason, another word or another id stay red"

# ---- AC4 only this hop's lines; deterministic; stable ids; a signed cap --------------------------------------------
ok=1
[[ "$(mut "$D")" == "$o1" ]] || { ok=0; echo "      the same tree printed different bytes"; }
printf '%s\n' "$o1" | grep -qE '^MUTANT .*(README\.md|docs/|app\.py:5 |app\.py:6 |app\.py:7 |app\.py:8 )' && { ok=0; echo "      a base line, .md or docs/ was mutated"; }
printf '%s\n' "$o1" | grep -q 'legacy\|x == 1' && ok=0
all="$(ids "$o1")"
o="$(mut "$D" MUTANTS_MAX=3)"; [[ "$(nlines "$o")" == 14 ]] || { ok=0; echo "      MUTANTS_MAX in the environment changed the run"; }
envelope "$D" "- MUTANTS_MAX: 5"
o="$(mut "$D")"; [[ "$(nlines "$o")" == 14 ]] || { ok=0; echo "      an uncommitted MUTANTS_MAX counted"; }
setup_commit "$D" "sign MUTANTS_MAX"
o5="$(mut "$D")"; r5=$?
low="$(printf '%s\n' $all | head -5 | tr '\n' ' ')"
[[ $r5 -eq 0 && "$(nlines "$o5")" == 5 && "$(ids "$o5")" == "$low" && "$o5" == *"MUTANTS 5/5 killed (the 5 lowest ids of 14)"* ]] || { ok=0; echo "      the signed cap: $(tail -1 <<<"$o5")"; }
[[ "$(mut "$D")" == "$o5" ]] || ok=0
envelope "$D"; setup_commit "$D" "unsign"
python3 - "$D/app.py" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, "w").write("# header\n\n" + s)
PY
o="$(mut "$D")"; [[ "$(ids "$o")" == "$all" ]] || { ok=0; echo "      ids moved with the line numbers"; }
build "$D"
t AC4 "$ok" "only lines added since the hop opened (no base line, no .md, no docs/); same tree, same bytes; ids do not move with line numbers; MUTANTS_MAX only when signed and committed: the 5 lowest ids"

# ---- AC5 binding: the GENERATE gate and the loop -------------------------------------------------------------------
ok=1
G="$TMP/gen"; mk "$G" a "bash tests/ac/a.sh"; gen "$G"
og="$(cd "$G" && bash tests/oracle.sh 2>&1)"; [[ $? -ne 0 && "$og" == *"run: bash tests/mutants.sh"* ]] || { ok=0; echo "      no mutants line: the gate is not red"; }
for weak in "bash tests/mutants.sh || true" "MUTANTS_MAX=0 bash tests/mutants.sh"; do
  ( cd "$G" && bash tests/oracle.sh --write --run "bash tests/ac/a.sh" --run "$weak" tests/ac/a.sh >/dev/null 2>&1 )
  o="$(cd "$G" && bash tests/oracle.sh 2>&1)"; [[ $? -ne 0 ]] || { ok=0; echo "      '$weak' passed the gate"; }
done
( cd "$G" && bash tests/oracle.sh --write --run "bash tests/ac/a.sh" --run "bash tests/mutants.sh" tests/ac/a.sh >/dev/null 2>&1 )
og2="$(cd "$G" && bash tests/oracle.sh 2>&1)"; [[ $? -eq 0 && "$og2" == *"the manifest runs the mutants"* ]] || { ok=0; echo "      the exact line did not pass"; }
( cd "$G" && bash tests/oracle.sh --write --run "bash tests/ac/a.sh" tests/ac/a.sh >/dev/null 2>&1 )
envelope "$G" "- MUTANTS: off"; setup_commit "$G" "sign MUTANTS off"
o="$(cd "$G" && bash tests/oracle.sh 2>&1)"; [[ $? -eq 0 ]] || { ok=0; echo "      a signed MUTANTS off did not lift the gate"; }
goal "$W" "bash tests/ac/weak.sh" "bash tests/mutants.sh"
ol="$(cd "$W" && bash tests/loop.sh 2>&1)"; rl=$?
[[ $rl -ne 0 && "$ol" == *"FAIL  bash tests/mutants.sh"* && "$ol" != *"LOOP 2/2"* ]] || { ok=0; echo "      a survivor did not stop the loop"; }
goal "$D" "bash tests/ac/a.sh" "bash tests/mutants.sh"
ol2="$(cd "$D" && bash tests/loop.sh 2>&1)"; [[ $? -eq 0 && "$ol2" == *"LOOP 2/2"* ]] || { ok=0; echo "      a strong oracle did not reach LOOP 2/2: $(tail -2 <<<"$ol2")"; }
t AC5 "$ok" "binding: the GENERATE gate needs exactly 'run: bash tests/mutants.sh' ('|| true' and an env prefix are red; signed MUTANTS off lifts it); on EXECUTE a survivor keeps the loop from n/n, a strong oracle reaches LOOP 2/2"

# ---- AC6 the operators; in place: untouched tree, ignored inputs, recovery -----------------------------------------
ok=1
ops_py="$(printf '%s\n' "$o1" | awk '$4 ~ /^app\.py/ {print $5}' | sort -u | tr '\n' ' ')"
ops_sh="$(printf '%s\n' "$o1" | awk '$4 ~ /^tools/ {print $5}' | sort -u | tr '\n' ' ')"
[[ "$ops_py" == "and-or delete drop-not false-true ge-lt gt-le true-false " ]] || { ok=0; echo "      py ops: $ops_py"; }
[[ "$ops_sh" == "and-or delete gt-le or-and " ]] || { ok=0; echo "      sh ops: $ops_sh"; }
snap() { (cd "$1" && git status --porcelain && shasum app.py tools/limit.sh README.md .venv/marker && ls -A "$(git rev-parse --git-dir)"); }
before="$(snap "$D")"; mut "$D" >/dev/null; after="$(snap "$D")"
[[ "$before" == "$after" ]] || { ok=0; echo "      the tree, an ignored input or the git dir changed after the run"; }
gd="$(cd "$D" && git rev-parse --absolute-git-dir)"
mkdir -p "$gd/cascade-mutants-backup"; cp "$D/app.py" "$gd/cascade-mutants-backup/app.py"
sed -i.bak 's/return 2/return 7/' "$D/app.py"; rm -f "$D/app.py.bak"
o="$(mut "$D")"; r=$?
[[ $r -eq 0 && "$o" == *"restored app.py from an interrupted run"* && "$o" == *"MUTANTS 14/14 killed"* ]] || { ok=0; echo "      recovery: $(head -2 <<<"$o")"; }
[[ "$(snap "$D")" == "$before" ]] || { ok=0; echo "      the tree after recovery differs"; }
t AC6 "$ok" "operators: py ge-lt, gt-le, and-or, drop-not, true/false, delete; sh gt-le, and-or, or-and, delete; in place, the tree, .venv/marker and the git dir are the same after a run; a killed run's file is put back by the next run"

# ---- AC7 edges -----------------------------------------------------------------------------------------------------
ok=1
E="$TMP/docs"; mk "$E" a; echo 'only docs == here' >> "$E/README.md"
o="$(mut "$E")"; [[ $? -eq 0 && "$o" == *"MUTANTS 0/0 killed"*"nothing to mutate"* ]] || { ok=0; echo "      docs-only: $o"; }
gen "$E"; o="$(mut "$E")"; [[ $? -eq 0 && "$o" == *"MUTANTS n/a"* ]] || { ok=0; echo "      GENERATE: $o"; }
SIGNED="- MUTANTS: off" mk "$TMP/moff" a; build "$TMP/moff"
o="$(mut "$TMP/moff")"; [[ $? -eq 0 && "$o" == *"MUTANTS off (signed)"* ]] || { ok=0; echo "      MUTANTS off: $o"; }
SIGNED="- ORACLE: off" mk "$TMP/ooff" a; build "$TMP/ooff"
o="$(mut "$TMP/ooff")"; [[ $? -eq 0 && "$o" == *"MUTANTS off"* ]] || { ok=0; echo "      ORACLE off: $o"; }
B="$TMP/broken"; mk "$B" a; build "$B"; printf 'def fee(amount):\n    return 5\n' > "$B/app.py"
o="$(mut "$B")"; [[ $? -ne 0 && "$o" == *"fails on the unmutated tree"* ]] || { ok=0; echo "      broken: $o"; }
H="$TMP/hang"; mk "$H" a "bash tests/ac/slow.sh"
printf '#!/usr/bin/env bash\ncd "$(dirname "$0")/../.."\npython3 -c "import app,time\nif app.fee(100) != 2: time.sleep(60)"\nbash tests/ac/a.sh\n' > "$H/tests/ac/slow.sh"
setup_commit "$H" slow
envelope "$H" "- MUTANTS_TIMEOUT: 3"; setup_commit "$H" "sign timeout"
build "$H"
o="$(mut "$H")"; printf '%s\n' "$o" | grep -qE '^MUTANT  [0-9a-f]{8}  KILLED \(timeout\) +app\.py:2  ge-lt' || { ok=0; echo "      timeout: $(grep ge-lt <<<"$o")"; }
V="$TMP/envchk"; mk "$V" a "bash tests/ac/a.sh" 'test "${BDD_MUTANT_RUN:-}" = 1'; build "$V"
o="$(mut "$V")"; [[ $? -eq 0 && "$o" == *"MUTANTS 14/14 killed"* ]] || { ok=0; echo "      BDD_MUTANT_RUN not exported to the judge: $(tail -1 <<<"$o")"; }
o="$(mut "$D" BDD_MUTANT_RUN=1)"; [[ $? -eq 0 && "$o" == *"MUTANTS n/a"*"inside a mutant run"* ]] || { ok=0; echo "      recursion: $o"; }
gd="$(cd "$D" && git rev-parse --absolute-git-dir)"; sleep 30 & holder=$!
mkdir -p "$gd/cascade-mutants.lock"; echo "$holder" > "$gd/cascade-mutants.lock/pid"
o="$(mut "$D")"; [[ $? -ne 0 && "$o" == *"another mutants run holds"* ]] || { ok=0; echo "      a held lock: $o"; }
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -rf "$gd/cascade-mutants.lock"
Q="$TMP/prose"; mk "$Q" a; build "$Q"
printf '"""Module doc: a == b and c > d\nor True\n"""\n\n\ndef f(x):\n    msg = "a == b"  # c > d\n    return msg\n' > "$Q/doc.py"
printf '#!/usr/bin/env bash\ncat <<'"'"'EOF'"'"'\na && b || c -eq 1\nEOF\n' > "$Q/tools/h.sh"
o="$(mut "$Q")"
got="$(printf '%s\n' "$o" | awk '/^MUTANT  / && $4 ~ /^(doc\.py|tools\/h\.sh)/ {print $4, $5}' | sort | tr '\n' ',')"
[[ "$got" == "doc.py:7 delete,doc.py:8 delete," ]] || { ok=0; echo "      prose: $got"; }
t AC7 "$ok" "edges: docs-only 0/0 green; GENERATE n/a; signed MUTANTS off and ORACLE off; red when the oracle fails unmutated; a hang is KILLED (timeout); BDD_MUTANT_RUN reaches the judge and stops recursion; a held lock is red; docstrings, heredocs, quotes, comments never mutated"

# ---- AC8 docs, release, time ---------------------------------------------------------------------------------------
ok=1
sec="$(sed -n '/^### B28\./,/^### B29\./p' "$ROOT/USAGE.md")"
[[ -n "$sec" && "$sec" == *"tests/mutants.sh"* && "$sec" == *"equivalent"* && "$sec" == *"MUTANTS: off"* ]] || ok=0
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
assert tuple(int(x) for x in v.split(".")) >= (3, 5, 11), v
for f in (".claude-plugin/plugin.json", ".codex-plugin/plugin.json"):
    assert json.load(open(os.path.join(r, f)))["version"] == v, f
m = json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))
assert all(p["version"] == v for p in m["plugins"]), "marketplace"
assert "## 3.5.11" in open(os.path.join(r, "CHANGELOG.md")).read()
assert "3.5.11" in open(os.path.join(r, "README.md")).read()
PY
el=$(( $(date +%s) - START )); [[ $el -lt 240 ]] || ok=0
t AC8 "$ok" "USAGE.md B28 names tests/mutants.sh, 'equivalent' and 'MUTANTS: off'; VERSION 3.5.11 or later and equal in the three manifests; CHANGELOG.md and README.md show 3.5.11; the run took ${el}s (< 240 s)"

echo
if [[ $fail -eq 0 ]]; then echo "T109 AC all PASS"; else echo "T109 AC FAILED"; exit 1; fi
