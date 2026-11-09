#!/usr/bin/env bash
# t99 oracle: the autopilot gate has one time limit, and a refusal always says why.
#   AC1  hop_guard waits for the whole gate: its subprocess timeout covers the loop limit it hands to autopilot.py
#        plus the switch review (300 s), and stays under the hook's own configured timeout. Unset means 60 minutes,
#        not reduced. A requested limit above what the hook allows is lowered so that autopilot.py stops first.
#   AC2  when hop_guard's own wait still ends (timeout, or the gate cannot start), the reason is not empty: it says
#        the gate did not finish or could not run, and names the variable that changes the limit.
#   AC3  end to end: the real hop_guard on a scratch repo, a slow loop, BDD_AUTOPILOT_LOOP_MINUTES=1 — the dialog's
#        reason holds autopilot.py's own message.
#   AC4  both shipped hook configs give hop_guard the same `timeout`, big enough for a 60-minute loop, at most 2 hours.
#   AC5  install.sh gives an existing cascade hop_guard entry that has no timeout the shipped one, keeps a larger
#        timeout the user set, adds no second hop_guard entry, and keeps the user's own hooks.
#   AC6  the /barbar command tells the agent to commit an EXECUTE→next edge in the background, in both copies.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED BDD_AUTOPILOT_LOOP_MINUTES PLUGIN_ROOT
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

# ---- AC1  hop_guard waits for the whole gate ---------------------------------------------------------------------
ok=1
if [[ -z "$T" ]]; then
  ok=0; echo "      hooks/hooks.json gives hop_guard no timeout, so AC1 has no hook limit to stay under"
else
  for req in unset 1 30 60 500; do
    out="$(cd "$ROOT/.claude/hooks" && REQ="$req" HOOK_T="$T" python3 -B - <<'PY' 2>&1
import os, subprocess, sys
req = os.environ["REQ"]; hook_t = int(os.environ["HOOK_T"])
if req == "unset":
    os.environ.pop("BDD_AUTOPILOT_LOOP_MINUTES", None)
else:
    os.environ["BDD_AUTOPILOT_LOOP_MINUTES"] = req
import hop_guard
seen = {}
class R:  # a gate that allows the edge
    returncode = 0; stdout = ""; stderr = "autopilot: allowed edge\n"
def fake_run(cmd, *a, **kw):
    if any("autopilot.py" in str(c) for c in cmd):
        seen["timeout"] = kw.get("timeout")
        seen["minutes"] = (kw.get("env") or os.environ).get("BDD_AUTOPILOT_LOOP_MINUTES", "")
    return R()
hop_guard.subprocess.run = fake_run
ok, why = hop_guard.autopilot_ok(os.getcwd(), "CURRENT_HOP: EXECUTE\n", "CURRENT_HOP: GENERATE\n")
t, m = seen.get("timeout"), seen.get("minutes", "")
want = 60 if req == "unset" else int(req)
problems = []
if not ok: problems.append(f"an allowing gate was refused ({why!r})")
if not isinstance(t, (int, float)): problems.append(f"no subprocess timeout seen ({t!r})")
if not m.isdigit(): problems.append(f"autopilot.py got no BDD_AUTOPILOT_LOOP_MINUTES ({m!r})")
if not problems:
    m = int(m)
    if want * 60 + 300 + 30 <= hook_t - 30 and m != want:
        problems.append(f"a limit the hook allows was changed: asked {want}, autopilot.py got {m}")
    if m > want: problems.append(f"the limit was raised: asked {want}, autopilot.py got {m}")
    if m < 1: problems.append(f"autopilot.py got {m} minutes")
    if t < m * 60 + 300 + 30: problems.append(f"hop_guard waits {t}s, less than {m} min + 300 s switch + 30 s")
    if t > hook_t - 30: problems.append(f"hop_guard waits {t}s, not under the hook timeout {hook_t}s - 30 s")
print("OK" if not problems else "; ".join(problems))
PY
)"
    [[ "$out" == OK ]] || { ok=0; echo "      BDD_AUTOPILOT_LOOP_MINUTES=$req: $(echo "$out" | tail -1)"; }
  done
fi
ac AC1 "$ok" "hop_guard waits for the loop limit + the switch review, under the hook timeout; 60 is not reduced; a too-high limit is lowered so autopilot.py stops first"

# ---- AC2  a refusal from hop_guard's own wait has a reason ------------------------------------------------------
ok=1
for kind in timeout oserror; do
  out="$(cd "$ROOT/.claude/hooks" && KIND="$kind" python3 -B - <<'PY' 2>&1
import os, subprocess
os.environ["BDD_AUTOPILOT_LOOP_MINUTES"] = "7"
import hop_guard
def fake_run(cmd, *a, **kw):
    if os.environ["KIND"] == "timeout":
        raise subprocess.TimeoutExpired(cmd, kw.get("timeout") or 1)
    raise OSError("no python here")
hop_guard.subprocess.run = fake_run
ok, why = hop_guard.autopilot_ok(os.getcwd(), "CURRENT_HOP: EXECUTE\n", "CURRENT_HOP: GENERATE\n")
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
ac AC2 "$ok" "when hop_guard's own wait ends or the gate cannot start, the edge is refused with a reason that names BDD_AUTOPILOT_LOOP_MINUTES"

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
for case in none bigger; do
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
                h["timeout"] = 7000
d["hooks"].setdefault("PostToolUse", []).append({"matcher": "Write", "hooks": [{"type": "command", "command": "echo users-own-hook"}]})
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
  # --no-plugin: the copy mode is the one that keeps hook entries in settings.json (plugin mode removes them).
  ( cd "$D" && unset BDD_PLUGIN_ROOT && bash "$ROOT/install.sh" --no-plugin . </dev/null >"$TMP/p5$case.log" 2>&1 ) || true
  n="$(python3 -B -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum("hop_guard" in h.get("command","") for e in d.get("hooks",{}).get("PreToolUse",[]) for h in e.get("hooks",[])))' "$D/.claude/settings.json" 2>/dev/null)"
  [[ "$n" == 1 ]] || { ok=0; echo "      ($case) install.sh left $n hop_guard entries, want 1"; }
  got="$(hook_timeout "$D/.claude/settings.json")"
  want="$T"; [[ "$case" == bigger ]] && want=7000
  [[ -n "$got" && "$got" == "$want" ]] || { ok=0; echo "      ($case) hop_guard timeout after install is '$got', want '$want' (log: $(tail -2 "$TMP/p5$case.log" | tr '\n' ' '))"; }
  grep -q 'users-own-hook' "$D/.claude/settings.json" || { ok=0; echo "      ($case) install.sh dropped the user's own hook"; }
done
ac AC5 "$ok" "install.sh sets the shipped hop_guard timeout on an existing entry that has none, keeps a larger one, adds no second entry, keeps the user's hooks"

# ---- AC6  the agent commits an EXECUTE→next edge in the background --------------------------------------------------
ok=1
for f in .claude/commands/barbar.md commands/barbar.md; do
  python3 -B - "$ROOT/$f" <<'PY' || { ok=0; echo "      $f: step 4 does not say to commit the edge with run_in_background"; }
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^4\. \*\*Advance\*\*.*$", s, re.M)
sys.exit(0 if m and "run_in_background" in m.group(0) and "pre-commit" in m.group(0) else 1)
PY
done
ac AC6 "$ok" "both copies of the /barbar command tell the agent to commit an EXECUTE→next edge with run_in_background, because pre-commit runs the loop again"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "T99 AC all PASS"; else echo "T99 AC FAILED ($FAILS)"; fi
exit $(( FAILS > 0 ))
