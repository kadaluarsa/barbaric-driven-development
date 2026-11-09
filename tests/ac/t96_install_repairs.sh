#!/usr/bin/env bash
# t96 oracle: a clean install reaches the merge gate, and each 3.5.0 stress-test fault stays fixed.
# T96_FAST=1 runs AC1-AC9 only: AC10 and AC11 run tests/enforcement.sh, and T96 itself runs inside that suite.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CASCADE_ENVELOPE CASCADE_HOPSTATE CASCADE_HUMAN BDD_LOOP_LOCKED \
      CLAUDE_PLUGIN_ROOT PLUGIN_ROOT BDD_PLUGIN_ROOT BDD_AUTO_REFRESH CASCADE_ENFORCEMENT_NESTED
TMP="$(mktemp -d "${TMPDIR:-/tmp}/t96.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
FAILS=0
ac() { if [[ "$2" -eq 1 ]]; then echo "  ok    $1"; else FAILS=$((FAILS+1)); echo "  FAIL  $1  ${3:-}"; fi; }
quiet_commit() { git -c core.hooksPath=/dev/null add -A >/dev/null 2>&1; git -c core.hooksPath=/dev/null commit -qm "$1" >/dev/null 2>&1; }
# fresh <name> <mode>: a repo with the pack installed and committed. The commit is fixture setup.
fresh() {
  local d="$TMP/$1"; mkdir -p "$d/src"
  ( cd "$d" && git init -q -b main && printf 'x=1\n' > src/app.py && git add -A && git commit -qm init \
    && bash "$ROOT/install.sh" "--$2" . >"$d.install" 2>&1; quiet_commit installed )
  echo "$d"
}
sethop() { ( cd "$1" && python3 -B - "$2" "$3" "$4" <<'PY'
import re, sys
p = 'docs/cascade/hop-state.md'; s = open(p).read()
for k, v in zip(('HOP', 'STAGE', 'SLICE'), sys.argv[1:4]):
    s = re.sub(rf'^CURRENT_{k}:.*$', f'CURRENT_{k}: {v}', s, flags=re.M)
open(p, 'w').write(s)
PY
quiet_commit "hop $2" ); }
line() { grep -E "^CURRENT_$2:" "$1/docs/cascade/hop-state.md" | head -1; }
sha() { python3 -B -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

echo "AC1 the hop seed"
for m in no-plugin plugin; do
  d="$(fresh seed-$m $m)"
  [[ "$(line "$d" HOP)" == "CURRENT_HOP: NONE" ]]; ac "$m: starts on NONE" $(( $? == 0 )) "$(line "$d" HOP)"
  [[ "$(line "$d" STAGE)" == "CURRENT_STAGE: 00" ]]; ac "$m: stage 00" $(( $? == 0 )) "$(line "$d" STAGE)"
  [[ "$(line "$d" SLICE)" == "CURRENT_SLICE: empty" ]]; ac "$m: slice empty" $(( $? == 0 )) "$(line "$d" SLICE)"
  grep -qE '^AUTOPILOT: *$' "$d/docs/cascade/hop-state.md"; ac "$m: AUTOPILOT is empty" $(( $? == 0 ))
  [[ -f "$d/docs/cascade/hop-state.template.md" ]]; ac "$m: ships the template" $(( $? == 0 ))
  ( cd "$d" && bash "$ROOT/install.sh" --check . ) >"$d.check" 2>&1; ac "$m: --check clean" $(( $? == 0 )) "$(tail -1 "$d.check" | cut -c1-140)"
  sethop "$d" GENERATE 05b mine; ( cd "$d" && bash "$ROOT/install.sh" "--$m" . ) >/dev/null 2>&1
  [[ "$(line "$d" HOP)" == "CURRENT_HOP: GENERATE" && "$(line "$d" SLICE)" == "CURRENT_SLICE: mine" ]]; ac "$m: a reinstall keeps an existing hop state" $(( $? == 0 ))
done
d="$TMP/presplit"; mkdir -p "$d/docs/cascade"; ( cd "$d" && git init -q -b main && printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: old\n' > docs/cascade/envelope.md && git add -A && git commit -qm init && bash "$ROOT/install.sh" --no-plugin . ) >"$d.o" 2>&1
[[ ! -e "$d/docs/cascade/hop-state.md" ]]; ac "a pre-split envelope gets no hop-state file" $(( $? == 0 ))

echo "AC2 bash_guard"
G="$(fresh guard no-plugin)"
verdict() { ( cd "$G" && python3 -B -c 'import json,os,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":os.getcwd(),"session_id":"s"}))' "$1" \
  | python3 -B .claude/hooks/bash_guard.py ) 2>&1; }
stops() { grep -qE '"permissionDecision": *"(deny|ask)"' <<<"$1"; }
while IFS= read -r c; do o="$(verdict "$c")"; stops "$o"; ac "denies: $c" $(( $? == 0 )); done <<'EOF'
git commit -n -m x
git commit -an -m x
git commit -m x -n
git -c core.hooksPath=/dev/null commit -m x
git -c core.hookspath=/dev/null commit -m x
git -C . -c core.hooksPath=/tmp commit -m x
git --config-env=core.hooksPath=H commit -m x
git -C . commit --no-verify -m x
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x
GIT_CONFIG_PARAMETERS="'core.hooksPath=/dev/null'" git commit -m x
git commit --no-veri -m x
H=/dev/null git --config-env core.hooksPath=H commit -m x
git config core.HOOKSPATH /dev/null
export GIT_CONFIG_COUNT=1; git commit -m x
EOF
while IFS= read -r c; do o="$(verdict "$c")"; stops "$o"; ac "allows: $c" $(( $? != 0 )) "$(cut -c1-120 <<<"$o")"; done <<'EOF'
git push -n origin feature
git merge -n feature
git log -n 3
git -c user.name=x commit -m y
git -C . status
git commit --amend -m x
git commit -m "add -n flag"
git commit -m now
git commit -am "add -n flag"
git commit -m"fix -n flag"
git commit --author "a -n b" -m x
EOF

echo "AC3 drift"
d="$(fresh drift plugin)"
[[ -f "$d/tests/drift.sh" ]]; ac "ships tests/drift.sh" $(( $? == 0 ))
grep -qE '^tests/drift\.sh$| tests/drift\.sh$' "$d/.cascade/manifest"; ac "the manifest lists tests/drift.sh" $(( $? == 0 ))
( cd "$d" && bash tests/drift.sh ) >"$d.o" 2>&1; ac "clean install exits 0" $(( $? == 0 )) "$(tail -1 "$d.o" | cut -c1-140)"
printf '#!/bin/bash\necho "LOOP 1/1"\n' > "$d/tests/loop.sh"
( cd "$d" && bash tests/drift.sh ) >"$d.o" 2>&1; rc=$?; ac "a softened file fails" $(( rc != 0 )); grep -q 'tests/loop.sh' "$d.o"; ac "the failure names the file" $(( $? == 0 ))
( cd "$d" && git checkout -q tests/loop.sh; mv tests/audit.sh "$TMP/audit.sh.saved"; bash tests/drift.sh ) >"$d.o" 2>&1; rc=$?; ac "a missing file fails" $(( rc != 0 )); grep -q 'tests/audit.sh' "$d.o"; ac "the failure names the missing file" $(( $? == 0 ))
mv "$TMP/audit.sh.saved" "$d/tests/audit.sh"
mkdir -p "$d/.cascade/disabled"; printf '{}\n' > "$d/.cascade/disabled/state.json"; printf 'x\n' >> "$d/tests/loop.sh"
( cd "$d" && bash tests/drift.sh ) >"$d.o" 2>&1; ac "a disabled marker does not hide a softened file" $(( $? != 0 ))
( cd "$d" && git checkout -q tests/loop.sh ); rm -f "$d/.cascade/disabled/state.json"; rmdir "$d/.cascade/disabled" 2>/dev/null
mkdir -p "$d/.claude-plugin"; printf '{"name":"their-plugin"}\n' > "$d/.claude-plugin/plugin.json"; printf 'x\n' >> "$d/tests/loop.sh"
( cd "$d" && bash tests/drift.sh ) >"$d.o" 2>&1; ac "a product that is itself a plugin still gets the check" $(( $? != 0 ))
( cd "$d" && git checkout -q tests/loop.sh ); rm -f "$d/.claude-plugin/plugin.json"; rmdir "$d/.claude-plugin" 2>/dev/null
printf 'tests/\n' >> "$d/.gitignore"; ( cd "$d" && bash tests/drift.sh ) >"$d.o" 2>&1; ac "ignored enforcement fails" $(( $? != 0 ))
( cd "$d" && git checkout -q .gitignore )
n="$(fresh drift2 no-plugin)"; python3 -B -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop("hooks",None); open(p,"w").write(json.dumps(d))' "$n/.claude/settings.json"
( cd "$n" && bash tests/drift.sh ) >"$n.o" 2>&1; rc=$?; ac "stripped agent hooks fail" $(( rc != 0 )); grep -q UNWIRED "$n.o"; ac "stripped agent hooks print UNWIRED" $(( $? == 0 ))
( cd "$n" && git checkout -q .claude/settings.json ); printf '\nA product rule.\n' >> "$n/AGENTS.md"
( cd "$n" && bash tests/drift.sh ) >"$n.o" 2>&1; ac "a product edit of AGENTS.md is not drift" $(( $? == 0 )) "$(tail -1 "$n.o" | cut -c1-120)"
mv "$d/.cascade/manifest" "$TMP/manifest.saved"
( cd "$d" && bash tests/drift.sh ) >"$d.o" 2>&1; ac "a product with no manifest fails" $(( $? != 0 ))
mv "$TMP/manifest.saved" "$d/.cascade/manifest"
if [[ -f "$ROOT/tests/drift.sh" ]]; then ( cd "$ROOT" && bash tests/drift.sh ) >"$TMP/pack.o" 2>&1; rc=$?; else rc=9; : >"$TMP/pack.o"; fi
ac "the pack exits 0" $(( rc == 0 )); grep -q 'n/a' "$TMP/pack.o"; ac "the pack prints n/a" $(( $? == 0 ))
wf="$ROOT/.github/workflows/control-line.yml"
python3 -B - "$wf" <<'PY'; ac "the eval job runs tests/drift.sh" $(( $? == 0 ))
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'^  eval:\n(.*?)(?=^  \S|\Z)', s, flags=re.M | re.S)
sys.exit(0 if m and re.search(r'^\s+run: bash tests/drift\.sh\s*$', m.group(1), flags=re.M) else 1)
PY

echo "AC4 a same-version reinstall commits through the real hook"
d="$(fresh mani no-plugin)"; sethop "$d" NONE 00 empty
( cd "$d" && bash "$ROOT/install.sh" --no-plugin . ) >/dev/null 2>&1
( cd "$d" && git add -A && git commit -qm reinstall --allow-empty ) >"$d.o" 2>&1; ac "the commit passes" $(( $? == 0 )) "$(grep -m1 BLOCKED "$d.o" | cut -c1-140)"

echo "AC5 the skill conflict"
SK=.agents/skills/bdd-work/SKILL.md
cur="$(git -C "$ROOT" rev-parse "HEAD:$SK" 2>/dev/null)"
n=0
for b in $(git -C "$ROOT" log --all --format=%h -- "$SK" | while read -r c; do git -C "$ROOT" rev-parse -q --verify "$c:$SK" 2>/dev/null; done | sort -u); do
  [[ "$b" == "$cur" ]] && continue
  n=$((n+1)); d="$(fresh sk$n no-plugin)"; git -C "$ROOT" cat-file -p "$b" > "$d/$SK"; ( cd "$d" && quiet_commit old )
  ( cd "$d" && bash "$ROOT/install.sh" --no-plugin . ) >"$d.o" 2>&1; rc=$?; ac "an untouched copy ${b:0:10} upgrades" $(( rc == 0 )) "$(grep -m1 CONFLICT "$d.o" | cut -c1-120)"
  cmp -s "$ROOT/$SK" "$d/$SK"; ac "an untouched copy ${b:0:10} is replaced" $(( $? == 0 ))
done
[[ $n -ge 1 ]]; ac "the history holds an earlier pack copy" $(( $? == 0 ))
d="$TMP/real302"; o="$TMP/pack302"; mkdir -p "$d" "$o"; git -C "$ROOT" archive v3.0.2 | tar -xf - -C "$o"
( cd "$d" && git init -q -b main && printf 'x=1\n' > app.py && git add -A && git commit -qm init && bash "$o/install.sh" --no-plugin . >/dev/null 2>&1; quiet_commit old; bash "$ROOT/install.sh" --no-plugin . ) >"$d.o" 2>&1; ac "a real v3.0.2 install upgrades" $(( $? == 0 )) "$(grep -m1 CONFLICT "$d.o" | cut -c1-120)"
d="$(fresh sk-edit no-plugin)"; printf 'the user edit\n' > "$d/$SK"; ( cd "$d" && quiet_commit edited )
( cd "$d" && bash "$ROOT/install.sh" --no-plugin . ) >"$d.o" 2>&1; rc=$?; ac "a user edit exits 1" $(( rc == 1 )) "rc=$rc"; grep -q CONFLICT "$d.o"; ac "a user edit prints CONFLICT" $(( $? == 0 ))
[[ "$(cat "$d/$SK")" == "the user edit" ]]; ac "a user edit is kept" $(( $? == 0 ))

echo "AC6 the workflow time limit"
python3 -B - "$wf" <<'PY'; ac "the eval job has timeout-minutes: 60" $(( $? == 0 ))
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'^  eval:\n(.*?)(?=^  \S|\Z)', s, flags=re.M | re.S)
sys.exit(0 if m and re.search(r'^\s+timeout-minutes: 60\s*$', m.group(1), flags=re.M) else 1)
PY

echo "AC7 farm residue is ignored"
d="$(fresh ign plugin)"; ( cd "$d" && git check-ignore -q evals/fixtures/any-product/.cascade/regress ); ac "an install ignores it" $(( $? == 0 ))
( cd "$ROOT" && git check-ignore -q evals/fixtures/any-product/.cascade/regress ); ac "the pack ignores it" $(( $? == 0 ))

echo "AC8 versions and the release"
# t99 (human-chosen, 2026-11-09): a later release must not break this check. VERSION is at least 3.5.1, every
# manifest agrees with it, the changelog starts with that version's dated section, and the 3.5.1 section stays.
v="$(tr -d '[:space:]' < "$ROOT/VERSION")"
python3 -B -c 'import sys; t=tuple(int(x) for x in sys.argv[1].split(".")); sys.exit(0 if len(t)==3 and t>=(3,5,1) else 1)' "$v" 2>/dev/null
ac "VERSION is 3.5.1 or later" $(( $? == 0 )) "$v"
for f in .claude-plugin/plugin.json .codex-plugin/plugin.json; do
  [[ "$(python3 -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/$f")" == "$v" ]]; ac "$f agrees with VERSION ($v)" $(( $? == 0 ))
done
[[ "$(python3 -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["plugins"][0]["version"])' "$ROOT/.claude-plugin/marketplace.json")" == "$v" ]]; ac "marketplace.json agrees with VERSION ($v)" $(( $? == 0 ))
head1="$(grep -m1 '^## ' "$ROOT/CHANGELOG.md")"; grep -qE "^## ${v//./\\.} — [0-9]{4}-[0-9]{2}-[0-9]{2}\$" <<<"$head1"; ac "the changelog starts with a dated $v section" $(( $? == 0 )) "$head1"
sec="$(awk '/^## /{p = ($2 == "3.5.1")} p' "$ROOT/CHANGELOG.md")"; grep -q 't93' <<<"$sec"; ac "the 3.5.1 changelog section tells users on the t93 hop to close it" $(( $? == 0 ))
( cd "$ROOT" && bash tests/ac/codex_compatibility.sh ) >"$TMP/cx.o" 2>&1; ac "the Codex check passes on the real tree" $(( $? == 0 )) "$(tail -1 "$TMP/cx.o" | cut -c1-140)"
tw="$TMP/cx"; mkdir -p "$tw"; ( cd "$ROOT" && tar -cf - --exclude .git --exclude .cascade . ) | tar -xf - -C "$tw"
( cd "$tw" && git init -q -b main && quiet_commit tree; printf '9.9.9\n' > VERSION; bash tests/ac/codex_compatibility.sh ) >"$TMP/cx2.o" 2>&1; ac "red twin: the Codex check fails on a version mismatch" $(( $? != 0 ))

echo "AC9 hop_guard protects its own files"
hd() { ( cd "$1" && python3 -B -c 'import json,os,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":os.path.join(os.getcwd(),sys.argv[1]),"content":"x"},"cwd":os.getcwd(),"session_id":"s"}))' "$2" \
  | python3 -B "$3" ) 2>&1 | grep -oE '"permissionDecision": *"[a-z]+"' | grep -oE '(deny|ask|allow)"' | tr -d '"'; }
d="$(fresh hg no-plugin)"; sethop "$d" EXECUTE 05b a
for p in .claude/hooks/hop_guard.py .claude/hooks/new_hook.py .claude/settings.json .claude/settings.local.json .githooks/pre-commit .cascade/manifest; do
  v="$(hd "$d" "$p" .claude/hooks/hop_guard.py)"; [[ "$v" == ask || "$v" == deny ]]; ac "installed repo stops a write to $p" $(( $? == 0 )) "got [$v]"
done
v="$(hd "$d" src/app.py .claude/hooks/hop_guard.py)"; [[ -z "$v" || "$v" == allow ]]; ac "control: product code on EXECUTE stays allowed" $(( $? == 0 )) "got [$v]"
v="$(hd "$d" docs/cascade/note.md .claude/hooks/hop_guard.py)"; [[ -z "$v" || "$v" == allow ]]; ac "control: a doc on EXECUTE stays allowed" $(( $? == 0 )) "got [$v]"
cx() { ( cd "$1" && python3 -B -c 'import json,os,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_use_id":"t96-"+sys.argv[1],"tool_input":{"command":"*** Begin Patch\n*** Update File: "+sys.argv[1]+"\n@@\n-a\n+b\n*** End Patch\n"},"cwd":os.getcwd(),"session_id":"s"}))' "$2" \
  | BDD_HOOK_HOST=codex python3 -B .claude/hooks/hop_guard.py ) 2>&1 | grep -oE '"permissionDecision": *"[a-z]+"' | grep -oE '(deny|ask|allow)"' | tr -d '"'; }
for p in .claude/hooks/hop_guard.py .claude/settings.json .githooks/pre-commit .cascade/manifest; do
  v="$(cx "$d" "$p")"; [[ "$v" == deny ]]; ac "Codex apply_patch is denied on $p" $(( $? == 0 )) "got [$v]"
done
v="$(cx "$d" src/app.py)"; [[ -z "$v" || "$v" == allow ]]; ac "control: Codex apply_patch on product code stays allowed" $(( $? == 0 )) "got [$v]"
mv "$d/.cascade/manifest" "$TMP/hg.manifest"
v="$(hd "$d" .claude/hooks/hop_guard.py .claude/hooks/hop_guard.py)"; [[ -z "$v" || "$v" == allow ]]; ac "a repo with no manifest keeps the current decision" $(( $? == 0 )) "got [$v]"
mv "$TMP/hg.manifest" "$d/.cascade/manifest"
d="$(fresh hgp plugin)"; sethop "$d" EXECUTE 05b a
for p in .githooks/pre-commit .cascade/manifest .claude/settings.json; do
  v="$(hd "$d" "$p" "$ROOT/.claude/hooks/hop_guard.py")"; [[ "$v" == ask || "$v" == deny ]]; ac "plugin mode stops a write to $p" $(( $? == 0 )) "got [$v]"
done

if [[ "${T96_FAST:-0}" == 1 ]]; then
  echo; [[ $FAILS -eq 0 ]] && { echo "T96 AC1-AC9 PASS"; exit 0; }; echo "T96 AC FAILED ($FAILS)"; exit 1
fi
if [[ $FAILS -ne 0 ]]; then
  echo; echo "AC10 and AC11 not run: AC1-AC9 are red."; echo "T96 AC FAILED ($FAILS)"; exit 1
fi

echo "AC10 a missing fixture in the pack is a FAIL, never a SKIP"
p="$TMP/packcopy"; mkdir -p "$p"; ( cd "$ROOT" && tar -cf - --exclude .cascade . ) | tar -xf - -C "$p"
mkdir -p "$TMP/saved"; ( cd "$p" && mv tests/ac/fixtures/t74_twins.py commands/doctor.md .claude/settings.json .claude/hooks "$TMP/saved/"; bash tests/enforcement.sh ) >"$TMP/pack74.o" 2>&1
for t in T52 T53 T54 T74; do grep -qE "^FAIL  $t\b" "$TMP/pack74.o"; ac "$t is a FAIL" $(( $? == 0 )) "$(grep -E "^[A-Z]+  $t\b" "$TMP/pack74.o" | head -1 | cut -c1-120)"; done
grep -qE '^SKIP  T(52|53|54|74)\b' "$TMP/pack74.o"; ac "the pack skips none of T52 T53 T54 T74" $(( $? != 0 ))

echo "AC11 a fresh clone of each install mode passes the workflow"
replay() {
  # Separate lines: bash 3.2 expands the values of one `local` before it assigns any of them.
  local m="$1" st o rc
  local s="$TMP/ci-src-$m"
  local c="$TMP/ci-$m"
  mkdir -p "$s"; ( cd "$s" && git init -q -b main && printf 'x=1\n' > app.py && git add -A && git commit -qm init \
    && bash "$ROOT/install.sh" "--$m" . >/dev/null 2>&1; git add -A && git commit -qm 'install bdd' ) >"$s.first" 2>&1 \
    && echo "ok    $m: the first commit passes the real hook" || echo "FAIL  $m: the first commit  $(grep -m1 BLOCKED "$s.first" | cut -c1-120)"
  git clone -q "$s" "$c" || { echo "FAIL  $m: clone"; return; }
  cd "$c" || return
  while IFS= read -r st; do
    o="$TMP/ci-$m-$(printf '%s' "$st" | tr -dc a-z).out"; bash -c "$st" >"$o" 2>&1; rc=$?
    [[ $rc -eq 0 ]] && echo "ok    $m: $st" || echo "FAIL  $m: $st rc=$rc  $(grep -E '^FAIL' "$o" | awk '{print $2}' | tr '\n' ',' | cut -c1-90)"
    if [[ "$st" == "bash tests/barbar.sh" ]]; then
      if grep -E '^BARBAR [0-9]+/[0-9]+' "$o" | tail -1 | awk '{split($2,a,"/"); exit !(a[1]==a[2])}'; then echo "ok    $m: the farm is n/n"; else echo "FAIL  $m: the farm  $(grep -E '^BARBAR' "$o" | tail -1)"; fi
    fi
  done <<'EOF'
bash tests/control-line.sh
bash tests/lint.sh
bash tests/critique.sh
bash tests/diverge.sh
bash tests/i17_dune.sh
bash tests/drift.sh
bash tests/enforcement.sh
bash tests/barbar.sh
bash tests/regress.sh --gate --ci
EOF
  o="$(git status --porcelain)"; [[ -z "$o" ]] && echo "ok    $m: the tree stays clean" || echo "FAIL  $m: the tree  $(head -2 <<<"$o" | tr '\n' ';' | cut -c1-100)"
  o="$(bash tests/barbar.sh merge 2>&1)"; grep -q 'farm is not n/n' <<<"$o" && echo "FAIL  $m: the merge gate still says farm is not n/n" || echo "ok    $m: the farm no longer blocks the merge gate"
  ( cd "$s" && bash tests/doctor.sh ) >"$c.doc" 2>&1 && echo "ok    $m: doctor exits 0" || echo "FAIL  $m: doctor  $(grep -E '^DOCTOR|RED' "$c.doc" | head -2 | tr '\n' ';' | cut -c1-130)"
}
replay no-plugin >"$TMP/r1.o" 2>&1 & p1=$!
replay plugin >"$TMP/r2.o" 2>&1 & p2=$!
wait "$p1" "$p2"
while IFS= read -r l; do echo "  $l"; [[ "$l" == FAIL* ]] && FAILS=$((FAILS+1)); done < <(cat "$TMP/r1.o" "$TMP/r2.o")

echo; [[ $FAILS -eq 0 ]] && { echo "T96 AC all PASS"; exit 0; }; echo "T96 AC FAILED ($FAILS)"; exit 1
