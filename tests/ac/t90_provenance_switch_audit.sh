#!/usr/bin/env bash
# AC tests for 05b t90-provenance-switch-audit — THE ORACLE for this slice, written at GENERATE before any implementation
# and pinned in docs/cascade/05b-t90-provenance-switch-audit.oracle. EXECUTE builds against it and does not edit it.
# (v2, after the critic: tests/lib/builders.py and .cascade/builders — provenance.py already exists; CASCADE_HOPSTATE;
#  every switch and every commit after the review; host/unknown folded; stages 05b and 06–09; handover --as.)
#   AC1  recording: host, model (event > transcript > BDD_MODEL > unknown), session, hop, HEAD, source → .cascade/builders.
#   AC2  two builders → --builders lists both; switch.sh red. host/unknown beside host/<model> is one builder.
#   AC3  a switched hop's accept is nudged, naming the diff base; a one-builder accept is untouched (empty output, no
#        CRASH). RED TWIN: switch_gate_red() → "".
#   AC4  the review: answered and after the last switch → ok; unanswered, older than the last switch (A→B→C), or
#        followed by a product commit → red.
#   AC5  autopilot's EXECUTE→next refuses a switched hop, reading the pre-edge hop from CASCADE_HOPSTATE.
#   AC6  one builder → none; GENERATE → n/a; EXECUTE 06 switched → red; lines from before the hop opened ignored.
#   AC7  handover.sh: --as records a claimed builder; its recall lines equal preserve's; the oracle line is real; NONE.
#        RED TWIN: builders() keeping only the first builder hides the switch.
#   AC8  presence: install.sh ignores .cascade/builders.
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
LOG=.cascade/builders

# mk <dir> <HOP> <STAGE> — slice a, goal `true`; tests/oracle.sh not copied (not due) unless ORACLE=1; hooks wired
mk() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests" "$d/lib"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh switch.sh handover.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$d/tests/"; done
  [[ -n "${ORACLE:-}" ]] && cp "$ROOT/tests/oracle.sh" "$d/tests/"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"; echo x > "$d/lib/x.txt"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: %s\nCURRENT_SLICE: a\n\n<EDIT>\n%s\n</EDIT>\n' "$2" "$3" "${AP:-}" > "$d/$HS"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  printf '# Stage %s — a — SPEC\n\n## Acceptance criteria\n\n- AC1\n' "$3" > "$d/docs/cascade/$3-a.md"
  printf '# briefs\n\n- a: the slice\n' > "$d/docs/cascade/05b-briefs.md"
  printf '# goal\n\n```\nGOAL_STAGE: %s\nGOAL_SLICE: a\nVALIDATOR: true\n```\n' "$3" > "$d/docs/cascade/goal.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
}
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }
# stop <dir> <transcript model or ""> <message> [hooks dir] [event model] — one Stop event
stop() {
  local d="$1" model="$2" msg="$3" hooks="${4:-$HOOKS}" evmodel="${5:-}" tr; tr="$TMP/tr-$(uid).jsonl"
  python3 - "$tr" "$model" "$msg" <<'PY'
import json, sys
tr, model, msg = sys.argv[1:4]
m = {"role": "assistant", "content": [{"type": "text", "text": msg}]}
if model:
    m["model"] = model
open(tr, "w").write(json.dumps({"type": "assistant", "message": m}) + "\n")
PY
  python3 - "$d" "$tr" "$msg" "$evmodel" "$(uid)" <<'PY' | (cd "$d" && python3 -B "$hooks/stop_guard.py")
import json, sys
d, tr, msg, evm, u = sys.argv[1:6]
ev = {"cwd": d, "session_id": "s-" + u, "prompt_id": "p-" + u, "transcript_path": tr,
      "last_assistant_message": msg, "stop_hook_active": False}
if evm:
    ev["model"] = evm
print(json.dumps(ev))
PY
}
last() { tail -1 "$1/$LOG" 2>/dev/null; }
builders() { (cd "$1" && python3 -B tests/lib/builders.py "$1" --builders); }
switch() { (cd "$1" && bash tests/switch.sh 2>&1); }
receipt() { (cd "$1" && bash tests/loop.sh >/dev/null 2>&1); }
at() { echo "@$(( $(date +%s) + $1 )) +0000"; }
commit_at() {  # commit_at <dir> <seconds from now> <message> — a commit without hooks, at a set time
  ( cd "$1" && git add -A && GIT_COMMITTER_DATE="$(at "$2")" GIT_AUTHOR_DATE="$(at "$2")" git -c core.hooksPath=/dev/null commit -qm "$3" )
}
review() {  # review <dir> <stage> <answered: yes|no> <seconds from now>
  local f="$1/docs/cascade/$2-a-switch-review.md"
  { printf '# switch review\n\n## Review\n\n| R# | severity | finding | evidence |\n|---|---|---|---|\n'
    printf '| R1 | low | ok | `git diff` |\n| R2 | low | ok | `git diff` |\n\n## Dispositions\n\n| R# | DISPOSITION |\n|---|---|\n| R1 | fixed a |\n'
    [[ "$3" == yes ]] && printf '| R2 | rejected b |\n'; } > "$f"
  commit_at "$1" "$4" review
}
two() { stop "$1" model-a "BLOCKED: x" >/dev/null; stop "$1" model-b "BLOCKED: x" >/dev/null; }
ACCEPT="STITCH NEEDED: accept execute for stage 05b, or send back."

# ---- AC1 recording ----------------------------------------------------------------------------------------------
D="$TMP/ac1"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; l1="$(last "$D")"
BDD_HOOK_HOST=codex stop "$D" model-a "BLOCKED: x" >/dev/null; l2="$(last "$D")"
stop "$D" model-a "BLOCKED: x" "" model-ev >/dev/null; l3="$(last "$D")"
BDD_MODEL=model-env stop "$D" "" "BLOCKED: x" >/dev/null; l4="$(last "$D")"
stop "$D" "" "BLOCKED: x" >/dev/null; l5="$(last "$D")"
head7="$(git -C "$D" rev-parse --short=7 HEAD)"
t AC1 "$([[ "$(cut -f2,3,5,6,7,8,9 <<< "$l1")" == "claude	model-a	EXECUTE	05b	a	$head7	hook" && "$(cut -f4 <<< "$l1")" == s-* \
         && "$(cut -f2 <<< "$l2")" == codex && "$(cut -f3 <<< "$l3")" == model-ev && "$(cut -f3 <<< "$l4")" == model-env \
         && "$(cut -f3 <<< "$l5")" == unknown ]] && echo 1 || echo 0)" \
  "a Stop records host, model, session, hop, HEAD and source=hook; codex host; event > transcript > BDD_MODEL > unknown"

# ---- AC2 builders and switch ------------------------------------------------------------------------------------
D="$TMP/ac2"; mk "$D" EXECUTE 05b; two "$D"
b="$(builders "$D")"; o="$(switch "$D")"; r=$?
t AC2a "$([[ "$b" == $'claude/model-a\nclaude/model-b' && $r -eq 1 && "$o" == *"switch review missing: docs/cascade/05b-a-switch-review.md"* ]] && echo 1 || echo 0)" \
  "two builders: --builders lists both in order; switch.sh red, naming the missing review"
D="$TMP/ac2b"; mk "$D" EXECUTE 05b; stop "$D" "" "BLOCKED: x" >/dev/null; stop "$D" model-a "BLOCKED: x" >/dev/null
t AC2b "$([[ "$(builders "$D")" == claude/model-a && "$(switch "$D")" == *"SWITCH none (claude/model-a)"* ]] && echo 1 || echo 0)" \
  "claude/unknown beside claude/model-a on the same host is one builder (C8)"

# ---- AC3 the accept edge ----------------------------------------------------------------------------------------
D="$TMP/ac3"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; base="$(git -C "$D" rev-parse --short=7 HEAD)"
echo y >> "$D/lib/x.txt"; commit_at "$D" 0 "work by b"; stop "$D" model-b "BLOCKED: x" >/dev/null; receipt "$D"
s="$(stop "$D" model-b "$ACCEPT")"
D1="$TMP/ac3one"; mk "$D1" EXECUTE 05b; stop "$D1" model-a "BLOCKED: x" >/dev/null; receipt "$D1"
s1="$(stop "$D1" model-a "$ACCEPT")"
t AC3 "$([[ "$s" == *"builder changed"* && "$s" == *"$base"* && -z "$s1" ]] && ! grep -q CRASH "$D1/.cascade/decisions.log" 2>/dev/null && echo 1 || echo 0)" \
  "a switched hop's accept is nudged with the diff base (HEAD at model-a's last Stop); a one-builder accept: empty output, no CRASH"
cp -R "$HOOKS" "$TMP/hooks3"
python3 - "$TMP/hooks3/stop_guard.py" <<'PY'
import re, sys; p=sys.argv[1]; s=open(p).read()
m = re.search(r"def switch_gate_red\(root: str\) -> str:\n", s)
assert m, "twin anchor: switch_gate_red(root) -> str"
open(p, "w").write(s[:m.end()] + '    return ""\n' + s[m.end():])
PY
D="$TMP/ac3t"; mk "$D" EXECUTE 05b; two "$D"; receipt "$D"
s="$(stop "$D" model-b "$ACCEPT" "$TMP/hooks3")"
t AC3t "$([[ -z "$s" ]] && ! grep -q CRASH "$D/.cascade/decisions.log" 2>/dev/null && echo 1 || echo 0)" "RED TWIN: switch_gate_red() returning \"\" passes the switched hop"

# ---- AC4 the review ---------------------------------------------------------------------------------------------
D="$TMP/ac4"; mk "$D" EXECUTE 05b; two "$D"; review "$D" 05b yes 30; o="$(switch "$D")"; r=$?; receipt "$D"
s="$(stop "$D" model-b "$ACCEPT")"
t AC4a "$([[ $r -eq 0 && "$o" == *"SWITCH ok (claude/model-a → claude/model-b)"* && -z "$s" ]] && echo 1 || echo 0)" \
  "a review after the switch, every row answered: SWITCH ok, and the accept is untouched"
D="$TMP/ac4b"; mk "$D" EXECUTE 05b; two "$D"; review "$D" 05b no 30; o="$(switch "$D")"; r=$?
t AC4b "$([[ $r -eq 1 && "$o" == *"unanswered: R2"* ]] && echo 1 || echo 0)" "a row without a disposition: red, unanswered: R2"
D="$TMP/ac4c"; mk "$D" EXECUTE 05b; two "$D"; review "$D" 05b yes 30
printf '%s\tclaude\tmodel-c\ts-c\tEXECUTE\t05b\ta\t-\thook\n' "$(( $(date +%s) + 60 ))" >> "$D/$LOG"
o="$(switch "$D")"; r=$?
t AC4c "$([[ $r -eq 1 && "$o" == *"switch review is older than the switch"* ]] && echo 1 || echo 0)" "A→B, review, then C: the review is older than the last switch (C5)"
D="$TMP/ac4d"; mk "$D" EXECUTE 05b; two "$D"; review "$D" 05b yes 30; echo z >> "$D/lib/x.txt"; commit_at "$D" 60 "more work"
o="$(switch "$D")"; r=$?
t AC4d "$([[ $r -eq 1 && "$o" == *"work after the review: 1 commit"* ]] && echo 1 || echo 0)" "a product commit after the review: red (C5)"

# ---- AC5 autopilot ----------------------------------------------------------------------------------------------
D="$TMP/ac5"; AP="AUTOPILOT: 05b a, 05b b" mk "$D" EXECUTE 05b; echo '# spec' > "$D/docs/cascade/05b-b.md"; commit_at "$D" 0 specb
two "$D"
cp "$D/$HS" "$TMP/before"; sed 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: b/' "$TMP/before" > "$TMP/after"
cp "$TMP/after" "$D/$HS"   # as pre-commit sees it: the working tree already holds the next hop (C4)
why="$(cd "$D" && python3 -B tests/lib/autopilot.py "$TMP/before" "$TMP/after" "$D" 2>&1)"; r=$?
t AC5 "$([[ $r -ne 0 && "$why" == *"switch.sh"* ]] && echo 1 || echo 0)" "autopilot refuses the switched hop's EXECUTE→next edge with the working tree already on the next hop"

# ---- AC6 one builder, other hops and stages, earlier lines ------------------------------------------------------
D="$TMP/ac6"; mk "$D" EXECUTE 05b; mkdir -p "$D/.cascade"
printf '1000\tclaude\tmodel-z\ts-old\tEXECUTE\t05b\ta\t-\thook\n' > "$D/$LOG"
stop "$D" model-a "BLOCKED: x" >/dev/null; o1="$(switch "$D")"; r1=$?
D2="$TMP/ac6g"; mk "$D2" GENERATE 05b; two "$D2"; o2="$(switch "$D2")"
D3="$TMP/ac6s"; mk "$D3" EXECUTE 06; two "$D3"; o3="$(switch "$D3")"; r3=$?
t AC6 "$([[ $r1 -eq 0 && "$o1" == *"SWITCH none (claude/model-a)"* && "$o2" == *"SWITCH n/a"* && $r3 -eq 1 && "$o3" == *"06-a-switch-review.md"* ]] && echo 1 || echo 0)" \
  "one builder → none (a line from before the hop opened ignored); GENERATE → n/a; a switched EXECUTE 06 → red (C2)"

# ---- AC7 handover -----------------------------------------------------------------------------------------------
D="$TMP/ac7"; ORACLE=1 mk "$D" EXECUTE 05b; stop "$D" model-a "BLOCKED: x" >/dev/null
h="$(cd "$D" && bash tests/handover.sh --as codex/model-x 2>&1)"; r=$?
index_of() { python3 -c 'import sys
lines = sys.stdin.read().splitlines(); out = []; on = False
for l in lines:
    if l.startswith("Recall index"): on = True; continue
    if on and l.startswith("  "): out.append(l[2:]); continue
    if on: break
print("\n".join(out))'; }
idx="$(printf '{"cwd":"%s","source":"compact","session_id":"%s"}' "$D" "$(uid)" | (cd "$D" && python3 -B "$HOOKS/preserve.py") \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' | index_of)"
hidx="$(index_of <<< "$h")"
t AC7a "$([[ $r -eq 0 && "$h" == *"CURRENT_HOP: EXECUTE"* && "$h" == *"oracle: FAIL"*"no oracle manifest"* && "$h" == *"builders: claude/model-a, codex/model-x"* \
         && "$(grep -c $'\tclaimed$' "$D/$LOG")" == 1 && -n "$hidx" && "$(grep -c '^spec ' <<< "$hidx")" == 1 && "$hidx" == "$idx" ]] && echo 1 || echo 0)" \
  "handover --as records a claimed builder; prints the hop, the real oracle state, the builders; its recall index matches preserve's"
D2="$TMP/ac7n"; mk "$D2" NONE 00; h2="$(cd "$D2" && bash tests/handover.sh 2>&1)"
t AC7b "$([[ "$h2" == *"(no recall index: no hop running)"* ]] && echo 1 || echo 0)" "at NONE: no recall index"
D="$TMP/ac7t"; mk "$D" EXECUTE 05b
python3 - "$D/tests/lib/builders.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
a = "def builders(root: str) -> list[str]:"
assert s.count(a) == 1, "twin anchor: builders(root) -> list[str]"
open(p, "w").write(s.replace(a, "def builders(root: str) -> list[str]:\n    return _all_builders(root)[:1]\n\n\ndef _all_builders(root: str) -> list[str]:"))
PY
two "$D"
t AC7t "$([[ "$(switch "$D")" == *"SWITCH none"* ]] && echo 1 || echo 0)" "RED TWIN: a builders() that keeps only the first builder hides the switch"

# ---- AC8 presence -----------------------------------------------------------------------------------------------
t AC8 "$(grep -q "'.cascade/builders'" "$ROOT/install.sh" && grep -qx '.cascade/builders' "$ROOT/.gitignore" && echo 1 || echo 0)" \
  "presence check (C10): install.sh and this repo's .gitignore ignore .cascade/builders"

exit "$fail"
