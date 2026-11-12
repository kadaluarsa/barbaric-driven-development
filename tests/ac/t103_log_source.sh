#!/usr/bin/env bash
# AC tests for 05b t103-log-source: each new decisions.log line ends `  src=<test|agent|human>`; test runs are tagged;
# display readers strip the field and hide test lines; old lines and today's display output do not change.
#   AC1  the writer: BDD_LOG_SRC wins when valid; sign_ok/human → human; other actors → agent; prefix = 0a3d5ce's line.
#   AC2  a real hook call (bash_guard, scratch repo): src=agent; with BDD_LOG_SRC=test, src=test.
#   AC3  old-format lines: source() unknown, display() unchanged, tail() returns them, recall.halt finds an old HALT.
#   AC4  no test lines: preserve.py's and handover.sh's "Last decisions" equal 0a3d5ce's with an old-format log.
#   AC5  test lines are hidden from tail(), preserve and recall.halt; --tail-all shows them.
#   AC6  the loop tags its goal line src=test and its own `loop PASS` line src=agent.
#   AC7  enforcement.sh, regress.sh and barbar.sh export BDD_LOG_SRC=test; a regress line writes src=test.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_RECALL_TIMEOUT BDD_PLUGIN_ROOT \
      PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT BDD_LOG_SRC
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell BDD_LOOP_CACHE=off
BASE=0a3d5ce   # the commit that opened GENERATE 05b t103 — the log format before this slice
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }
OLD="$TMP/old"; mkdir -p "$OLD"; git -C "$ROOT" archive "$BASE" tests .claude/hooks | tar -x -C "$OLD"
find "$OLD" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null

readl() { L=(); [[ -f "$1" ]] || return 0; while IFS= read -r _l; do L+=("$_l"); done < "$1"; }   # bash 3.2: no mapfile
# py <lib dir> <code> — run python with that tests/lib first on the path
py() { python3 -B -c "import sys; sys.path.insert(0, '$1'); $2"; }

# ---------- AC1: the writer ----------
ok=1
W="$TMP/w"; mkdir -p "$W"
rec() {  # rec <lib> <root> <actor> <verdict> <detail> — one record() call
  py "$1" "import decisions; decisions.record('$2', '$3', '$4', '$5')"
}
rec "$ROOT/tests/lib" "$W" hop_guard DENY "src/x.kt — product path"
BDD_LOG_SRC=test rec "$ROOT/tests/lib" "$W" hop_guard DENY "probe test"
rec "$ROOT/tests/lib" "$W" sign_ok SIGNED "docs/cascade/hop-state.md sha=abc"
rec "$ROOT/tests/lib" "$W" human SENDBACK "05b a — reason"
BDD_LOG_SRC=bogus rec "$ROOT/tests/lib" "$W" stop_guard HALT "x"
BDD_LOG_SRC=human rec "$ROOT/tests/lib" "$W" loop PASS "LOOP 1/1"
readl "$W/.cascade/decisions.log"
want=(agent test human human agent human)
if [[ ${#L[@]} -ne 6 ]]; then ok=0; echo "  expected 6 lines, got ${#L[@]}"; else
  for i in 0 1 2 3 4 5; do
    [[ "${L[$i]}" == *"  src=${want[$i]}" ]] || { ok=0; echo "  line $((i+1)) does not end '  src=${want[$i]}': ${L[$i]}"; }
  done
fi
WO="$TMP/wo"; mkdir -p "$WO"
rec "$OLD/tests/lib" "$WO" hop_guard DENY "src/x.kt — product path"
oldl="$(sed -E 's/^[0-9TZ:-]+//' "$WO/.cascade/decisions.log")"
newl="$(head -1 "$W/.cascade/decisions.log" | sed -E 's/^[0-9TZ:-]+//; s/  src=[a-z]+$//')"
[[ -n "$oldl" && "$oldl" == "$newl" ]] || { ok=0; echo "  the text before the field differs from $BASE's line: '$oldl' vs '$newl'"; }
t AC1 "$ok" "BDD_LOG_SRC wins when valid; sign_ok/human → human; other actors → agent; prefix equals $BASE's line"

# ---------- fixture ----------
# mk <dir> <hop> [lib-and-hooks source root] — tests/ and .claude/ are git-ignored, so swapping them leaves git alone
mk() {
  local d="$1" hop="$2" src="${3:-$ROOT}"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/.claude"
  cp -R "$src/tests" "$d/tests"; cp -R "$src/.claude/hooks" "$d/.claude/hooks"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\ntests/\n.claude/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n' "$hop" > "$d/docs/cascade/hop-state.md"
  printf -- '- a: alpha brief\n' > "$d/docs/cascade/05b-briefs.md"
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" commit -qm init
}
swap() {  # swap <dir> <source root> — replace tests/ and .claude/hooks
  rm -rf "$1/tests" "$1/.claude/hooks"; cp -R "$2/tests" "$1/tests"; cp -R "$2/.claude/hooks" "$1/.claude/hooks"
  find "$1" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
}
pj() {  # pj <dir> <source> — preserve.py's additionalContext
  printf '{"cwd":"%s","source":"%s","session_id":"%s"}' "$1" "$2" "$(uid)" | (cd "$1" && python3 -B "$1/.claude/hooks/preserve.py") \
    | python3 -c 'import json,sys
t=sys.stdin.read().strip()
print(json.loads(t).get("hookSpecificOutput",{}).get("additionalContext","") if t else "")'
}
lastdec() { sed -n '/Last decisions/,$p'; }   # the "Last decisions" section of preserve or handover output

# ---------- AC2: a real hook call ----------
ok=1
D="$TMP/ac2"; mk "$D" NONE
ev() { printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push origin main"},"session_id":"%s","tool_use_id":"%s"}' "$D" "$(uid)" "$(uid)"; }
ev | python3 -B "$D/.claude/hooks/bash_guard.py" >/dev/null 2>&1
ev | BDD_LOG_SRC=test python3 -B "$D/.claude/hooks/bash_guard.py" >/dev/null 2>&1
readl "$D/.cascade/decisions.log"
[[ ${#L[@]} -eq 2 ]] || { ok=0; echo "  expected 2 bash_guard lines, got ${#L[@]}"; }
[[ "${L[0]:-}" == *"bash_guard"*"DENY"*"  src=agent" ]] || { ok=0; echo "  hook with no env: ${L[0]:-<none>}"; }
[[ "${L[1]:-}" == *"bash_guard"*"DENY"*"  src=test" ]] || { ok=0; echo "  hook with BDD_LOG_SRC=test: ${L[1]:-<none>}"; }
t AC2 "$ok" "a bash_guard denial writes src=agent, or src=test under BDD_LOG_SRC=test"

# ---------- AC3: old-format lines ----------
ok=1
D="$TMP/ac3"; mkdir -p "$D/.cascade"
{ printf '2026-09-08T03:14:22Z  stop_guard  HALT    D3 theater\n'
  for i in $(seq 1 13); do printf '2026-09-08T03:15:%02dZ  hop_guard   DENY    src/f%s.kt — product path\n' "$i" "$i"; done
} > "$D/.cascade/decisions.log"
out="$(py "$ROOT/tests/lib" "
import decisions, recall
lines = open('$D/.cascade/decisions.log').read().splitlines()
bad = [l for l in lines if decisions.source(l) != 'unknown' or decisions.display(l) != l]
tl = decisions.tail('$D', 40).splitlines()
print('srcdisp', 'ok' if not bad else bad[0])
print('tail', 'ok' if tl == lines else f'{len(tl)} of {len(lines)}')
h = recall.halt('$D') or ''
print('halt', 'ok' if 'D3 theater' in h else repr(h))
" 2>&1)"
for k in srcdisp tail halt; do grep -q "^$k ok" <<< "$out" || { ok=0; echo "  $k: $(grep "^$k" <<< "$out" || echo "$out" | head -2)"; }; done
t AC3 "$ok" "old lines: source() unknown, display() unchanged, tail() returns all, recall.halt finds the old HALT"

# ---------- AC4: display output does not change for a log with no test lines ----------
ok=1
D="$TMP/ac4"; mk "$D" GENERATE
for i in 1 2 3; do rec "$ROOT/tests/lib" "$D" hop_guard DENY "src/p$i.kt — product path"; done
rec "$ROOT/tests/lib" "$D" sign_ok SIGNED "docs/cascade/hop-state.md sha=abc"
new_p="$(pj "$D" compact | lastdec)"
new_h="$(cd "$D" && bash tests/handover.sh --as t/t 2>&1 | lastdec)"
sed -i.bak -E 's/  src=[a-z]+$//' "$D/.cascade/decisions.log"; rm -f "$D/.cascade/decisions.log.bak"
swap "$D" "$OLD"
old_p="$(pj "$D" compact | lastdec)"
old_h="$(cd "$D" && bash tests/handover.sh --as t/t 2>&1 | lastdec)"
[[ -n "$old_p" && "$new_p" == "$old_p" ]] || { ok=0; echo "  preserve's Last decisions differ from $BASE's"; diff <(echo "$old_p") <(echo "$new_p") | head -6; }
[[ -n "$old_h" && "$new_h" == "$old_h" ]] || { ok=0; echo "  handover's Last decisions differ from $BASE's"; diff <(echo "$old_h") <(echo "$new_h") | head -6; }
t AC4 "$ok" "with no test lines, preserve's and handover's Last decisions equal $BASE's"

# ---------- AC5: test lines are hidden from display ----------
ok=1
D="$TMP/ac5"; mk "$D" GENERATE
rec "$ROOT/tests/lib" "$D" stop_guard HALT "real halt R1"
for i in $(seq 1 13); do rec "$ROOT/tests/lib" "$D" hop_guard DENY "real deny r$i"; done
BDD_LOG_SRC=test rec "$ROOT/tests/lib" "$D" stop_guard HALT "fixture halt F0"
for i in $(seq 1 20); do BDD_LOG_SRC=test rec "$ROOT/tests/lib" "$D" bash_guard DENY "fixture deny f$i"; done
out="$(py "$ROOT/tests/lib" "
import decisions, recall
t = decisions.tail('$D', 12)
print('tail', 'ok' if 'fixture' not in t and 'real deny r13' in t and 'src=' not in t else repr(t[:200]))
h = recall.halt('$D') or ''
print('halt', 'ok' if 'real halt R1' in h and 'src=' not in h else repr(h))
" 2>&1)"
for k in tail halt; do grep -q "^$k ok" <<< "$out" || { ok=0; echo "  $k: $(grep "^$k" <<< "$out" || echo "$out" | head -2)"; }; done
p="$(pj "$D" compact | lastdec)"
grep -q 'fixture' <<< "$p" && { ok=0; echo "  preserve's Last decisions show fixture lines"; }
grep -q 'real deny r13' <<< "$p" || { ok=0; echo "  preserve's Last decisions miss the newest real line"; }
all="$(python3 -B "$D/tests/lib/decisions.py" "$D" --tail-all 100 2>&1)"
grep -q 'fixture deny f20.*src=test' <<< "$all" || { ok=0; echo "  --tail-all does not show the test lines with their field"; }
t AC5 "$ok" "tail(), preserve and recall.halt hide src=test lines; --tail-all shows them"

# ---------- AC6: the loop tags its goal line, not itself ----------
ok=1
D="$TMP/ac6"; mk "$D" GENERATE
printf 'python3 -B tests/lib/decisions.py . probe NOTE t103probe\n' > "$D/probe.sh"
git -C "$D" add -A && git -C "$D" commit -qm probe
( cd "$D" && bash tests/oracle.sh --write --run "bash probe.sh" probe.sh >/dev/null 2>&1 )
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n' > "$D/docs/cascade/hop-state.md"
printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\nVALIDATOR: bash probe.sh\n```\n' > "$D/docs/cascade/goal.md"
git -C "$D" add -A && git -C "$D" commit -qm execute
rm -f "$D/.cascade/decisions.log"
lo="$(cd "$D" && bash tests/loop.sh 2>&1)"
grep -q '^LOOP 1/1' <<< "$lo" || { ok=0; echo "  the scratch loop did not reach LOOP 1/1: $(grep -E '^(LOOP|FAIL)' <<< "$lo" | head -3)"; }
grep -q 't103probe  src=test$' "$D/.cascade/decisions.log" 2>/dev/null || { ok=0; echo "  the goal line's record is not src=test: $(grep t103probe "$D/.cascade/decisions.log" 2>/dev/null)"; }
grep -qE 'loop +PASS .*  src=agent$' "$D/.cascade/decisions.log" 2>/dev/null || { ok=0; echo "  the loop's own PASS record is not src=agent: $(grep 'loop ' "$D/.cascade/decisions.log" 2>/dev/null)"; }
t AC6 "$ok" "loop.sh: the goal line writes src=test, the loop's own PASS line src=agent"

# ---------- AC7: the suites export the tag ----------
ok=1
for f in tests/enforcement.sh tests/regress.sh tests/barbar.sh; do
  grep -qE '^export BDD_LOG_SRC=test( |$)' "$ROOT/$f" || { ok=0; echo "  $f has no 'export BDD_LOG_SRC=test' line"; }
done
D="$TMP/ac7"; mk "$D" NONE
printf '# regress\n\nREGRESS: python3 -B tests/lib/decisions.py . probe NOTE t103regress\n' > "$D/docs/cascade/regress.md"
git -C "$D" add -A && git -C "$D" commit -qm regress
( cd "$D" && bash tests/regress.sh >/dev/null 2>&1 )
grep -q 't103regress  src=test$' "$D/.cascade/decisions.log" 2>/dev/null || { ok=0; echo "  a regress line's record is not src=test: $(cat "$D/.cascade/decisions.log" 2>/dev/null)"; }
t AC7 "$ok" "enforcement, regress and barbar export BDD_LOG_SRC=test; a regress line writes src=test"

[[ $fail -eq 0 ]] && echo "t103: all AC PASS" || echo "t103: FAIL"
exit "$fail"
