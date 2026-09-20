#!/usr/bin/env bash
# AC tests for 05b t55-sign-ux-docs. Docs-only slice: the permission dialog (T30) is the headline
# signing path everywhere; `bash tests/sign.sh` (T33) stays as the labelled fallback.
# AC3 is the RED TWIN — it asserts the fallback and its bash_guard denial are untouched, so a future
# edit that removes or guts them turns this test red.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

# "dialog" is mentioned before "tests/sign.sh" (dialog leads; the bash path comes after, if at all).
dialog_first() {
  python3 - "$1" <<'PY'
import sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read().lower()
d = txt.find("dialog"); s = txt.find("tests/sign.sh")
sys.exit(0 if (s < 0 or (0 <= d < s)) else 1)
PY
}

# AC1 — the two human-owned envelope files lead with the dialog and label the bash path a fallback.
for f in docs/cascade/envelope.md docs/cascade/hop-state.md; do
  ok=1
  dialog_first "$f" || ok=0
  grep -qi "fallback" "$f" || ok=0
  t AC1 "$ok" "$f — dialog before tests/sign.sh, bash path labelled fallback"
done

# AC1 — README presents the dialog as the signing method.
ok=1; grep -qi "permission dialog is your signature" README.md || ok=0
t AC1 "$ok" "README.md — dialog is the headline signing path"

# AC2 — USAGE and INTEGRATION carry the explicit Remote/web, no-local-pull note.
for f in USAGE.md INTEGRATION.md; do
  ok=1
  grep -qi "Claude Code Remote and the web" "$f" || ok=0
  grep -qi "local machine" "$f" || ok=0
  t AC2 "$ok" "$f — Remote/web: approve the dialog, no local pull"
done

# AC3 — RED TWIN: the fallback and its guard survive this docs slice.
ok=1; [[ -f tests/sign.sh ]] || ok=0
t AC3 "$ok" "tests/sign.sh still exists (fallback not removed)"

out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"bash tests/sign.sh"},"cwd":"'"$ROOT"'"}' \
        | python3 -B .claude/hooks/bash_guard.py 2>/dev/null)"
ok=1; printf '%s' "$out" | grep -q '"permissionDecision": "deny"' || ok=0
t AC3 "$ok" "bash_guard still DENIES 'bash tests/sign.sh' (agent cannot sign via terminal)"

ok=1
git diff --quiet HEAD -- .claude/hooks/bash_guard.py .claude/hooks/hop_guard.py \
                          .claude/hooks/sign_ok.py tests/sign.sh 2>/dev/null || ok=0
t AC3 "$ok" "signing enforcement layer (hooks + sign.sh) unchanged by this slice"

# AC4 — version bumped and changelog entry present.
ok=1; [[ "$(cat VERSION)" == "1.9.3" ]] || ok=0
t AC4 "$ok" "VERSION == 1.9.3"
ok=1; grep -q '## 1.9.3' CHANGELOG.md || ok=0
t AC4 "$ok" "CHANGELOG.md has the 1.9.3 entry"
ok=1
grep -q '"version": "1.9.3"' .claude-plugin/plugin.json || ok=0
grep -q '"version": "1.9.3"' .claude-plugin/marketplace.json || ok=0
t AC4 "$ok" "plugin.json + marketplace.json match VERSION (updater compares them)"

echo
[[ "$fail" -eq 0 ]] && echo "t55 AC: all green" || echo "t55 AC: FAILURES above"
exit "$fail"
