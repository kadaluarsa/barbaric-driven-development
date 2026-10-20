#!/usr/bin/env bash
# AC tests for 05b t63-quiet-stop-guard. The Stop hook talks to the agent in `additionalContext` and to the human
# in `systemMessage`, always exits 0 and never writes stderr (Claude Code shows both exit 2 and `decision: block`
# to the human as a "Stop hook error"). It ignores edge strings quoted in code and caps identical nudges.
# Verdicts must not change except where the spec names it (I18).
#   AC1   the five agent nudges arrive on the quiet channel with the pre-t63 text, byte for byte (I1 excepted).
#         RED TWIN: the pre-t63 hook (tests/ac/fixtures/t63-pre) is not read as a nudge.
#   AC2   budget, continuation cap and punch cap reach the human in systemMessage.
#         RED TWIN: the pre-t63 hook leaves systemMessage empty on the same stops.
#   AC3   an edge quoted in code is not an edge; plain-text edges still are, mid-line too.
#         RED TWIN: unquoted() as the identity makes a code-quoted edge continue autopilot.
#   AC4   identical nudges: nudge, nudge, then warn + NUDGECAP; a clean stop, a different text and a human
#         prompt (seam.py) each start the count over. RED TWIN: without the counter the third stop nudges.
#   AC4b  a second stop with the same prompt_id is not judged. RED TWIN: without the marker it nudges again.
#   AC5   no stop_guard assertion in the tests is read by exit code. RED TWIN: the lint flags a planted one.
#   AC6   the I1 text and the conductor no longer say to reprint the invariants at an edge.
#   AC7   an exception inside the hook exits 0 silently and logs CRASH. RED TWIN: unwrapped, it shows a traceback.
#   AC8   every nudge writes its line to .cascade/decisions.log.
# AC9 (the live session shows no "Stop hook error") is the human's, at the accept edge.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset BDD_AUTOPILOT_MINUTES CASCADE_HUMAN
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

NEW="$ROOT/.claude/hooks"
OLD="$ROOT/tests/ac/fixtures/t63-pre"      # the hook as it was before t63, verbatim: the red twin's source

# sgv <hooks dir> <out prefix>  (event on stdin) -> nudge | warn | nudge+warn | pass | broken
# <prefix>.agent / .human hold the texts; .err the stderr. A non-zero exit or any stderr is `broken`.
sgv() {
  # shellcheck disable=SC2086  # SGV_ENV is a list of VAR=value words
  env ${SGV_ENV:-} python3 -B "$1/stop_guard.py" >"$2.out" 2>"$2.err"; local rc=$?   # lint63-ok
  python3 -B - "$2" "$rc" <<'PY'
import json, sys
pre, rc = sys.argv[1], sys.argv[2]
raw = open(pre + ".out", encoding="utf-8").read().strip()
agent = human = ""
ok = True
try:
    d = json.loads(raw) if raw else {}
    if not isinstance(d, dict):
        ok = False
    else:
        hs = d.get("hookSpecificOutput") or {}
        if d and hs and hs.get("hookEventName") != "Stop":
            ok = False
        agent = hs.get("additionalContext", "")
        human = d.get("systemMessage", "")
except ValueError:
    ok = False
open(pre + ".agent", "w", encoding="utf-8").write(agent)
open(pre + ".human", "w", encoding="utf-8").write(human)
if rc != "0" or open(pre + ".err", encoding="utf-8").read().strip() or not ok:
    print("broken")
else:
    print("nudge+warn" if agent and human else "nudge" if agent else "warn" if human else "pass")
PY
}
ev() {  # ev <dir> <session> <prompt_id|""> <stop_hook_active> <message>  -> the Stop event JSON
  python3 -c 'import json,sys; d,s,p,a,m=sys.argv[1:6]; e={"cwd":d,"session_id":s,"stop_hook_active":a=="true","last_assistant_message":m,"hook_event_name":"Stop"}
if p: e["prompt_id"]=p
print(json.dumps(e))' "$@"
}
fixture() {  # fixture <dir> <hop-state body>  -> a git repo with the pack's tests/ and that hop state
  local d="$1"
  mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  cp "$ROOT/tests/loop.sh" "$ROOT/tests/audit.sh" "$ROOT/tests/critique.sh" "$ROOT/tests/diverge.sh" "$d/tests/" 2>/dev/null
  printf '%b' "$2" > "$d/docs/cascade/hop-state.md"
  printf '# envelope\n' > "$d/docs/cascade/envelope.md"
  ( cd "$d" && git init -q && git add -A && git commit -qm init )
}
twin() {  # twin <name> <python replace: old> <new>  -> a copy of the new hooks with one line changed
  local d="$TMP/twin-$1"; rm -rf "$d"; cp -R "$NEW" "$d"
  python3 - "$d/stop_guard.py" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit("twin: the line was not found — update the red twin with the code")
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  echo "$d"
}
logged() { grep -c "stop_guard  $2" "$1/.cascade/decisions.log" 2>/dev/null | tr -d ' '; }

MSG_ACCEPT='STITCH NEEDED: accept execute for stage 05b, or send back.'

# ---- AC1  the agent channel, same words ----------------------------------------------------------------
ok=1
# one fixture per nudge; the old hook and the new one judge the same stop (different sessions, no prompt_id)
A1="$TMP/a1"
fixture "$A1/i10" 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s\n'
fixture "$A1/i1" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
fixture "$A1/halt" 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s\n'
fixture "$A1/gate" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s\n'
fixture "$A1/ap" 'CURRENT_HOP: NONE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s\n\n<EDIT>\nAUTOPILOT: 05b a\n</EDIT>\n'
cases=( "i10|$MSG_ACCEPT" "i1|Implemented the slice. Done." "halt|AUTOPILOT HALT: D4 is red." \
        "gate|STITCH NEEDED: review spec+plan for stage 05b." "ap|STITCH NEEDED: review spec+plan for stage 04." )
for c in "${cases[@]}"; do
  name="${c%%|*}"; msg="${c#*|}"; d="$A1/$name"
  vn="$(ev "$d" "new-$name" "" false "$msg" | sgv "$NEW" "$TMP/a1-$name-new")"
  vo="$(ev "$d" "old-$name" "" false "$msg" | sgv "$OLD" "$TMP/a1-$name-old")"
  [[ "$vn" == nudge ]] || { ok=0; echo "  $name: the new hook gave '$vn', not a nudge: $(head -c 200 "$TMP/a1-$name-new.err")"; continue; }
  if [[ "$name" == i1 ]]; then
    grep -q 'Hop not closed (I1)' "$TMP/a1-$name-new.agent" || { ok=0; echo "  i1: not the I1 nudge"; }
  else
    cmp -s "$TMP/a1-$name-new.agent" <(printf '%s' "$(cat "$TMP/a1-$name-old.err")") \
      || { ok=0; echo "  $name: the agent text differs from the pre-t63 stderr"; diff <(cat "$TMP/a1-$name-new.agent") "$TMP/a1-$name-old.err" | head -4; }
  fi
  [[ "$vo" == broken ]] || { ok=0; echo "  red twin: the pre-t63 hook was read as '$vo' for $name, so AC1 cannot tell them apart"; }
done
t AC1 "$ok" "the five agent nudges (I1, I10, HALT block, spec gate, autopilot) arrive in additionalContext on exit 0 with no stderr, in the pre-t63 words except I1; the pre-t63 hook fails the same read"

# ---- AC2  the human channel ----------------------------------------------------------------------------
ok=1
A2="$TMP/a2"; fixture "$A2" 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\nAUTOPILOT: 05b a, 05b b\n</EDIT>\n'
GD2="$A2/.git"
ap_state() {  # ap_state <session> <hops so far> <minutes ago it started>
  printf '%s' "$2" > "$GD2/cascade-autopilot-$1"
  python3 -c 'import sys,time; open(sys.argv[1],"w").write(str(time.time()-float(sys.argv[2])*60))' "$GD2/cascade-autopilot-$1-started" "$3"
}
for hooks in NEW OLD; do
  dir="${!hooks}"
  ap_state "b-$hooks" 1 120
  v="$(ev "$A2" "b-$hooks" "" true "$MSG_ACCEPT" | SGV_ENV="BDD_AUTOPILOT_MINUTES=1" sgv "$dir" "$TMP/a2-b-$hooks")"
  vf="$(ap_state "bf-$hooks" 1 120; ev "$A2" "bf-$hooks" "" false "$MSG_ACCEPT" | SGV_ENV="BDD_AUTOPILOT_MINUTES=1" sgv "$dir" "$TMP/a2-bf-$hooks")"
  ap_state "c-$hooks" 12 0
  vc="$(ev "$A2" "c-$hooks" "" true "$MSG_ACCEPT" | sgv "$dir" "$TMP/a2-c-$hooks")"
  if [[ "$hooks" == NEW ]]; then
    [[ "$v" == warn ]] && grep -q 'minute budget reached' "$TMP/a2-b-$hooks.human" || { ok=0; echo "  budget on a real edge: '$v' — $(cat "$TMP/a2-b-$hooks.human")"; }
    [[ "$vf" == nudge+warn ]] && grep -q 'minute budget reached' "$TMP/a2-bf-$hooks.human" && grep -q 'without evidence (I10)' "$TMP/a2-bf-$hooks.agent" \
      || { ok=0; echo "  budget falling through to I10: '$vf'"; }
    [[ "$vc" == warn ]] && grep -q 'continuation cap reached (12)' "$TMP/a2-c-$hooks.human" || { ok=0; echo "  continuation cap: '$vc' — $(cat "$TMP/a2-c-$hooks.human")"; }
  else
    [[ ! -s "$TMP/a2-b-$hooks.human" && ! -s "$TMP/a2-c-$hooks.human" ]] || { ok=0; echo "  red twin: the pre-t63 hook already told the human, so AC2 proves nothing"; }
  fi
done
# punch cap: four DIRTY stage-10 rounds; round 4 tells the agent and the human, and is the punch cap, not NUDGECAP
P2="$TMP/a2p"; fixture "$P2" 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 10\nCURRENT_SLICE: punchy\n'
printf '| FR-1 | x | path: nope/missing.kt test: false | IMPLEMENTED |\n' > "$P2/docs/cascade/10-audit.md"
for r in 1 2 3 4; do
  v="$(ev "$P2" "punch" "" false 'STITCH NEEDED: accept execute for stage 10, or send back.' | sgv "$NEW" "$TMP/a2p-$r")"
done
[[ "$v" == nudge+warn ]] && grep -q 'punch cap reached for punchy' "$TMP/a2p-4.human" && grep -q 'rounds and the audit is still DIRTY' "$TMP/a2p-4.agent" \
  || { ok=0; echo "  punch round 4: '$v' — $(cat "$TMP/a2p-4.human")"; }
[[ "$(logged "$P2" NUDGECAP)" -eq 0 ]] || { ok=0; echo "  four punch rounds tripped NUDGECAP: rounds must not count as identical nudges"; }
t AC2 "$ok" "the budget, the continuation cap and the punch cap reach the human in systemMessage — alone on a real edge, beside the nudge on fall-through; punch rounds never trip NUDGECAP; the pre-t63 hook told no one"

# ---- AC3  quoting ----------------------------------------------------------------------------------------
ok=1
I3="$TMP/a3idle"; fixture "$I3" 'CURRENT_HOP: NONE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: s\n\n<EDIT>\nAUTOPILOT: 05b a\n</EDIT>\n'
O3="$TMP/a3open"; fixture "$O3" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
SPAN='The hook looks for a `STITCH NEEDED:` line and for `AUTOPILOT HALT`.'
FENCE=$'Example:\n```\nSTITCH NEEDED: review spec+plan for stage 06.\n```\nThat is all.'
[[ "$(ev "$I3" i-span "" false "$SPAN" | sgv "$NEW" "$TMP/a3-1")" == pass ]] || { ok=0; echo "  idle + signed list: a code-span edge continued autopilot"; }
[[ "$(ev "$I3" i-fence "" false "$FENCE" | sgv "$NEW" "$TMP/a3-2")" == pass ]] || { ok=0; echo "  idle + signed list: a fenced edge continued autopilot"; }
[[ "$(ev "$I3" i-prose "" false "Done. STITCH NEEDED: review spec+plan for stage 04." | sgv "$NEW" "$TMP/a3-3")" == nudge ]] \
  && grep -q 'signed edges remain' "$TMP/a3-3.agent" || { ok=0; echo "  idle + signed list: an unquoted edge mid-prose no longer continues autopilot (it must, as today)"; }
[[ "$(ev "$O3" o-span "" false "$SPAN" | sgv "$NEW" "$TMP/a3-4")" == nudge ]] && grep -q 'Hop not closed' "$TMP/a3-4.agent" \
  || { ok=0; echo "  open hop: a reply whose only edge is in code was counted as closed"; }
[[ "$(ev "$O3" o-last "" false $'Spec written.\nSTITCH NEEDED: review spec+plan for stage 06' | sgv "$NEW" "$TMP/a3-5")" == pass ]] \
  || { ok=0; echo "  open hop: a plain last-line edge was refused"; }
[[ "$(ev "$O3" o-mid "" false 'Spec written. STITCH NEEDED: review spec+plan for stage 06. Bye.' | sgv "$NEW" "$TMP/a3-6")" == pass ]] \
  || { ok=0; echo "  open hop: a plain mid-line edge was refused (it passes today)"; }
# code review of c76a545: a halt the agent issues is still a halt when it is fenced, as barbar.md's template is
HALTF=$'Blocked.\n```\nAUTOPILOT HALT: D4 is red\n  BOTTLENECK:  D4\n  WHAT TO DO:  bash tests/sign.sh\n  RESUME WITH: /barbar auto\n```'
[[ "$(ev "$O3" o-halt-fenced "" false "$HALTF" | sgv "$NEW" "$TMP/a3-h1")" == pass ]] \
  || { ok=0; echo "  open hop: a complete halt inside a fence was nudged ($(head -c 80 "$TMP/a3-h1.agent"))"; }
HALTB=$'AUTOPILOT HALT: D4 is red\n```\n  BOTTLENECK:  D4\n  WHAT TO DO:  bash tests/sign.sh\n  RESUME WITH: /barbar auto\n```'
[[ "$(ev "$O3" o-halt-block "" false "$HALTB" | sgv "$NEW" "$TMP/a3-h2")" == pass ]] \
  || { ok=0; echo "  open hop: a plain halt with a fenced instruction block was told its block is missing"; }
grep -q 'stop_guard  HALT' "$O3/.cascade/decisions.log" 2>/dev/null || { ok=0; echo "  a halt with a fenced block was not logged as HALT"; }
NEST=$'````\n```\ninner\n````\nSTITCH NEEDED: review spec+plan for stage 06.'
[[ "$(ev "$O3" o-nest "" false "$NEST" | sgv "$NEW" "$TMP/a3-n")" == pass ]] \
  || { ok=0; echo "  open hop: a four-backtick fence holding a three-backtick line hid the plain edge after it"; }
UNCL=$'Here:\n```\nsome code\nSTITCH NEEDED: review spec+plan for stage 06.'
[[ "$(ev "$O3" o-unclosed "" false "$UNCL" | sgv "$NEW" "$TMP/a3-u")" == pass ]] \
  || { ok=0; echo "  open hop: an unclosed fence hid the plain edge after it"; }
T3="$(twin unquoted '    return "\n".join(out)' '    return text')" || { ok=0; echo "  red twin: could not build"; }
[[ -n "$T3" && "$(ev "$I3" i-twin "" false "$SPAN" | sgv "$T3" "$TMP/a3-7")" == nudge ]] \
  || { ok=0; echo "  red twin: unquoted() as identity did not continue autopilot on a code-span edge, so AC3 proves nothing"; }
t AC3 "$ok" "an edge quoted in a code span or fence is not an edge (idle: no autopilot; open hop: still nudged); plain edges count on the last line or mid-line, as today"

# ---- AC4  identical nudges ---------------------------------------------------------------------------------
ok=1
F4="$TMP/a4"; fixture "$F4" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
nostop() { ev "$F4" s4 "$1" false "Still working on it." | sgv "${2:-$NEW}" "$TMP/a4-$1"; }
seq4="$(nostop p1) $(nostop p2) $(nostop p3)"
[[ "$seq4" == "nudge nudge warn" ]] && grep -q 'Hop not closed (I1)' "$TMP/a4-p3.human" && ! grep -qi 'sign' "$TMP/a4-p3.human" \
  || { ok=0; echo "  three identical nudges gave: $seq4 — $(cat "$TMP/a4-p3.human")"; }
[[ "$(logged "$F4" NUDGECAP)" -eq 1 ]] || { ok=0; echo "  NUDGECAP was not logged once"; }
# a clean stop starts over
ev "$F4" s4 p4 false 'STITCH NEEDED: review spec+plan for stage 06.' | sgv "$NEW" "$TMP/a4-p4" >/dev/null
[[ "$(nostop p5) $(nostop p6)" == "nudge nudge" ]] || { ok=0; echo "  a clean stop did not reset the count"; }
# a different nudge text starts over
sed -i.bak 's/CURRENT_STAGE: 06/CURRENT_STAGE: 07/' "$F4/docs/cascade/hop-state.md"
[[ "$(nostop p7)" == nudge ]] || { ok=0; echo "  a different nudge text did not reset the count"; }
sed -i.bak 's/CURRENT_STAGE: 07/CURRENT_STAGE: 06/' "$F4/docs/cascade/hop-state.md"
nostop p8 >/dev/null; nostop p9 >/dev/null
# a human prompt starts over
printf '{"cwd":"%s","session_id":"s4","prompt_id":"u1","hook_event_name":"UserPromptSubmit","prompt":"next"}' "$F4" \
  | python3 -B "$NEW/seam.py" >/dev/null 2>&1
[[ "$(nostop p10)" == nudge ]] || { ok=0; echo "  seam.py did not reset the count on a human prompt"; }
# RED TWIN: without the counter the third identical stop nudges again
T4="$(twin counter '    return n <= NUDGE_CAP' '    return True')" || { ok=0; echo "  red twin: could not build"; }
F4b="$TMP/a4b"; fixture "$F4b" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
seqt=""; for p in q1 q2 q3; do seqt+="$(ev "$F4b" s4 "$p" false 'Still working.' | sgv "$T4" "$TMP/a4t-$p") "; done
[[ "$seqt" == "nudge nudge nudge " ]] || { ok=0; echo "  red twin: without the counter the sequence was '$seqt', so AC4 proves nothing"; }
t AC4 "$ok" "identical nudges in a row: nudge, nudge, then a warning and NUDGECAP; a clean stop, a different nudge and a human prompt each start the count over"

# ---- AC4b  the prompt marker -------------------------------------------------------------------------------
ok=1
F4c="$TMP/a4c"; fixture "$F4c" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
v1="$(ev "$F4c" s same false 'Working.' | sgv "$NEW" "$TMP/a4c-1")"; n1="$(logged "$F4c" NOEDGE)"
v2="$(ev "$F4c" s same true 'Still working.' | sgv "$NEW" "$TMP/a4c-2")"; n2="$(logged "$F4c" NOEDGE)"
[[ "$v1" == nudge && "$v2" == pass && "$n1" == "$n2" ]] || { ok=0; echo "  same prompt_id twice: '$v1' then '$v2', NOEDGE $n1 -> $n2"; }
T4c="$(twin marker '    if root0 and already_event(ev, root0, NAME, "prompt_id"):' '    if False:')" || { ok=0; echo "  red twin: could not build"; }
F4d="$TMP/a4d"; fixture "$F4d" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
ev "$F4d" s same false 'Working.' | sgv "$T4c" "$TMP/a4d-1" >/dev/null
[[ "$(ev "$F4d" s same false 'Still working.' | sgv "$T4c" "$TMP/a4d-2")" == nudge ]] \
  || { ok=0; echo "  red twin: without the marker the second stop was not judged, so AC4b proves nothing"; }
t AC4b "$ok" "a second stop in the same prompt is not judged again — the guard nudges at most once per prompt"

# ---- AC5  no exit-code reads of stop_guard left ---------------------------------------------------------------
lint63() {  # lint63 <file>…  -> prints offending lines; exit 1 if any
  python3 -B - "$@" <<'PY'
import re, sys
bad = []
for p in sys.argv[1:]:
    lines = open(p, encoding="utf-8").read().splitlines()
    for i, ln in enumerate(lines):
        if "stop_guard" not in ln or "lint63-ok" in ln or ln.lstrip().startswith("#"):
            continue
        if re.search(r"from stop_guard import|sgv|SG=|for n in|for h in|cp -R|python3 - \"\$TMP/twin|OLD=", ln):
            continue
        window = ln + "\n" + (lines[i + 1] if i + 1 < len(lines) else "")
        if re.search(r"\$\?|rc=\$|-eq [02]\b", window):
            bad.append(f"{p}:{i + 1}: {ln.strip()[:120]}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}
ok=1
out5="$(lint63 "$ROOT/tests/enforcement.sh" "$ROOT"/tests/ac/*.sh)" || { ok=0; echo "  stop_guard still read by exit code:"; echo "$out5" | sed 's/^/    /'; }   # lint63-ok
printf 'printf x | python3 -B "$L2/.claude/hooks/stop_guard.py"; rc=$?\n[[ "$rc" -eq 2 ]]\n' > "$TMP/planted.sh"   # lint63-ok
lint63 "$TMP/planted.sh" >/dev/null && { ok=0; echo "  red twin: the lint missed a planted exit-code check"; }
t AC5 "$ok" "no test reads stop_guard's verdict from its exit code; the lint catches a planted one"

# ---- AC6  the edge texts -------------------------------------------------------------------------------------
ok=1
F6="$TMP/a6"; fixture "$F6" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
ev "$F6" s6 "" false 'Done.' | sgv "$NEW" "$TMP/a6" >/dev/null
grep -q 'invariant block' "$TMP/a6.agent" && { ok=0; echo "  the I1 nudge still says to print the invariant block"; }
grep -q 'STITCH NEEDED: review spec+plan for stage 06.' "$TMP/a6.agent" || { ok=0; echo "  the I1 nudge does not name this hop's edge: $(cat "$TMP/a6.agent")"; }
grep -q 'Print I1–I18' "$ROOT/docs/cascade/product-e2e-gre-pipeline.md" && { ok=0; echo "  the conductor still says 'Print I1–I18' at the GENERATE edge"; }
t AC6 "$ok" "the I1 nudge and the conductor say to end with the edge line, not to reprint I1–I18"

# ---- AC7  a crash is silent ---------------------------------------------------------------------------------------
ok=1
F7="$TMP/a7"; fixture "$F7" 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: s\n'
crash() {  # crash <entry: main|judge>  -> "<rc>|<stdout>|<stderr first line>"
  ( cd "$F7" && ev "$F7" s7 "" false 'x' | python3 -B -c '
import io, sys, contextlib
sys.path.insert(0, sys.argv[1]); import stop_guard as g
def boom(_): raise RuntimeError("t63 crash probe")
g.unquoted = boom
out, err = io.StringIO(), io.StringIO()
rc = "exc"
with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
    try:
        rc = getattr(g, sys.argv[2])()
    except BaseException as e:
        rc = "raised " + type(e).__name__
print(f"{rc}|{out.getvalue().strip()}|{err.getvalue().strip()[:80]}")' "$NEW" "$1" )
}
r7="$(crash main)"
[[ "$r7" == "0||" ]] || { ok=0; echo "  main() under a crash gave '$r7', not a silent 0"; }
[[ "$(logged "$F7" CRASH)" -ge 1 ]] || { ok=0; echo "  the crash was not logged"; }
[[ "$(crash judge)" == raised* ]] || { ok=0; echo "  red twin: judge() unwrapped did not raise, so AC7 proves nothing"; }
t AC7 "$ok" "an exception inside the hook exits 0 with no output and logs CRASH; unwrapped, the same probe raises"

# ---- AC8  every nudge is logged ------------------------------------------------------------------------------------
ok=1
for pair in "i10 NOEVID" "i1 NOEDGE" "halt NOHALTBLOCK" "gate NOSPECGATE" "ap CONTINUE"; do
  name="${pair% *}"; verdict="${pair#* }"
  [[ "$(logged "$A1/$name" "$verdict")" -ge 1 ]] || { ok=0; echo "  the $name nudge did not log $verdict"; }
done
t AC8 "$ok" "each of the five nudges writes its line to .cascade/decisions.log (NOEVID, NOEDGE, NOHALTBLOCK, NOSPECGATE, CONTINUE)"

exit "$fail"
