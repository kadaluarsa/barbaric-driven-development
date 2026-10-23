#!/usr/bin/env bash
# AC tests for 05b t67-envelope-shards: laws may live in docs/cascade/laws/*.md, read with the envelope as one set,
# guarded like the envelope, and a split repo proves exactly what the unsplit one proves. Gradle is the stub
# (tests/ac/fixtures/gradlew-stub.py), so this runs without a JVM.
#   AC1  split vs unsplit: same DSHARP k/n, verdict per id, laws.py --count/--in-force/--unproven, loop's required
#        ids, affected.sh's selection; README.md is not a shard.
#   AC2  a duplicate id (two shards, envelope + shard, envelope alone) is FATAL in laws.py, dsharp, loop, seam,
#        affected and audit. RED TWIN: laws.py without the duplicate check lets dsharp print DSHARP.
#   AC3  the git and agent guards: unsigned shard D# edits, new shards, removals, moves and renames are blocked;
#        signed ones (tests/sign.sh, a new untracked shard and a removal included) land; prose passes.
#        RED TWIN: a pre-commit that does not guard docs/cascade/laws/ lets an unsigned shard edit through.
#   AC4  no shards is the baseline (505ec73) byte for byte, except the two named changes (a duplicate is FATAL;
#        the tests/inv reuse check sees ###-form laws), which are asserted.
#   AC5  every reader: gradle_runner's merge exclusion (HEAD and worktree), the tests/inv reuse check, sign_ok,
#        preserve, CASCADE_ENVELOPE pointing at a temp copy, a missing envelope, audit on a duplicate.
#   AC6  the shard index lint and decision lines in shards.
#   AC7  the read-list: the seam's shard line before and after the spec exists, on EXECUTE; affected.sh --shards.
#   AC8  install.sh ships docs/cascade/laws/README.md only, keeps it and existing shards, --check clean.
#   AC9  E1: 2,000 laws in 20 shards — bytes of what a hop reads, preserve's injected context, laws.py time.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HUMAN DSHARP_CACHE DSHARP_HARNESS DSHARP_JOBS INV_MUTANT STUB_COUNT STUB_AFFECTED_FAIL
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off   # these assertions compare fresh verdicts
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STUB="$ROOT/tests/ac/fixtures/gradlew-stub.py"
BASELINE=505ec73     # the last tree before t67

law_g() { printf '### %s — %s\ncheck:  ./gradlew %s --tests p.%sTest\nbreak:  INV_MUTANT=%s ./gradlew %s --tests p.%sTest --rerun\n\n' "$1" "$2" "$3" "$1" "$1" "$3" "$1"; }
D1="$(law_g D1 'core module' :core:test)"
D2="$(law_g D2 'app module, depends on core' :app:test)"
D3="$(law_g D3 'web module' :web:test)"
D4="$(printf '### D4 — a core file\ncheck:  test -f core/x.txt\nbreak:  test -f core/missing.txt\nreason: REMOVED_GUARD — fixture\npath:   core/x.txt\n\n')"
D5='D5 | a web file, legacy form | test -f web/z.txt | test -f web/missing.txt'
D6="$(printf '### D6 — unproven\ncheck:  true\nbreak:  TODO\n\n')"
D7="$(printf '### D7 — red\ncheck:  false\nbreak:  true\n\n')"
README_LAW="$(printf '### D99 — an example in the README, never a law\ncheck:  true\nbreak:  false\n')"

scenario() {
  cat > "$1/gradle-stub.json" <<'EOF'
{"tasks": {
  ":core:test": {"test": true, "tests": ["p.D1Test#law"], "mutantFails": {"D1": ["p.D1Test#law"]}},
  ":app:test": {"test": true, "tests": ["p.D2Test#law"], "mutantFails": {"D2": ["p.D2Test#law"]}},
  ":web:test": {"test": true, "tests": ["p.D3Test#law"], "mutantFails": {"D3": ["p.D3Test#law"]}}
 },
 "select": {"p.D1Test": ["p.D1Test#law"], "p.D2Test": ["p.D2Test#law"], "p.D3Test": ["p.D3Test#law"]},
 "projects": {":core": {"dir": "core", "deps": []}, ":app": {"dir": "app", "deps": [":core"]},
              ":web": {"dir": "web", "deps": []}}
}
EOF
}
envelope() {  # envelope <laws text> [index rows]
  printf '# envelope\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n\n## Law shards\n\n<EDIT>\n%s\n</EDIT>\n\n## Locked decisions\n\n<EDIT>\n</EDIT>\n' "$1" "${2:-}"
}
shard() {  # SHARD_BARE=1: laws outside <EDIT>, so only the protected-line guard can stop an edit (not the tag scan)
  if [[ "${SHARD_BARE:-0}" == 1 ]]; then printf '# %s laws\n\n%s\n' "$1" "$2"
  else printf '# %s laws\n\n<EDIT>\n%s\n</EDIT>\n' "$1" "$2"; fi
}
INDEX='| laws/app.md | :app |
| laws/core.md | :core |
| laws/web.md | :web |'
mkprod() {  # mkprod <dir> <split|unsplit|none>
  local d="$1" shape="$2"
  mkdir -p "$d/docs/cascade" "$d/tests" "$d/core" "$d/app" "$d/web" "$d/.claude"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in dsharp_strength audit loop affected sign lint; do cp "$ROOT/tests/$f.sh" "$d/tests/"; done
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/.claude/hooks" "$d/.claude/hooks"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '#!/bin/sh\nexec python3 -B "%s" "$@"\n' "$STUB" > "$d/gradlew"; chmod +x "$d/gradlew"
  printf '.cascade/\n.gradle/\n' > "$d/.gitignore"
  echo x > "$d/core/x.txt"; echo y > "$d/app/y.txt"; echo z > "$d/web/z.txt"
  printf 'CURRENT_HOP: NONE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$d/docs/cascade/hop-state.md"
  printf '```\nGOAL_STAGE: 05b\nGOAL_SLICE: x\n```\n' > "$d/docs/cascade/goal.md"
  case "$shape" in
    unsplit) envelope "$(printf '%s\n%s\n%s\n%s\n%s\n\n%s\n%s' "$D1" "$D2" "$D3" "$D4" "$D5" "$D6" "$D7")" > "$d/docs/cascade/envelope.md" ;;
    split|split-mapped)   # split-mapped: no D7, so every in-force law is mapped and t66 selection can narrow
      if [[ "$shape" == split ]]; then envelope "$(printf '%s\n%s' "$D6" "$D7")" "$INDEX" > "$d/docs/cascade/envelope.md"
      else envelope "$D6" "$INDEX" > "$d/docs/cascade/envelope.md"; fi
      mkdir -p "$d/docs/cascade/laws"
      shard core "$(printf '%s\n%s' "$D1" "$D4")" > "$d/docs/cascade/laws/core.md"
      shard app "$D2" > "$d/docs/cascade/laws/app.md"
      if [[ "$shape" == split ]]; then shard web "$(printf '%s\n%s' "$D3" "$D5")" > "$d/docs/cascade/laws/web.md"
      else shard web "$D3" > "$d/docs/cascade/laws/web.md"; fi   # D5 (legacy, no path:) would force the full set
      printf '# Law shards\n\nAn example:\n\n%s\n' "$README_LAW" > "$d/docs/cascade/laws/README.md" ;;
    none) envelope "$(printf '%s\n%s\n%s' "$D4" "$D5" "$D7")" > "$d/docs/cascade/envelope.md" ;;
  esac
  scenario "$d"
  ( cd "$d" && git init -q && git add -A && git -c core.hooksPath=/dev/null commit -qm init )
}
laws_py() { ( cd "$1" && shift && python3 -B tests/lib/laws.py docs/cascade/envelope.md "$@" --shards docs/cascade/laws ); }
by_id() { grep -E '^(GREEN|RED|THEATER|UNPROVEN) ' | awk '{print $2, $1}' | sort; }
dsharp() { ( cd "$1" && bash tests/dsharp_strength.sh 2>&1 ); }
hop() { sed -i.bak -e "s/^CURRENT_HOP: .*/CURRENT_HOP: $2/" "$1/docs/cascade/hop-state.md" && rm -f "$1/docs/cascade/hop-state.md.bak"; }
open_hop() {  # open_hop <dir> <HOP> — a committed hop-open edge, as t66's base needs
  hop "$1" "$2"; ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm "open $2" )
}
omitted() { ( cd "$1" && bash tests/loop.sh --list 2>/dev/null ) | sed -n 's/^OMITTED D#: \(D[0-9]*\).*/\1/p' | sort | tr '\n' ' '; }
seam() {  # seam <dir> -> the additionalContext the prompt hook gives
  ( cd "$1" && printf '{"cwd": "%s", "prompt_id": "p-%s", "session_id": "s", "hook_event_name": "UserPromptSubmit"}' "$1" "$RANDOM$RANDOM" \
      | python3 -B .claude/hooks/seam.py 2>/dev/null ) | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: pass'
}

# ---- AC1  the split proves the same thing ---------------------------------------------------------------------
ok=1
U="$TMP/u"; S="$TMP/s"; mkprod "$U" unsplit; mkprod "$S" split
du="$(dsharp "$U")"; ds="$(dsharp "$S")"
[[ "$(echo "$du" | grep '^DSHARP')" == "$(echo "$ds" | grep '^DSHARP')" ]] || { ok=0; echo "  DSHARP differs: $(echo "$du" | grep '^DSHARP') vs $(echo "$ds" | grep '^DSHARP')"; }
[[ "$(echo "$du" | grep '^DSHARP')" == "DSHARP 5/7" ]] || { ok=0; echo "  the fixture is not 5 GREEN of 7: $(echo "$du" | grep '^DSHARP')"; }
[[ "$(echo "$du" | by_id)" == "$(echo "$ds" | by_id)" ]] || { ok=0; echo "  verdicts by id differ:"; diff <(echo "$du" | by_id) <(echo "$ds" | by_id) | sed 's/^/    /'; }
for m in --count --in-force --unproven; do
  [[ "$(laws_py "$U" $m | sort)" == "$(laws_py "$S" $m | sort)" ]] || { ok=0; echo "  laws.py $m differs split vs unsplit"; }
done
[[ "$(laws_py "$S" --count)" == "7" ]] || { ok=0; echo "  the split count is $(laws_py "$S" --count), want 7 (README.md's D99 must not be read)"; }
open_hop "$U" EXECUTE; open_hop "$S" EXECUTE
echo 'x2' > "$U/core/x.txt"; echo 'x2' > "$S/core/x.txt"
[[ "$(omitted "$U")" == "$(omitted "$S")" && -n "$(omitted "$S")" ]] || { ok=0; echo "  loop requires different ids: unsplit '$(omitted "$U")' split '$(omitted "$S")'"; }
au="$( cd "$U" && bash tests/affected.sh --list | sort )"; as="$( cd "$S" && bash tests/affected.sh --list | sort )"
[[ "$au" == "$as" && "$(echo "$as" | tr '\n' ' ')" == *D4* ]] || { ok=0; echo "  affected.sh selects '$(echo "$au" | tr '\n' ' ')' unsplit, '$(echo "$as" | tr '\n' ' ')' split"; }
t AC1 "$ok" "a split repo gives the same DSHARP k/n, verdict per id, laws.py --count/--in-force/--unproven, loop requirement and affected selection as the unsplit one; README.md is not a shard"

# ---- AC2  a duplicate id is FATAL everywhere ------------------------------------------------------------------
ok=1
dup_case() {  # dup_case <label> <dir>
  local d="$2" out rc
  out="$(laws_py "$d" --declared 2>&1)"; rc=$?
  [[ "$rc" -eq 2 && "$out" == *"FATAL duplicate D"* ]] || { ok=0; echo "  $1: laws.py exit $rc: $out"; }
  [[ "$(laws_py "$d" --declared 2>/dev/null)" == "" ]] || { ok=0; echo "  $1: laws.py printed rows on FATAL"; }
  out="$(dsharp "$d")"; rc=$?
  [[ "$rc" -eq 1 && "$out" == *"FATAL     the laws cannot be read"* && "$out" != *"DSHARP "* ]] || { ok=0; echo "  $1: dsharp exit $rc: $(echo "$out" | head -2)"; }
  out="$( cd "$d" && bash tests/loop.sh 2>&1 )"; rc=$?
  [[ "$rc" -eq 3 && "$out" == *"LOOP REFUSED: the laws cannot be read"* ]] || { ok=0; echo "  $1: loop exit $rc: $(echo "$out" | head -1)"; }
  [[ "$(seam "$d")" == *"LAWS UNREADABLE"* ]] || { ok=0; echo "  $1: the seam did not say LAWS UNREADABLE"; }
  [[ "$( cd "$d" && bash tests/affected.sh )" == "AFFECTED full — the laws cannot be read"* ]] || { ok=0; echo "  $1: affected.sh did not go full"; }
  printf '| D4 | x | path: core/x.txt test: true | IMPLEMENTED |\n' > "$d/docs/cascade/10-audit.md"
  out="$( cd "$d" && bash tests/audit.sh 2>&1 )"; rc=$?
  [[ "$rc" -ne 0 && "$out" == *"DIRTY (laws unreadable"* ]] || { ok=0; echo "  $1: audit exit $rc: $(echo "$out" | tail -1)"; }
}
A="$TMP/a2a"; mkprod "$A" split; shard app2 "$D2" > "$A/docs/cascade/laws/app2.md"; open_hop "$A" EXECUTE; dup_case "two shards" "$A"
grep -q 'app.md' <<<"$(laws_py "$A" --count 2>&1)" && grep -q 'app2.md' <<<"$(laws_py "$A" --count 2>&1)" || { ok=0; echo "  the FATAL does not name both files"; }
B="$TMP/a2b"; mkprod "$B" split; printf '%s\n' "$D1" >> "$B/docs/cascade/envelope.md"; open_hop "$B" EXECUTE; dup_case "envelope and shard" "$B"
C="$TMP/a2c"; mkprod "$C" none; printf '\n<EDIT>\n%s\n</EDIT>\n' "$D4" >> "$C/docs/cascade/envelope.md"; open_hop "$C" EXECUTE; dup_case "the envelope alone" "$C"
# red twin: a laws.py that does not check duplicates
T="$TMP/a2t"; mkprod "$T" split; shard app2 "$D2" > "$T/docs/cascade/laws/app2.md"
python3 - "$T/tests/lib/laws.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '        if d["id"] in seen:\n            raise LawsError('
if old not in s: sys.exit("twin: the duplicate check is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, '        if False:\n            raise LawsError(', 1))
PY
[[ "$(dsharp "$T")" == *"DSHARP "* ]] || { ok=0; echo "  red twin did not go red: without the duplicate check dsharp still refused"; }
t AC2 "$ok" "a duplicate id across shards, envelope and shard, or in the envelope alone is FATAL in laws.py (no rows), dsharp, loop, the seam, affected.sh and audit (red twin: no duplicate check scores DSHARP)"

# ---- AC3  guards ----------------------------------------------------------------------------------------------
ok=1
export SHARD_BARE=1
G="$TMP/a3"; mkprod "$G" split; ( cd "$G" && git config core.hooksPath .githooks )
try() {  # try <label> <want: blocked|lands> — commit what is staged; restore the tree afterwards
  local out rc
  out="$( cd "$G" && git commit -qm "$1" 2>&1 )"; rc=$?
  if [[ "$2" == blocked ]]; then
    [[ "$rc" -ne 0 && "$out" == *BLOCKED* ]] || { ok=0; echo "  $1: committed unsigned (want blocked)"; }
  else
    [[ "$rc" -eq 0 ]] || { ok=0; echo "  $1: blocked (want it to land): $(echo "$out" | grep BLOCKED | head -1)"; }
  fi
  ( cd "$G" && { [[ "$rc" -eq 0 ]] || { git reset -q --hard HEAD; git clean -qfd docs/; }; } )
}
( cd "$G" && sed -i.bak 's/test -f core\/x.txt/true/' docs/cascade/laws/core.md && rm -f docs/cascade/laws/core.md.bak && git add -A ); try "edit a shard check:" blocked
( cd "$G" && shard extra "$(printf '### D20 — new\ncheck:  true\nbreak:  false\n')" > docs/cascade/laws/extra.md && git add -A ); try "add a shard with a law" blocked
( cd "$G" && git rm -q docs/cascade/laws/web.md ); try "remove a shard" blocked
( cd "$G" && git mv docs/cascade/laws/core.md docs/cascade/laws/README2.txt ); try "rename core.md to core.txt-ish" blocked
( cd "$G" && git rm -q docs/cascade/laws/README.md && git mv docs/cascade/laws/core.md docs/cascade/laws/README.md ); try "rename core.md to README.md" blocked
( cd "$G" && python3 - <<'PY'
p = "docs/cascade/envelope.md"; s = open(p).read()
open(p, "w").write(s.replace("### D7 — red\ncheck:  false\nbreak:  true\n", ""))
open("docs/cascade/laws/core.md", "a").write("\n### D7 — red\ncheck:  false\nbreak:  true\n")
PY
  git add -A ); try "move a law from the envelope into a shard" blocked
( cd "$G" && printf '\nA note about these laws.\n' >> docs/cascade/laws/core.md && git add -A ); try "prose-only shard edit" lands
# signed with tests/sign.sh: a modification, a new untracked shard, a removal
( cd "$G" && sed -i.bak 's/test -f core\/x.txt/test -s core\/x.txt/' docs/cascade/laws/core.md && rm -f docs/cascade/laws/core.md.bak && bash tests/sign.sh >/dev/null && git add -A ); try "signed shard edit" lands
( cd "$G" && shard extra "$(printf '### D20 — new\ncheck:  true\nbreak:  false\n')" > docs/cascade/laws/extra.md && bash tests/sign.sh >/dev/null && git add -A ); try "signed new untracked shard" lands
( cd "$G" && rm docs/cascade/laws/extra.md && bash tests/sign.sh >/dev/null && git add -A ); try "signed shard removal" lands
( cd "$G" && git mv docs/cascade/laws/web.md docs/cascade/laws/frontend.md && bash tests/sign.sh >/dev/null && git add -A ); try "signed shard rename (git mv)" lands
# hop_guard: the agent-side guard
hg() {  # hg <json tool call> -> the permission decision
  ( cd "$G" && python3 -B .claude/hooks/hop_guard.py <<<"$1" 2>/dev/null ) | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])
except Exception: print("none")'
}
dec="$(hg "{\"tool_name\": \"Edit\", \"permission_mode\": \"bypassPermissions\", \"cwd\": \"$G\", \"tool_input\": {\"file_path\": \"$G/docs/cascade/laws/core.md\", \"old_string\": \"break:  INV_MUTANT=D1\", \"new_string\": \"break:  true # INV_MUTANT=D1\"}}")"
[[ "$dec" == deny ]] || { ok=0; echo "  hop_guard let an Edit of a shard break: through ($dec)"; }
dec="$(hg "{\"tool_name\": \"Write\", \"permission_mode\": \"bypassPermissions\", \"cwd\": \"$G\", \"tool_input\": {\"file_path\": \"$G/docs/cascade/laws/new.md\", \"content\": \"### D30 — x\\ncheck:  true\\nbreak:  false\\n\"}}")"
[[ "$dec" == deny ]] || { ok=0; echo "  hop_guard let a Write creating a shard with a law through ($dec)"; }
dec="$(hg "{\"tool_name\": \"Write\", \"permission_mode\": \"bypassPermissions\", \"cwd\": \"$G\", \"tool_input\": {\"file_path\": \"$G/docs/cascade/laws/README.md\", \"content\": \"# notes\\n\"}}")"
[[ "$dec" == none ]] || { ok=0; echo "  hop_guard guarded README.md, which is not a shard ($dec)"; }
# red twin: a pre-commit that does not guard docs/cascade/laws/
T="$TMP/a3t"; mkprod "$T" split; ( cd "$T" && git config core.hooksPath .githooks )
python3 - "$T/.githooks/pre-commit" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "done < <(git diff --cached --no-renames --name-only -- 'docs/cascade/laws/*.md' 2>/dev/null || true)"
if old not in s: sys.exit("twin: the shard list is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, "done < /dev/null", 1))
PY
( cd "$T" && sed -i.bak 's/test -f core\/x.txt/true/' docs/cascade/laws/core.md && rm -f docs/cascade/laws/core.md.bak && git add -A )
( cd "$T" && git commit -qm twin >/dev/null 2>&1 ) || { ok=0; echo "  red twin did not go red: without the shard guard the unsigned edit was still blocked"; }
unset SHARD_BARE
t AC3 "$ok" "unsigned shard D# edits, new shards, removals, moves and renames (to README.md too) are blocked; signed ones land (new untracked and removed shards included); prose passes; hop_guard denies shard D# edits (red twin: no shard guard)"

# ---- AC4  no shards is the baseline ---------------------------------------------------------------------------
ok=1
if ! git -C "$ROOT" cat-file -e "$BASELINE^{commit}" 2>/dev/null; then
  ok=0; echo "  the baseline $BASELINE is not in this clone — fetch full history (actions/checkout fetch-depth: 0)"
else
  N="$TMP/a4"; mkprod "$N" none
  P="$TMP/a4base"; mkdir -p "$P/tests"; git -C "$ROOT" archive "$BASELINE" tests/lib tests/dsharp_strength.sh .githooks | tar -x -C "$P"
  for m in --declared --in-force --unproven --protected --count; do
    a="$( cd "$N" && python3 -B "$P/tests/lib/laws.py" docs/cascade/envelope.md $m 2>&1 )"
    b="$( cd "$N" && python3 -B tests/lib/laws.py docs/cascade/envelope.md $m 2>&1 )"
    [[ "$a" == "$b" ]] || { ok=0; echo "  laws.py $m differs from $BASELINE"; }
  done
  a="$(bash "$P/tests/dsharp_strength.sh" --root "$N" 2>&1)"; b="$(dsharp "$N")"
  [[ "$a" == "$b" ]] || { ok=0; echo "  dsharp differs from $BASELINE:"; diff <(echo "$a") <(echo "$b") | sed 's/^/    /' | head; }
  a="$(bash "$P/tests/dsharp_strength.sh" --root "$ROOT" 2>&1)"; b="$(bash "$ROOT/tests/dsharp_strength.sh" --root "$ROOT" 2>&1)"
  [[ "$a" == "$b" ]] || { ok=0; echo "  dsharp on the pack repo differs from $BASELINE"; }
  # named change 1: a duplicate in the envelope alone is DSHARP at the baseline and FATAL now
  printf '\n<EDIT>\n%s\n</EDIT>\n' "$D4" >> "$N/docs/cascade/envelope.md"
  [[ "$(bash "$P/tests/dsharp_strength.sh" --root "$N" 2>&1)" == *"DSHARP "* && "$(dsharp "$N")" == *FATAL* ]] \
    || { ok=0; echo "  the duplicate change is not the named one (baseline DSHARP, now FATAL)"; }
  ( cd "$N" && git checkout -q -- docs/cascade/envelope.md )
  # named change 2: a new tests/inv test reusing a ###-form law's id under another name
  for which in base now; do
    W="$TMP/a4-$which"; mkprod "$W" none
    printf '### D8 — a law naming its own test\ncheck:  bash tests/inv/test_D8.sh\nbreak:  false\n' > "$TMP/d8"
    python3 - "$W/docs/cascade/envelope.md" "$TMP/d8" <<'PY'
import sys
p, add = sys.argv[1], open(sys.argv[2]).read(); s = open(p).read()
open(p, "w").write(s.replace("## Law shards", "<EDIT>\n" + add + "</EDIT>\n\n## Law shards", 1))
PY
    ( cd "$W" && git add -A && git -c core.hooksPath=/dev/null commit -qm d8 )
    [[ "$which" == base ]] && cp "$P/.githooks/pre-commit" "$W/.githooks/pre-commit"
    ( cd "$W" && git config core.hooksPath .githooks && mkdir -p tests/inv && echo 'true' > tests/inv/test_D8_vip.sh && git add -A )
    if ( cd "$W" && git commit -qm reuse >/dev/null 2>&1 ); then eval "reuse_$which=lands"; else eval "reuse_$which=blocked"; fi
  done
  [[ "${reuse_base:-}" == lands && "${reuse_now:-}" == blocked ]] \
    || { ok=0; echo "  the tests/inv change is not the named one: baseline $reuse_base, now $reuse_now (want lands, blocked)"; }
fi
t AC4 "$ok" "with no shards, laws.py (every mode) and dsharp equal $BASELINE byte for byte; the two named changes hold: an envelope duplicate is FATAL, and a tests/inv reuse of a ###-form law is blocked"

# ---- AC5  every reader --------------------------------------------------------------------------------------
ok=1
R="$TMP/a5"; mkprod "$R" split
# gradle_runner's merge exclusion: a shard law's check, at HEAD and in the worktree; None on a duplicate
lc() { ( cd "$R" && python3 -B -c '
import sys; sys.path.insert(0, "tests/lib")
from gradle_runner import law_checks, _envelopes
c = law_checks(_envelopes("."), "docs/cascade/envelope.md", ".")
print("NONE" if c is None else "\n".join(sorted(c)))' ); }
lc | grep -qF './gradlew :core:test --tests p.D1Test' || { ok=0; echo "  the merge exclusion misses the shard law D1"; }
mv "$R/docs/cascade/laws/core.md" "$TMP/core.md.away"
lc | grep -qF './gradlew :core:test --tests p.D1Test' || { ok=0; echo "  the merge exclusion forgot D1 once its shard left the worktree (HEAD still has it)"; }
mv "$TMP/core.md.away" "$R/docs/cascade/laws/core.md"
shard dup "$D2" > "$R/docs/cascade/laws/dup.md"
[[ "$(lc)" == NONE ]] || { ok=0; echo "  a duplicate did not turn the merge exclusion unknown"; }
rm "$R/docs/cascade/laws/dup.md"
# CASCADE_ENVELOPE at a temp copy (a pre-split envelope, as autopilot passes): loop still requires the repo's shard laws,
# and a stray laws/ beside the copy is not read
X="$TMP/xcopy"; mkdir -p "$X/laws"; cp "$R/docs/cascade/envelope.md" "$X/env.md"
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' >> "$X/env.md"
shard stray "$(printf '### D77 — stray\ncheck:  true\nbreak:  false\n')" > "$X/laws/stray.md"
om="$( cd "$R" && CASCADE_ENVELOPE="$X/env.md" bash tests/loop.sh --list 2>/dev/null | sed -n 's/^OMITTED D#: \(D[0-9]*\).*/\1/p' | sort | tr '\n' ' ' )"
[[ "$om" == *D1* && "$om" == *D3* && "$om" != *D77* ]] || { ok=0; echo "  with CASCADE_ENVELOPE at a temp copy loop required '$om' (want the shard laws, not D77)"; }
# a missing envelope: the shard laws are still scored
M="$TMP/a5m"; mkprod "$M" split; rm "$M/docs/cascade/envelope.md"
[[ "$(dsharp "$M" | grep '^DSHARP')" == "DSHARP 5/5" ]] || { ok=0; echo "  with no envelope dsharp gave '$(dsharp "$M" | grep -E '^(DSHARP|FATAL)')' (want the 5 shard laws)"; }
# the tests/inv reuse check sees a legacy-form law in a shard
L="$TMP/a5l"; mkprod "$L" split; ( cd "$L" && git config core.hooksPath .githooks && mkdir -p tests/inv && echo true > tests/inv/test_D5_extra.sh && git add -A )
( cd "$L" && git commit -qm reuse >/dev/null 2>&1 ) && { ok=0; echo "  a tests/inv test reusing shard law D5 (legacy form) was not blocked"; }
# sign_ok re-scores the laws after a signed shard edit
K="$TMP/a5k"; mkprod "$K" split
gd="$( cd "$K" && git rev-parse --git-dir )"; [[ "$gd" == /* ]] || gd="$K/$gd"
( cd "$K" && printf '\nA note.\n' >> docs/cascade/laws/web.md )
echo "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$K/docs/cascade/laws/web.md") docs/cascade/laws/web.md" > "$gd/cascade-sign-pending"
so="$( cd "$K" && printf '{"tool_name": "Edit", "cwd": "%s", "tool_input": {"file_path": "%s/docs/cascade/laws/web.md"}, "tool_use_id": "u1"}' "$K" "$K" \
       | python3 -B .claude/hooks/sign_ok.py 2>&1 )"
[[ "$so" == *"DSHARP 5/7"* ]] || { ok=0; echo "  sign_ok did not re-score after a shard edit: $(echo "$so" | tail -2)"; }
# preserve: envelope laws in full, a shard as one summary line
pv="$( cd "$R" && printf '{"cwd": "%s", "source": "compact", "session_id": "s%s", "hook_event_name": "SessionStart"}' "$R" "$RANDOM" \
       | python3 -B .claude/hooks/preserve.py 2>/dev/null )"
[[ "$pv" == *"D7"* && "$pv" == *"laws/core.md: 2 laws"* && "$pv" != *"test -f core/x.txt"* ]] || { ok=0; echo "  preserve did not summarise the shards: $(echo "$pv" | head -c 300)"; }
shard dup "$D2" > "$R/docs/cascade/laws/dup.md"
pv="$( cd "$R" && printf '{"cwd": "%s", "source": "compact", "session_id": "s%s", "hook_event_name": "SessionStart"}' "$R" "$RANDOM" \
       | python3 -B .claude/hooks/preserve.py 2>/dev/null )"
[[ "$pv" == *"LAWS UNREADABLE"* && "$pv" != *"CASCADE NOT INITIALIZED"* ]] || { ok=0; echo "  preserve on a duplicate did not say LAWS UNREADABLE alone"; }
rm "$R/docs/cascade/laws/dup.md"
t AC5 "$ok" "gradle_runner excludes shard laws' checks from merging (HEAD and worktree; unknown on a duplicate); a temp CASCADE_ENVELOPE keeps the repo's shard laws and ignores a stray laws/; no envelope still scores shards; the tests/inv check sees shard laws; sign_ok re-scores; preserve summarises shards"

# ---- AC6  the index ------------------------------------------------------------------------------------------
ok=1
I="$TMP/a6"; mkprod "$I" split
lint() { ( cd "$I" && bash tests/lint.sh 2>&1 ) || true; }
lo="$(lint)"; grep -q '^SHARDS' <<<"$lo" && { ok=0; echo "  lint flags a correct index: $(grep '^SHARDS' <<<"$lo" | head -1)"; }
shard extra "$(printf '### D20 — unindexed\ncheck:  true\nbreak:  false\n')" > "$I/docs/cascade/laws/extra.md"
lo="$(lint)"; grep -q 'laws/extra.md is not in the envelope' <<<"$lo" || { ok=0; echo "  lint missed an unindexed shard"; }
[[ "$(dsharp "$I" | grep '^GREEN     D20')" != "" ]] || { ok=0; echo "  an unindexed shard's law was not scored"; }
rm "$I/docs/cascade/laws/extra.md"; rm "$I/docs/cascade/laws/app.md"
lo="$(lint)"; grep -q 'names laws/app.md, which does not exist' <<<"$lo" || { ok=0; echo "  lint missed an index row for a missing shard"; }
( cd "$I" && git checkout -q -- docs/cascade/laws/app.md )
printf -- '- DSHARP_GRADLE_HARNESS: on — locked 2026-10-21 — reason: misplaced\n' >> "$I/docs/cascade/laws/web.md"
lo="$(lint)"; grep -q 'web.md:.* holds the locked decision DSHARP_GRADLE_HARNESS' <<<"$lo" || { ok=0; echo "  lint missed a locked decision in a shard"; }
t AC6 "$ok" "lint is clean on a correct index, flags an unindexed shard (whose laws are still scored), an index row for a missing shard, and a locked decision in a shard"

# ---- AC7  the read-list ----------------------------------------------------------------------------------------
ok=1
V="$TMP/a7"; mkprod "$V" split-mapped; hop "$V" GENERATE
ctx="$(seam "$V")"
[[ "$ctx" == *"LAW SHARDS THIS HOP: no spec yet"* && "$ctx" == *"docs/cascade/laws/core.md: 2 laws, D1–D4"* && "$ctx" == *"laws/web.md: 1 law, D3."* ]] \
  || { ok=0; echo "  before the spec the seam did not list every shard: $(echo "$ctx" | grep 'LAW SHARDS')"; }
printf '# spec\n\nTouches docs/cascade/laws/core.md only.\n' > "$V/docs/cascade/05b-x.md"
ctx="$(seam "$V")"
[[ "$(echo "$ctx" | grep 'LAW SHARDS')" == "LAW SHARDS THIS HOP: docs/cascade/laws/core.md (from docs/cascade/05b-x.md)." ]] \
  || { ok=0; echo "  with a spec the seam listed: $(echo "$ctx" | grep 'LAW SHARDS')"; }
open_hop "$V" EXECUTE
[[ "$(seam "$V")" == *"bash tests/affected.sh --shards"* ]] || { ok=0; echo "  on EXECUTE the seam did not point at affected.sh --shards"; }
echo 'x3' > "$V/core/x.txt"
sh_="$( cd "$V" && bash tests/affected.sh --shards | tr '\n' ' ' )"
[[ "$sh_" == "docs/cascade/laws/app.md docs/cascade/laws/core.md " ]] || { ok=0; echo "  affected.sh --shards for a core/x.txt diff gave '$sh_' (want core.md, and app.md: :app depends on :core)"; }
echo 'include x' > "$V/settings.gradle"
sh_="$( cd "$V" && bash tests/affected.sh --shards | grep -v '^#' | tr '\n' ' ' )"
[[ "$sh_" == *app.md* && "$sh_" == *core.md* && "$sh_" == *web.md* && "$sh_" == *envelope.md* ]] || { ok=0; echo "  on the full set affected.sh --shards gave '$sh_'"; }
# no shard directory: the seam's context is the baseline's
if git -C "$ROOT" cat-file -e "$BASELINE^{commit}" 2>/dev/null; then
  W="$TMP/a7n"; mkprod "$W" none; hop "$W" GENERATE
  now_ctx="$(seam "$W")"
  git -C "$ROOT" show "$BASELINE:.claude/hooks/seam.py" > "$W/.claude/hooks/seam.py"
  [[ "$(seam "$W")" == "$now_ctx" ]] || { ok=0; echo "  with no shards the seam's context changed from $BASELINE"; }
fi
t AC7 "$ok" "the seam lists every shard with count and ids before the spec, exactly the spec's shards after, and points EXECUTE at affected.sh --shards, which names the affected laws' shards (every file on full); no shards is the baseline seam"

# ---- AC8  install ---------------------------------------------------------------------------------------------
ok=1
J="$TMP/a8"; mkdir -p "$J"; ( cd "$J" && git init -q )
bash "$ROOT/install.sh" "$J" >"$TMP/i1" 2>&1 || { ok=0; echo "  install.sh failed: $(tail -2 "$TMP/i1")"; }
[[ -f "$J/docs/cascade/laws/README.md" && "$(ls "$J/docs/cascade/laws")" == "README.md" ]] || { ok=0; echo "  install did not ship README.md alone: $(ls "$J/docs/cascade/laws" 2>&1)"; }
echo 'mine' >> "$J/docs/cascade/laws/README.md"; shard core "$D4" > "$J/docs/cascade/laws/core.md"
bash "$ROOT/install.sh" "$J" >"$TMP/i2" 2>&1
grep -q '^mine$' "$J/docs/cascade/laws/README.md" && [[ -f "$J/docs/cascade/laws/core.md" ]] || { ok=0; echo "  a re-install replaced the README or lost a shard"; }
bash "$ROOT/install.sh" --check "$J" >"$TMP/i3" 2>&1 || { ok=0; echo "  install.sh --check is not clean: $(tail -2 "$TMP/i3")"; }
t AC8 "$ok" "install.sh ships docs/cascade/laws/README.md and no shard, keeps an edited README and existing shards on re-install, and --check stays clean"

# ---- AC9  E1, measured ----------------------------------------------------------------------------------------
ok=1
E="$TMP/e1"; mkprod "$E" none
python3 - "$E" <<'PY'
import os, sys
d = sys.argv[1]
law = lambda i: (f"### D{i} — law {i} MUST hold for module m{(i - 1) // 100}\ncheck:  bash tests/inv/test_D{i}.sh\n"
                 f"break:  INV_MUTANT=D{i} bash tests/inv/test_D{i}.sh\nreason: REMOVED_GUARD — the guard of law {i}\n"
                 f"path:   src/m{(i - 1) // 100}/law{i}.py\ntier:   all\n")
head = "# envelope\n\n## Laws\n\n<EDIT>\n"
tail = "</EDIT>\n\n## Law shards\n\n<EDIT>\n{}\n</EDIT>\n"
open(os.path.join(d, "unsplit.md"), "w").write(head + "\n".join(law(i) for i in range(1, 2001)) + tail.format(""))
os.makedirs(os.path.join(d, "split/laws"), exist_ok=True)
open(os.path.join(d, "split/envelope.md"), "w").write(head + tail.format("\n".join(f"| laws/m{k:02d}.md |" for k in range(20))))
for k in range(20):
    open(os.path.join(d, f"split/laws/m{k:02d}.md"), "w").write(
        "<EDIT>\n" + "\n".join(law(i) for i in range(k * 100 + 1, k * 100 + 101)) + "</EDIT>\n")
PY
bu="$(wc -c < "$E/unsplit.md" | tr -d ' ')"; bs="$(( $(wc -c < "$E/split/envelope.md") + $(wc -c < "$E/split/laws/m00.md") ))"
now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
t0="$(now)"; nu="$(python3 -B "$E/tests/lib/laws.py" "$E/unsplit.md" --count --shards "$E/none")"; t1="$(now)"
ns="$(python3 -B "$E/tests/lib/laws.py" "$E/split/envelope.md" --count --shards "$E/split/laws")"; t2="$(now)"
printf '  E1  read by a hop     unsplit %7s bytes (~%6s tokens)   split envelope + one shard %6s bytes (~%5s tokens)\n' "$bu" "$((bu / 4))" "$bs" "$((bs / 4))"
printf '  E1  laws.py --count   unsplit %s laws in %.2fs   split %s laws in %.2fs\n' "$nu" "$(python3 -c "print($t1 - $t0)")" "$ns" "$(python3 -c "print($t2 - $t1)")"
[[ "$nu" == 2000 && "$ns" == 2000 ]] || { ok=0; echo "  counts differ: $nu vs $ns"; }
[[ "$bs" -lt $((bu / 10)) ]] || { ok=0; echo "  a hop still reads $bs of $bu bytes"; }
# preserve's injected context, unsplit vs split
for shape in unsplit split; do
  Q="$TMP/e1-$shape"; mkprod "$Q" none
  if [[ "$shape" == unsplit ]]; then cp "$E/unsplit.md" "$Q/docs/cascade/envelope.md"
  else cp "$E/split/envelope.md" "$Q/docs/cascade/envelope.md"; cp -R "$E/split/laws" "$Q/docs/cascade/laws"; fi
  out="$( cd "$Q" && printf '{"cwd": "%s", "source": "compact", "session_id": "e%s", "hook_event_name": "SessionStart"}' "$Q" "$RANDOM" \
          | python3 -B .claude/hooks/preserve.py 2>/dev/null | wc -c | tr -d ' ' )"
  eval "pv_$shape=$out"
done
printf '  E1  preserve context  unsplit %7s bytes   split %7s bytes\n' "$pv_unsplit" "$pv_split"
[[ "$pv_split" -lt $((pv_unsplit / 5)) ]] || { ok=0; echo "  preserve still injects $pv_split of $pv_unsplit bytes"; }
t AC9 "$ok" "E1: 2,000 laws in 20 shards — same count, a hop reads under a tenth of the bytes, preserve injects under a fifth; numbers above"

exit "$fail"
