#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bdd-codex-compat.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

ok=1
[[ -f "$ROOT/.codex-plugin/plugin.json" ]] || ok=0
if [[ -f "$ROOT/.codex-plugin/plugin.json" ]]; then
  python3 -B - "$ROOT" <<'PY' || ok=0
import json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".codex-plugin", "plugin.json"), encoding="utf-8"))
v = open(os.path.join(root, "VERSION"), encoding="utf-8").read().strip()
assert m.get("name") == "bdd"
assert m.get("version") == v
assert m.get("skills") == "./skills/"
assert "hooks" not in m, "use default hooks/hooks.json discovery"
assert os.path.isdir(os.path.join(root, "skills"))
PY
fi
t AC1 "$ok" "Codex compatibility manifest points to packaged skills and default hooks"

ok=1
python3 -B - "$ROOT" <<'PY' || ok=0
import json, os, sys
root = sys.argv[1]
h = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))["hooks"]
pre = h["PreToolUse"]
assert any("apply_patch" in x.get("matcher", "") for x in pre)
assert any("Bash" in x.get("matcher", "") for x in pre)
PY
t AC2 "$ok" "Codex apply_patch and Bash tool names are registered for PreToolUse"

ok=1
out="$(BDD_HOOK_HOST=codex python3 -B - "$ROOT" <<'PY'
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], ".claude", "hooks"))
from _common import ask
ask("test", "synthetic guard failure")
PY
)"
python3 -B - "$out" <<'PY' || ok=0
import json, sys
d = json.loads(sys.argv[1])
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse"
assert h["permissionDecision"] == "deny"
assert h["permissionDecision"] != "ask"
PY
t AC3 "$ok" "Codex guard fallback uses a supported fail-closed response"

R="$TMP/repo"
mkdir -p "$R/docs/cascade"
git -C "$R" init -q
git -C "$R" config user.email codex@example.invalid
git -C "$R" config user.name Codex-Compatibility
cat > "$R/docs/cascade/hop-state.md" <<'EOF'
CURRENT_HOP: EXECUTE
CURRENT_STAGE: 06
CURRENT_SLICE: codex-compatibility
EOF
cat > "$R/docs/cascade/envelope.md" <<'EOF'
# No laws in this fixture
EOF
cat > "$R/README.md" <<'EOF'
# fixture
EOF
mkdir -p "$R/src"
cat > "$R/src/hook_comment.py" <<'EOF'
# The token <EDIT> in source is documentation, not a human-owned edit block.
EOF

patch_event() {
  local path="$1" body="$2"
  python3 - "$R" "$path" "$body" <<'PY'
import json, sys
root, path, body = sys.argv[1:]
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "apply_patch",
    "tool_use_id": "fixture-" + path,
    "cwd": root,
    "permission_mode": "default",
    "tool_input": {"command": f"*** Begin Patch\n*** Update File: {path}\n{body}\n*** End Patch"},
}))
PY
}

out="$(patch_event docs/cascade/hop-state.md $'@@\n-CURRENT_SLICE: codex-compatibility\n+CURRENT_SLICE: forged' \
  | BDD_HOOK_HOST=codex python3 -B "$ROOT/.claude/hooks/hop_guard.py")"
ok=0
python3 -B - "$out" <<'PY' && ok=1
import json, sys
d = json.loads(sys.argv[1])
h = d["hookSpecificOutput"]
assert h["permissionDecision"] == "deny"
assert h["hookEventName"] == "PreToolUse"
PY
t AC4 "$ok" "Codex apply_patch cannot change human-owned hop state"

out="$(patch_event README.md $'@@\n-# fixture\n+# fixture update' \
  | BDD_HOOK_HOST=codex python3 -B "$ROOT/.claude/hooks/hop_guard.py")"
ok=0; [[ -z "$out" ]] && ok=1
t AC5 "$ok" "ordinary Codex apply_patch in an accepted execute slice remains available"

out="$(patch_event src/hook_comment.py $'@@\n-# The token <EDIT> in source is documentation, not a human-owned edit block.\n+# The token remains documented in source.' \
  | BDD_HOOK_HOST=codex python3 -B "$ROOT/.claude/hooks/hop_guard.py")"
ok=0; [[ -z "$out" ]] && ok=1
t AC5b "$ok" "a source file that mentions <EDIT> remains editable"

out="$(python3 - "$R" <<'PY' | BDD_HOOK_HOST=codex python3 -B "$ROOT/.claude/hooks/hop_guard.py"
import json, sys
print(json.dumps({
    "hook_event_name": "PreToolUse", "tool_name": "apply_patch",
    "tool_use_id": "fixture-unknown-patch", "cwd": sys.argv[1],
    "permission_mode": "default", "tool_input": {"command": "not a patch"},
}))
PY
)"
ok=0
python3 -B - "$out" <<'PY' && ok=1
import json, sys
d = json.loads(sys.argv[1])
assert d["hookSpecificOutput"]["permissionDecision"] == "deny"
PY
t AC6 "$ok" "unrecognized Codex apply_patch input fails closed"

out="$(patch_event .git $'*** Add File: ignored' \
  | BDD_HOOK_HOST=codex python3 -B "$ROOT/.claude/hooks/hop_guard.py")"
ok=0
python3 -B - "$out" <<'PY' && ok=1
import json, sys
d = json.loads(sys.argv[1])
assert d["hookSpecificOutput"]["permissionDecision"] == "deny"
PY
t AC6b "$ok" "Codex apply_patch cannot target the git directory"

sig="$(python3 - "$R" <<'PY'
import json, sys
root = sys.argv[1]
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Write",
    "tool_use_id": "fixture-human-signature",
    "cwd": root,
    "permission_mode": "default",
    "tool_input": {
        "file_path": root + "/docs/cascade/hop-state.md",
        "content": "CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 06\nCURRENT_SLICE: changed\n",
    },
}))
PY
)"
out="$(printf '%s\n' "$sig" | BDD_HOOK_HOST=codex python3 -B "$ROOT/.claude/hooks/hop_guard.py")"
ok=0
python3 -B - "$out" "$R/.git/cascade-sign-pending" <<'PY' && ok=1
import json, os, sys
d = json.loads(sys.argv[1])
assert d["hookSpecificOutput"]["permissionDecision"] == "deny"
assert "human" in d["hookSpecificOutput"]["permissionDecisionReason"].lower()
assert not os.path.exists(sys.argv[2]), "a denied write must not create a pending signature"
PY
t AC7 "$ok" "Codex human-signature changes deny without minting a pending signature"

out="$(BDD_HOOK_HOST=codex python3 -B - "$ROOT" <<'PY'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], ".claude", "hooks"))
import stop_guard
stop_guard.emit("The hop is still open; end with STITCH NEEDED.")
PY
)"
ok=0
python3 -B - "$out" <<'PY' && ok=1
import json, sys
d = json.loads(sys.argv[1])
assert d["decision"] == "block"
assert "STITCH NEEDED" in d["reason"]
assert "hookSpecificOutput" not in d
PY
t AC8 "$ok" "Codex Stop nudges use its supported continuation response"

ok=0
python3 -B - "$ROOT" "$R" <<'PY' && ok=1
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], ".claude", "hooks"))
from _common import already_event
event = {"hook_event_name": "UserPromptSubmit", "session_id": "s", "turn_id": "t-1"}
assert already_event(event, sys.argv[2], "seam.py", "prompt_id") is False
assert already_event(event, sys.argv[2], "seam.py", "prompt_id") is True
PY
t AC9 "$ok" "Codex turn IDs deduplicate repeated prompt hook events"

out="$(printf '%s\n' "$sig" | sed 's/fixture-human-signature/fixture-runner-human-signature/' \
  | env -u BDD_HOOK_HOST PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/run.sh" hop_guard)"
ok=0
python3 -B - "$out" "$R/.git/cascade-sign-pending" <<'PY' && ok=1
import json, os, sys
d = json.loads(sys.argv[1])
assert d["hookSpecificOutput"]["permissionDecision"] == "deny"
assert not os.path.exists(sys.argv[2])
PY
t AC10 "$ok" "Codex plugin runner detects PLUGIN_ROOT and keeps signature writes blocked"

out="$(python3 - "$R" <<'PY' | env PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/run.sh" preserve
import json, sys
print(json.dumps({
    "hook_event_name": "SessionStart", "source": "fork",
    "session_id": "fixture-fork", "cwd": sys.argv[1],
}))
PY
)"
ok=0
python3 -B - "$out" <<'PY' && ok=1
import json, sys
d = json.loads(sys.argv[1])
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart"
assert "Current hop" in d["hookSpecificOutput"]["additionalContext"]
PY
t AC11 "$ok" "Codex fork SessionStart restores the cascade control context"

echo
[[ "$fail" -eq 0 ]] && echo "Codex compatibility AC all PASS" || echo "Codex compatibility AC FAILED"
exit "$fail"
