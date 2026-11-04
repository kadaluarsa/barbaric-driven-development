#!/usr/bin/env bash
# AC tests for 05b t91-scorecard-routing — THE ORACLE for this slice, written at GENERATE before any implementation and
# pinned (with tests/ac/data/t91_routes.tsv) in docs/cascade/05b-t91-scorecard-routing.oracle.
# (v2, after the critic: SCORECARD incomplete; loop from the fingerprinted receipt; [bug-fix] is an explicit brief
#  tag and --write records the failing-first run; per-route eval incl. ambiguity; harder labeled rows.)
#   AC1  a passing card, byte-identical whoever runs it.            AC2  failures name the field; --full regression.
#   AC3  unknown → SCORECARD incomplete (exit 2), never pass; a deleted oracle.sh mid-hop still fails.
#        RED TWIN: oracle_field() → "pass".
#   AC4  classifier ≥ 85% overall, every ambiguous row ambiguous. RED TWIN: always feature.
#   AC5  the seam's ROUTE line, hop-aware; nothing on a plain question at NONE.
#   AC6  a [bug-fix] brief's oracle must fail on the unfixed tree (recorded by --write); an untagged brief full of
#        "fails" keeps ORACLE 4/4. RED TWIN: bugfix_oracle_fails() → True.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT BDD_MODEL
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOOKS="$ROOT/.claude/hooks"
HS=docs/cascade/hop-state.md

# mk <dir> <HOP> <brief text> [oracle command] — slice a on 05b; oracle tests/ac/a.sh (exit 0) unless given
mk() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests/ac" "$d/lib"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh oracle.sh switch.sh scorecard.sh regress.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$d/tests/" 2>/dev/null; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"; echo x > "$d/lib/x.txt"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\n</EDIT>\n' > "$d/$HS"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  printf '# briefs\n\n- a: %s\n' "$3" > "$d/docs/cascade/05b-briefs.md"
  printf '# Stage 05b — a — SPEC\n\n# Stage 05b — PLAN\n\n## In scope this execute\n\n- [ ] `lib/x.txt`\n' > "$d/docs/cascade/05b-a.md"
  printf '%s\n' "#!/usr/bin/env bash" "${4:-exit 0}" > "$d/tests/ac/a.sh"
  printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\nVALIDATOR: bash tests/ac/a.sh\n```\n' > "$d/docs/cascade/goal.md"
  printf '# regress\n' > "$d/docs/cascade/regress.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
  [[ "$2" == EXECUTE ]] || return 0
  ( cd "$d" && bash tests/oracle.sh --write --run "bash tests/ac/a.sh" tests/ac/a.sh >/dev/null 2>&1 \
      && git add -A && git -c core.hooksPath=/dev/null commit -qm pin )
  sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: EXECUTE/' "$d/$HS" && rm -f "$d/$HS.bak"
  ( cd "$d" && git add -A && git -c core.hooksPath=/dev/null commit -qm exec )
}
critique() {  # critique <dir> <answered: yes|no>
  { printf '# c\n\n## Brief\n\n| C# | s | f | e |\n|---|---|---|---|\n| C1 | low | x | `y` |\n\n## Spec\n\n| C# | s | f | e |\n|---|---|---|---|\n| C2 | low | x | `y` |\n\n## Dispositions\n\n| C# | D |\n|---|---|\n| C1 | fixed a |\n'
    [[ "$2" == yes ]] && printf '| C2 | fixed b |\n'; } > "$1/docs/cascade/05b-a-critique.md"
  ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm critique )
}
builder() {  # builder <dir> <model> — one recorded Stop by that model (tests/lib/builders.py, t90)
  (cd "$1" && python3 -B tests/lib/builders.py "$1" --record claude "$2" s1 >/dev/null 2>&1)
}
card() { (cd "$1" && bash tests/scorecard.sh "${@:2}" 2>&1); }
field() { grep -E "^$2 " <<< "$1" | head -1; }
green() {  # green <dir> — EXECUTE hop with a green oracle, a LOOP 1/1 pass, an answered critique, one builder
  mk "$1" EXECUTE "the export button is missing; add it" ; critique "$1" yes; builder "$1" model-a
  (cd "$1" && bash tests/loop.sh >/dev/null 2>&1)
}

# ---- AC1 a passing card, identical for anyone -------------------------------------------------------------------
D="$TMP/ac1"; green "$D"
c1="$(card "$D")"; r1=$?
c2="$(cd / && BDD_HOOK_HOST=codex BDD_MODEL=other bash "$D/tests/scorecard.sh" 2>&1)"
t AC1 "$([[ $r1 -eq 0 && "$c1" == *"SCORECARD pass"* && "$(field "$c1" oracle)" == *pass* && "$(field "$c1" loop)" == *"pass (LOOP 1/1)"* \
         && "$(field "$c1" review)" == *pass* && "$(field "$c1" builders)" == *"claude/model-a"* && "$c1" == "$c2" ]] && echo 1 || echo 0)" \
  "a green hop: SCORECARD pass; oracle, loop (LOOP 1/1), review pass; builders named; byte-identical from another dir, host and model"

# ---- AC2 failures name the field --------------------------------------------------------------------------------
D="$TMP/ac2a"; green "$D"; echo '# weakened' >> "$D/tests/ac/a.sh"
c="$(card "$D")"; r=$?
t AC2a "$([[ $r -eq 1 && "$(field "$c" oracle)" == "oracle      fail"* && "$c" == *"SCORECARD fail"* ]] && echo 1 || echo 0)" "an edited oracle: oracle fail, SCORECARD fail"
D="$TMP/ac2b"; mk "$D" EXECUTE "x; add it"; critique "$D" no; builder "$D" model-a; (cd "$D" && bash tests/loop.sh >/dev/null 2>&1)
c="$(card "$D")"; r=$?
t AC2b "$([[ $r -eq 1 && "$(field "$c" review)" == "review      fail unanswered critique: C2"* ]] && echo 1 || echo 0)" "an unanswered critique row: review fail, naming it"
D="$TMP/ac2c"; green "$D"; builder "$D" model-b
c="$(card "$D")"; r=$?
t AC2c "$([[ $r -eq 1 && "$(field "$c" review)" == "review      fail switch"* ]] && echo 1 || echo 0)" "two builders without a switch review: review fail switch"
D="$TMP/ac2d"; mk "$D" EXECUTE "x; add it"; critique "$D" yes; builder "$D" model-a
printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\nVALIDATOR: bash tests/ac/a.sh\nVALIDATOR: false\n```\n' > "$D/docs/cascade/goal.md"
(cd "$D" && bash tests/loop.sh >/dev/null 2>&1); c="$(card "$D")"; r=$?
t AC2d "$([[ $r -eq 1 && "$(field "$c" loop)" == "loop        fail (LOOP 1/2)"* ]] && echo 1 || echo 0)" "a last pass at LOOP 1/2: loop fail"
D="$TMP/ac2f"; green "$D"; echo changed >> "$D/lib/x.txt"
c="$(card "$D")"; r=$?
t AC2f "$([[ $r -eq 1 && "$(field "$c" loop)" == "loop        fail (tree changed since the last n/n pass)"* ]] && echo 1 || echo 0)" \
  "an edit after the n/n pass: loop fail — the receipt's fingerprint no longer matches the tree (C4)"
D="$TMP/ac2e"; green "$D"; printf '# regress\n\n### old\nREGRESS: false\n' > "$D/docs/cascade/regress.md"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm reg )
cf="$(card "$D" --full)"; rf=$?; cn="$(card "$D")"
t AC2e "$([[ $rf -eq 1 && "$(field "$cf" regression)" == "regression  fail"* && "$(field "$cn" regression)" == "regression  not run (--full)"* ]] && echo 1 || echo 0)" \
  "--full runs the regression suite (a red REGRESS line fails it); without --full: not run"

# ---- AC3 unknown, never pass ------------------------------------------------------------------------------------
D="$TMP/ac3"; mk "$D" GENERATE "x; add it"; rm "$D/tests/oracle.sh"
sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: EXECUTE/' "$D/$HS" && rm -f "$D/$HS.bak"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm exec )
c="$(card "$D")"
r=0; (cd "$D" && bash tests/scorecard.sh >/dev/null 2>&1) || r=$?
t AC3 "$([[ "$(field "$c" oracle)" == "oracle      unknown"* && "$(field "$c" loop)" == "loop        unknown"* && "$(field "$c" builders)" == "builders    unknown"* \
         && "$c" == *"SCORECARD incomplete"* && "$c" != *"SCORECARD pass"* && $r -eq 2 ]] && echo 1 || echo 0)" \
  "no oracle (not due), no loop pass, no builder log: unknown fields, SCORECARD incomplete, exit 2 — never pass (C3)"
D="$TMP/ac3b"; green "$D"; rm "$D/tests/oracle.sh"; ( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm "drop oracle.sh" )
c="$(card "$D")"; r=$?
t AC3b "$([[ $r -eq 1 && "$(field "$c" oracle)" == "oracle      fail"* ]] && echo 1 || echo 0)" "tests/oracle.sh deleted mid-hop: the oracle is still due — oracle fail, not unknown (C10)"
D="$TMP/ac3t"; green "$D"; echo '# weakened' >> "$D/tests/ac/a.sh"
python3 - "$D/tests/lib/scorecard.py" <<'PY'
import re, sys; p=sys.argv[1]; s=open(p).read()
m = re.search(r"def oracle_field\(root: str\) -> str:\n", s)
assert m, "twin anchor: oracle_field(root) -> str"
open(p, "w").write(s[:m.end()] + '    return "pass"\n' + s[m.end():])
PY
c="$(card "$D")"
t AC3t "$([[ "$(field "$c" oracle)" == "oracle      pass"* ]] && echo 1 || echo 0)" "RED TWIN: an oracle_field() that does not read the tree passes an edited oracle"

# ---- AC4 the classifier -----------------------------------------------------------------------------------------
o="$(python3 -B "$ROOT/tests/lib/route.py" --eval "$ROOT/tests/ac/data/t91_routes.tsv" 2>&1)"; r=$?
amb="$(grep -E '^ambiguous [0-9]+/[0-9]+$' <<< "$o")"; ak="${amb#ambiguous }"
t AC4 "$([[ $r -eq 0 && "$o" == *"ROUTE EVAL"* && -n "$amb" && "${ak%/*}" == "${ak#*/}" ]] && echo 1 || echo 0)" \
  "the frozen labeled set scores ≥ 85% ($(tail -1 <<< "$o")), and every ambiguous row is reported ambiguous ($amb) (C7, C8)"
mkdir -p "$TMP/lib4"; cp -R "$ROOT/tests/lib/." "$TMP/lib4/"
python3 - "$TMP/lib4/route.py" <<'PY'
import re, sys; p=sys.argv[1]; s=open(p).read()
m = re.search(r"def classify\(prompt: str\) -> tuple\[str, list\[str\]\]:\n", s)
assert m, "twin anchor: classify(prompt) -> tuple[str, list[str]]"
open(p, "w").write(s[:m.end()] + '    return "feature", []\n' + s[m.end():])
PY
python3 -B "$TMP/lib4/route.py" --eval "$ROOT/tests/ac/data/t91_routes.tsv" >/dev/null 2>&1; r=$?
t AC4t "$([[ $r -ne 0 ]] && echo 1 || echo 0)" "RED TWIN: a classifier that always says feature fails the bar"

# ---- AC5 the ROUTE line -----------------------------------------------------------------------------------------
seam() { printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps({"cwd": sys.argv[1], "prompt": sys.stdin.read(), "session_id": "s"}))' "$1" \
         | (cd "$1" && python3 -B "$HOOKS/seam.py"); }
D="$TMP/ac5e"; green "$D"; s1="$(seam "$D" "the export button crashes on empty input, fix it")"
D="$TMP/ac5g"; mk "$D" GENERATE "x; add it"; s2="$(seam "$D" "the login fails for uppercase emails, fix it")"
D="$TMP/ac5n"; mk "$D" GENERATE "x"; sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: NONE/' "$D/$HS" && rm -f "$D/$HS.bak"
s3="$(seam "$D" "how does the loop work?")"; s4="$(seam "$D" "add a dark mode toggle")"
t AC5 "$([[ "$s1" == *"ROUTE bug-fix"* && "$s1" == *"STEPS"* && "$s2" == *"frozen oracle"* && "$s3" != *"ROUTE"* && "$s4" == *"ROUTE feature"* ]] && echo 1 || echo 0)" \
  "EXECUTE bug-fix → ROUTE + STEPS; GENERATE bug-fix → the frozen-oracle hint; NONE question → no ROUTE; NONE change → ROUTE feature"

# ---- AC6 the bug-fix oracle rule (an explicit [bug-fix] brief tag, recorded by --write) --------------------------
pin() { (cd "$1" && bash tests/oracle.sh --write --run "bash tests/ac/a.sh" tests/ac/a.sh >/dev/null 2>&1); }
D="$TMP/ac6a"; mk "$D" GENERATE "[bug-fix] the login form crashes on an empty email" "exit 0"; pin "$D"
o1="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r1=$?; m1="$(grep -c '^# fails-before-fix: no$' "$D/docs/cascade/05b-a.oracle")"
D="$TMP/ac6b"; mk "$D" GENERATE "[bug-fix] the login form crashes on an empty email" "exit 1"; pin "$D"
o2="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r2=$?; m2="$(grep -c '^# fails-before-fix: yes$' "$D/docs/cascade/05b-a.oracle")"
D="$TMP/ac6c"; mk "$D" GENERATE "the old check fails and red twins must fail; fix the regression wording" "exit 0"; pin "$D"
o3="$(cd "$D" && bash tests/oracle.sh 2>&1)"; r3=$?
t AC6 "$([[ $r1 -ne 0 && "$o1" == *"must fail on the unfixed tree"* && $m1 == 1 && $r2 -eq 0 && $m2 == 1 && $r3 -eq 0 && "$o3" == *"ORACLE 4/4"* ]] && echo 1 || echo 0)" \
  "[bug-fix] brief: --write records whether the oracle fails now; a passing one is red, a failing one green; an untagged brief full of 'fails' keeps ORACLE 4/4 (C1)"
D="$TMP/ac6t"; mk "$D" GENERATE "[bug-fix] the login form crashes on an empty email" "exit 0"
python3 - "$D/tests/lib/oracle.py" <<'PY'
import re, sys; p=sys.argv[1]; s=open(p).read()
m = re.search(r"def bugfix_oracle_fails\(root: str, runs: list\[str\]\) -> bool:\n", s)
assert m, "twin anchor: bugfix_oracle_fails(root, runs) -> bool"
open(p, "w").write(s[:m.end()] + "    return True\n" + s[m.end():])
PY
pin "$D"; (cd "$D" && bash tests/oracle.sh >/dev/null 2>&1); r=$?
t AC6t "$([[ $r -eq 0 ]] && echo 1 || echo 0)" "RED TWIN: bugfix_oracle_fails() returning True passes a bug-fix oracle that tests nothing"

exit "$fail"
