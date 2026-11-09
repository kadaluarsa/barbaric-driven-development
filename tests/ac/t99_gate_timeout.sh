#!/usr/bin/env bash
# t99 oracle: the autopilot gate has one time limit, and a refusal always says why.
#   AC1  hop_guard reads its own hook `timeout` H from the config that runs it (plugin: $BDD_PLUGIN_ROOT/hooks/hooks.json;
#        copy mode: <root>/.claude/settings.json; none found: 600 s). It hands autopilot.py M = min(asked, (H-360)//60)
#        minutes (at least 1), asked read by <root>/tests/lib/autopilot.py's own loop_minutes(), and waits at least
#        M*60 + 330 s and at most H - 30 s. Checked for several H and asked values, on a scratch root.
#   AC2  when hop_guard's own wait ends, or the gate cannot start, the reason is not empty: it says the gate did not
#        finish or could not run, and names BDD_AUTOPILOT_LOOP_MINUTES. A timeout kills the gate's process group.
#   AC3  end to end: the real hop_guard on a scratch repo, a slow loop, BDD_AUTOPILOT_LOOP_MINUTES=1 — the dialog's
#        reason holds autopilot.py's own message. (It passes before the fix too: it guards the path.)
#   AC4  both shipped hook configs give hop_guard the same `timeout`, big enough for a 60-minute loop, at most 2 hours.
#   AC5  install.sh gives an existing cascade hop_guard entry the shipped timeout when it has none or a smaller one,
#        keeps a larger one, adds no second hop_guard entry, and keeps the user's own hooks.
#   AC6  the /barbar command tells the agent to commit both autopilot edges (steps 2 and 4) in the background.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_AUTOPILOT_LOOP_MINUTES PLUGIN_ROOT BDD_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export DSHARP_CACHE=off BDD_LOOP_RUNNER=shell BDD_HOOK_HOST=claude
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t99.XXXXXX")"; trap 'pkill -f "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAILS=0
ac() { if [[ "$2" -eq 1 ]]; then echo "  ok    $1  $3"; else FAILS=$((FAILS+1)); echo "  FAIL  $1  $3"; fi; }

# hook_timeout <json file>: the `timeout` of the PreToolUse entry whose command names hop_guard ("" if none).
hook_timeout() { python3 -B - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
got = [h.get("timeout") for e in d.get("hooks", {}).get("PreToolUse", []) for h in e.get("hooks", [])
       if "hop_guard" in h.get("command", "")]
print(got[0] if len(got) == 1 and isinstance(got[0], int) else "")
PY
}
T="$(hook_timeout "$ROOT/hooks/hooks.json")"

# fixroot <dir> <settings timeout|none>: a scratch root with the pack's tests/lib and a settings.json for hop_guard.
fixroot() {
  rm -rf "$1"; mkdir -p "$1/tests" "$1/.claude"; cp -R "$ROOT/tests/lib" "$1/tests/lib"
  find "$1" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
  python3 -B - "$ROOT/.claude/settings.json" "$1/.claude/settings.json" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for e in d["hooks"]["PreToolUse"]:
    for h in e["hooks"]:
        if "hop_guard" in h.get("command", ""):
            h.pop("timeout", None)
            if sys.argv[3] != "none":
                h["timeout"] = int(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
}
# probe <root> <asked|unset> [plugin root]: run autopilot_ok with a fake subprocess layer; print H-independent facts.
probe() { ( cd "$ROOT/.claude/hooks" && R="$1" REQ="$2" PR="${3:-}" python3 -B - <<'PY' 2>&1
import os, subprocess, sys
req = os.environ["REQ"]
if req == "unset":
    os.environ.pop("BDD_AUTOPILOT_LOOP_MINUTES", None)
else:
    os.environ["BDD_AUTOPILOT_LOOP_MINUTES"] = req
if os.environ["PR"]:
    os.environ["BDD_PLUGIN_ROOT"] = os.environ["PR"]
import hop_guard
seen = {}
class P:   # stands in for both subprocess.run's result and a Popen object
    returncode = 0; stdout = ""; stderr = "autopilot: allowed edge\n"; pid = 0
    def communicate(self, timeout=None, **kw):
        seen["timeout"] = timeout; return ("", "autopilot: allowed edge\n")
    def wait(self, timeout=None): return 0
    def kill(self): pass
def note(cmd, kw):
    if any("autopilot.py" in str(c) for c in cmd):
        seen.setdefault("timeout", kw.get("timeout"))
        seen["minutes"] = (kw.get("env") or os.environ).get("BDD_AUTOPILOT_LOOP_MINUTES", "")
        seen["script"] = next(str(c) for c in cmd if "autopilot.py" in str(c))
def fake_run(cmd, *a, **kw):
    note(cmd, kw); return P()
def fake_popen(cmd, *a, **kw):
    note(cmd, kw); seen.pop("timeout", None); return P()
hop_guard.subprocess.run = fake_run
hop_guard.subprocess.Popen = fake_popen
ok, why = hop_guard.autopilot_ok(os.environ["R"], "CURRENT_HOP: EXECUTE\n", "CURRENT_HOP: GENERATE\n")
print(f"ok={ok} timeout={seen.get('timeout')} minutes={seen.get('minutes', '')} script={seen.get('script', '')} why={why!r}")
PY
); }
field() { sed -n "s/.*$1=\([^ ]*\).*/\1/p" <<<"$2"; }

# ---- AC1  hop_guard waits for the whole gate, from its own hook timeout ---------------------------------------------
ok=1
check1() {  # check1 <label> <root> <H> <asked|unset> [plugin root]
  local label="$1" r="$2" h="$3" req="$4" pr="${5:-}" out m t want cap
  out="$(probe "$r" "$req" "$pr")"
  m="$(field minutes "$out")"; t="$(field timeout "$out")"; t="${t%.*}"
  cap=$(( (h - 360) / 60 )); (( cap < 1 )) && cap=1
  want=$([[ "$req" =~ ^[0-9]+$ && "$req" -gt 0 ]] && echo "$req" || echo 60); (( want > cap )) && want=$cap
  if [[ "$out" != ok=True* ]]; then ok=0; echo "      $label: an allowing gate was refused: $out" | head -2; return; fi
  [[ "$(field script "$out")" == "$r/tests/lib/autopilot.py" ]] || { ok=0; echo "      $label: hop_guard did not run <root>/tests/lib/autopilot.py: $out"; }
  [[ "$m" =~ ^[0-9]+$ && "$m" -eq "$want" ]] || { ok=0; echo "      $label: autopilot.py got BDD_AUTOPILOT_LOOP_MINUTES='$m', want $want (H=$h, asked $req)"; return; }
  [[ "$t" =~ ^[0-9]+$ ]] || { ok=0; echo "      $label: no wait seen ($out)"; return; }
  (( t >= m * 60 + 330 )) || { ok=0; echo "      $label: hop_guard waits ${t}s, less than $m min + 300 s switch + 30 s"; }
  (( t <= h - 30 )) || { ok=0; echo "      $label: hop_guard waits ${t}s, not under its hook timeout ${h}s - 30 s"; }
}
fixroot "$TMP/r7200" 7200
for req in unset 1 30 60 66 500; do check1 "H=7200 asked=$req" "$TMP/r7200" 7200 "$req"; done
fixroot "$TMP/r1000" 1000
for req in unset 5; do check1 "H=1000 asked=$req" "$TMP/r1000" 1000 "$req"; done
fixroot "$TMP/rnone" none
check1 "no timeout in settings (600 s assumed)" "$TMP/rnone" 600 unset
check1 "garbage asked value means 60" "$TMP/r7200" 7200 abc
# plugin mode: the plugin's hooks.json decides, not the product's settings.json
mkdir -p "$TMP/plug/hooks"; printf '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"run.sh hop_guard","timeout":3000}]}]}}\n' > "$TMP/plug/hooks/hooks.json"
check1 "plugin hooks.json H=3000 over settings H=7200" "$TMP/r7200" 3000 unset "$TMP/plug"
ac AC1 "$ok" "hop_guard reads its own hook timeout (plugin hooks.json, else settings.json, else 600 s), hands autopilot.py min(asked, (H-360)/60) minutes and waits for them + 330 s, under H - 30 s"

# ---- AC2  a refusal from hop_guard's own wait has a reason, and kills the gate ---------------------------------------
ok=1
fixroot "$TMP/r2" 7200
for kind in timeout oserror; do
  out="$(cd "$ROOT/.claude/hooks" && R="$TMP/r2" KIND="$kind" python3 -B - <<'PY' 2>&1
import os, subprocess
os.environ["BDD_AUTOPILOT_LOOP_MINUTES"] = "7"
import hop_guard
def boom(cmd, *a, **kw):
    if os.environ["KIND"] == "timeout":
        raise subprocess.TimeoutExpired(cmd, kw.get("timeout") or 1)
    raise OSError("no python here")
class P:
    pid = 0; returncode = None
    def communicate(self, timeout=None, **kw):
        if os.environ["KIND"] == "timeout" and timeout is not None:
            raise subprocess.TimeoutExpired("autopilot.py", timeout)
        return ("", "")
    def kill(self): pass
    def wait(self, timeout=None): return -9
def popen(cmd, *a, **kw):
    if os.environ["KIND"] == "oserror":
        raise OSError("no python here")
    return P()
hop_guard.subprocess.run = boom
hop_guard.subprocess.Popen = popen
hop_guard.os.killpg = lambda *a: None
ok, why = hop_guard.autopilot_ok(os.environ["R"], "CURRENT_HOP: EXECUTE\n", "CURRENT_HOP: GENERATE\n")
need = ("did not finish",) if os.environ["KIND"] == "timeout" else ("could not run",)
problems = []
if ok: problems.append("a gate that did not answer allowed the edge")
if not why.strip(): problems.append("the reason is empty")
for n in need + ("BDD_AUTOPILOT_LOOP_MINUTES",):
    if n not in why: problems.append(f"the reason does not say {n!r}: {why!r}")
print("OK" if not problems else "; ".join(problems))
PY
)"
  [[ "$out" == OK ]] || { ok=0; echo "      $kind: $(echo "$out" | tail -1)"; }
done
# A real timeout: a stub autopilot.py that ignores its limit, starts a child in its own process group and sleeps.
# Settings H=120: hop_guard's wait is min(M*60 + 330, H - 30) = 90 s, so hop_guard's own wait must end it.
fixroot "$TMP/r2k" 120
cat > "$TMP/r2k/tests/lib/autopilot.py" <<PY2
import os, subprocess, time
def loop_minutes():
    v = os.environ.get("BDD_AUTOPILOT_LOOP_MINUTES", ""); return int(v) if v.isdigit() and int(v) > 0 else 60
if __name__ == "__main__":
    # same process group as this stub; no inherited pipes, so a caller reading the stub's output is not held open by it
    subprocess.Popen(["sh", "-c", "sleep 600; true", "$TMP/r2k-kid"], stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # 150 s: longer than the fixed wait (90 s), short enough that the unfixed tree's run of this whole file ends
    # inside tests/oracle.sh's 300 s fails-before-fix check (a timeout there counts as "did not fail").
    time.sleep(150)
PY2
s0=$SECONDS
out="$(cd "$ROOT/.claude/hooks" && R="$TMP/r2k" python3 -B -c '
import os, hop_guard
ok, why = hop_guard.autopilot_ok(os.environ["R"], "CURRENT_HOP: EXECUTE\n", "CURRENT_HOP: GENERATE\n")
print(f"ok={ok} why={why!r}")' 2>&1)"; took=$((SECONDS - s0))
[[ "$out" == ok=False* && "$out" == *"did not finish"* ]] || { ok=0; echo "      real timeout: $out"; }
(( took >= 80 && took <= 110 )) || { ok=0; echo "      real timeout: hop_guard gave up after ${took}s, want about 90 s (H=120)"; }
sleep 2
! pgrep -f "$TMP/r2k-kid" >/dev/null || { ok=0; echo "      real timeout: the gate's child kept running after hop_guard gave up"; }
ac AC2 "$ok" "when hop_guard's own wait ends or the gate cannot start, the edge is refused with a reason that names BDD_AUTOPILOT_LOOP_MINUTES, and the gate's process group is killed"

# ---- AC3  end to end: autopilot.py's own message reaches the dialog -------------------------------------------------
ok=1
P="$TMP/p3"; mkdir -p "$P/docs/cascade" "$P/tests" "$P/.claude"
cp -R "$ROOT/.githooks" "$P/.githooks"; cp -R "$ROOT/tests/lib" "$P/tests/lib"; cp -R "$ROOT/.claude/hooks" "$P/.claude/hooks"
for f in loop.sh critique.sh diverge.sh; do cp "$ROOT/tests/$f" "$P/tests/"; done
find "$P" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
printf '.cascade/\n' > "$P/.gitignore"; echo '# spec' > "$P/docs/cascade/05b-a.md"
printf '# envelope\n\n## Laws\n\n<EDIT>\n</EDIT>\n' > "$P/docs/cascade/envelope.md"
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n\n<EDIT>\nAUTOPILOT: 05b a, 05b b\n</EDIT>\n' > "$P/docs/cascade/hop-state.md"
{ echo '```'; echo 'GOAL_STAGE: 05b'; echo 'GOAL_SLICE: a'; echo "VALIDATOR: sleep 90 && touch $TMP/p3-marker"; echo '```'; } > "$P/docs/cascade/goal.md"
( cd "$P" && git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && git -c core.hooksPath=/dev/null commit -qm init \
    && git config core.hooksPath .githooks )
EV="$(python3 -B -c 'import json,sys; p=sys.argv[1]; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":p,
  "tool_use_id":"t99-ac3","tool_input":{"file_path":p+"/docs/cascade/hop-state.md","old_string":"CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a",
  "new_string":"CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: b"}}))' "$P")"
s0=$SECONDS
out="$(cd "$P" && printf '%s' "$EV" | BDD_AUTOPILOT_LOOP_MINUTES=1 python3 -B .claude/hooks/hop_guard.py 2>&1)"; took=$((SECONDS - s0))
reason="$(printf '%s' "$out" | python3 -B -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])
except Exception: print("")')"
[[ "$reason" == *"did not finish in 1 minutes"* ]] || { ok=0; echo "      the dialog does not carry autopilot.py's message (${took}s): ${reason:-$out}" | head -3; }
[[ "$took" -lt 150 ]] || { ok=0; echo "      the hook took ${took}s for a 1-minute limit"; }
ac AC3 "$ok" "the real hop_guard, a slow loop and a 1-minute limit: the dialog's reason says the gate did not finish in 1 minutes"

# ---- AC4  the shipped hook configs --------------------------------------------------------------------------------
ok=1
S="$(hook_timeout "$ROOT/.claude/settings.json")"
for pair in "hooks/hooks.json:$T" ".claude/settings.json:$S"; do
  f="${pair%%:*}"; v="${pair#*:}"
  if [[ -z "$v" ]]; then ok=0; echo "      $f: hop_guard has no integer timeout"; continue; fi
  (( v >= 60 * 60 + 300 + 60 )) || { ok=0; echo "      $f: hop_guard timeout ${v}s cannot hold a 60-minute loop, the switch review and a margin"; }
  (( v <= 7200 )) || { ok=0; echo "      $f: hop_guard timeout ${v}s is more than 2 hours"; }
done
[[ -n "$T" && "$T" == "$S" ]] || { ok=0; echo "      the two configs disagree: hooks.json '$T', settings.json '$S'"; }
ac AC4 "$ok" "hooks/hooks.json and .claude/settings.json give hop_guard the same timeout, at least 60 min + 360 s and at most 2 h"

# ---- AC5  install.sh brings the timeout to an existing install ----------------------------------------------------
ok=1
for case in none smaller bigger; do
  D="$TMP/p5$case"; mkdir -p "$D/.claude"
  ( cd "$D" && git init -q && git symbolic-ref HEAD refs/heads/main && echo x > x && git add -A && git -c core.hooksPath=/dev/null commit -qm init )
  CASE="$case" python3 -B - "$ROOT/.claude/settings.json" "$D/.claude/settings.json" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
for e in d["hooks"]["PreToolUse"]:
    for h in e["hooks"]:
        if "hop_guard" in h.get("command", ""):
            h.pop("timeout", None)
            if os.environ["CASE"] == "bigger":
                h["timeout"] = 9000
            if os.environ["CASE"] == "smaller":
                h["timeout"] = 60
d["hooks"].setdefault("PostToolUse", []).append({"matcher": "Write", "hooks": [{"type": "command", "command": "echo users-own-hook"}]})
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
  # --no-plugin: the copy mode is the one that keeps hook entries in settings.json (plugin mode removes them).
  ( cd "$D" && unset BDD_PLUGIN_ROOT && bash "$ROOT/install.sh" --no-plugin . </dev/null >"$TMP/p5$case.log" 2>&1 ) || true
  n="$(python3 -B -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum("hop_guard" in h.get("command","") for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))' "$D/.claude/settings.json" 2>/dev/null)"
  [[ "$n" == 1 ]] || { ok=0; echo "      ($case) install.sh left $n hop_guard entries, want 1"; }
  got="$(hook_timeout "$D/.claude/settings.json")"
  want="$T"; [[ "$case" == bigger ]] && want=9000
  [[ -n "$got" && "$got" == "$want" ]] || { ok=0; echo "      ($case) hop_guard timeout after install is '$got', want '$want' (log: $(tail -2 "$TMP/p5$case.log" | tr '\n' ' '))"; }
  grep -q 'users-own-hook' "$D/.claude/settings.json" || { ok=0; echo "      ($case) install.sh dropped the user's own hook"; }
done
ac AC5 "$ok" "install.sh sets the shipped hop_guard timeout on an existing entry that has none, keeps a larger one, adds no second entry, keeps the user's hooks"

# ---- AC6  the agent commits both autopilot edges in the background --------------------------------------------------
ok=1
for f in .claude/commands/barbar.md commands/barbar.md; do
  python3 -B - "$ROOT/$f" <<'PY' || { ok=0; echo "      $f: steps 2 and 4 do not both say to commit the edge with run_in_background"; }
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
ok = True
for n in ("2", "4"):
    m = re.search(r"^" + n + r"\. \*\*Advance\*\*.*$", s, re.M)
    ok = ok and bool(m) and "run_in_background" in m.group(0) and "pre-commit" in m.group(0)
sys.exit(0 if ok else 1)
PY
done
ac AC6 "$ok" "both copies of the /barbar command tell the agent to commit both autopilot edges (steps 2 and 4) with run_in_background, because pre-commit runs the gate again"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "T99 AC all PASS"; else echo "T99 AC FAILED ($FAILS)"; fi
exit $(( FAILS > 0 ))
