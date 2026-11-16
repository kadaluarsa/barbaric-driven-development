#!/usr/bin/env bash
# AC tests for 05b t108-work-in-flight: the Stop hook never demands an edge that its own next check would refuse.
#   AC1  a live tests/loop.sh lock (live pid, or no pid yet and under a minute old) is work in flight: a reply that
#        wrote files and has no edge line gets no nudge and no NOEDGE line, and logs PASS — on GENERATE and EXECUTE.
#   AC2  a broken lock gives no pass: a dead pid, or no pid and over a minute old, is judged as if there were no lock.
#   AC3  no work in flight: GENERATE 05b with a red spec gate, and EXECUTE with no loop receipt for this tree, each get
#        a nudge that names the step ("Hop not finished (I1)") and log UNFINISHED, not NOEDGE.
#   AC4  no verdict is weaker: a green spec gate (GENERATE 05b), a fresh receipt (EXECUTE), stage 10 and a GENERATE
#        outside 05b, with no edge line, still get "Hop not closed (I1)" and NOEDGE.
#   AC5  edges are judged as before while a lock is live: an accept with no receipt is NOEVID, an edge with a red spec
#        gate is NOSPECGATE, a halt with no WHAT TO DO is NOHALTBLOCK.
#   AC6  red twin: a hook that trusts the reply's words ("waiting for the loop") lets an unfinished hop pass with no lock;
#        the real hook sends it back.
#   AC7  t105 (with its widened checks) and t63 still pass; a stop takes under 5 s; USAGE.md B27; release 3.5.10 or later.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOG_SRC BDD_HOOK_HOST PLUGIN_ROOT CLAUDE_PLUGIN_ROOT BDD_PLUGIN_ROOT \
      BDD_LOOP_LOCKED
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; SLEEPER=""
trap '[[ -n "$SLEEPER" ]] && kill "$SLEEPER" 2>/dev/null; rm -rf "$TMP"' EXIT

# ---------- fixture: a copy of this tree as on disk, its own git repo ----------
F="$TMP/f"; mkdir -p "$F"
( cd "$ROOT" && git ls-files -z -co --exclude-standard | python3 -B -c '
import os, sys
sys.stdout.write("\0".join(p for p in sys.stdin.read().split("\0") if p and os.path.isfile(p)))' \
  | tar --null -T - -cf - ) | tar -x -C "$F"
rm -rf "$F/.cascade"; mkdir -p "$F/.cascade"
git -C "$F" init -q
GD="$(git -C "$F" rev-parse --absolute-git-dir)"
LOCK="$GD/cascade-loop.lock"
hop() {  # hop <HOP> <stage>: commit the hop state before the prompt
  python3 - "$F/docs/cascade/hop-state.md" "$1" "$2" <<'PY'
import re, sys
p, h, st = sys.argv[1:]
s = open(p).read()
s = re.sub(r"(?m)^CURRENT_HOP:.*$", f"CURRENT_HOP: {h}", s, count=1)
s = re.sub(r"(?m)^CURRENT_STAGE:.*$", f"CURRENT_STAGE: {st}", s, count=1)
s = re.sub(r"(?m)^CURRENT_SLICE:.*$", "CURRENT_SLICE: t108-fixture", s, count=1)
s = re.sub(r"(?m)^AUTOPILOT:.*$", "AUTOPILOT:", s)
open(p, "w").write(s)
PY
  git -C "$F" add -A && { git -C "$F" commit -qm "hop $1 $2" >/dev/null || true; }
}
HOOKS="$F/.claude/hooks"
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }
prompt() {  # prompt <session>: a human prompt (the prompt hook records the tree)
  printf '{"cwd": "%s", "prompt": "go on", "prompt_id": "%s", "session_id": "%s", "hook_event_name": "UserPromptSubmit"}' \
    "$F" "$(uid)" "$1" | ( cd "$F" && python3 -B "$HOOKS/seam.py" ) >/dev/null
}
stop() {  # stop <session> <reply> [twin]: prints the agent nudge ("" when none)
  local ev
  ev="$(python3 -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "session_id": sys.argv[2], "prompt_id": sys.argv[3], "hook_event_name": "Stop", "last_assistant_message": sys.argv[4]}))' "$F" "$1" "$(uid)" "$2")"
  if [[ "${3:-}" == twin ]]; then
    ( cd "$F" && python3 -B - "$HOOKS" "$ev" <<'PY'
import io, json, sys
hooks, data = sys.argv[1], sys.argv[2]
sys.path.insert(0, hooks)
import stop_guard as sg
ev = json.loads(data)
# the red twin: "work in flight" decided by the reply's words, not by the lock
sg.loop_in_flight = lambda root: "waiting for the loop" in (ev.get("last_assistant_message") or "")
sys.stdin = io.StringIO(data)
sg.main()
PY
    )
  else
    printf '%s' "$ev" | ( cd "$F" && python3 -B "$HOOKS/stop_guard.py" )
  fi | python3 -c '
import json, sys
s = sys.stdin.read().strip()
d = json.loads(s) if s else {}
print((d.get("hookSpecificOutput") or {}).get("additionalContext") or d.get("reason") or "")'
}
count() { local n; n="$(grep -c "  $1 " "$F/.cascade/decisions.log" 2>/dev/null)"; echo "${n:-0}"; }
clean() { git -C "$F" reset -q --hard HEAD; git -C "$F" clean -qfd -e .cascade; rm -f "$F/.cascade/loop-receipt"; }
work() {  # work <session>: a prompt, then a write in it (so t105 does not call the reply an answer)
  prompt "$1"; echo "$1" >> "$F/work.txt"
}
live_lock() { rm -rf "$LOCK"; mkdir "$LOCK"; sleep 300 & SLEEPER=$!; echo "$SLEEPER" > "$LOCK/pid"; }
no_lock() { [[ -n "$SLEEPER" ]] && kill "$SLEEPER" 2>/dev/null; SLEEPER=""; rm -rf "$LOCK"; }
age() { python3 -c 'import os, sys, time; t = time.time() - float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }

# ---------- AC1: a live lock is work in flight ----------
ok=1
for h in GENERATE EXECUTE; do
  hop "$h" 05b; live_lock
  n0="$(count NOEDGE)"; u0="$(count UNFINISHED)"; p0="$(count PASS)"
  work "a1-$h"
  out="$(stop "a1-$h" "The loop runs in the background; I will report it.")"
  [[ -z "$out" ]] || { ok=0; echo "      $h, live lock: got a nudge: ${out:0:100}"; }
  [[ "$(count NOEDGE)" == "$n0" && "$(count UNFINISHED)" == "$u0" ]] || { ok=0; echo "      $h, live lock: logged NOEDGE or UNFINISHED"; }
  grep -q "stop_guard  PASS    $h 05b work in flight" "$F/.cascade/decisions.log" || { ok=0; echo "      $h, live lock: no 'work in flight' PASS line"; }
  no_lock; clean
done
hop EXECUTE 05b; rm -rf "$LOCK"; mkdir "$LOCK"   # no pid yet, just made: live for its first minute
work a1-nopid
out="$(stop a1-nopid "Starting.")"
[[ -z "$out" ]] || { ok=0; echo "      a lock with no pid, under a minute old, was not work in flight"; }
no_lock; clean
t AC1 "$ok" "a live loop lock (live pid, or no pid and under a minute old) on GENERATE and EXECUTE: a reply that wrote, with no edge line, gets no nudge and no NOEDGE/UNFINISHED, and logs 'work in flight' PASS"

# ---------- AC2: a broken lock is no lock ----------
ok=1
hop EXECUTE 05b
rm -rf "$LOCK"; mkdir "$LOCK"; sleep 0 & dead=$!; wait "$dead" 2>/dev/null; echo "$dead" > "$LOCK/pid"
work a2-dead
out="$(stop a2-dead "The loop runs.")"
[[ "$out" == *"Hop not finished (I1)"* ]] || { ok=0; echo "      a lock with a dead pid passed: ${out:0:80}"; }
rm -rf "$LOCK"; mkdir "$LOCK"; age "$LOCK" 120
work a2-old
out="$(stop a2-old "The loop runs.")"
[[ "$out" == *"Hop not finished (I1)"* ]] || { ok=0; echo "      a lock with no pid, two minutes old, passed: ${out:0:80}"; }
no_lock; clean
t AC2 "$ok" "a broken lock (dead pid, or no pid and over a minute old) is judged as no lock: the reply is sent back"

# ---------- AC3: the unfinished step is named, and is not NOEDGE ----------
ok=1
hop GENERATE 05b   # the fixture slice has no spec, critique or oracle: the spec gate is red
n0="$(count NOEDGE)"; u0="$(count UNFINISHED)"
work a3-g
out="$(stop a3-g "Spec drafted.")"
[[ "$out" == *"Hop not finished (I1)"* && "$out" == *"spec gate is red"* && "$out" != *"STITCH NEEDED: review"* ]] \
  || { ok=0; echo "      GENERATE 05b, red gate: wrong nudge: ${out:0:120}"; }
[[ "$(count NOEDGE)" == "$n0" && "$(count UNFINISHED)" -gt "$u0" ]] || { ok=0; echo "      GENERATE 05b, red gate: not logged as UNFINISHED (or NOEDGE logged)"; }
clean
hop EXECUTE 05b
n0="$(count NOEDGE)"; u0="$(count UNFINISHED)"
work a3-e
out="$(stop a3-e "Built it.")"
[[ "$out" == *"Hop not finished (I1)"* && "$out" == *"tests/loop.sh"* && "$out" != *"STITCH NEEDED: accept"* ]] \
  || { ok=0; echo "      EXECUTE, no receipt: wrong nudge: ${out:0:120}"; }
[[ "$(count NOEDGE)" == "$n0" && "$(count UNFINISHED)" -gt "$u0" ]] || { ok=0; echo "      EXECUTE, no receipt: not logged as UNFINISHED (or NOEDGE logged)"; }
clean
t AC3 "$ok" "no work in flight: GENERATE 05b with a red spec gate and EXECUTE with no receipt each get 'Hop not finished (I1)' naming the step (not the edge), logged UNFINISHED, not NOEDGE"

# ---------- AC4: no verdict weaker ----------
ok=1
closed() {  # closed <label> <session>: the reply must get the old I1 nudge and a NOEDGE line
  local n0 out; n0="$(count NOEDGE)"
  out="$(stop "$2" "Done.")"
  [[ "$out" == *"Hop not closed (I1)"* && "$(count NOEDGE)" -gt "$n0" ]] || { ok=0; echo "      $1: no 'Hop not closed' nudge or no NOEDGE (${out:0:80})"; }
}
# a green spec gate: the three gates of this fixture exit 0
mkdir -p "$TMP/gates"
for g in critique diverge oracle; do
  cp "$F/tests/$g.sh" "$TMP/gates/$g.sh"
  printf '#!/usr/bin/env bash\necho "%s green (fixture)"\nexit 0\n' "$g" > "$F/tests/$g.sh"
done
hop GENERATE 05b
work a4-g; closed "GENERATE 05b, green gate" a4-g
clean; for g in critique diverge oracle; do cp "$TMP/gates/$g.sh" "$F/tests/$g.sh"; done
git -C "$F" add -A && git -C "$F" commit -qm "gates back" >/dev/null
# a fresh receipt for this tree
hop EXECUTE 05b
work a4-e
sha="$(bash -c '. "$1/tests/lib/cascade.sh"; cascade_worktree_sha "$1"' _ "$F")"
printf 'EXECUTE 05b %s\n' "$sha" > "$F/.cascade/loop-receipt"   # the receipt a passing loop writes for this tree
closed "EXECUTE, fresh receipt" a4-e
clean
hop EXECUTE 10; work a4-10; closed "EXECUTE stage 10" a4-10; clean
hop GENERATE 06; work a4-06; closed "GENERATE 06" a4-06; clean
t AC4 "$ok" "no verdict weaker: a green spec gate, a fresh receipt, stage 10 and GENERATE 06, with no edge line, still get 'Hop not closed (I1)' and NOEDGE"

# ---------- AC5: edges while a lock is live ----------
ok=1
hop EXECUTE 05b; live_lock; work a5-e
out="$(stop a5-e "STITCH NEEDED: accept execute for stage 05b, or send back")"
[[ "$out" == *"without evidence"* ]] || { ok=0; echo "      an accept with no receipt during a live lock was not NOEVID: ${out:0:80}"; }
work a5-h
out="$(stop a5-h "AUTOPILOT HALT: blocked")"
[[ "$out" == *"missing its instruction block"* ]] || { ok=0; echo "      a halt with no WHAT TO DO during a live lock was not sent back: ${out:0:80}"; }
no_lock; clean
hop GENERATE 05b; live_lock; work a5-g
out="$(stop a5-g "STITCH NEEDED: review spec+plan for stage 05b")"
[[ "$out" == *"spec gate is red"* ]] || { ok=0; echo "      an edge with a red spec gate during a live lock was not NOSPECGATE: ${out:0:80}"; }
no_lock; clean
t AC5 "$ok" "while a lock is live: an accept with no receipt is NOEVID, a halt with no WHAT TO DO is NOHALTBLOCK, an edge with a red spec gate is NOSPECGATE"

# ---------- AC6: the red twin trusts the words ----------
ok=1
hop EXECUTE 05b
work a6
real="$(stop a6 "Built it; waiting for the loop.")"
twin="$(stop a6 "Built it; waiting for the loop." twin)"
[[ -n "$real" ]] || { ok=0; echo "      the real hook passed a reply with no lock because it said 'waiting for the loop'"; }
[[ -z "$twin" ]] || { ok=0; echo "      the red twin (reply words) sent it back — the scenario does not tell the two apart"; }
clean
t AC6 "$ok" "red twin: a hook that reads 'waiting for the loop' as work in flight lets an unfinished hop with no lock pass; the real hook sends it back"

# ---------- AC7: earlier slices, cost, docs, release ----------
ok=1
hop EXECUTE 05b; work a7
s0="$(python3 -c 'import time; print(time.time())')"; stop a7 "x" >/dev/null
dt="$(python3 -c "import time; print(time.time() - $s0)")"
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 5 else 1)" "$dt" || { ok=0; echo "      a stop took ${dt}s"; }
clean
for x in t105_question_not_a_hop t63_quiet_stop_guard; do
  bash "$ROOT/tests/ac/$x.sh" > "$TMP/$x.out" 2>&1 || { ok=0; echo "      tests/ac/$x.sh fails:"; grep -E '^FAIL' "$TMP/$x.out" | sed 's/^/        /'; }
done
if ! grep -q '^### B27\.' "$ROOT/USAGE.md" || ! grep -q 'cascade-loop.lock' "$ROOT/USAGE.md"; then
  ok=0; echo "      USAGE.md has no B27 naming cascade-loop.lock"
fi
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
num = lambda s: tuple(int(x) for x in s.split("."))
bad = [] if num(v) >= (3, 5, 10) else [f"VERSION is {v}, want 3.5.10 or later"]   # t108 ships in 3.5.10; later passes
for p in (".claude-plugin/plugin.json", ".codex-plugin/plugin.json"):
    if json.load(open(os.path.join(r, p))).get("version") != v:
        bad.append(f"{p} is not {v}")
if v not in json.dumps(json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))):
    bad.append(f".claude-plugin/marketplace.json does not show {v}")
if "## 3.5.10" not in open(os.path.join(r, "CHANGELOG.md")).read():
    bad.append("CHANGELOG.md has no ## 3.5.10")
if "3.5.10" not in open(os.path.join(r, "README.md")).read():
    bad.append("README.md does not show 3.5.10")
for b in bad:
    print("      " + b)
sys.exit(1 if bad else 0)
PY
t AC7 "$ok" "a stop takes under 5 s; tests/ac/t105_question_not_a_hop.sh and tests/ac/t63_quiet_stop_guard.sh pass; USAGE.md B27 names cascade-loop.lock; 3.5.10 or later in VERSION and the manifests; CHANGELOG.md and README.md show 3.5.10"

[[ $fail -eq 0 ]] && echo "T108 AC all PASS" || echo "T108 AC FAILED"
exit $fail
