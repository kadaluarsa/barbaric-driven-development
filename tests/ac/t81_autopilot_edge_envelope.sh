#!/usr/bin/env bash
# AC tests for 05b t81-autopilot-edge-envelope: an autopilot edge gets the verdict the human's own loop would print.
# Every edge here is a real commit through the real pre-commit hook in a scratch repo (hooks wired, no key).
#   AC1  split repo: a goal omitting an envelope law — the edge is BLOCKED naming it; with the law, it lands.
#        RED TWIN: an autopilot.py that hands the hop-state copy over as CASCADE_ENVELOPE lets the first edge land.
#   AC2  validators run on the tree: a validator that runs another repo's own loop (on a different slice) passes,
#        split and pre-split. RED TWIN: a loop that does not unset the variables for validators refuses both.
#   AC2b the selector reads the pre-edge hop: a law the diff cannot reach stays `not affected` on the edge.
#        RED TWIN: an affected.py that reads the working-tree hop state refuses the edge (full set).
#   AC3  a refused edge names what failed: a FAIL line, and a LOOP REFUSED line for a goal on another slice.
#   AC4  the time limit: BDD_AUTOPILOT_LOOP_MINUTES=1 refuses a slow loop and kills its whole process group;
#        a garbage value means 60.
#   AC5  a pre-split repo (hop state inside the envelope) behaves as before: lands when n/n, blocked when not.
#   AC6  GENERATE→EXECUTE reads the pre-edge hop: a red critique blocks the edge.
#        RED TWIN: gates run with no variable read the post-edge EXECUTE hop (CRITIQUE n/a) and let it land.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_AUTOPILOT_LOOP_MINUTES
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'pkill -f "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

LAW='### D1 — balance never negative
check:  echo law-d1
break:  false'
mkap() {  # mkap <dir> <split|presplit> [tests/lib dir] [law block] — EXECUTE of entry "a" on list "a, b"
  local d="$1" kind="$2" lib="${3:-$ROOT/tests/lib}" law="${4:-$LAW}"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests" "$d/lib"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$lib" "$d/tests/lib"
  for f in loop.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$d/tests/"; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"; echo a > "$d/lib/a.txt"; echo b > "$d/lib/b.txt"
  echo '# spec' > "$d/docs/cascade/05b-a.md"
  if [[ "$kind" == split ]]; then
    printf '# envelope\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n' "$law" > "$d/docs/cascade/envelope.md"
    printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\nAUTOPILOT: 05b a, 05b b\n</EDIT>\n' > "$d/docs/cascade/hop-state.md"
  else
    printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\nAUTOPILOT: 05b a, 05b b\n</EDIT>\n\n## Laws\n\n<EDIT>\n%s\n</EDIT>\n' "$law" > "$d/docs/cascade/envelope.md"
  fi
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
}
goal() {  # goal <dir> <slice> <validator…> — committed without hooks (the goal is the agent's, not under test)
  local d="$1" s="$2"; shift 2
  { echo '```'; echo 'GOAL_STAGE: 05b'; echo "GOAL_SLICE: $s"; for v in "$@"; do echo "VALIDATOR: $v"; done; echo '```'; } > "$d/docs/cascade/goal.md"
  ( cd "$d" && git add -A && git -c core.hooksPath=/dev/null commit -qm goal )
}
edge() {  # edge <dir> <HOP> <SLICE> [VAR=value…] — the agent commits the hop move; $RC, $ERR; resets when refused
  local d="$1" hop="$2" sl="$3"; shift 3
  local f=docs/cascade/hop-state.md; [[ -f "$d/$f" ]] || f=docs/cascade/envelope.md
  ( cd "$d" && sed -i.bak "s/^CURRENT_HOP:.*/CURRENT_HOP: $hop/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: $sl/" "$f" && rm -f "$f.bak" \
      && git add -A && env "$@" git commit -qm "agent: $hop $sl" </dev/null >/dev/null 2>"$TMP/err" ); RC=$?
  ERR="$(cat "$TMP/err")"
  [[ "$RC" -ne 0 ]] && ( cd "$d" && git reset -q --hard HEAD )
  return 0
}
twinlib() {  # twinlib <name> <file> <old> <new> -> a tests/lib copy with one edit (fails loudly if the anchor moved)
  local t="$TMP/$1"; rm -rf "$t"; cp -R "$ROOT/tests/lib" "$t"
  python3 - "$t/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit("twin: anchor not found in " + p + " — update the red twin with the code: " + old)
open(p, "w").write(s.replace(old, new, 1))
PY
  echo "$t"
}

# ---- AC1  the fail-open is closed --------------------------------------------------------------------------------
ok=1
P="$TMP/p1"; mkap "$P" split; goal "$P" a 'true'
o="$(cd "$P" && bash tests/loop.sh </dev/null 2>&1)"
grep -q 'FAIL  in-force D# omitted from /goal: D1' <<<"$o" || { ok=0; echo "  the fixture's own loop does not FAIL the omitted law (setup)"; }
edge "$P" GENERATE b
[[ "$RC" -ne 0 && "$ERR" == *"D1"* ]] || { ok=0; echo "  a goal omitting an envelope law passed the autopilot edge (rc $RC): $(echo "$ERR" | head -3)"; }
goal "$P" a 'true' 'echo law-d1'; edge "$P" GENERATE b
[[ "$RC" -eq 0 ]] || { ok=0; echo "  with the law in the goal the edge was refused: $(echo "$ERR" | head -3)"; }
TW="$(twinlib twin1 autopilot.py '        return {"CASCADE_HOPSTATE": before}' '        return {"CASCADE_ENVELOPE": before}')"
P="$TMP/p1t"; mkap "$P" split "$TW"; goal "$P" a 'true'; edge "$P" GENERATE b
[[ "$RC" -eq 0 ]] || { ok=0; echo "  red twin did not go red: the old CASCADE_ENVELOPE hand-over still blocked the omitted law"; }
t AC1 "$ok" "split repo: a goal omitting an envelope law is BLOCKED at the autopilot edge, naming D1; with the law it lands (red twin: the hop-state copy as CASCADE_ENVELOPE lets it land)"

# ---- AC2  validators run on the tree --------------------------------------------------------------------------------
ok=1
INNER="$TMP/inner"; mkap "$INNER" split; goal "$INNER" a 'true' 'echo law-d1'
( cd "$INNER" && sed -i.bak 's/^CURRENT_SLICE:.*/CURRENT_SLICE: inner/' docs/cascade/hop-state.md && rm -f docs/cascade/hop-state.md.bak \
    && sed -i.bak 's/^GOAL_SLICE:.*/GOAL_SLICE: inner/' docs/cascade/goal.md && rm -f docs/cascade/goal.md.bak \
    && git add -A && git -c core.hooksPath=/dev/null commit -qm inner )
NESTED="cd $INNER && bash tests/loop.sh"
for kind in split presplit; do
  P="$TMP/p2$kind"; mkap "$P" "$kind"; goal "$P" a 'echo law-d1' "$NESTED"; edge "$P" GENERATE b
  [[ "$RC" -eq 0 ]] || { ok=0; echo "  ($kind) a validator running another repo's own loop failed on the edge: $(echo "$ERR" | head -4)"; }
done
cp "$ROOT/tests/loop.sh" "$TMP/twin2.loop.sh"
python3 - "$TMP/twin2.loop.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); old = "unset CASCADE_ENVELOPE CASCADE_HOPSTATE && "
if old not in s: sys.exit("twin: the validators' unset is not found — update the red twin with the code")
open(p, "w").write(s.replace(old, ""))
PY
for kind in split presplit; do
  P="$TMP/p2t$kind"; mkap "$P" "$kind"; cp "$TMP/twin2.loop.sh" "$P/tests/loop.sh"
  goal "$P" a 'echo law-d1' "$NESTED"; edge "$P" GENERATE b
  [[ "$RC" -ne 0 ]] || { ok=0; echo "  red twin did not go red ($kind): a loop leaking the variables still let the nested loop pass"; }
done
t AC2 "$ok" "a validator that runs another repo's own loop on a different slice passes the edge, split and pre-split (red twin: a loop that leaks the variables to validators refuses both)"

# ---- AC2b  the selector reads the pre-edge hop ----------------------------------------------------------------------
ok=1
PLAW="$LAW
path: lib/a.txt

### D2 — the b file holds
check:  echo law-d2
break:  false
path: lib/b.txt"
P="$TMP/p2b"; mkap "$P" split "$ROOT/tests/lib" "$PLAW"
echo b2 > "$P/lib/b.txt"; goal "$P" a 'true' 'echo law-d2'
o="$(cd "$P" && bash tests/loop.sh </dev/null 2>&1)"
grep -q '^not affected  D1' <<<"$o" && grep -q 'LOOP 2/2' <<<"$o" || { ok=0; echo "  the human's loop does not leave D1 not affected (setup):"; echo "$o" | sed "s/^/      /"; }
edge "$P" GENERATE b
[[ "$RC" -eq 0 ]] || { ok=0; echo "  a law the diff cannot reach was required on the edge: $(echo "$ERR" | head -3)"; }
TW="$(twinlib twin2b affected.py '    now_path = hop_now_path(root, rel)' '    now_path = os.path.join(root, rel)')"
P="$TMP/p2bt"; mkap "$P" split "$TW" "$PLAW"; echo b2 > "$P/lib/b.txt"; goal "$P" a 'true' 'echo law-d2'; edge "$P" GENERATE b
[[ "$RC" -ne 0 ]] || { ok=0; echo "  red twin did not go red: a selector reading the post-edge hop still narrowed"; }
t AC2b "$ok" "a law the hop's diff cannot reach stays not affected on the autopilot edge, as in the human's loop (red twin: the selector reads the post-edge hop and requires it)"

# ---- AC3  refusals name the failure -----------------------------------------------------------------------------------
ok=1
P="$TMP/p3"; mkap "$P" split; goal "$P" a 'echo law-d1' 'false'; edge "$P" GENERATE b
[[ "$RC" -ne 0 && "$ERR" == *"FAIL  false"* ]] || { ok=0; echo "  a failing validator was not named: $(echo "$ERR" | head -3)"; }
goal "$P" other 'echo law-d1'; edge "$P" GENERATE b
[[ "$RC" -ne 0 && "$ERR" == *"LOOP REFUSED"* && "$ERR" == *"is for slice other"* ]] || { ok=0; echo "  a goal for another slice was not named: $(echo "$ERR" | head -3)"; }
t AC3 "$ok" "a refused edge names the failing validator (FAIL false) and a loop refusal (LOOP REFUSED … is for slice other)"

# ---- AC4  the time limit --------------------------------------------------------------------------------------------
ok=1
P="$TMP/p4"; mkap "$P" split; goal "$P" a 'echo law-d1' "sleep 90 && touch $TMP/p4-marker"
s0=$SECONDS; edge "$P" GENERATE b BDD_AUTOPILOT_LOOP_MINUTES=1; took=$((SECONDS - s0))
[[ "$RC" -ne 0 && "$ERR" == *"did not finish in 1 minutes"* && "$took" -lt 85 ]] || { ok=0; echo "  a slow loop was not refused at 1 minute (rc $RC, ${took}s): $(echo "$ERR" | head -2)"; }
sleep 35
[[ ! -e "$TMP/p4-marker" ]] && ! pgrep -f "touch $TMP/p4-marker" >/dev/null || { ok=0; echo "  the timed-out loop's validator kept running"; }
lim="$(cd "$ROOT/tests/lib" && BDD_AUTOPILOT_LOOP_MINUTES=abc python3 -B -c 'import autopilot; print(autopilot.loop_minutes())')"
[[ "$lim" == 60 ]] || { ok=0; echo "  a garbage BDD_AUTOPILOT_LOOP_MINUTES gave $lim, not 60"; }
t AC4 "$ok" "BDD_AUTOPILOT_LOOP_MINUTES=1 refuses a slow loop at the limit, names it, and kills the whole process group; a garbage value means 60"

# ---- AC5  pre-split repos ---------------------------------------------------------------------------------------------
ok=1
P="$TMP/p5"; mkap "$P" presplit; goal "$P" a 'true'; edge "$P" GENERATE b
[[ "$RC" -ne 0 && "$ERR" == *"D1"* ]] || { ok=0; echo "  pre-split: a goal omitting the law passed (rc $RC)"; }
goal "$P" a 'true' 'echo law-d1'; edge "$P" GENERATE b
[[ "$RC" -eq 0 ]] || { ok=0; echo "  pre-split: the n/n edge was refused: $(echo "$ERR" | head -3)"; }
t AC5 "$ok" "a pre-split repo (hop state inside the envelope) blocks the omitted law and lands the n/n edge, as before"

# ---- AC6  GENERATE→EXECUTE reads the pre-edge hop -----------------------------------------------------------------------
ok=1
gen() {  # gen <dir> [lib] — GENERATE of entry "a" with a spec doc and a critique that is red (rows never committed)
  mkap "$1" split "${2:-$ROOT/tests/lib}"
  ( cd "$1" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' docs/cascade/hop-state.md && rm -f docs/cascade/hop-state.md.bak \
      && git add -A && git -c core.hooksPath=/dev/null commit -qm gen )
}
P="$TMP/p6"; gen "$P"; o="$(cd "$P" && bash tests/critique.sh </dev/null 2>&1)"
[[ "$o" == *"CRITIQUE "*"/"* && "$o" != *"n/a"* ]] || { ok=0; echo "  setup: the critique gate is not red on the GENERATE hop: $(echo "$o" | tail -1)"; }
edge "$P" EXECUTE a
[[ "$RC" -ne 0 && "$ERR" == *"critique"* ]] || { ok=0; echo "  a red critique did not block GENERATE→EXECUTE (rc $RC): $(echo "$ERR" | head -2)"; }
TW="$(twinlib twin6 autopilot.py 'clean_env(gate_env(root, before_path))' 'clean_env({})')"
P="$TMP/p6t"; gen "$P" "$TW"; edge "$P" EXECUTE a
[[ "$RC" -eq 0 ]] || { ok=0; echo "  red twin did not go red: gates with no variable still blocked (rc $RC)"; }
t AC6 "$ok" "GENERATE→EXECUTE: a red critique blocks the edge, read on the pre-edge hop (red twin: no variable — CRITIQUE n/a lets it land)"

echo
[[ "$fail" -eq 0 ]] && echo "T81 AC all PASS" || echo "T81 AC FAILED"
exit "$fail"
