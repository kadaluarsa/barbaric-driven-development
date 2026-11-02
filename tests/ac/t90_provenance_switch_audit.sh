#!/usr/bin/env bash
# AC tests for 05b t90-provenance-switch-audit — THE ORACLE for this slice, written at GENERATE before any implementation
# and pinned in docs/cascade/05b-t90-provenance-switch-audit.oracle. EXECUTE builds against it and does not edit it.
#   AC1  recording: host, model (event > transcript > BDD_MODEL > unknown), session, hop → .cascade/provenance.
#   AC2  two builders on an EXECUTE 05b hop → --builders lists both; switch.sh red: switch review missing.
#   AC3  the accept edge of a switched hop is nudged; a one-builder hop is not. RED TWIN: switch_gate_red() → "".
#   AC4  a review committed after the switch, all rows answered → SWITCH ok and accept passes; unanswered → red;
#        committed before the switch → red.
#   AC5  autopilot's EXECUTE→next edge refuses a switched hop without its review, naming switch.sh.
#   AC6  one builder → SWITCH none; GENERATE / stage 06 → n/a; lines from before the hop opened do not count.
#   AC7  handover.sh prints the hop, the recall index, the oracle and the builders; at NONE, no recall index.
#        RED TWIN: a builders() that returns only the first builder makes the switched hop SWITCH none.
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
REV=docs/cascade/05b-a-switch-review.md

# mk <dir> <HOP> <STAGE> — slice a, goal `true`, no oracle (tests/oracle.sh is not copied: not due), hooks wired
mk() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh switch.sh handover.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$d/tests/"; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
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
# stop <dir> <model or ""> <message> [hooks dir] [event model] — a Stop event whose transcript names the model
stop() {
  local d="$1" model="$2" msg="$3" hooks="${4:-$HOOKS}" evmodel="${5:-}" tr; tr="$TMP/tr-$(uid).jsonl"
  python3 - "$tr" "$model" "$msg" <<'PY'
import json, sys
tr, model, msg = sys.argv[1:4]
with open(tr, "w") as f:
    m = {"role": "assistant", "content": [{"type": "text", "text": msg}]}
    if model:
        m["model"] = model
    f.write(json.dumps({"type": "assistant", "message": m}) + "\n")
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
prov() { cat "$1/.cascade/provenance" 2>/dev/null; }
builders() { python3 -B "$1/tests/lib/provenance.py" "$1" --builders; }
switch() { (cd "$1" && bash tests/switch.sh 2>&1); }
receipt() { (cd "$1" && bash tests/loop.sh >/dev/null 2>&1); }
review() {  # review <dir> <answered: yes|no> <committer date> — a switch review, committed without hooks
  { printf '# switch review\n\n## Review\n\n| R# | severity | finding | evidence |\n|---|---|---|---|\n'
    printf '| R1 | low | ok | `git diff` |\n| R2 | low | ok | `git diff` |\n\n## Dispositions\n\n| R# | DISPOSITION |\n|---|---|\n| R1 | fixed a |\n'
    [[ "$2" == yes ]] && printf '| R2 | rejected b |\n'; } > "$1/$REV"
  ( cd "$1" && git add -A && GIT_COMMITTER_DATE="$3" GIT_AUTHOR_DATE="$3" git -c core.hooksPath=/dev/null commit -qm review )
}
ACCEPT="STITCH NEEDED: accept execute for stage 05b, or send back."

# ---- AC1 recording ----------------------------------------------------------------------------------------------
D="$TMP/ac1"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null
l1="$(prov "$D" | tail -1)"
BDD_HOOK_HOST=codex stop "$D" model-a "BLOCKED: x" >/dev/null; l2="$(prov "$D" | tail -1)"
stop "$D" model-a "BLOCKED: x" "" model-ev >/dev/null; l3="$(prov "$D" | tail -1)"
stop "$D" "" "BLOCKED: x" >/dev/null; l4="$(prov "$D" | tail -1)"
t AC1 "$([[ "$(cut -f2,3,5,6,7 <<< "$l1")" == $'claude\tmodel-a\tEXECUTE\t05b\ta' && "$(cut -f4 <<< "$l1")" == s-* \
         && "$(cut -f2 <<< "$l2")" == codex && "$(cut -f3 <<< "$l3")" == model-ev && "$(cut -f3 <<< "$l4")" == unknown ]] && echo 1 || echo 0)" \
  "a Stop records host, model, session and hop; codex host; the event's model wins; no model → unknown"

# ---- AC2 builders and switch ------------------------------------------------------------------------------------
D="$TMP/ac2"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null
b="$(builders "$D")"; o="$(switch "$D")"; r=$?
t AC2 "$([[ "$b" == $'claude/model-a\nclaude/model-b' && $r -eq 1 && "$o" == *"switch review missing: $REV"* ]] && echo 1 || echo 0)" \
  "two builders on EXECUTE 05b: --builders lists both in order; switch.sh is red, naming the missing review"

# ---- AC3 the accept edge ----------------------------------------------------------------------------------------
D="$TMP/ac3"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null; receipt "$D"
s="$(stop "$D" model-b "$ACCEPT")"
D1="$TMP/ac3one"; mk "$D1" EXECUTE 05b; stop "$D1" model-a "BLOCKED: x" >/dev/null; receipt "$D1"
s1="$(stop "$D1" model-a "$ACCEPT")"
t AC3 "$([[ "$s" == *"builder changed"* && "$s1" != *"builder changed"* ]] && echo 1 || echo 0)" \
  "accept on a switched hop is nudged (builder changed); on a one-builder hop it is not"
cp -R "$HOOKS" "$TMP/hooks3"
python3 - "$TMP/hooks3/stop_guard.py" <<'PY'
import re, sys; p=sys.argv[1]; s=open(p).read()
m = re.search(r"def switch_gate_red\(root: str\) -> str:\n", s)
assert m, "twin anchor: switch_gate_red(root) -> str"
open(p, "w").write(s[:m.end()] + '    return ""\n' + s[m.end():])
PY
D="$TMP/ac3t"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null; receipt "$D"
s="$(stop "$D" model-b "$ACCEPT" "$TMP/hooks3")"
t AC3t "$([[ "$s" != *"builder changed"* && "$s" != *"Traceback"* ]] && echo 1 || echo 0)" "RED TWIN: switch_gate_red() returning \"\" passes the switched hop"

# ---- AC4 the review ---------------------------------------------------------------------------------------------
later="@$(( $(date +%s) + 30 )) +0000"; earlier="@$(( $(date +%s) - 3600 )) +0000"
D="$TMP/ac4"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null
review "$D" yes "$later"; o="$(switch "$D")"; r=$?; receipt "$D"
s="$(stop "$D" model-b "$ACCEPT")"
t AC4a "$([[ $r -eq 0 && "$o" == *"SWITCH ok (claude/model-a → claude/model-b)"* && "$s" != *"builder changed"* ]] && echo 1 || echo 0)" \
  "a review committed after the switch with every row answered: SWITCH ok, and the accept passes"
D="$TMP/ac4b"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null
review "$D" no "$later"; o="$(switch "$D")"; r=$?
t AC4b "$([[ $r -eq 1 && "$o" == *"unanswered: R2"* ]] && echo 1 || echo 0)" "a row without a disposition: red, unanswered: R2"
D="$TMP/ac4c"; mk "$D" EXECUTE 05b
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null
review "$D" yes "$earlier"; o="$(switch "$D")"; r=$?
t AC4c "$([[ $r -eq 1 && "$o" == *"switch review is older than the switch"* ]] && echo 1 || echo 0)" "a review committed before the switch: red"

# ---- AC5 autopilot ----------------------------------------------------------------------------------------------
D="$TMP/ac5"; AP="AUTOPILOT: 05b a, 05b b" mk "$D" EXECUTE 05b; echo '# spec' > "$D/docs/cascade/05b-b.md"
( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm specb )
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null
cp "$D/$HS" "$TMP/before"; sed 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: b/' "$TMP/before" > "$TMP/after"
why="$(cd "$D" && python3 -B tests/lib/autopilot.py "$TMP/before" "$TMP/after" "$D" 2>&1)"; r=$?
t AC5 "$([[ $r -ne 0 && "$why" == *"switch.sh"* ]] && echo 1 || echo 0)" "autopilot refuses the switched hop's EXECUTE→next edge, naming switch.sh"

# ---- AC6 one builder, other hops, earlier lines -----------------------------------------------------------------
D="$TMP/ac6"; mk "$D" EXECUTE 05b; mkdir -p "$D/.cascade"
printf '1000\tclaude\tmodel-z\ts-old\tEXECUTE\t05b\ta\t-\n' > "$D/.cascade/provenance"
stop "$D" model-a "BLOCKED: x" >/dev/null; o1="$(switch "$D")"; r1=$?
D2="$TMP/ac6g"; mk "$D2" GENERATE 05b; o2="$(switch "$D2")"
D3="$TMP/ac6s"; mk "$D3" EXECUTE 06; o3="$(switch "$D3")"
t AC6 "$([[ $r1 -eq 0 && "$o1" == *"SWITCH none (claude/model-a)"* && "$(builders "$D")" == claude/model-a && "$o2" == *"SWITCH n/a"* && "$o3" == *"SWITCH n/a"* ]] && echo 1 || echo 0)" \
  "one builder → SWITCH none (a line from before the hop opened does not count); GENERATE and stage 06 → n/a"

# ---- AC7 handover -----------------------------------------------------------------------------------------------
D="$TMP/ac7"; mk "$D" EXECUTE 05b; stop "$D" model-a "BLOCKED: x" >/dev/null
h="$(cd "$D" && bash tests/handover.sh 2>&1)"; r=$?
D2="$TMP/ac7n"; mk "$D2" NONE 00; h2="$(cd "$D2" && bash tests/handover.sh 2>&1)"
t AC7 "$([[ $r -eq 0 && "$h" == *"CURRENT_HOP: EXECUTE"* && "$h" == *"spec       docs/cascade/05b-a.md"* && "$h" == *"oracle:"* && "$h" == *"builders: claude/model-a"* \
         && "$h2" == *"(no recall index: no hop running)"* ]] && echo 1 || echo 0)" \
  "handover.sh prints the hop, the recall index, the oracle state and the builders; at NONE, no recall index"
D="$TMP/ac7t"; mk "$D" EXECUTE 05b
python3 - "$D/tests/lib/provenance.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
a = "def builders(root: str) -> list[str]:"
assert s.count(a) == 1, "twin anchor: builders(root) -> list[str]"
open(p, "w").write(s.replace(a, "def builders(root: str) -> list[str]:\n    return _all_builders(root)[:1]\n\n\ndef _all_builders(root: str) -> list[str]:"))
PY
stop "$D" model-a "BLOCKED: x" >/dev/null; stop "$D" model-b "BLOCKED: x" >/dev/null
t AC7t "$([[ "$(switch "$D")" == *"SWITCH none"* ]] && echo 1 || echo 0)" "RED TWIN: a builders() that keeps only the first builder hides the switch"

exit "$fail"
