#!/usr/bin/env bash
# AC tests for 05b t84-progress-watchdog: a stalled autopilot run ends for a human; a moving one does not; out-of-plan
# paths are named at the accept edge. Scratch git repos run the real tests/loop.sh and the real Stop hook.
#   AC1  stuck (same k, same FAIL set, edits between passes): WATCHDOG line on pass 3; the Stop hook does not continue.
#        RED TWIN: a loop.sh that writes no history → the same stop is continued.
#   AC2  moving (k rises each pass): no WATCHDOG line; continued.
#   AC3  changing failures with edits: OK, continued. RED TWIN: a watchdog that ignores the FAIL set stops it.
#   AC4  no edit, two validators taking turns failing: STALLED "no edit". RED TWIN: no fingerprint rule → OK.
#   AC4b autopilot gate runs (CASCADE_HOPSTATE set) are not recorded.
#   AC4c no hop base (hop-state.md differs from its last commit): passes record `-`, --check is OK.
#   AC5  a new hop (a new hop-state commit) starts fresh.
#   AC6  no signed list, or a `done` list: no WATCHDOG line; Stop hook output equals BDD_WATCHDOG_PASSES=0's.
#   AC7  BDD_WATCHDOG_PASSES: 0 → OFF, 1 → 2, garbage → 3.
#   AC8  drift: the out-of-plan path is named, with and without a signed list; DRIFT in decisions.log; non-paths
#        in the list are ignored. RED TWINS: an exact-only matcher names a prefix-covered path; a drift check
#        skipped under autopilot gives the signed-list stop no notice.
#   AC9  verdicts preserved: exit codes and LOOP lines as expected everywhere, and with an unwritable history.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_WATCHDOG_PASSES BDD_AUTOPILOT_MINUTES \
      PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOOKS="$ROOT/.claude/hooks"

# mk <dir> <list|nolist|done> <validator>... — EXECUTE 05b a, committed (the hop base), plan In scope: lib/a.txt
mk() {
  local d="$1" kind="$2"; shift 2
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests" "$d/lib"
  cp "$ROOT/tests/loop.sh" "$d/tests/"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"; echo a > "$d/lib/a.txt"; echo b > "$d/lib/b.txt"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  local ap=""
  case "$kind" in list) ap="AUTOPILOT: 05b a, 05b b" ;; done) ap="AUTOPILOT: 05b z, 05b a" ;; esac
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\n%s\n</EDIT>\n' "$ap" > "$d/docs/cascade/hop-state.md"
  { printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\n'
    for v in "$@"; do printf 'VALIDATOR: %s\n' "$v"; done
    printf '```\n'; } > "$d/docs/cascade/goal.md"
  printf '# spec\n\n## In scope this execute\n\n- [ ] `lib/a.txt`\n- [ ] `tests/ac/`\n- [ ] `--check` and `bash tests/goal.sh reset`\n\n## Out of scope\n\n- `lib/b.txt`\n' \
    > "$d/docs/cascade/05b-a.md"
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" commit -qm init
}
loop() { (cd "$1" && bash tests/loop.sh 2>&1); }
edit() { echo "$RANDOM$RANDOM" >> "$1/lib/a.txt"; }
n_ev=0
stop() {  # stop <dir> <message> [hooks dir] — the Stop hook's JSON output
  n_ev=$((n_ev + 1))
  python3 - "$1" "$2" "$n_ev" <<'PY' | (cd "$1" && python3 -B "${3:-$HOOKS}/stop_guard.py")
import json, sys
print(json.dumps({"cwd": sys.argv[1], "session_id": "s" + sys.argv[3], "prompt_id": "p" + sys.argv[3],
                  "last_assistant_message": sys.argv[2], "stop_hook_active": False}))
PY
}
continued() { [[ "$1" == *"signed edges remain"* ]]; }
check() { (cd "$1" && python3 -B tests/lib/watchdog.py "$1" --check); }
hist() { [[ -f "$1/.cascade/loop-history" ]] && wc -l < "$1/.cascade/loop-history" | tr -d ' ' || echo 0; }

# ---- AC1 stuck --------------------------------------------------------------------------------------------------
D="$TMP/ac1"; mk "$D" list true false
o1="$(loop "$D")"; r1=$?; edit "$D"; o2="$(loop "$D")"; edit "$D"
c2="$(check "$D")"; c2_1="$(cd "$D" && BDD_WATCHDOG_PASSES=1 python3 -B tests/lib/watchdog.py "$D" --check)"
c2_x="$(cd "$D" && BDD_WATCHDOG_PASSES=abc python3 -B tests/lib/watchdog.py "$D" --check)"
o3="$(loop "$D")"; r3=$?
t AC1a "$([[ "$(hist "$D")" == 3 ]] && echo 1 || echo 0)" "three passes, three history lines"
t AC1b "$([[ "$o3" == *"WATCHDOG: no progress over 3 passes of a: LOOP 1/2, FAIL  false"* && "$o2" != *WATCHDOG* ]] && echo 1 || echo 0)" \
  "pass 3 prints the WATCHDOG line naming LOOP 1/2 and the failing validator; pass 2 does not"
s="$(stop "$D" "BLOCKED: false still fails")"
t AC1c "$( ! continued "$s" && [[ "$s" == *"watchdog"* && "$s" == *"FAIL  false"* ]] && echo 1 || echo 0)" \
  "the Stop hook ends the run and tells the human why"
t AC1d "$(grep -q "WATCHDOG" "$D/.cascade/decisions.log" 2>/dev/null && echo 1 || echo 0)" "decisions.log records WATCHDOG"
t AC9a "$([[ $r1 -eq 1 && $r3 -eq 1 && "$o1" == *"LOOP 1/2"* && "$o3" == *"LOOP 1/2"* ]] && echo 1 || echo 0)" \
  "verdicts unchanged: exit 1, LOOP 1/2"
# twin: a loop that writes no history
D="$TMP/ac1t"; mk "$D" list true false
grep -v -- '--record' "$D/tests/loop.sh" > "$D/tests/loop.t" && mv "$D/tests/loop.t" "$D/tests/loop.sh"
for _ in 1 2 3; do loop "$D" >/dev/null; edit "$D"; done
s="$(stop "$D" "BLOCKED: false still fails")"
t AC1t "$(continued "$s" && echo 1 || echo 0)" "RED TWIN: with no history the stuck run is continued"

# ---- AC7 the knob (on AC1's history) ----------------------------------------------------------------------------
D="$TMP/ac1"
t AC7a "$([[ "$c2" == OK && "$c2_1" == STALLED* && "$c2_x" == OK ]] && echo 1 || echo 0)" \
  "after 2 passes: default OK, PASSES=1 behaves as 2 (STALLED), PASSES=abc behaves as 3 (OK)"
t AC7b "$([[ "$(cd "$D" && BDD_WATCHDOG_PASSES=0 python3 -B tests/lib/watchdog.py "$D" --check)" == OFF ]] && echo 1 || echo 0)" \
  "PASSES=0 is OFF"

# ---- AC2 moving -------------------------------------------------------------------------------------------------
D="$TMP/ac2"; mk "$D" list "test -f s1" "test -f s2" "test -f s3"
o="$(loop "$D")"; touch "$D/s1"; o="$o$(loop "$D")"; touch "$D/s2"; o3="$(loop "$D")"
s="$(stop "$D" "BLOCKED: s3 missing")"
t AC2 "$([[ "$o$o3" != *WATCHDOG* && "$o3" == *"LOOP 2/3"* && "$(check "$D")" == OK ]] && continued "$s" && echo 1 || echo 0)" \
  "k rising 0→1→2: no WATCHDOG line, OK, continued"

# ---- AC3 changing failures --------------------------------------------------------------------------------------
mk3() { mk "$1" list "test -f A" "test -f B"; touch "$1/A"; loop "$1" >/dev/null
        rm "$1/A"; touch "$1/B"; loop "$1" >/dev/null; rm "$1/B"; touch "$1/A"; loop "$1"; }
D="$TMP/ac3"; o="$(mk3 "$D")"
s="$(stop "$D" "BLOCKED: one of A/B")"
t AC3 "$([[ "$o" == *"LOOP 1/2"* && "$o" != *WATCHDOG* && "$(check "$D")" == OK ]] && continued "$s" && echo 1 || echo 0)" \
  "same k but a different FAIL each pass, after edits: OK, continued"
D="$TMP/ac3t"; mkdir -p "$TMP/lib3"; cp -R "$ROOT/tests/lib/." "$TMP/lib3/"
python3 - "$TMP/lib3/watchdog.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace(" and len({p[6] for p in last}) == 1", ""); open(p,"w").write(s)
PY
mk3_twin() { mk "$D" list "test -f A" "test -f B"; rm -rf "$D/tests/lib"; cp -R "$TMP/lib3" "$D/tests/lib"
             touch "$D/A"; loop "$D" >/dev/null; rm "$D/A"; touch "$D/B"; loop "$D" >/dev/null; rm "$D/B"; touch "$D/A"; loop "$D" >/dev/null; }
mk3_twin
t AC3t "$([[ "$(check "$D")" == STALLED* ]] && echo 1 || echo 0)" "RED TWIN: a watchdog ignoring the FAIL set stops a moving run"

# ---- AC4 no edit ------------------------------------------------------------------------------------------------
V1='n=$(cat .cascade/c 2>/dev/null || echo 0); mkdir -p .cascade; echo $((n + 1)) > .cascade/c; [ $((n % 2)) -eq 0 ]'
V2='n=$(cat .cascade/c); [ $((n % 2)) -eq 0 ]'
D="$TMP/ac4"; mk "$D" list "$V1" "$V2"
for _ in 1 2 3; do o="$(loop "$D")"; done
t AC4 "$([[ "$o" == *"LOOP 1/2"* && "$(check "$D")" == "STALLED no edit between the last 3 passes of a"* \
         && "$(cut -f7 "$D/.cascade/loop-history" | sort -u | wc -l | tr -d ' ')" == 2 ]] && echo 1 || echo 0)" \
  "no edit, failures taking turns (two FAIL sets): STALLED no edit"
D="$TMP/ac4t"; mkdir -p "$TMP/lib4"; cp -R "$ROOT/tests/lib/." "$TMP/lib4/"
python3 - "$TMP/lib4/watchdog.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('if len(fps) == 1 and "-" not in fps:', 'if False:'); open(p,"w").write(s)
PY
mk "$D" list "$V1" "$V2"; rm -rf "$D/tests/lib"; cp -R "$TMP/lib4" "$D/tests/lib"
for _ in 1 2 3; do loop "$D" >/dev/null; done
t AC4t "$([[ "$(check "$D")" == OK ]] && echo 1 || echo 0)" "RED TWIN: without the fingerprint rule the no-edit run is OK"

# ---- AC4b gate runs ---------------------------------------------------------------------------------------------
D="$TMP/ac4b"; mk "$D" list true false
loop "$D" >/dev/null; cp "$D/docs/cascade/hop-state.md" "$TMP/hs-before"
for _ in 1 2; do (cd "$D" && CASCADE_HOPSTATE="$TMP/hs-before" bash tests/loop.sh >/dev/null 2>&1); done
t AC4b "$([[ "$(hist "$D")" == 1 && "$(check "$D")" == OK ]] && echo 1 || echo 0)" "autopilot gate runs add no history line"

# ---- AC4c no hop base -------------------------------------------------------------------------------------------
D="$TMP/ac4c"; mk "$D" list true false
sed 's/^CURRENT_SLICE: a$/CURRENT_SLICE: zzz/' "$D/docs/cascade/hop-state.md" > "$TMP/hs-z"
cp "$D/docs/cascade/hop-state.md" "$TMP/hs-a"; cp "$TMP/hs-z" "$D/docs/cascade/hop-state.md"
git -C "$D" commit -qam "other hop"; cp "$TMP/hs-a" "$D/docs/cascade/hop-state.md"
for _ in 1 2 3; do loop "$D" >/dev/null; edit "$D"; done
t AC4c "$([[ "$(cut -f2 "$D/.cascade/loop-history" | sort -u)" == "-" && "$(check "$D")" == OK ]] && echo 1 || echo 0)" \
  "no hop base: passes record '-', --check is OK"

# ---- AC5 a new hop starts fresh ---------------------------------------------------------------------------------
D="$TMP/ac5"; mk "$D" list true false
for _ in 1 2 3; do loop "$D" >/dev/null; edit "$D"; done
before="$(check "$D")"
printf '\n<!-- send-back -->\n' >> "$D/docs/cascade/hop-state.md"; git -C "$D" commit -qam "send back"
o="$(loop "$D")"
t AC5 "$([[ "$before" == STALLED* && "$(check "$D")" == OK && "$o" != *WATCHDOG* ]] && echo 1 || echo 0)" \
  "stalled before a new hop-state commit; OK on the new hop's first pass"

# ---- AC6 human hops unchanged -----------------------------------------------------------------------------------
for kind in nolist done; do
  D="$TMP/ac6-$kind"; mk "$D" "$kind" true false
  for _ in 1 2 3; do o="$(loop "$D")"; edit "$D"; done
  o0="$(cd "$D" && BDD_WATCHDOG_PASSES=0 bash tests/loop.sh 2>&1)"
  strip() { grep -v '^loop: '; }
  s="$(stop "$D" "BLOCKED: false still fails")"; s0="$(BDD_WATCHDOG_PASSES=0 stop "$D" "BLOCKED: false still fails")"
  t "AC6-$kind" "$([[ "$o" != *WATCHDOG* && "$(strip <<< "$o")" == "$(strip <<< "$o0")" && "$s" == "$s0" ]] && echo 1 || echo 0)" \
    "$kind: no WATCHDOG line; loop and Stop hook output equal those with the watchdog off"
done

# ---- AC8 drift --------------------------------------------------------------------------------------------------
mk8() { mk "$1" "$2" true; echo changed >> "$1/lib/a.txt"; echo changed >> "$1/lib/b.txt"
        mkdir -p "$1/tests/ac"; echo 'true' > "$1/tests/ac/x.sh"; loop "$1" >/dev/null; }
ACCEPT="STITCH NEEDED: accept execute for stage 05b, or send back."
D="$TMP/ac8n"; mk8 "$D" nolist; s="$(stop "$D" "$ACCEPT")"
t AC8a "$([[ "$s" == *"scope: 1 changed path(s) the plan does not list: lib/b.txt"* && "$s" != *"tests/ac/x.sh"* ]] && echo 1 || echo 0)" \
  "no list: the notice names lib/b.txt only (lib/a.txt and tests/ac/ are in scope; --check and goal.sh ignored)"
D="$TMP/ac8l"; mk8 "$D" list; s="$(stop "$D" "$ACCEPT")"
t AC8b "$(continued "$s" && [[ "$s" == *"lib/b.txt"* ]] && grep -q "DRIFT.*lib/b.txt" "$D/.cascade/decisions.log" && echo 1 || echo 0)" \
  "signed list: continued, the notice names lib/b.txt, decisions.log has DRIFT"
git -C "$D" checkout -q -- lib/b.txt; (cd "$D" && bash tests/loop.sh >/dev/null 2>&1); s="$(stop "$D" "$ACCEPT")"
t AC8c "$([[ "$s" != *"scope:"* ]] && echo 1 || echo 0)" "nothing out of plan: no notice"
D="$TMP/ac8s"; mk8 "$D" nolist; printf '# spec\n\nno plan list\n' > "$D/docs/cascade/05b-a.md"
(cd "$D" && bash tests/loop.sh >/dev/null 2>&1); s="$(stop "$D" "$ACCEPT")"
t AC8d "$([[ "$s" != *"scope:"* ]] && echo 1 || echo 0)" "no In scope section: no notice"
# twin 1: exact-only matcher
mkdir -p "$TMP/lib8"; cp -R "$ROOT/tests/lib/." "$TMP/lib8/"
python3 - "$TMP/lib8/watchdog.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('if e.endswith("/") and path.startswith(e):', 'if False:'); open(p,"w").write(s)
PY
D="$TMP/ac8t1"; mk8 "$D" nolist; rm -rf "$D/tests/lib"; cp -R "$TMP/lib8" "$D/tests/lib"; (cd "$D" && bash tests/loop.sh >/dev/null 2>&1)
s="$(stop "$D" "$ACCEPT")"
t AC8t1 "$([[ "$s" == *"tests/ac/x.sh"* ]] && echo 1 || echo 0)" "RED TWIN: an exact-only matcher names tests/ac/x.sh"
# twin 2: drift skipped under autopilot (the check placed after the autopilot branch)
cp -R "$HOOKS" "$TMP/hooks8"
python3 - "$TMP/hooks8/stop_guard.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("note = drift_note(root0, said)", 'note = "" if autopilot_status(root0).startswith("next") else drift_note(root0, said)')
open(p,"w").write(s)
PY
D="$TMP/ac8t2"; mk8 "$D" list; s="$(stop "$D" "$ACCEPT" "$TMP/hooks8")"
t AC8t2 "$(continued "$s" && [[ "$s" != *"lib/b.txt"* ]] && echo 1 || echo 0)" \
  "RED TWIN: a drift check after the autopilot branch gives the signed-list stop no notice"

# ---- AC9 an unwritable history never changes the verdict --------------------------------------------------------
D="$TMP/ac9"; mk "$D" list true false; mkdir -p "$D/.cascade/loop-history"
o="$(loop "$D")"; r=$?
mk "$TMP/ac9b" list true; mkdir -p "$TMP/ac9b/.cascade/loop-history"; ob="$(loop "$TMP/ac9b")"; rb=$?
t AC9b "$([[ $r -eq 1 && "$o" == *"LOOP 1/2"* && $rb -eq 0 && "$ob" == *"LOOP 1/1"* && -f "$TMP/ac9b/.cascade/loop-receipt" ]] && echo 1 || echo 0)" \
  "history unwritable: LOOP 1/2 still exits 1; LOOP 1/1 still exits 0 and writes the receipt"

exit "$fail"
