#!/usr/bin/env bash
# AC tests for 05b t85-recall-index: after a context break mid-hop, preserve.py adds a computed recall index —
# pointers to files that exist, capped — and changes nothing else. Scratch git repos; preserve.py fed SessionStart.
#   AC1  GENERATE: brief (wrapped, anchored), spec anchors, critique counts, candidates; no goal or loop line.
#   AC2  EXECUTE: goal, last loop pass, an older HALT as a record, commits since the hop opened; a HALT already in
#        the 12-line tail is not repeated.
#   AC3  no dead path: each source removed in turn drops only its line; every printed path exists.
#        RED TWIN: a recall.py that lists the critique without checking it exists.
#   AC4  the cap: ≤25 lines, none over 240 characters. RED TWIN: no cut.
#   AC5  a goal for another slice says so.
#   AC6  NONE and startup: byte-identical with and without recall.py.
#   AC7  a crash before or after printing, or a timeout: no index line, valid JSON, Current hop present.
#        RED TWINS: preserve.py ignoring the exit code keeps partial lines; one with no timeout hangs.
#   AC8  plugin mode with an older pack (no recall.py): one "Recall index unavailable" line on an open hop only.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_RECALL_TIMEOUT BDD_PLUGIN_ROOT \
      PLUGIN_ROOT BDD_HOOK_HOST CLAUDE_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 BDD_AUTO_REFRESH=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOOKS="$ROOT/.claude/hooks"

# mk <dir> <GENERATE|EXECUTE|NONE> — slice a, a wrapped brief, a spec with all three anchors, committed
mk() {
  local d="$1" hop="$2"
  rm -rf "$d"; mkdir -p "$d/docs/cascade" "$d/tests"
  cp "$ROOT/tests/loop.sh" "$d/tests/"; cp -R "$ROOT/tests/lib" "$d/tests/lib"
  find "$d" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  printf '.cascade/\n' > "$d/.gitignore"
  printf '# envelope\n\n## Laws\n\nnone\n' > "$d/docs/cascade/envelope.md"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\n</EDIT>\n' "$hop" > "$d/docs/cascade/hop-state.md"
  printf '# briefs\n\n- z: another slice\n- a: alpha first line of the brief\n  beta second line\n  gamma third line\n- b: next\n' \
    > "$d/docs/cascade/05b-briefs.md"
  printf '# Stage 05b — a — SPEC\n\n## Acceptance criteria\n\n- AC1\n\n# Stage 05b — PLAN\n\n## In scope this execute\n\n- [ ] `lib/a.txt`\n' \
    > "$d/docs/cascade/05b-a.md"
  printf '# goal\n\n```\nGOAL_STAGE: 05b\nGOAL_SLICE: a\nVALIDATOR: true\nVALIDATOR: false\n```\n' > "$d/docs/cascade/goal.md"
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" commit -qm init
}
critique() {  # critique <dir> — 3 findings, 2 answered
  printf '# c\n\n## Brief\n\n| C# | s | f | e |\n|---|---|---|---|\n| C1 | low | x | `y` |\n\n## Spec\n\n| C# | s | f | e |\n|---|---|---|---|\n| C2 | low | x | `y` |\n| C3 | low | x | `y` |\n\n## Dispositions\n\n| C# | D |\n|---|---|\n| C1 | fixed a |\n| C2 | fixed b |\n' \
    > "$1/docs/cascade/05b-a-critique.md"
}
uid() { python3 -c 'import uuid; print(uuid.uuid4().hex)'; }   # a unique event id: callers run in $(…) subshells
pjson() {  # pjson <dir> <source> [hooks dir] — preserve.py's raw stdout
  printf '{"cwd":"%s","source":"%s","session_id":"%s"}' "$1" "$2" "$(uid)" | (cd "$1" && python3 -B "${3:-$HOOKS}/preserve.py")
}
ctx() { pjson "$@" | python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["hookSpecificOutput"]["additionalContext"] if t.strip() else "")'; }
idx() { ctx "$@" | sed -n '/^Recall index/,/^Domain laws/p' | grep '^  ' | sed 's/^  //'; }
has() { grep -qF -- "$2" <<< "$1"; }
paths_exist() {  # every docs/… or .cascade/… path the index names exists
  local d="$1" p ok=1
  for p in $(grep -oE '(docs/cascade/[A-Za-z0-9._-]+\.md|\.cascade/[a-z.-]+)' <<< "$2" | sort -u); do
    [[ -e "$d/$p" ]] || { ok=0; echo "    missing: $p" >&2; }
  done
  echo $ok
}

# ---- AC1 GENERATE -----------------------------------------------------------------------------------------------
D="$TMP/ac1"; mk "$D" GENERATE; critique "$D"; echo cand > "$D/docs/cascade/05b-a-candidates.md"
i="$(idx "$D" compact)"
bl="$(grep -oE '05b-briefs\.md:[0-9]+' <<< "$i" | cut -d: -f2)"
pl="$(grep -oE 'plan :[0-9]+' <<< "$i" | grep -oE '[0-9]+')"; al="$(grep -oE 'AC :[0-9]+' <<< "$i" | grep -oE '[0-9]+')"
sl="$(grep -oE 'scope :[0-9]+' <<< "$i" | grep -oE '[0-9]+')"
t AC1a "$([[ -n "$bl" && "$(sed -n "${bl}p" "$D/docs/cascade/05b-briefs.md")" == "- a:"* ]] && has "$i" "gamma third line" && echo 1 || echo 0)" \
  "brief: anchored at its '- a:' line, wrapped lines joined"
t AC1b "$([[ "$(sed -n "${pl}p" "$D/docs/cascade/05b-a.md")" == "# Stage 05b — PLAN" && "$(sed -n "${al}p" "$D/docs/cascade/05b-a.md")" == "## Acceptance criteria" \
         && "$(sed -n "${sl}p" "$D/docs/cascade/05b-a.md")" == "## In scope this execute" ]] && echo 1 || echo 0)" "spec: plan, AC and scope anchors point at their headings"
t AC1c "$(has "$i" "(3 findings, 2 answered)" && has "$i" "candidates docs/cascade/05b-a-candidates.md" && echo 1 || echo 0)" "critique counts and candidates path"
t AC1d "$( ! grep -qE '^(goal|loop) ' <<< "$i" && [[ "$(paths_exist "$D" "$i")" == 1 ]] && echo 1 || echo 0)" "no goal or loop line on GENERATE; every path exists"

# ---- AC2 EXECUTE ------------------------------------------------------------------------------------------------
D="$TMP/ac2"; mk "$D" EXECUTE; critique "$D"
(cd "$D" && bash tests/loop.sh >/dev/null 2>&1)
{ echo "2026-11-01T00:00:00Z  stop_guard  HALT    AUTOPILOT HALT: old reason"
  for n in $(seq 1 20); do echo "2026-11-01T00:00:${n}Z  loop  PASS  filler $n"; done; } >> "$D/.cascade/decisions.log"
echo x > "$D/new.txt"; git -C "$D" add new.txt; git -C "$D" commit -qm "work on a"
i="$(idx "$D" resume)"
t AC2a "$(has "$i" "goal       docs/cascade/goal.md  (for a; 2 validators)" && echo 1 || echo 0)" "goal line"
t AC2b "$(grep -qE '^loop .*LOOP 1/2, FAIL  false' <<< "$i" && echo 1 || echo 0)" "loop line: LOOP 1/2 and the failing validator"
t AC2c "$(has "$i" "record: 2026-11-01T00:00:00Z stop_guard HALT AUTOPILOT HALT: old reason" && echo 1 || echo 0)" "an older HALT, quoted as a record"
t AC2d "$(has "$i" "commits    1 since the hop opened" && has "$i" "newest: work on a" && echo 1 || echo 0)" "commits since the hop opened"
echo "2026-11-02T00:00:00Z  stop_guard  WATCHDOG stalled" >> "$D/.cascade/decisions.log"
i="$(idx "$D" resume)"
t AC2e "$( ! grep -q '^halt ' <<< "$i" && echo 1 || echo 0)" "a halt already in the 12-line tail is not repeated"

# ---- AC3 no dead path -------------------------------------------------------------------------------------------
base_ok() { mk "$1" EXECUTE; critique "$1"; echo c > "$1/docs/cascade/05b-a-candidates.md"; (cd "$1" && bash tests/loop.sh >/dev/null 2>&1)
            echo "2026-11-01T00:00:00Z  stop_guard  HALT    x" >> "$1/.cascade/decisions.log"
            for n in $(seq 1 13); do echo "2026-11-01T00:00:${n}Z  loop  PASS  f" >> "$1/.cascade/decisions.log"; done; }
ok=1
for case in critique candidates spec goal history foreign decisions base; do
  D="$TMP/ac3-$case"; base_ok "$D"
  case "$case" in
    critique)   rm "$D/docs/cascade/05b-a-critique.md"; gone='^critique ' ;;
    candidates) rm "$D/docs/cascade/05b-a-candidates.md"; gone='^candidates ' ;;
    spec)       rm "$D/docs/cascade/05b-a.md"; gone='^spec ' ;;
    goal)       rm "$D/docs/cascade/goal.md"; gone='^goal ' ;;
    history)    rm "$D/.cascade/loop-history"; gone='^loop ' ;;
    foreign)    sed -i.bak 's/\t05b\ta\t/\t05b\tz\t/' "$D/.cascade/loop-history"; rm -f "$D/.cascade/loop-history.bak"; gone='^loop ' ;;
    decisions)  rm "$D/.cascade/decisions.log"; gone='^halt ' ;;
    base)       sed 's/^CURRENT_SLICE: a$/CURRENT_SLICE: zz/' "$D/docs/cascade/hop-state.md" > "$TMP/hs"; cp "$D/docs/cascade/hop-state.md" "$TMP/hs-a"
                cp "$TMP/hs" "$D/docs/cascade/hop-state.md"; git -C "$D" commit -qam other; cp "$TMP/hs-a" "$D/docs/cascade/hop-state.md"; gone='^commits ' ;;
  esac
  i="$(idx "$D" compact)"
  if grep -qE "$gone" <<< "$i" || ! grep -q '^brief ' <<< "$i" || [[ "$(paths_exist "$D" "$i")" != 1 ]]; then ok=0; echo "  AC3 case $case:"; sed 's/^/    /' <<< "$i"; fi
done
t AC3 "$ok" "each missing source drops only its own line (critique, candidates, spec, goal, history, foreign history, decisions, hop base); every printed path exists"
mkdir -p "$TMP/lib3"; cp -R "$ROOT/tests/lib/." "$TMP/lib3/"
python3 - "$TMP/lib3/recall.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('''    text = read(root, path)
    if text is None:
        return None
    k = sum''', '''    text = read(root, path) or ""
    k = sum'''); open(p,"w").write(s)
PY
D="$TMP/ac3t"; mk "$D" GENERATE; rm -rf "$D/tests/lib"; cp -R "$TMP/lib3" "$D/tests/lib"
t AC3t "$(grep -q '^critique ' <<< "$(idx "$D" compact)" && echo 1 || echo 0)" "RED TWIN: a recall.py without the exists check lists a missing critique"

# ---- AC4 the cap ------------------------------------------------------------------------------------------------
cap_fixture() {
  mk "$1" EXECUTE; critique "$1"; mkdir -p "$1/.cascade"
  python3 - "$1" <<'PY'
import sys; d=sys.argv[1]
long = " ".join(["word%03d" % i for i in range(110)])
lines = open(d + "/docs/cascade/05b-briefs.md").read().replace("- a: alpha first line of the brief\n",
        "- a: " + "\n  ".join(long[j:j+110] for j in range(0, len(long), 110)) + "\n")
open(d + "/docs/cascade/05b-briefs.md", "w").write(lines)
with open(d + "/.cascade/decisions.log", "w") as f:
    f.write("2026-11-01T00:00:00Z  stop_guard  HALT    " + "x" * 600 + "\n")
    for n in range(3000):
        f.write("2026-11-01T00:00:00Z  loop  PASS  filler %d\n" % n)
PY
}
D="$TMP/ac4"; cap_fixture "$D"; i="$(idx "$D" compact)"
t AC4 "$([[ "$(wc -l <<< "$i" | tr -d ' ')" -le 25 && "$(awk 'length($0) > 240' <<< "$i" | wc -l | tr -d ' ')" == 0 ]] && has "$i" "word000" && echo 1 || echo 0)" \
  "≤25 index lines, none over 240 characters (8-line brief, 3000-line log)"
mkdir -p "$TMP/lib4"; cp -R "$ROOT/tests/lib/." "$TMP/lib4/"
python3 - "$TMP/lib4/recall.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("[l[:WIDTH] for l in out if l]", "[l for l in out if l]"); open(p,"w").write(s)
PY
D="$TMP/ac4t"; cap_fixture "$D"; rm -rf "$D/tests/lib"; cp -R "$TMP/lib4" "$D/tests/lib"
t AC4t "$([[ "$(idx "$D" compact | awk 'length($0) > 240' | wc -l | tr -d ' ')" -gt 0 ]] && echo 1 || echo 0)" "RED TWIN: without the cut a line exceeds 240"

# ---- AC5 a goal for another slice -------------------------------------------------------------------------------
D="$TMP/ac5"; mk "$D" EXECUTE; sed -i.bak 's/^GOAL_SLICE: a$/GOAL_SLICE: b/' "$D/docs/cascade/goal.md"; rm -f "$D/docs/cascade/goal.md.bak"
t AC5 "$(has "$(idx "$D" compact)" "for ANOTHER slice: b — reset it" && echo 1 || echo 0)" "a goal for slice b is named as another slice's"

# ---- AC6 unchanged when idle ------------------------------------------------------------------------------------
ok=1
for src in compact startup; do
  D="$TMP/ac6-$src"; mk "$D" NONE
  with="$(pjson "$D" "$src")"; mv "$D/tests/lib/recall.py" "$TMP/recall.bak"; without="$(pjson "$D" "$src")"; mv "$TMP/recall.bak" "$D/tests/lib/recall.py"
  [[ "$with" == "$without" ]] || { ok=0; echo "  NONE/$src differs"; }
done
D="$TMP/ac6-gen"; mk "$D" GENERATE
with="$(pjson "$D" startup)"; rm "$D/tests/lib/recall.py"; without="$(pjson "$D" startup)"
[[ "$with" == "$without" ]] || { ok=0; echo "  startup on an open hop differs"; }
t AC6 "$ok" "NONE (compact, startup) and startup on an open hop: byte-identical with and without recall.py"

# ---- AC7 a broken index is harmless -----------------------------------------------------------------------------
broken() {  # broken <dir> <python body>
  mk "$1" EXECUTE; printf 'import sys, time\n%s\n' "$2" > "$1/tests/lib/recall.py"
}
ok=1
for body in 'raise SystemExit(1)' 'print("spec       docs/cascade/05b-a.md"); print("goal       docs/cascade/goal.md"); sys.stdout.flush(); raise RuntimeError("late")' 'time.sleep(30)'; do
  D="$TMP/ac7"; broken "$D" "$body"
  j="$(BDD_RECALL_TIMEOUT=1 pjson "$D" compact)"
  python3 -c 'import json,sys; c=json.loads(sys.stdin.read())["hookSpecificOutput"]["additionalContext"]; assert "Current hop: EXECUTE" in c and "Recall index" not in c' <<< "$j" \
    || { ok=0; echo "  broken recall ($body) leaked into the output"; }
done
t AC7 "$ok" "a crash before printing, a crash after printing two lines, and a timeout: valid JSON, Current hop present, no index"
cp -R "$HOOKS" "$TMP/hooks7a"
python3 - "$TMP/hooks7a/preserve.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("if r.returncode != 0 or not lines:", "if not lines:"); open(p,"w").write(s)
PY
D="$TMP/ac7t1"; broken "$D" 'print("spec       docs/cascade/05b-a.md"); raise RuntimeError("late")'
t AC7t1 "$(has "$(BDD_RECALL_TIMEOUT=1 ctx "$D" compact "$TMP/hooks7a")" "Recall index" && echo 1 || echo 0)" "RED TWIN: ignoring the exit code keeps partial lines"
cp -R "$HOOKS" "$TMP/hooks7b"
python3 - "$TMP/hooks7b/preserve.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("capture_output=True, text=True,\n                           timeout=limit)", "capture_output=True, text=True)"); open(p,"w").write(s)
PY
D="$TMP/ac7t2"; broken "$D" 'time.sleep(30)'
hung="$(python3 - "$D" "$TMP/hooks7b/preserve.py" <<'PY'
import subprocess, sys
try:
    subprocess.run([sys.executable, "-B", sys.argv[2]], cwd=sys.argv[1], timeout=5, capture_output=True,
                   input='{"cwd":"%s","source":"compact","session_id":"hang"}' % sys.argv[1], text=True)
    print("returned")
except subprocess.TimeoutExpired:
    print("hung")
PY
)"
t AC7t2 "$([[ "$hung" == hung ]] && echo 1 || echo 0)" "RED TWIN: with no timeout a slow recall.py holds the session start past 5 s"

# ---- AC8 plugin mode, older pack --------------------------------------------------------------------------------
D="$TMP/ac8"; mk "$D" EXECUTE; rm "$D/tests/lib/recall.py"
c="$(ctx "$D" compact)"
D2="$TMP/ac8n"; mk "$D2" NONE; rm "$D2/tests/lib/recall.py"
c2="$(ctx "$D2" compact)"
t AC8 "$(has "$c" "Recall index unavailable: tests/lib/recall.py is not in this repo" && ! has "$c2" "Recall index unavailable" && echo 1 || echo 0)" \
  "the pack's preserve.py on a repo without recall.py: one unavailable line on an open hop, nothing at NONE"

exit "$fail"
