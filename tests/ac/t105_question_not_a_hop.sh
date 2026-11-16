#!/usr/bin/env bash
# AC tests for 05b t105-question-not-a-hop: the Stop hook tells an answer from hop work by what the prompt wrote (the
# tree), not by the reply's words. A reply that wrote nothing in this prompt needs no edge line and logs no NOEDGE.
#   AC1  an open GENERATE hop: a reply that wrote nothing gets no nudge and no NOEDGE line (a PASS line instead).
#   AC2  an open EXECUTE hop: the same.
#   AC3  a write still needs the edge line: a tracked file, a new file, docs/cascade/, a staged change, a commit — in
#        GENERATE and EXECUTE. A write only under .cascade/, or one made before the prompt, is not this prompt's write.
#   AC4  no record means the old verdict: a session with no prompt record, or another session's record, gets NOEDGE.
#   AC5  no verdict is weaker: an edge line with a red spec gate is NOSPECGATE, an accept with no loop is NOEVID, a
#        halt with no WHAT TO DO is NOHALTBLOCK — each on a reply that wrote nothing.
#   AC6  red twin: a Stop hook that reads the reply text ("?" at the end means an answer) lets an unfinished hop pass
#        where the real one sends it back.
#   AC7  the prompt hook records the tree per session in the git dir, adds no context byte, and both hooks stay fast.
#   AC8  t107 and t106 tests still pass; USAGE.md B26; release 3.5.9 or later.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOG_SRC BDD_HOOK_HOST PLUGIN_ROOT CLAUDE_PLUGIN_ROOT BDD_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------- fixture: a copy of this tree as on disk, its own git repo, an open hop ----------
F="$TMP/f"; mkdir -p "$F"
( cd "$ROOT" && git ls-files -z -co --exclude-standard | python3 -B -c '
import os, sys
sys.stdout.write("\0".join(p for p in sys.stdin.read().split("\0") if p and os.path.isfile(p)))' \
  | tar --null -T - -cf - ) | tar -x -C "$F"
rm -rf "$F/.cascade"; mkdir -p "$F/.cascade"
git -C "$F" init -q
hop() {  # hop <HOP> <stage>: commit the hop state (the commit is before the prompt, so it is not this prompt's write)
  python3 - "$F/docs/cascade/hop-state.md" "$1" "$2" <<'PY'
import re, sys
p, h, st = sys.argv[1:]
s = open(p).read()
s = re.sub(r"(?m)^CURRENT_HOP:.*$", f"CURRENT_HOP: {h}", s, count=1)
s = re.sub(r"(?m)^CURRENT_STAGE:.*$", f"CURRENT_STAGE: {st}", s, count=1)
s = re.sub(r"(?m)^CURRENT_SLICE:.*$", "CURRENT_SLICE: t105-fixture", s, count=1)
s = re.sub(r"(?m)^AUTOPILOT:.*$", "AUTOPILOT:", s)
open(p, "w").write(s)
PY
  git -C "$F" add -A && git -C "$F" commit -qm "hop $1 $2"
}
hop GENERATE 05b
HOOKS="$F/.claude/hooks"
run_hook() {  # run_hook <script or "twin"> <event json> -> stdout of the hook
  if [[ "$1" == twin ]]; then
    python3 -B - "$HOOKS" "$2" <<'PY'
import io, json, os, sys
hooks, data = sys.argv[1], sys.argv[2]
sys.path.insert(0, hooks)
import stop_guard as sg
ev = json.loads(data)
# the red twin: "an answer" decided by the reply's words, not by the tree
sg.wrote_this_prompt = lambda root, session: not (ev.get("last_assistant_message") or "").rstrip().endswith("?")
sys.stdin = io.StringIO(data)
sg.main()
PY
  else
    printf '%s' "$2" | ( cd "$F" && env -u CASCADE_HUMAN python3 -B "$HOOKS/$1" )
  fi
}
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }
prompt() {  # prompt <session>: a human prompt arrives (the prompt hook runs)
  run_hook seam.py "{\"cwd\": \"$F\", \"prompt\": \"what does this do?\", \"prompt_id\": \"$(uid)\", \"session_id\": \"$1\", \"hook_event_name\": \"UserPromptSubmit\"}" >/dev/null
}
stop() {  # stop <session> <reply> [twin]: the reply ends; prints the agent nudge ("" when none)
  local ev
  ev="$(python3 -c 'import json, sys; print(json.dumps({"cwd": sys.argv[1], "session_id": sys.argv[2], "prompt_id": sys.argv[3], "hook_event_name": "Stop", "last_assistant_message": sys.argv[4]}))' "$F" "$1" "$(uid)" "$2")"
  run_hook "${3:-stop_guard.py}" "$ev" | python3 -c '
import json, sys
s = sys.stdin.read().strip()
d = json.loads(s) if s else {}
print((d.get("hookSpecificOutput") or {}).get("additionalContext") or d.get("reason") or "")'
}
count() { local n; n="$(grep -c "  $1 " "$F/.cascade/decisions.log" 2>/dev/null)"; echo "${n:-0}"; }   # 0 before the log exists
clean() { git -C "$F" reset -q --hard HEAD; git -C "$F" clean -qfd -e .cascade; }

# ---------- AC1: GENERATE, nothing written ----------
ok=1
n0="$(count NOEDGE)"; p0="$(count PASS)"
prompt s1
out="$(stop s1 "It runs the loop and prints LOOP k/n.")"
[[ -z "$out" ]] || { ok=0; echo "      GENERATE answer got a nudge: ${out:0:120}"; }
[[ "$(count NOEDGE)" == "$n0" ]] || { ok=0; echo "      GENERATE answer logged NOEDGE"; }
[[ "$(count PASS)" -gt "$p0" ]] || { ok=0; echo "      GENERATE answer logged no PASS line"; }
t AC1 "$ok" "an open GENERATE hop: a reply that wrote nothing in this prompt gets no nudge and no NOEDGE line, and logs PASS"

# ---------- AC2: EXECUTE, nothing written ----------
ok=1
hop EXECUTE 05b
n0="$(count NOEDGE)"
prompt s2
out="$(stop s2 "The loop failed on lint; here is why.")"
[[ -z "$out" ]] || { ok=0; echo "      EXECUTE answer got a nudge: ${out:0:120}"; }
[[ "$(count NOEDGE)" == "$n0" ]] || { ok=0; echo "      EXECUTE answer logged NOEDGE"; }
t AC2 "$ok" "an open EXECUTE hop: a reply that wrote nothing in this prompt gets no nudge and no NOEDGE line"

# ---------- AC3: a write still needs the edge line ----------
ok=1
writes() {  # writes <kind>: one kind of write, during the prompt
  case "$1" in
    tracked) echo "# x" >> "$F/README.md" ;;
    new)     echo x > "$F/newfile.txt" ;;
    cascade) echo x >> "$F/docs/cascade/05b-briefs.md" ;;
    staged)  git -C "$F" add README.md ;;
    commit)  echo x > "$F/c.txt"; git -C "$F" add c.txt; git -C "$F" commit -qm c ;;
  esac
}
for h in GENERATE EXECUTE; do
  hop "$h" 05b
  for kind in tracked new cascade staged commit; do
    [[ "$kind" == staged ]] && echo "# before the prompt" >> "$F/README.md"   # the change itself predates the prompt
    n0="$(count NOEDGE)"
    prompt "w-$h-$kind"
    writes "$kind"
    out="$(stop "w-$h-$kind" "Done with that part.")"
    [[ "$out" == *"Hop not closed (I1)"* && "$(count NOEDGE)" -gt "$n0" ]] \
      || { ok=0; echo "      $h, $kind write, no edge line: no nudge or no NOEDGE (${out:0:60})"; }
    [[ "$kind" == commit ]] && git -C "$F" reset -q --hard HEAD~1
    clean
  done
done
hop GENERATE 05b
prompt only-cascade; echo x > "$F/.cascade/scratch.log"
out="$(stop only-cascade "Here is the log.")"
[[ -z "$out" ]] || { ok=0; echo "      a write only under .cascade/ was taken as hop work"; }
prompt before; echo "# earlier" >> "$F/README.md"   # one session, two prompts: the write is in the first one only
out="$(stop before "Done with that part.")"
[[ "$out" == *"Hop not closed (I1)"* ]] || { ok=0; echo "      the first prompt's write got no nudge"; }
prompt before   # the next human prompt records the tree again
out="$(stop before "That edit is from your last request.")"
[[ -z "$out" ]] || { ok=0; echo "      a change made before this prompt (same session) was taken as this prompt's write"; }
clean
t AC3 "$ok" "a write in this prompt (tracked, new, docs/cascade/, staged, commit; GENERATE and EXECUTE) still needs the edge line and logs NOEDGE; .cascade/ only, or a change from before the prompt, does not"

# ---------- AC4: no record, the old verdict ----------
ok=1
n0="$(count NOEDGE)"
out="$(stop never-prompted "An answer.")"
[[ "$out" == *"Hop not closed (I1)"* && "$(count NOEDGE)" -gt "$n0" ]] || { ok=0; echo "      a session with no record passed"; }
prompt other-a
n0="$(count NOEDGE)"
out="$(stop other-b "An answer.")"
[[ "$out" == *"Hop not closed (I1)"* && "$(count NOEDGE)" -gt "$n0" ]] || { ok=0; echo "      another session's record was used"; }
t AC4 "$ok" "no record of this session's prompt (none, or another session's) gives the old verdict: nudge and NOEDGE"

# ---------- AC5: no verdict is weaker ----------
ok=1
hop GENERATE 05b   # the fixture slice has no critique and no oracle: the spec gate is red
prompt g5
out="$(stop g5 "STITCH NEEDED: review spec+plan for stage 05b")"
[[ "$out" == *"spec gate is red"* ]] || { ok=0; echo "      an edge line with a red spec gate was not sent back: ${out:0:80}"; }
hop EXECUTE 05b
prompt e5
out="$(stop e5 "STITCH NEEDED: accept execute for stage 05b, or send back")"
[[ "$out" == *"without evidence"* ]] || { ok=0; echo "      an accept with no loop was not sent back: ${out:0:80}"; }
prompt h5
out="$(stop h5 "AUTOPILOT HALT: blocked")"
[[ "$out" == *"missing its instruction block"* ]] || { ok=0; echo "      a halt with no WHAT TO DO was not sent back: ${out:0:80}"; }
t AC5 "$ok" "on replies that wrote nothing: an edge line with a red spec gate (NOSPECGATE), an accept with no loop (NOEVID) and a halt with no WHAT TO DO (NOHALTBLOCK) are still sent back"

# ---------- AC6: the red twin reads the words ----------
ok=1
hop GENERATE 05b
prompt r6; echo x > "$F/work.txt"
real="$(stop r6 "Is this the shape you want?")"
prompt r6t; echo y >> "$F/work.txt"
twin="$(stop r6t "Is this the shape you want?" twin)"
[[ "$real" == *"Hop not closed (I1)"* ]] || { ok=0; echo "      the real hook let a reply that wrote a file pass because it ended with '?'"; }
[[ -z "$twin" ]] || { ok=0; echo "      the red twin (reply text) did not let the unfinished hop pass — the scenario does not tell the two apart"; }
clean
t AC6 "$ok" "red twin: a hook that calls a reply ending in '?' an answer lets a hop that wrote a file pass; the real hook sends it back"

# ---------- AC7: the record, the context, the time ----------
ok=1
prompt rec7
gd="$(git -C "$F" rev-parse --absolute-git-dir)"
[[ -s "$gd/cascade-tree-rec7" ]] || { ok=0; echo "      no record at <git dir>/cascade-tree-rec7"; }
[[ -z "$(git -C "$F" status --porcelain)" ]] || { ok=0; echo "      the record changed the tree: $(git -C "$F" status --porcelain | head -2)"; }
python3 - "$F" "$ROOT" <<'PY' || ok=0
import json, os, subprocess, sys, time, uuid
f, root = sys.argv[1:]
env = {k: v for k, v in os.environ.items() if not k.startswith(("CASCADE_", "BDD_", "CLAUDE"))}
def ctx(hooks):
    ev = {"cwd": f, "prompt": "continue", "prompt_id": uuid.uuid4().hex, "session_id": "ctx7", "hook_event_name": "UserPromptSubmit"}
    t0 = time.time()
    r = subprocess.run([sys.executable, "-B", os.path.join(hooks, "seam.py")], input=json.dumps(ev), capture_output=True,
                       text=True, env=env, cwd=f, timeout=120)
    return (json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"] if r.stdout.strip() else ""), time.time() - t0
new, dt = ctx(os.path.join(f, ".claude", "hooks"))
bad = []
if "cascade-tree" in new or "fingerprint" in new.lower():
    bad.append("the prompt context mentions the record")
if dt > 5:
    bad.append(f"the prompt hook took {dt:.1f}s")
t0 = time.time()
ev = {"cwd": f, "session_id": "ctx7", "prompt_id": uuid.uuid4().hex, "hook_event_name": "Stop", "last_assistant_message": "ok"}
subprocess.run([sys.executable, "-B", os.path.join(f, ".claude", "hooks", "stop_guard.py")], input=json.dumps(ev),
               capture_output=True, text=True, env=env, cwd=f, timeout=120)
if time.time() - t0 > 5:
    bad.append(f"the stop hook took {time.time() - t0:.1f}s")
for b in bad:
    print("      " + b)
sys.exit(1 if bad else 0)
PY
t AC7 "$ok" "the prompt hook records the tree in <git dir>/cascade-tree-<session> (the tree is unchanged), the prompt context does not mention it, and each hook finishes in under 5 s"

# ---------- AC8: earlier slices; docs and release ----------
ok=1
for x in t107_lesson_recall t106_lessons; do
  bash "$ROOT/tests/ac/$x.sh" > "$TMP/$x.out" 2>&1 || { ok=0; echo "      tests/ac/$x.sh fails:"; grep -E '^FAIL' "$TMP/$x.out" | sed 's/^/        /'; }
done
if ! grep -q '^### B26\.' "$ROOT/USAGE.md" || ! grep -q 'cascade-tree' "$ROOT/USAGE.md"; then
  ok=0; echo "      USAGE.md has no B26 naming the cascade-tree record"
fi
python3 - "$ROOT" <<'PY' || ok=0
import json, os, sys
r = sys.argv[1]
v = open(os.path.join(r, "VERSION")).read().strip()
num = lambda s: tuple(int(x) for x in s.split("."))
# t105 shipped in 3.5.9: any later release passes (no exact pin)
bad = [] if num(v) >= (3, 5, 9) else [f"VERSION is {v}, want 3.5.9 or later"]
for p in (".claude-plugin/plugin.json", ".codex-plugin/plugin.json"):
    if json.load(open(os.path.join(r, p))).get("version") != v:
        bad.append(f"{p} is not {v}")
if v not in json.dumps(json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))):
    bad.append(f".claude-plugin/marketplace.json does not show {v}")
if "## 3.5.9" not in open(os.path.join(r, "CHANGELOG.md")).read():
    bad.append("CHANGELOG.md has no ## 3.5.9")
if "3.5.9" not in open(os.path.join(r, "README.md")).read():
    bad.append("README.md does not show 3.5.9")
for b in bad:
    print("      " + b)
sys.exit(1 if bad else 0)
PY
t AC8 "$ok" "tests/ac/t107_lesson_recall.sh and tests/ac/t106_lessons.sh still pass; USAGE.md B26 names the cascade-tree record; 3.5.9 or later in VERSION and the manifests; CHANGELOG.md and README.md show 3.5.9"

[[ $fail -eq 0 ]] && echo "T105 AC all PASS" || echo "T105 AC FAILED"
exit $fail
