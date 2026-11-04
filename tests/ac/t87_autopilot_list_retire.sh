#!/usr/bin/env bash
# AC tests for 05b t87-autopilot-list-retire: a signed list no longer hijacks an off-list open hop, and a list whose
# first entry was already accepted (per the hop state's git history) is stale, not restarted. Scratch repos with the
# real pre-commit hook wired; acceptance is made by real hop-state commits, never by writing headings.
#   AC1  off-list open hop: status off-list, no Stop-hook continuation. RED TWIN: the old idx<0 fold continues.
#   AC2  its edges are refused naming "not on the signed list" — in pre-commit and in hop_guard's dialog.
#   AC3  a fresh list at NONE still starts entry 1.
#   AC4  accepted by history: stale names accepted + remaining; GENERATE of entry 1 refused; all accepted → none;
#        a send-back is not an accept. RED TWIN: an accepted() that finds nothing lets the edge land.
#   AC5  unreadable history (hop state never committed): the old start.
#   AC6  on-list runs unchanged: next GENERATE b, then done.
#   AC7  one retire notice per status per session.
#   AC8  the seam: ON for next and done (+ last entry), "not on it" off-list, "is stale" at NONE, off with no list.
#   AC9  presence (by design): barbar.md copies and USAGE.md name off-list, stale and the done retire proposal.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOOKS="$ROOT/.claude/hooks"
HS=docs/cascade/hop-state.md

hs() {  # hs <dir> <HOP> <SLICE> [list] — write the hop state
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: %s\nCURRENT_SLICE: %s\n\n<EDIT>\n%s\n</EDIT>\n' "$2" "$([[ "$2" == NONE ]] && echo 00 || echo 05b)" \
    "$3" "${4-AUTOPILOT: 05b a, 05b b}" > "$1/$HS"
}
mk() {  # mk <dir> <HOP> <SLICE> [list] — repo with hooks wired, hop state committed (no hooks: setup, not under test)
  local d="$1"; rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$ROOT/.githooks" "$d/.githooks"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  for f in loop.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$d/tests/"; done
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf '# skills\n' > "$d/docs/cascade/skill-binding.md"
  echo '# spec' > "$d/docs/cascade/05b-a.md"; echo '# spec' > "$d/docs/cascade/05b-b.md"
  hs "$d" "$2" "$3" "${4-AUTOPILOT: 05b a, 05b b}"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
      && git config core.hooksPath .githooks )
}
step() {  # step <dir> <HOP> <SLICE> — a history commit without hooks (the past, not under test)
  local list; list="$(grep '^AUTOPILOT:' "$1/$HS" || true)"
  hs "$1" "$2" "$3" "$list"; ( cd "$1" && git add -A && git -c core.hooksPath=/dev/null commit -qm "$2 $3" )
}
edge() {  # edge <dir> <HOP> <SLICE> — the agent commits the move through the real pre-commit; $RC, $ERR
  local d="$1" list; list="$(grep '^AUTOPILOT:' "$d/$HS" || true)"
  hs "$d" "$2" "$3" "$list"
  ( cd "$d" && git add -A && git commit -qm "agent: $2 $3" </dev/null >/dev/null 2>"$TMP/err" ); RC=$?
  ERR="$(cat "$TMP/err")"; [[ "$RC" -ne 0 ]] && ( cd "$d" && git reset -q --hard HEAD )
  return 0
}
status() { python3 -B "$1/tests/lib/autopilot.py" --status "$1"; }
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }
stop() {  # stop <dir> <message> [session] — the Stop hook's JSON output
  local sid="${3:-$(uid)}"
  python3 - "$1" "$2" "$sid" "$(uid)" <<'PY' | (cd "$1" && python3 -B "$HOOKS/stop_guard.py")
import json, sys
print(json.dumps({"cwd": sys.argv[1], "session_id": sys.argv[3], "prompt_id": sys.argv[4],
                  "last_assistant_message": sys.argv[2], "stop_hook_active": False}))
PY
}
seam() { printf '{"cwd":"%s","prompt":"x","session_id":"%s"}' "$1" "$(uid)" | (cd "$1" && python3 -B "$HOOKS/seam.py"); }
twin_old_fold() {  # a tests/lib whose autopilot.py has today's idx<0 fold back
  local t="$TMP/lib-fold"; rm -rf "$t"; cp -R "$ROOT/tests/lib" "$t"
  python3 - "$t/autopilot.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
a = 'if idx < 0 and hop in ("GENERATE", "EXECUTE"):'
assert s.count(a) == 2, "twin anchor moved"
open(p, "w").write(s.replace(a, "if False:"))
PY
  echo "$t"
}

# ---- AC1 off-list open hop --------------------------------------------------------------------------------------
D="$TMP/ac1"; mk "$D" EXECUTE x
s="$(stop "$D" "BLOCKED: x still fails")"
t AC1 "$([[ "$(status "$D")" == "off-list EXECUTE 05b x" && "$s" != *"signed edges remain"* ]] && echo 1 || echo 0)" \
  "an open hop off the list is off-list; the Stop hook does not continue it"
D="$TMP/ac1t"; mk "$D" EXECUTE x; rm -rf "$D/tests/lib"; cp -R "$(twin_old_fold)" "$D/tests/lib"
s="$(stop "$D" "BLOCKED: x still fails")"
t AC1t "$([[ "$(status "$D")" == "next GENERATE 05b a" && "$s" == *"signed edges remain"* ]] && echo 1 || echo 0)" \
  "RED TWIN: the old fold sends the off-list hop to entry 1 and continues it"

# ---- AC2 its edges are refused, with the reason -----------------------------------------------------------------
D="$TMP/ac2"; mk "$D" EXECUTE x
edge "$D" GENERATE a
t AC2a "$([[ "$RC" -ne 0 && "$ERR" == *"not on the signed list"* ]] && echo 1 || echo 0)" "pre-commit refuses the jump to entry 1, naming why"
j="$(python3 - "$D" <<'PY' | (cd "$D" && python3 -B "$HOOKS/hop_guard.py")
import json, sys
d = sys.argv[1]; f = d + "/docs/cascade/hop-state.md"
print(json.dumps({"tool_name": "Edit", "cwd": d, "session_id": "s1",
                  "tool_input": {"file_path": f, "old_string": "CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x",
                                 "new_string": "CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a"}}))
PY
)"
t AC2b "$([[ "$j" == *"autopilot:"* && "$j" == *"not on the signed list"* ]] && echo 1 || echo 0)" "the in-session dialog names autopilot's reason"

# ---- AC3 a fresh list at NONE still starts ----------------------------------------------------------------------
D="$TMP/ac3"; mk "$D" NONE ""
st="$(status "$D")"; edge "$D" GENERATE a
t AC3 "$([[ "$st" == "next GENERATE 05b a" && "$RC" -eq 0 ]] && echo 1 || echo 0)" "fresh list at NONE: next GENERATE 05b a, and the edge lands"

# ---- AC4 accepted by history ------------------------------------------------------------------------------------
D="$TMP/ac4"; mk "$D" NONE ""; step "$D" GENERATE a; step "$D" EXECUTE a; step "$D" NONE ""
st="$(status "$D")"; edge "$D" GENERATE a
t AC4a "$([[ "$st" == "stale accepted: 05b a; remaining: 05b b" && "$RC" -ne 0 && "$ERR" == *"stale"* ]] && echo 1 || echo 0)" \
  "entry 1 accepted (EXECUTE a → NONE): stale, naming the remaining entry; GENERATE a refused"
step "$D" GENERATE b; step "$D" EXECUTE b; step "$D" NONE ""
t AC4b "$([[ "$(status "$D")" == "stale accepted: 05b a, 05b b; remaining: none" ]] && echo 1 || echo 0)" "every entry accepted: remaining none"
D="$TMP/ac4s"; mk "$D" NONE ""; step "$D" GENERATE a; step "$D" EXECUTE a; step "$D" GENERATE a; step "$D" NONE ""
t AC4c "$([[ "$(status "$D")" == "next GENERATE 05b a" ]] && echo 1 || echo 0)" "a send-back (EXECUTE a → GENERATE a) is not an accept"
D="$TMP/ac4t"; mk "$D" NONE ""; step "$D" GENERATE a; step "$D" EXECUTE a; step "$D" NONE ""
rm -rf "$D/tests/lib" "$D/.githooks/lib" 2>/dev/null; cp -R "$ROOT/tests/lib" "$D/tests/lib"
python3 - "$D/tests/lib/autopilot.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
a = "    return {e for e in plan if e in done}"
assert a in s, "twin anchor moved"; open(p, "w").write(s.replace(a, "    return set()"))
PY
( cd "$D" && git add -A && git -c core.hooksPath=/dev/null commit -qm twin )
edge "$D" GENERATE a
t AC4t "$([[ "$RC" -eq 0 ]] && echo 1 || echo 0)" "RED TWIN: an accepted() that finds nothing lets the accepted entry be rebuilt"

# ---- AC5 unreadable history -------------------------------------------------------------------------------------
D="$TMP/ac5"; mk "$D" NONE ""; ( cd "$D" && git rm -q --cached "$HS" && git -c core.hooksPath=/dev/null commit -qm untrack )
t AC5 "$([[ "$(status "$D")" == "next GENERATE 05b a" ]] && echo 1 || echo 0)" "no hop-state history: the old start (fails open)"

# ---- AC6 on-list runs unchanged ---------------------------------------------------------------------------------
D="$TMP/ac6"; mk "$D" EXECUTE a; s1="$(status "$D")"; step "$D" EXECUTE b; s2="$(status "$D")"
t AC6 "$([[ "$s1" == "next GENERATE 05b b" && "$s2" == "done" ]] && echo 1 || echo 0)" "EXECUTE a → next GENERATE 05b b; EXECUTE b → done"

# ---- AC7 one retire notice per status per session ---------------------------------------------------------------
D="$TMP/ac7"; mk "$D" NONE ""; step "$D" GENERATE a; step "$D" EXECUTE a; step "$D" GENERATE b; step "$D" EXECUTE b
sid="$(uid)"
n1="$(stop "$D" "BLOCKED: one" "$sid")"; n2="$(stop "$D" "BLOCKED: two" "$sid")"
step "$D" NONE ""; n3="$(stop "$D" "a question answered" "$sid")"
t AC7 "$([[ "$n1" == *"signed list is finished (done)"* && "$n2" != *"signed list is finished"* && "$n3" == *"finished (stale accepted"* ]] && echo 1 || echo 0)" \
  "done notifies once; a second stop does not; the change to stale notifies again"

# ---- AC8 the seam -----------------------------------------------------------------------------------------------
ok=1
D="$TMP/ac8a"; mk "$D" EXECUTE a; [[ "$(seam "$D")" == *"AUTOPILOT is ON"* ]] || { ok=0; echo "  next: no ON"; }
step "$D" EXECUTE b; o="$(seam "$D")"; [[ "$o" == *"AUTOPILOT is ON"* && "$o" == *"last entry"* ]] || { ok=0; echo "  done: no ON + last entry"; }
D="$TMP/ac8b"; mk "$D" EXECUTE x; o="$(seam "$D")"; [[ "$o" == *"not on it"* && "$o" != *"AUTOPILOT is ON"* ]] || { ok=0; echo "  off-list: wrong text"; }
D="$TMP/ac8c"; mk "$D" NONE ""; step "$D" GENERATE a; step "$D" EXECUTE a; step "$D" NONE ""
[[ "$(seam "$D")" == *"is stale (stale accepted: 05b a"* ]] || { ok=0; echo "  NONE stale: not named"; }
D="$TMP/ac8d"; mk "$D" EXECUTE a ""; [[ "$(seam "$D")" == *"AUTOPILOT is off"* ]] || { ok=0; echo "  no list: not off"; }
t AC8 "$ok" "seam: ON for next and done (+ last entry), 'not on it' off-list, 'is stale' at NONE, off with no list"

# ---- AC9 presence, by design ------------------------------------------------------------------------------------
ok=1
for f in "$ROOT/commands/barbar.md" "$ROOT/.claude/commands/barbar.md"; do
  for want in 'If it prints `off-list' 'If it prints `stale accepted' 'propose the edit that empties the `AUTOPILOT:` line'; do
    grep -qF -- "$want" "$f" || { ok=0; echo "  $f lacks: $want"; }
  done
done
for want in '`off`' '`off-list' '`stale accepted' '`done`' '`next <HOP>'; do grep -qF -- "$want" "$ROOT/USAGE.md" || { ok=0; echo "  USAGE.md lacks $want"; }; done
t AC9 "$ok" "presence check (it guards against deletion, not against an agent ignoring it): barbar.md copies and USAGE.md name all statuses"

exit "$fail"
