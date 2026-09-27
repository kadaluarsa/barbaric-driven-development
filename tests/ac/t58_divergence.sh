#!/usr/bin/env bash
# AC tests for 05b t58-divergence. tests/diverge.sh gates GENERATE 05b of a `[diverge]` brief on N committed
# options (O1 the baseline), each complete and distinct in the ways a script can see, and on a pick made by
# filling the one empty <EDIT>CHOSEN:</EDIT> placeholder that landed with them.
# AC2 is the RED TWIN: each mutant breaks one thing about an otherwise clean fixture and diverge.sh MUST go
# red. Mutants live here, in the fixture builder, never in the gate.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

opt() {  # opt <id> <constraint> <approach> <falsifier>
  printf '### %s — option %s\n\nconstraint: %s\napproach: %s\ngives up: something real\nregret when: the load doubles\nfailure modes: it breaks quietly\nfalsifier: %s\n\n' "$1" "$1" "$2" "$3" "$4"
}

# fixture <dir> <mutant> [tag]  — GENERATE 05b slice fx, options committed with an empty placeholder, then a
# committed pick of O2 and a spec naming it.
fixture() {
  local d="$1" m="${2:-}" tg="${3:-[diverge]}"
  mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"; cp "$ROOT/tests/diverge.sh" "$d/tests/diverge.sh"
  printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: fx\n' > "$d/docs/cascade/hop-state.md"
  printf -- '- other: an untagged brief\n- fx: %s pick a storage design for the ledger\n' "$tg" > "$d/docs/cascade/05b-briefs.md"
  local a2='append-only event log replayed into an in-memory projection at startup'
  local f3='`bash bench/write.sh --rows 1e6` shows p99 over 50ms'
  [[ "$m" == clone ]]   && a2='one sqlite table with a row per account, updated in a transaction'
  [[ "$m" == samefals ]] && f3='`bash bench/restart.sh` takes longer than 2s'
  {
    echo '# Options — 05b fx'; echo; echo '## Options'; echo
    if [[ "$m" == nobaseline ]]; then opt O1 'no database' 'one sqlite table with a row per account, updated in a transaction' '`bash bench/lock.sh` shows writer contention'
    else opt O1 baseline 'one sqlite table with a row per account, updated in a transaction' '`bash bench/lock.sh` shows writer contention'; fi
    if [[ "$m" == samecon ]]; then opt O2 baseline "$a2" '`bash bench/restart.sh` takes longer than 2s'
    elif [[ "$m" == emptyfield ]]; then printf '### O2 — option O2\n\nconstraint: no database\napproach: %s\ngives up:\nregret when: x\nfailure modes: y\nfalsifier: `bash bench/restart.sh` takes longer than 2s\n\n' "$a2"
    else opt O2 'no database' "$a2" '`bash bench/restart.sh` takes longer than 2s'; fi
    if [[ "$m" != short ]]; then
      if [[ "$m" == nofalsifier ]]; then opt O3 'optimise p99 write latency' 'sharded key-value store behind a write-ahead queue, flushed in batches' 'benchmark it'
      else opt O3 'optimise p99 write latency' 'sharded key-value store behind a write-ahead queue, flushed in batches' "$f3"; fi
    fi
    echo '## Ranking'; echo; echo '1. O1 — simplest to verify'; echo '2. O2 — fast reads'; echo '3. O3 — fastest writes'; echo
    echo '## Choice'; echo
    case "$m" in
      prechosen)     echo '<EDIT>CHOSEN: O2 — agent pick</EDIT>' ;;
      noplaceholder) : ;;
      *)             echo '<EDIT>CHOSEN:</EDIT>' ;;
    esac
  } > "$d/docs/cascade/05b-fx-candidates.md"
  ( cd "$d" && git init -q && git add -A && git commit -qm "options, verbatim" )
  local c="$d/docs/cascade/05b-fx-candidates.md"
  case "$m" in
    noplaceholder) printf '<EDIT>CHOSEN: O2 — the human, in chat</EDIT>\n' >> "$c" ;;
    secondblock)   printf '\n<EDIT>CHOSEN: O2 — slipped in beside the empty one</EDIT>\n' >> "$c" ;;
    badchoice)     sed -i.bak 's/<EDIT>CHOSEN:<\/EDIT>/<EDIT>CHOSEN: O9 — no such option<\/EDIT>/' "$c" ;;
    prechosen)     : ;;
    *)             sed -i.bak 's/<EDIT>CHOSEN:<\/EDIT>/<EDIT>CHOSEN: O2 — the human, in chat<\/EDIT>/' "$c" ;;
  esac
  [[ "$m" == rewritten ]] && sed -i.bak 's/fastest writes/fastest writes/; s/sharded key-value store/sharded kv store/' "$c"
  rm -f "$c.bak"
  if [[ "$m" == specmiss ]]; then printf '# fx\n\n## Chosen design\n\nO3, sharded.\n' > "$d/docs/cascade/05b-fx.md"
  else printf '# fx\n\n## Chosen design\n\nO2 — the event log, chosen by the human.\n' > "$d/docs/cascade/05b-fx.md"; fi
  [[ "$m" == missing ]] && ( cd "$d" && git rm -qf docs/cascade/05b-fx-candidates.md )
  [[ "$m" == uncommittedpick ]] || ( cd "$d" && git add -A && git commit -qm "the human's pick, signed" ) >/dev/null 2>&1
  [[ "$m" == uncommittedpick ]] && ( cd "$d" && git add docs/cascade/05b-fx.md && git commit -qm spec ) >/dev/null 2>&1
  return 0
}
score() { ( cd "$1" && bash tests/diverge.sh ) > "$TMP/out" 2>&1; echo $?; }

# AC1 — clean fixture is green; [diverge 4] demands a fourth option.
fixture "$TMP/clean"
rc="$(score "$TMP/clean")"
ok=0; [[ "$rc" -eq 0 ]] && grep -qE '^DIVERGE ([0-9]+)/\1$' "$TMP/out" && ok=1
[[ "$ok" -eq 1 ]] || cat "$TMP/out"
t AC1 "$ok" "clean tagged fixture scores DIVERGE n/n"
fixture "$TMP/four" "" '[diverge 4]'
rc="$(score "$TMP/four")"
ok=0; [[ "$rc" -ne 0 ]] && grep -q 'at least 4 options (found 3)' "$TMP/out" && ok=1
t AC1b "$ok" "[diverge 4] requires four options"

# AC2 — RED TWIN: each mutant must turn it red.
for m in missing short clone samecon samefals nobaseline nofalsifier emptyfield rewritten prechosen \
         noplaceholder secondblock uncommittedpick badchoice specmiss; do
  fixture "$TMP/m-$m" "$m"
  rc="$(score "$TMP/m-$m")"
  ok=0; [[ "$rc" -ne 0 ]] && grep -q '^FAIL' "$TMP/out" && ok=1
  [[ "$ok" -eq 1 ]] || { echo "  mutant $m stayed green:"; sed 's/^/    /' "$TMP/out"; }
  t "AC2:$m" "$ok" "RED TWIN: DIVERGE mutant '$m' makes tests/diverge.sh fail"
done

# Before the pick the red is expected, and says so.
fixture "$TMP/wait" uncommittedpick
( cd "$TMP/wait" && git stash -q ) >/dev/null 2>&1
score "$TMP/wait" >/dev/null
ok=0; grep -q 'waiting on your choice' "$TMP/out" && ok=1
t AC2b "$ok" "before the pick, the score says it is waiting on the human, not broken"

# AC3 — untagged brief and EXECUTE are n/a; the documented tag form is still found by doctor's brief check.
fixture "$TMP/scope"
ok=1
printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: other\n' > "$TMP/scope/docs/cascade/hop-state.md"
rc="$(score "$TMP/scope")"; [[ "$rc" -eq 0 ]] && grep -q '^DIVERGE n/a' "$TMP/out" || { ok=0; echo "  untagged brief not n/a"; cat "$TMP/out"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: fx\n' > "$TMP/scope/docs/cascade/hop-state.md"
rc="$(score "$TMP/scope")"; [[ "$rc" -eq 0 ]] && grep -q '^DIVERGE n/a' "$TMP/out" || { ok=0; echo "  EXECUTE not n/a"; cat "$TMP/out"; }
grep -q "^- fx:" "$TMP/scope/docs/cascade/05b-briefs.md" || { ok=0; echo "  doctor's '^- <slug>:' check cannot see a tagged brief"; }
t AC3 "$ok" "untagged brief and EXECUTE score DIVERGE n/a; '- <slug>: [diverge]' still matches doctor's brief check"

exit "$fail"
