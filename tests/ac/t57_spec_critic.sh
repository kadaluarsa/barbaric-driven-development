#!/usr/bin/env bash
# AC tests for 05b t57-spec-critic. tests/critique.sh gates the GENERATE 05b edge on a committed, answered
# critique and a spec a non-specialist can read (before/after diagrams + a trade-offs table).
# AC2 is the RED TWIN: each CRITIQUE mutant corrupts one thing about an otherwise clean fixture, and
# critique.sh MUST go red for every one — proving each check can fail. Mutants live here, in the fixture
# builder, never in the gate: nothing a caller sets can soften the real check.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# One finding row. $4 is the evidence cell, written as the critic would (a literal pipe escaped as \|).
row() { printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4"; }

# fixture <dir> <mutant>  — a repo on GENERATE 05b slice fx with a spec, a raw critique commit, then answers.
fixture() {
  local d="$1" m="${2:-}"
  mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/critique.sh" "$d/tests/critique.sh"
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: fx\n' > "$d/docs/cascade/hop-state.md"
  # AC6: an older slice's spec with no critique beside it must not be scored.
  printf '# Stage 05b — old — SPEC\n' > "$d/docs/cascade/05b-old.md"
  {
    echo '# Stage 05b — fx — SPEC'; echo
    echo '## Before vs after'; echo
    echo '```mermaid'; echo 'flowchart TD'; echo '  A --> B'; echo '```'; echo
    if [[ "$m" != nodiagram ]]; then echo '```mermaid'; echo 'flowchart TD'; echo '  A --> C --> B'; echo '```'; echo; fi
    echo '## Benefits and trade-offs'; echo
    echo '| | gain | cost |'; echo '|---|---|---|'; echo '| x | a | b |'; echo
    echo '## PLAN'; echo; echo '1. build it'
  } > "$d/docs/cascade/05b-fx.md"
  local ev1='`grep -n x f \| head`' ev2='`docs/cascade/05b-fx.md:3`' n=2
  [[ "$m" == pipes ]]      && ev1='`grep -n x f | head`'
  [[ "$m" == noevidence ]] && ev2=''
  [[ "$m" == vague ]]      && ev2='trust me, it is wrong'
  [[ "$m" == overcap ]]    && n=11
  {
    echo '# Critique — 05b fx'; echo
    echo '## Brief'; echo
    echo '| C# | severity | finding | evidence |'; echo '|---|---|---|---|'
    row C1 medium 'the brief conflicts with nothing, but says X' "$ev1"; echo
    echo '## Spec'; echo
    echo '| C# | severity | finding | evidence |'; echo '|---|---|---|---|'
    row C2 high 'the plan misses Y' "$ev2"
    local i; for ((i = 3; i <= n; i++)); do row "C$i" low "finding $i" UNEVIDENCED; done
  } > "$d/docs/cascade/05b-fx-critique.md"
  ( cd "$d" && git init -q && git add -A && git commit -qm "raw critique" )
  # together: rows and answers land in one commit. uncommitted: the critique never reaches git at all.
  [[ "$m" == together || "$m" == uncommitted ]] && ( cd "$d" && git rm -q --cached docs/cascade/05b-fx-critique.md && git commit -qm untrack )
  {
    echo; echo '## Dispositions'; echo
    echo '| C# | DISPOSITION |'; echo '|---|---|'
    echo '| C1 | rejected the brief is deliberate |'
    if [[ "$m" == undispositioned ]]; then echo '| C2 |  |'; else echo '| C2 | fixed PLAN step 1 |'; fi
    for ((i = 3; i <= n; i++)); do echo "| C$i | human is this in scope? |"; done
  } >> "$d/docs/cascade/05b-fx-critique.md"
  case "$m" in
    rewritten) sed -i.bak 's/the plan misses Y/the plan is fine/' "$d/docs/cascade/05b-fx-critique.md" ;;
    deleted)   sed -i.bak '/| C2 | high |/d' "$d/docs/cascade/05b-fx-critique.md"
               sed -i.bak '/| C2 | fixed/d' "$d/docs/cascade/05b-fx-critique.md" ;;
    missing)   rm "$d/docs/cascade/05b-fx-critique.md" ;;
  esac
  rm -f "$d/docs/cascade/"*.bak
  [[ "$m" == uncommitted ]] || ( cd "$d" && git add -A && git commit -qm answers ) >/dev/null 2>&1
  return 0
}
score() { ( cd "$1" && bash tests/critique.sh ) > "$TMP/out" 2>&1; echo $?; }

# AC1 — a clean fixture is green, and an escaped pipe in evidence parses as one cell.
fixture "$TMP/clean"
rc="$(score "$TMP/clean")"
ok=0; [[ "$rc" -eq 0 ]] && grep -qE '^CRITIQUE ([0-9]+)/\1$' "$TMP/out" && ok=1
[[ "$ok" -eq 1 ]] || cat "$TMP/out"
t AC1 "$ok" "clean fixture scores CRITIQUE n/n (escaped \\| in evidence is one cell; an older slice is ignored — AC6)"

# AC2 — RED TWIN: every mutant must turn it red, each for its own reason.
for m in missing undispositioned rewritten deleted pipes nodiagram overcap noevidence vague together uncommitted; do
  fixture "$TMP/m-$m" "$m"
  rc="$(score "$TMP/m-$m")"
  ok=0; [[ "$rc" -ne 0 ]] && grep -q '^FAIL' "$TMP/out" && ok=1
  [[ "$ok" -eq 1 ]] || { echo "  mutant $m stayed green:"; sed 's/^/    /' "$TMP/out"; }
  t "AC2:$m" "$ok" "RED TWIN: CRITIQUE mutant '$m' makes tests/critique.sh fail"
done

# human rows are surfaced for the edge.
fixture "$TMP/human" overcap
score "$TMP/human" >/dev/null
ok=0; grep -q '^HUMAN   questions for the edge: C3' "$TMP/out" && ok=1
t AC2b "$ok" "human dispositions are listed for the edge"

# AC5 — scope: EXECUTE 05b and GENERATE 06 are n/a and exit 0, even with no critique at all.
fixture "$TMP/scope" missing
ok=1
for hs in 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: fx' 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: fx'; do
  printf "$hs\n" > "$TMP/scope/docs/cascade/hop-state.md"
  rc="$(score "$TMP/scope")"
  [[ "$rc" -eq 0 ]] && grep -q '^CRITIQUE n/a' "$TMP/out" || { ok=0; echo "  not n/a for: $hs"; cat "$TMP/out"; }
done
t AC5 "$ok" "EXECUTE 05b and GENERATE 06 score CRITIQUE n/a and exit 0"

exit "$fail"
