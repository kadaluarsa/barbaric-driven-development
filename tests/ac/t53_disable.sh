#!/usr/bin/env bash
# AC tests for 05b t53-bdd-disable. AC2 (Layer 0 survives a disable) is T53 in
# tests/enforcement.sh — it is the slice's red twin and lives with the other I18 evidence.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
D="python3 -B $ROOT/tests/lib/disable.py"

mkrepo() {  # a repo with both local layers wired, like a real install
  local d="$1" hookspath="${2-.githooks}"
  mkdir -p "$d/.githooks" "$d/.claude" "$d/.github/workflows" "$d/tests"
  printf '#!/bin/sh\nexit 0\n' > "$d/.githooks/pre-commit"; chmod +x "$d/.githooks/pre-commit"
  cp "$ROOT/tests/barbar.sh" "$d/tests/barbar.sh" 2>/dev/null || printf '#!/bin/sh\nexit 0\n' > "$d/tests/barbar.sh"
  printf 'name: ci\non: [push]\n' > "$d/.github/workflows/control-line.yml"
  cat > "$d/.claude/settings.json" <<'S'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "echo hop"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}]
  },
  "localOnly": "a product setting the pack must not eat"
}
S
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main
    [[ -n "$hookspath" ]] && git config core.hooksPath "$hookspath"
    git add -A && git commit -qm init ) >/dev/null 2>&1
}

# ---- AC1  round-trip restores both layers byte-for-byte ------------------------------------------
R="$TMP/ac1"; mkrepo "$R"
before_settings="$(cat "$R/.claude/settings.json")"
before_hp="$(git -C "$R" config --get core.hooksPath)"
$D "$R" --disable >/dev/null 2>&1
$D "$R" --enable  >/dev/null 2>&1
ok=1
[[ "$(cat "$R/.claude/settings.json")" == "$before_settings" ]] || { ok=0; echo "  settings.json not restored byte-for-byte"; }
[[ "$(git -C "$R" config --get core.hooksPath)" == "$before_hp" ]] || { ok=0; echo "  core.hooksPath not restored"; }
t AC1a "$ok" "disable -> enable restores .claude/settings.json and core.hooksPath exactly"

# The restore must be the SAVED bytes, not the pack's default — a non-default hooksPath survives,
# and a local key sitting beside "hooks" is never eaten.
R="$TMP/ac1b"; mkrepo "$R" ".myhooks"
$D "$R" --disable >/dev/null 2>&1; $D "$R" --enable >/dev/null 2>&1
ok=1
[[ "$(git -C "$R" config --get core.hooksPath)" == ".myhooks" ]] \
  || { ok=0; echo "  a non-default hooksPath was replaced with the pack default — restore is a guess"; }
grep -q 'localOnly' "$R/.claude/settings.json" || { ok=0; echo "  a product's own settings key was lost"; }
t AC1b "$ok" "restore returns the saved value, not the pack default, and keeps local settings keys"

# A repo that had NO hooksPath must come back with none — not with .githooks invented for it.
R="$TMP/ac1c"; mkrepo "$R" ""
$D "$R" --disable >/dev/null 2>&1; $D "$R" --enable >/dev/null 2>&1
ok=1; [[ -z "$(git -C "$R" config --get core.hooksPath || true)" ]] \
  || { ok=0; echo "  enable invented a hooksPath on a repo that never had one"; }
t AC1c "$ok" "'there was nothing' is restored as nothing"

# ---- AC6  idempotence ----------------------------------------------------------------------------
R="$TMP/ac6"; mkrepo "$R"
before_settings="$(cat "$R/.claude/settings.json")"
$D "$R" --disable >/dev/null 2>&1
$D "$R" --disable >/dev/null 2>&1   # the dangerous one: must not save the already-stripped state
$D "$R" --enable  >/dev/null 2>&1
ok=1
[[ "$(cat "$R/.claude/settings.json")" == "$before_settings" ]] \
  || { ok=0; echo "  a second disable overwrote the saved state — enable restored the disabled form"; }
out="$($D "$R" --enable 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && echo "$out" | grep -qi 'not disabled' \
  || { ok=0; echo "  enable on a never-disabled repo did not exit 0 saying so"; }
t AC6 "$ok" "disable is idempotent and never clobbers the saved state; enable on an enabled repo is a no-op"

# ---- AC5  a disable is local and cannot be committed ---------------------------------------------
R="$TMP/ac5"; mkrepo "$R"
cp "$ROOT/.gitignore" "$R/.gitignore"; ( cd "$R" && git add -A && git commit -qm ignore ) >/dev/null 2>&1
$D "$R" --disable >/dev/null 2>&1
ok=1
[[ -z "$(git -C "$R" status --short)" ]] || { ok=0; echo "  disable left the tree dirty:"; git -C "$R" status --short | sed 's/^/    /'; }
( cd "$R" && git check-ignore -q .cascade/disabled/state.json ) || { ok=0; echo "  .cascade/disabled/ is not gitignored"; }
t AC5 "$ok" "a disable leaves a clean tree and .cascade/disabled/ is gitignored"

# ---- AC3  install.sh --check says DISABLED, not DRIFT or UNWIRED ---------------------------------
R="$TMP/ac3"; mkrepo "$R"
$D "$R" --disable >/dev/null 2>&1
out="$(bash "$ROOT/install.sh" --check "$R" 2>&1)"; rc=$?
ok=1
[[ "$rc" -eq 0 ]] || { ok=0; echo "  --check exited $rc on a deliberately disabled repo"; }
echo "$out" | grep -q 'DISABLED' || { ok=0; echo "  --check did not say DISABLED"; }
echo "$out" | grep -qE 'DRIFT|UNWIRED' && { ok=0; echo "  --check called a deliberate disable drift/unwired"; }
t AC3 "$ok" "install.sh --check reports DISABLED (exit 0), distinct from DRIFT and UNWIRED"

# ---- AC4  every status surface leads with it -----------------------------------------------------
R="$TMP/ac4"
mkdir -p "$R"
for x in tests .githooks .github .claude docs commands VERSION install.sh install-global.sh AGENTS.md CONTROL-LINE.md; do
  [[ -e "$ROOT/$x" ]] && cp -R "$ROOT/$x" "$R/$x"
done
( cd "$R" && git init -q && git config core.hooksPath .githooks ) >/dev/null 2>&1
$D "$R" --disable >/dev/null 2>&1
ok=1
dout="$(cd "$R" && DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"
echo "$dout" | grep -q 'BDD DISABLED' || { ok=0; echo "  doctor did not lead with BDD DISABLED"; }
echo "$dout" | grep -E 'L1 +hooksPath|L2 +agent hooks' | grep -q 'RED' \
  && { ok=0; echo "  doctor called a deliberate stand-down RED instead of skipped"; }
sout="$(cd "$R" && python3 -B "$ROOT/.claude/hooks/seam.py" <<< '{"prompt":"x","cwd":"'"$R"'"}' 2>&1)"
echo "$sout" | grep -q 'BDD DISABLED' || { ok=0; echo "  the seam banner did not say BDD DISABLED"; }
t AC4 "$ok" "doctor and the seam banner both lead with BDD DISABLED; stood-down layers read skipped, not RED"

if [[ "$fail" -ne 0 ]]; then exit 1; fi
echo "PASS: t53-bdd-disable AC1, AC3, AC4, AC5, AC6 (AC2 is T53 in tests/enforcement.sh)"
