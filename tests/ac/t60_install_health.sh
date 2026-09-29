#!/usr/bin/env bash
# AC tests for 05b t60-install-health-multi-break (2.1.1). No product installed with 2.0.0 or 2.1.0 reported
# healthy: installs copied the pack's live hop state and goal, T52 compared a pack-only folder, upgrades never
# refreshed AGENTS.md, and a second `break:` line was dropped without a word. Each fix has a red twin that
# reproduces the old behaviour in a scratch copy and must make its check fail.
#   AC1  a fresh install starts clean; an upgrade names leaked lines and never edits them   (2 twins)
#   AC2  T52 passes inside an installed product, and still catches drift in the pack        (twin: unguarded)
#   AC3  AGENTS.md: the cascade block is refreshed in place and watched; own rules kept      (twin: old install)
#   AC4m the settings merge refreshes the matcher of the pack's own entries only             (twin: no refresh)
#   AC5  a law with two `break:` lines is UNPROVEN everywhere; one-break and legacy unchanged (twin: last-wins)
# AC4 (preserve.py on startup) and AC6 (heading-style laws guarded) run through the real hooks: enforcement.sh T60.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR BDD_PLUGIN_ROOT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

packcopy() { mkdir -p "$1"; ( cd "$ROOT" && tar --exclude=./.git --exclude=./.cascade -cf - . ) | ( cd "$1" && tar -xf - ); }
newrepo() { mkdir -p "$1"; git -C "$1" init -q; echo 'print(1)' > "$1/app.py"; git -C "$1" add -A; git -C "$1" commit -qm init; }
install_into() { bash "$1/install.sh" --no-plugin "$2" > "$TMP/install.out" 2>&1; }
patch() {  # patch <file> <old> <new> — exact, once; a missing anchor fails the twin loudly, never silently
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit(f"red twin: anchor not found in {p} — update the twin with the code: {old[:60]!r}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

# ---- AC1  fresh install is clean; an upgrade names what to clear -------------------------------------------
L="$TMP/leakpack"; packcopy "$L"
sed -i.bak 's/^AUTOPILOT:.*/AUTOPILOT: 05b zzleak60/' "$L/docs/cascade/hop-state.md"; rm -f "$L/docs/cascade/hop-state.md.bak"
printf 'VALIDATOR: bash tests/ac/zzleak60.sh\n' >> "$L/docs/cascade/goal.md"
P="$TMP/p1"; newrepo "$P"; install_into "$L" "$P"
hs="$P/docs/cascade/hop-state.md"; gl="$P/docs/cascade/goal.md"
ok=1
grep -qx 'CURRENT_HOP: NONE' "$hs" && grep -qx 'CURRENT_SLICE:' "$hs" && grep -qx 'AUTOPILOT:' "$hs" \
  || { ok=0; echo "  fresh hop state is not blank: $(grep -E '^(CURRENT_|AUTOPILOT)' "$hs" | tr '\n' ' ')"; }
! grep -q '^VALIDATOR:' "$gl" || { ok=0; echo "  fresh goal carries validators: $(grep '^VALIDATOR:' "$gl")"; }
! grep -rqs 'zzleak60' "$P/docs/cascade" || { ok=0; echo "  the pack's live state leaked into the product"; }
[[ -z "$(python3 -B "$P/tests/lib/laws.py" "$P/docs/cascade/envelope.md" --declared)" ]] || { ok=0; echo "  a fresh product declares a law"; }
bash "$L/install.sh" --check "$P" >/dev/null 2>&1 || { ok=0; echo "  --check is not clean after a fresh install"; }
doc="$(cd "$P" && DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"   # captured: doctor's own exit code must not decide the grep
echo "$doc" | grep -E '^ +-- +hop state' | grep -q RED && { ok=0; echo "  doctor's hop-state line is RED on a fresh install"; }
# Upgrade over a product that already carries the leaked lines: warn with the fix, change nothing.
Q="$TMP/p1up"; newrepo "$Q"; install_into "$ROOT" "$Q"
sed -i.bak 's/^AUTOPILOT:.*/AUTOPILOT: 05b zzleak60/' "$Q/docs/cascade/hop-state.md"; rm -f "$Q/docs/cascade/hop-state.md.bak"
printf 'VALIDATOR: bash tests/ac/zzleak60.sh\n' >> "$Q/docs/cascade/goal.md"
before="$(cat "$Q/docs/cascade/hop-state.md" "$Q/docs/cascade/goal.md")"
install_into "$ROOT" "$Q"
grep -q "LEAKED? docs/cascade/hop-state.md: AUTOPILOT lists 05b 'zzleak60'" "$TMP/install.out" && grep -q 'bash tests/sign.sh' "$TMP/install.out" \
  || { ok=0; echo "  the upgrade did not name the leaked AUTOPILOT line and its fix"; }
grep -q 'LEAKED? docs/cascade/goal.md: VALIDATOR names tests/ac/zzleak60.sh' "$TMP/install.out" || { ok=0; echo "  the upgrade did not name the leaked goal validator"; }
[[ "$before" == "$(cat "$Q/docs/cascade/hop-state.md" "$Q/docs/cascade/goal.md")" ]] || { ok=0; echo "  the upgrade edited hop state or goal"; }
t AC1 "$ok" "a fresh install starts with no hop, an empty list, a goal with no validators and no law, --check clean and doctor's hop state not RED; an upgrade over leaked lines names each with its fix and changes neither file"
# RED TWIN A: the old keep lines copy the live files.
L2="$TMP/leakpack-old"; packcopy "$L2"; cp "$L/docs/cascade/hop-state.md" "$L/docs/cascade/goal.md" "$L2/docs/cascade/"
patch "$L2/install.sh" 'keep docs/cascade/goal.md templates/goal.md' 'keep docs/cascade/goal.md' \
  && patch "$L2/install.sh" 'keep docs/cascade/hop-state.md templates/hop-state.md' 'keep docs/cascade/hop-state.md'
twin=$?; P2="$TMP/p1old"; newrepo "$P2"; install_into "$L2" "$P2"
ok=0; [[ "$twin" -eq 0 ]] && grep -rqs 'zzleak60' "$P2/docs/cascade" && ok=1
t AC1-twin-leak "$ok" "RED TWIN: with the old keep lines the pack's live AUTOPILOT and goal reach the product, so AC1 can tell"
# RED TWIN B: an install without the warnings stays silent over leaked lines.
L3="$TMP/nowarn"; packcopy "$L3"; patch "$L3/install.sh" $'\nwarn_leaked\n' $'\n:\n'; twin=$?
install_into "$L3" "$Q"
ok=0; [[ "$twin" -eq 0 ]] && ! grep -q 'LEAKED?' "$TMP/install.out" && ok=1
t AC1-twin-silent "$ok" "RED TWIN: an install without warn_leaked stays silent over the same leaked lines, so AC1 can tell"

# ---- AC2  T52 inside an installed product ------------------------------------------------------------------
t52_in() {  # t52_in <repo> [unguard] -> runs enforcement.sh's prelude + T52 inside <repo>/tests; output on stdout
  local r="$1" x="$1/tests/t52_only.sh"
  { awk '/^# ---- T8 \/ T9/{exit} {print}' "$r/tests/enforcement.sh"
    awk '/^# ---- T52/{p=1; print; next} p && /^# ---- T/{exit} p' "$r/tests/enforcement.sh"
    echo 'exit $fail'; } > "$x"
  [[ "${2:-}" == unguard ]] && python3 - "$x" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s2 = s.replace('  if [[ -d "$ROOT/commands" ]]; then\n', "  if true; then\n", 1)
if s2 == s:
    sys.exit("red twin: T52 guard not found — update the twin")
open(p, "w", encoding="utf-8").write(s2)
PY
  ( cd "$r" && bash "$x" 2>&1 ); local rc=$?; rm -f "$x"; return "$rc"
}
P3="$TMP/p2"; newrepo "$P3"; echo '# the product has its own installer' > "$P3/install.sh"; git -C "$P3" add -A; git -C "$P3" commit -qm own
install_into "$ROOT" "$P3"
ok=1
out="$(t52_in "$P3")"; echo "$out" | grep -q '^PASS  T52' || { ok=0; echo "  T52 failed in an installed product: $(echo "$out" | grep -vE '^PASS' | head -3)"; }
K="$TMP/pack52"; packcopy "$K"; echo "drifted" >> "$K/commands/doctor.md"
out="$(t52_in "$K")"; echo "$out" | grep -q 'commands/doctor.md and .claude/commands/doctor.md differ' || { ok=0; echo "  T52 no longer catches a drifted command file in the pack"; }
t AC2 "$ok" "T52 passes inside an installed product that has its own install.sh, and still catches a drifted command file in the pack"
out="$(t52_in "$P3" unguard)"
ok=0; echo "$out" | grep -q 'commands/doctor.md and .claude/commands/doctor.md differ' && ok=1
t AC2-twin "$ok" "RED TWIN: the unguarded comparison fails T52 in the same product, so AC2 can tell"

# ---- AC3  AGENTS.md refresh -------------------------------------------------------------------------------
old_rules() { sed 's/^1\. One hop per reply.*/1. OLD RULE ONE./' "$ROOT/AGENTS.md" | grep -v '^<!-- end of the Barbaric'; }
block() { awk -v h='# Agent rules — Barbaric Driven Development' -v m='<!-- end of the Barbaric Driven Development rules' \
            '$0 == h {on = 1} on {print} on && index($0, m) == 1 {exit}' "$1"; }
A="$TMP/agents"; mkdir -p "$A"
for c in a b c; do newrepo "$A/$c"; done
{ printf '# My product rules\n\nUse tabs.\n\n---\n\n'; old_rules; } > "$A/a/AGENTS.md"
old_rules > "$A/b/AGENTS.md"
{ printf '# Mine\n\nNo globals.\n\n---\n\n'; sed 's/^1\. One hop per reply.*/1. STALE IN C./' "$ROOT/AGENTS.md"; printf '\nNote after the marker.\n'; } > "$A/c/AGENTS.md"
cp -R "$A/a" "$A/a-old"   # for the twin, before anything refreshes it
ok=1
for c in a b c; do
  install_into "$ROOT" "$A/$c"
  [[ "$(block "$A/$c/AGENTS.md")" == "$(cat "$ROOT/AGENTS.md")" ]] || { ok=0; echo "  $c: the block is not the pack's AGENTS.md"; }
  grep -q 'AGENTS.md#bdd-rules' "$A/$c/.cascade/manifest" || { ok=0; echo "  $c: the manifest does not watch the block"; }
  bash "$ROOT/install.sh" --check "$A/$c" >/dev/null 2>&1 || { ok=0; echo "  $c: --check is not clean after the refresh"; }
done
[[ "$(head -3 "$A/a/AGENTS.md")" == "$(printf '# My product rules\n\nUse tabs.')" ]] || { ok=0; echo "  a: own rules changed"; }
grep -q 'OLD RULE ONE' "$A/a/.cascade/agents-rules.prev" && grep -q 'OLD RULE ONE' "$A/b/.cascade/agents-rules.prev" \
  || { ok=0; echo "  a/b: the replaced text was not saved to .cascade/agents-rules.prev"; }
[[ "$(tail -1 "$A/c/AGENTS.md")" == "Note after the marker." && "$(head -3 "$A/c/AGENTS.md")" == "$(printf '# Mine\n\nNo globals.')" ]] \
  || { ok=0; echo "  c: text above the block or after the marker changed"; }
[[ ! -f "$A/c/.cascade/agents-rules.prev" ]] || { ok=0; echo "  c: a copy was saved although the marker made the boundary exact"; }
install_into "$ROOT" "$A/c"; grep -q '= AGENTS.md (cascade rules current)' "$TMP/install.out" || { ok=0; echo "  c: a second install did not see the rules as current"; }
grep -qxF '.cascade/agents-rules.prev' "$A/a/.gitignore" || { ok=0; echo "  .cascade/agents-rules.prev is not gitignored"; }
sed -i.bak 's/Use tabs./Use spaces./' "$A/a/AGENTS.md"; rm -f "$A/a/AGENTS.md.bak"
bash "$ROOT/install.sh" --check "$A/a" >/dev/null 2>&1 || { ok=0; echo "  editing the product's own rules counted as drift"; }
# (d) an older install where the team wrote their own section BELOW the block: refuse, change nothing, do not watch.
newrepo "$A/d"; { printf '# Mine\n\n---\n\n'; old_rules; printf '\n## my later rule\n\nNever deploy on Fridays.\n'; } > "$A/d/AGENTS.md"
cp -R "$A/d" "$A/d-old"; dh="$(cat "$A/d/AGENTS.md")"; install_into "$ROOT" "$A/d"
[[ "$(cat "$A/d/AGENTS.md")" == "$dh" ]] && grep -q 'sections the pack never wrote (## my later rule)' "$TMP/install.out" \
  && ! grep -q 'AGENTS.md#bdd-rules' "$A/d/.cascade/manifest" \
  || { ok=0; echo "  d: a section the team wrote below the old block was not left alone and named"; }
sed -i.bak 's/^1\. One hop per reply/1. Two hops per reply/' "$A/a/AGENTS.md"; rm -f "$A/a/AGENTS.md.bak"
chk="$(bash "$ROOT/install.sh" --check "$A/a" 2>&1)"   # captured: --check exits 1 on drift, which pipefail would read as a miss
echo "$chk" | grep -q 'DRIFTED  AGENTS.md#bdd-rules' || { ok=0; echo "  editing the cascade block was not reported as drift"; }
t AC3 "$ok" "AGENTS.md: the cascade block is replaced by the pack's in all three layouts, own rules and after-marker text kept, old text saved when there was no marker, the block watched — own edits are not drift, rule edits are; a section the team wrote below an old block is left alone and named"
# RED TWIN: the pre-t60 install leaves the old rule in place.
O="$TMP/oldinstall"; packcopy "$O"
python3 - "$O/install.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = s.index('if [[ -f "$DST/AGENTS.md" ]] && grep -qxF "$AGENTS_HEAD"')
b = s.index('grep -qxF "$AGENTS_HEAD" "$DST/AGENTS.md" && shipped+=')
old = ('if [[ -f "$DST/AGENTS.md" ]]; then\n'
       "  if grep -q 'Barbaric Driven Development' \"$DST/AGENTS.md\"; then echo \"  = AGENTS.md (already carries the cascade rules)\"\n"
       '  else { echo; echo "---"; echo; cat "$SRC/AGENTS.md"; } >> "$DST/AGENTS.md"; fi\n'
       'else cp "$SRC/AGENTS.md" "$DST/AGENTS.md"; fi\n')
open(p, "w", encoding="utf-8").write(s[:a] + old + s[b:])
PY
twin=$?; install_into "$O" "$A/a-old"
ok=0; [[ "$twin" -eq 0 ]] && grep -q 'OLD RULE ONE' "$A/a-old/AGENTS.md" && ok=1
t AC3-twin "$ok" "RED TWIN: the pre-t60 install leaves the old rule in an upgraded AGENTS.md, so AC3 can tell"
# RED TWIN (d): a refresh without the refusal deletes the team's section from AGENTS.md.
D="$TMP/norefuse"; packcopy "$D"; patch "$D/install.sh" '    if theirs:' '    if False:'; twin=$?
install_into "$D" "$A/d-old"
ok=0; [[ "$twin" -eq 0 ]] && ! grep -q 'my later rule' "$A/d-old/AGENTS.md" && ok=1
t AC3-twin-below "$ok" "RED TWIN: without the refusal, a section the team wrote below the old block is deleted from AGENTS.md, so AC3 can tell"

# ---- AC4m  the settings merge refreshes the matcher of the pack's own entries only --------------------------
mk_old_settings() {  # mk_old_settings <settings.json>: the pack's hooks with a 2.1.0 SessionStart matcher + a product hook
  python3 - "$1" "$ROOT/.claude/settings.json" <<'PY'
import json, sys
dst, src = sys.argv[1:3]; ours = json.load(open(src))
hooks = {k: [dict(e) for e in v] for k, v in ours["hooks"].items()}
for e in hooks["SessionStart"]:
    e["matcher"] = "compact|resume|clear"
hooks["SessionStart"].append({"matcher": "startup", "hooks": [{"type": "command", "command": "echo product-own"}]})
json.dump({"hooks": hooks, "permissions": {"allow": ["Bash(ls)"]}}, open(dst, "w"), indent=2)
PY
}
matchers() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ; ".join(str(e.get("matcher"))+"="+",".join(h["command"][-18:] for h in e["hooks"]) for e in d["hooks"]["SessionStart"]))' "$1"; }
M="$TMP/merge"; newrepo "$M"; mkdir -p "$M/.claude"; mk_old_settings "$M/.claude/settings.json"
install_into "$ROOT" "$M"; got="$(matchers "$M/.claude/settings.json")"
ok=1
[[ "$got" == *'startup|compact|resume|clear='*'preserve.py"'* ]] || { ok=0; echo "  the pack's SessionStart entry kept its old matcher: $got"; }
[[ "$got" == *'startup=echo product-own'* ]] || { ok=0; echo "  the product's own hook entry changed: $got"; }
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("permissions")=={"allow":["Bash(ls)"]} else 1)' "$M/.claude/settings.json" \
  || { ok=0; echo "  the product's permissions changed"; }
t AC4m "$ok" "the settings merge gives an upgraded product's SessionStart entry the new startup matcher and leaves the product's own hook entry and permissions exactly as they were"
N="$TMP/norefresh"; packcopy "$N"
patch "$N/install.sh" '            if mine and mine <= cmds and "matcher" in entry and e.get("matcher") != entry["matcher"]:' \
                      '            if False:'
twin=$?; M2="$TMP/merge-old"; newrepo "$M2"; mkdir -p "$M2/.claude"; mk_old_settings "$M2/.claude/settings.json"
install_into "$N" "$M2"
ok=0; [[ "$twin" -eq 0 && "$(matchers "$M2/.claude/settings.json")" == *'compact|resume|clear='*'preserve.py"'* ]] && ok=1
t AC4m-twin "$ok" "RED TWIN: a merge without the matcher refresh leaves the old matcher, so AC4m can tell"

# ---- AC5  a second break: line is never silently ignored ------------------------------------------------------
E="$TMP/laws"; mkdir -p "$E/docs/cascade" "$E/tests"; cp -R "$ROOT/tests/lib" "$E/tests/lib"
cp "$ROOT/tests/dsharp_strength.sh" "$ROOT/tests/loop.sh" "$E/tests/"
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: x\n' > "$E/docs/cascade/hop-state.md"
printf 'VALIDATOR: true\n' > "$E/docs/cascade/goal.md"
printf '# env\n\n### D2 — two breaks\ncheck:  true\nbreak:  false\nbreak:  true\n\n### D4 — one break\ncheck:  true\nbreak:  false\n\nD5 | legacy | true | false\n' > "$E/docs/cascade/envelope.md"
git -C "$E" init -q
ds="$(bash "$E/tests/dsharp_strength.sh" --root "$E" 2>&1)"
ok=1
echo "$ds" | grep -qxF 'UNPROVEN  D2  two breaks  (2 break: lines — only one is supported until 2.2.0)' || { ok=0; echo "  D2 is not UNPROVEN with the reason: $(echo "$ds" | grep D2)"; }
echo "$ds" | grep -qxF 'GREEN     D4  one break' && echo "$ds" | grep -qxF 'GREEN     D5  legacy' || { ok=0; echo "  a one-break or legacy law no longer scores as in 2.1.0"; }
[[ "$(DSHARP_JOBS=4 bash "$E/tests/dsharp_strength.sh" --root "$E" 2>&1)" == "$ds" ]] || { ok=0; echo "  DSHARP_JOBS=4 prints a different report"; }
lp="$(cd "$E" && bash tests/loop.sh 2>&1)"; lrc=$?
[[ "$lrc" -eq 3 ]] && echo "$lp" | grep -q 'D2  two breaks  (2 break: lines — only one is supported until 2.2.0)' || { ok=0; echo "  loop.sh did not refuse naming D2's reason (rc=$lrc)"; }
python3 -B "$E/tests/lib/laws.py" "$E/docs/cascade/envelope.md" --in-force | grep -q '^D2|' && { ok=0; echo "  --in-force still lists D2"; }
[[ "$(python3 -B "$E/tests/lib/laws.py" "$E/docs/cascade/envelope.md" --commands | grep -c "^D2	break	")" -eq 2 ]] || { ok=0; echo "  --commands does not list both of D2's break lines"; }
t AC5 "$ok" "a law with two break: lines is UNPROVEN with its reason in dsharp_strength and loop.sh and out of --in-force; one-break and legacy laws score as in 2.1.0; DSHARP_JOBS=4 prints the same report"
# RED TWIN: the old last-wins parser keeps only D2's last break (`true`) and scores it THEATER, never UNPROVEN.
patch "$E/tests/lib/laws.py" $'                    cur["breaks"].append(f.group(2))\n                    cur["break"] = cur["breaks"][0]' \
                             $'                    cur["breaks"] = [f.group(2)]\n                    cur["break"] = f.group(2)'
twin=$?; ds="$(bash "$E/tests/dsharp_strength.sh" --root "$E" 2>&1)"
ok=0; [[ "$twin" -eq 0 ]] && echo "$ds" | grep -q '^THEATER   D2' && ok=1
t AC5-twin "$ok" "RED TWIN: the old last-wins parser scores D2 THEATER on its last break alone, so AC5 can tell"

echo
if [[ "$fail" -ne 0 ]]; then echo "t60-install-health: FAIL"; exit 1; fi
echo "t60-install-health: PASS"
