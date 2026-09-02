#!/usr/bin/env bash
# I18 evidence: T8–T15. Each enforcement layer is exercised for real, in a throwaway
# git repo, the way an agent would hit it. Not greps. If one is red, that layer is prose.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

# ---- helpers ------------------------------------------------------------------
mkrepo() {  # mkrepo <dir> <HOP> <STAGE> [dsharp-line]
  local d="$1"
  mkdir -p "$d/docs/cascade" "$d/tests"
  cp -R "$ROOT/.githooks" "$d/.githooks"
  cp -R "$ROOT/tests/lib" "$d/tests/lib"
  cp "$ROOT/tests/loop.sh" "$d/tests/loop.sh"
  printf 'CURRENT_HOP: %s\nCURRENT_STAGE: %s\n\n%s\n' "$2" "$3" "${4:-}" > "$d/docs/cascade/envelope.md"
  ( cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/main \
      && git config core.hooksPath .githooks && git add -A && git commit -qm init )
}
commit_try() {  # commit_try <dir> <file> <content>  -> prints rc
  ( cd "$1" && mkdir -p "$(dirname "$2")" && printf '%s\n' "$3" > "$2" && git add -A \
      && git commit -qm t >/dev/null 2>"$TMP/err"; echo $? )
}
hook() { python3 "$ROOT/.claude/hooks/$1" 2>"$TMP/hook.err"; }

# ---- T8 / T9  git pre-commit: hop guard --------------------------------------
R="$TMP/t8"; mkrepo "$R" GENERATE 05b
rc="$(commit_try "$R" src/app.py 'print(1)')"
ok=0; [[ "$rc" -ne 0 ]] && grep -q 'BLOCKED: GENERATE' "$TMP/err" && ok=1
t T8 "$ok" "pre-commit blocks product code on a GENERATE hop"

R1="$TMP/t9a"; mkrepo "$R1" GENERATE 05b
rc1="$(commit_try "$R1" docs/cascade/05b-spec.md '# spec')"
R2="$TMP/t9"; mkrepo "$R2" EXECUTE 05b
rc2="$(commit_try "$R2" src/app.py 'print(1)')"
ok=0; [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]] && ok=1
t T9 "$ok" "pre-commit allows spec on GENERATE and product code on EXECUTE"

# ---- T10  git pre-commit: <EDIT> tags are human ------------------------------
R="$TMP/t10"; mkrepo "$R" EXECUTE 05b
( cd "$R" && printf 'Product: <EDIT>{{NAME}}</EDIT>\n' > docs/cascade/00-intake.md && git add -A && git commit -qm intake )
rc="$(commit_try "$R" docs/cascade/00-intake.md 'Product: <EDIT>Acme</EDIT>')"
ok=0; [[ "$rc" -ne 0 ]] && grep -q 'EDIT' "$TMP/err" && ok=1
rc2="$(commit_try "$R" docs/cascade/00-intake.md 'Product: <EDIT>{{NAME}}</EDIT>
Owner: <EDIT>{{OWNER}}</EDIT>')"
[[ "$rc2" -eq 0 ]] || ok=0
t T10 "$ok" "pre-commit blocks a changed <EDIT>, allows adding a new one"

# ---- T11  git pre-push: never straight to main --------------------------------
R="$TMP/t11"; mkrepo "$R" EXECUTE 05b
git init -q --bare "$TMP/t11-remote.git"
( cd "$R" && git remote add origin "$TMP/t11-remote.git" )
( cd "$R" && git push -q origin main 2>"$TMP/err" ); rc_main=$?
( cd "$R" && git checkout -q -b 05b-slice && git push -q origin 05b-slice 2>/dev/null ); rc_branch=$?
ok=0; [[ "$rc_main" -ne 0 && "$rc_branch" -eq 0 ]] && grep -q 'BLOCKED: direct push' "$TMP/err" && ok=1
t T11 "$ok" "pre-push blocks main, allows a slice branch"

# ---- T12 / T13  tests/loop.sh -------------------------------------------------
R="$TMP/t12"; mkrepo "$R" GENERATE 05b
printf 'VALIDATOR: true\n' > "$R/docs/cascade/goal.md"
( cd "$R" && bash tests/loop.sh >/dev/null 2>"$TMP/err" ); rc=$?
ok=0; [[ "$rc" -eq 3 ]] && grep -q 'illegal on a GENERATE' "$TMP/err" && ok=1
t T12 "$ok" "loop.sh refuses on a GENERATE hop"

R="$TMP/t13"; mkrepo "$R" EXECUTE 05b 'D1 | balance MUST NOT go negative | test 1 = 1 | test 1 = 2'
printf 'VALIDATOR: true\n' > "$R/docs/cascade/goal.md"
out="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc_omit=$?
printf 'VALIDATOR: true\nVALIDATOR: test 1 = 1\n' > "$R/docs/cascade/goal.md"
out2="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc_full=$?
ok=0
[[ "$rc_omit" -ne 0 ]] && echo "$out" | grep -q 'omitted from /goal: D1' && echo "$out" | grep -q 'LOOP 1/2' \
  && [[ "$rc_full" -eq 0 ]] && echo "$out2" | grep -q 'LOOP 2/2' && ok=1
t T13 "$ok" "loop.sh: omitted in-force D# is a FAIL entry; LOOP k/n is machine output"

# ---- T14  farm fails closed ---------------------------------------------------
P="$TMP/t14"; mkdir -p "$P"
for x in tests evals docs .claude .github CONTROL-LINE.md AGENTS.md; do cp -R "$ROOT/$x" "$P/$x"; done
rm -f "$P/tests/enforcement.sh"   # no recursion; farm skips it when absent
printf 'CURRENT_HOP: NONE\nCURRENT_STAGE:\n' > "$P/docs/cascade/envelope.md"   # hermetic
printf '# oneshot-not-barbar implemented-needs-evidence\nraise SystemExit(3)\n' > "$P/tests/score_hops.py"
out="$(bash "$P/tests/barbar.sh" 2>&1)"; rc=$?
ok=0; [[ "$rc" -ne 0 ]] && echo "$out" | grep -q 'FAIL  hop-scorer' && ok=1
out2="$(BARBAR_ROOT="$P/evals/fixtures/ready-product" bash "$P/tests/barbar.sh" merge 2>&1)"; rc2=$?
[[ "$rc2" -ne 0 ]] && echo "$out2" | grep -q 'farm is not n/n' || ok=0
# A product that legitimately reaches CLEAN 10 + READY 11 must still farm n/n (found by the Docker spike, S13).
P2="$TMP/t14b"; mkdir -p "$P2"   # copy first; a pre-existing docs/ would make cp nest into docs/docs
for x in tests evals docs .claude .github CONTROL-LINE.md AGENTS.md; do cp -R "$ROOT/$x" "$P2/$x"; done
rm -f "$P2/tests/enforcement.sh"
# Hermetic: never inherit the host's envelope (a product's D# validators need product code we did not copy).
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 11\n\nD1 | balance MUST NOT go negative | true | false\n' > "$P2/docs/cascade/envelope.md"
printf '| ID | claim | evidence | status |\n| FR-1 | envelope | path: docs/cascade/envelope.md test: true | IMPLEMENTED |\n| D1 | balance | validator | IMPLEMENTED |\n' > "$P2/docs/cascade/10-audit.md"
printf '# 11\n\n<EDIT>\n## Verdict: READY\n</EDIT>\n' > "$P2/docs/cascade/11-prr.md"
out3="$(bash "$P2/tests/barbar.sh" 2>&1)"; rc3=$?
[[ "$rc3" -eq 0 ]] && echo "$out3" | grep -qE 'BARBAR [0-9]+/[0-9]+' || { ok=0; echo "  farm went red inside a READY product: $(echo "$out3" | grep FAIL | head -2)"; }
out4="$(bash "$P2/tests/barbar.sh" merge 2>&1)"; rc4=$?
[[ "$rc4" -eq 0 ]] && echo "$out4" | grep -q ALLOWED || { ok=0; echo "  merge not ALLOWED in a READY product (rc=$rc4)"; }
t T14 "$ok" "farm is red when the scorer dies; merge runs the farm first; READY product still farms n/n and merges"

# ---- T15  Claude Code hooks ---------------------------------------------------
R="$TMP/t15"; mkrepo "$R" GENERATE 05b
ok=1
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/src/app.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard did not deny product Write on GENERATE"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/x.md","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard denied a spec write"; }

j="$(printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | hook bash_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard did not deny push to main"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 12 --squash"}}' | hook bash_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard did not deny gh pr merge"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"cat > x.md <<EOF\\nnever run git push origin main\\nEOF\\necho \\"gh pr merge is forbidden\\""}}' | hook bash_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  bash_guard denied prose in a heredoc/echo"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"git config core.hooksPath /dev/null"}}' | hook bash_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard did not deny re-pointing core.hooksPath"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"git config core.hooksPath && git config core.hooksPath .githooks"}}' | hook bash_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  bash_guard denied reading hooksPath or setting .githooks"; }

tr="$TMP/transcript.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Implemented the slice. Done."}]}}\n' > "$tr"
sed -i.bak 's/GENERATE/EXECUTE/' "$R/docs/cascade/envelope.md"
printf '{"cwd":"%s","transcript_path":"%s","stop_hook_active":false}' "$R" "$tr" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 2 ]] && grep -q 'STITCH NEEDED' "$TMP/hook.err" || { ok=0; echo "  stop_guard let a hop end without STITCH NEEDED (rc=$rc)"; }
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"...\\nSTITCH NEEDED: accept execute for stage 05b, or send back."}]}}\n' > "$tr"
printf '{"cwd":"%s","transcript_path":"%s","stop_hook_active":false}' "$R" "$tr" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 0 ]] || { ok=0; echo "  stop_guard blocked a closed hop"; }

j="$(printf '{"cwd":"%s","source":"compact"}' "$R" | hook preserve.py)"
echo "$j" | grep -q 'additionalContext' && echo "$j" | grep -q 'Current hop: EXECUTE' || { ok=0; echo "  preserve did not re-inject after compact"; }
j="$(printf '{"cwd":"%s","source":"startup"}' "$R" | hook preserve.py)"
[[ -z "$j" ]] || { ok=0; echo "  preserve fired on plain startup"; }
t T15 "$ok" "Claude hooks: deny product Write on GENERATE, deny ship escapes, block open hop, re-inject on compact"

# ---- T17  hop state and D# lines are human-owned; CASCADE_HUMAN=1 is the human's key ----
R="$TMP/t17"; mkrepo "$R" GENERATE 05b 'D1 | balance MUST NOT go negative | test 1 = 1 | test 1 = 2'
( cd "$R" && sed -i.bak 's/^CURRENT_HOP: GENERATE/CURRENT_HOP: EXECUTE/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak \
    && git add -A && git commit -qm "agent flips hop" >/dev/null 2>"$TMP/err" ); rc_flip=$?
ok=0; [[ "$rc_flip" -ne 0 ]] && grep -q 'human-owned' "$TMP/err" && ok=1
( cd "$R" && CASCADE_HUMAN=1 git commit -qm "human: approved, execute 05b" >/dev/null 2>&1 ); [[ $? -eq 0 ]] || { ok=0; echo "  human could not commit the hop edge with the key"; }
( cd "$R" && sed -i.bak 's/| test 1 = 1 | test 1 = 2$/| true | false/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "agent softens D1" >/dev/null 2>"$TMP/err" ); [[ $? -ne 0 ]] && grep -q 'human-owned' "$TMP/err" || { ok=0; echo "  agent changed a D# validator"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_HOP: EXECUTE","new_string":"CURRENT_HOP: GENERATE"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard let the agent flip the hop"; }
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_SLICE:","new_string":"CURRENT_SLICE:"}}' "$R" "$R" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard denied a no-op edit"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"CASCADE_HUMAN=1 git commit -m x"}}' | hook bash_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard let the agent use the human key"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: mention CASCADE_HUMAN=1 in INTEGRATION\""}}' | hook bash_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  bash_guard denied merely mentioning the key in quotes"; }
t T17 "$ok" "agent cannot flip the hop or soften a D# (pre-commit + hop_guard); human can with the key; agent denied the key"

# ---- T18  red twin: a D# is in force only when it can fail ----
R="$TMP/t18"; mkrepo "$R" EXECUTE 05b 'D1 | balance MUST NOT go negative | true | true'
out="$(bash "$ROOT/tests/dsharp_strength.sh" --root "$R" 2>&1)"; rc_th=$?
ok=0; [[ "$rc_th" -ne 0 ]] && echo "$out" | grep -q '^THEATER' && echo "$out" | grep -q 'DSHARP 0/1' && ok=1
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\n\nD1 | balance MUST NOT go negative | true | false\nD2 | tenant isolation | true\n' > "$R/docs/cascade/envelope.md"
out="$(bash "$ROOT/tests/dsharp_strength.sh" --root "$R" 2>&1)"; rc_un=$?
[[ "$rc_un" -ne 0 ]] && echo "$out" | grep -q '^GREEN     D1' && echo "$out" | grep -q '^UNPROVEN  D2' && echo "$out" | grep -q 'DSHARP 1/2' || { ok=0; echo "  strength did not report GREEN D1 + UNPROVEN D2"; }
printf 'VALIDATOR: true\nVALIDATOR: true\n' > "$R/docs/cascade/goal.md"
( cd "$R" && bash tests/loop.sh >/dev/null 2>"$TMP/err" ); rc=$?
[[ "$rc" -eq 3 ]] && grep -q 'not in force' "$TMP/err" || { ok=0; echo "  loop.sh did not refuse on an UNPROVEN D# (rc=$rc)"; }
printf 'VALIDATOR: true\nVALIDATOR: true\nWAIVE_DSHARP: D2 tenancy lands in slice 3 — approved by human 2026-09-02\n' > "$R/docs/cascade/goal.md"
out="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'WAIVED  D2' && echo "$out" | grep -q 'LOOP 2/2' || { ok=0; echo "  written waiver did not lift the block (rc=$rc)"; }
t T18 "$ok" "red twin: THEATER is red, UNPROVEN blocks loop.sh, a written waiver lifts it, DSHARP k/n is machine output"

# ---- T19  stage 10 is computed from the tree, never read from prose (I7, I8) ----
R="$TMP/t19"; mkrepo "$R" EXECUTE 10 'D1 | balance MUST NOT go negative | true | false'
mkdir -p "$R/src"; echo 'x=1' > "$R/src/app.py"
printf '# 03 PRD\n\nFR-1 login\nFR-2 refunds\n' > "$R/docs/cascade/03-prd.md"
cat > "$R/docs/cascade/10-audit.md" <<'A'
| ID | Spec claim | Evidence | Primary status |
| FR-1 | login | path: src/app.py test: true | IMPLEMENTED |
| D1 | balance MUST NOT go negative | validator in envelope | IMPLEMENTED |
| FR-3 | extra | path: src/nope.py test: true | IMPLEMENTED |
| FR-4 | lied | path: src/app.py test: false | IMPLEMENTED |
| FR-5 | improved | path: src/app.py test: true | REFINED |
<EDIT>
| FR-6 | promoted | path: src/app.py test: true | REFINED |
</EDIT>
## Audit verdict: CLEAN
A
out="$(bash "$ROOT/tests/audit.sh" --root "$R" 2>&1)"; rc=$?
ok=1; [[ "$rc" -ne 0 ]] || { ok=0; echo "  audit exit 0 despite bad rows"; }
echo "$out" | grep -q '^IMPLEMENTED  FR-1' || { ok=0; echo "  FR-1 real evidence not IMPLEMENTED"; }
echo "$out" | grep -q '^MISSING      FR-2' || { ok=0; echo "  FR-2 in PRD with no row not MISSING"; }
echo "$out" | grep -q '^MISSING      FR-3' || { ok=0; echo "  FR-3 fake path not MISSING"; }
echo "$out" | grep -q '^VIOLATED     FR-4' || { ok=0; echo "  FR-4 red test not VIOLATED"; }
echo "$out" | grep -q '^DRIFTED      FR-5' || { ok=0; echo "  FR-5 unpromoted REFINED not DRIFTED"; }
echo "$out" | grep -q '^IMPLEMENTED  FR-6' || { ok=0; echo "  FR-6 human-promoted REFINED not IMPLEMENTED"; }
echo "$out" | grep -q '^IMPLEMENTED  D1' || { ok=0; echo "  GREEN D1 not IMPLEMENTED"; }
echo "$out" | grep -q 'Audit verdict: DIRTY' || { ok=0; echo "  prose CLEAN line was believed"; }
printf 'D1 | balance MUST NOT go negative | false | false\n' >> "$R/docs/cascade/envelope.md"
sed -i.bak 's/^D1 | balance MUST NOT go negative | true | false$//' "$R/docs/cascade/envelope.md"; rm -f "$R/docs/cascade/envelope.md.bak"
out="$(bash "$ROOT/tests/audit.sh" --root "$R" 2>&1)"; echo "$out" | grep -q '^VIOLATED     D1' || { ok=0; echo "  RED D1 not VIOLATED"; }
t T19 "$ok" "audit.sh: path must exist, test must pass, REFINED needs <EDIT>, PRD IDs without rows are MISSING, prose verdict ignored"

# ---- T20  seam hook: per-hop skill binding is injected, cascade precedence stated (I14 as mechanism) ----
R="$TMP/t20"; mkrepo "$R" GENERATE 05b
cp "$ROOT/docs/cascade/skill-binding.md" "$R/docs/cascade/"
ok=1
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"
echo "$j" | grep -q 'class GENERATE' && echo "$j" | grep -q 'allowed this hop: brainstorming' && echo "$j" | grep -q 'denied this hop: executing-plans' && echo "$j" | grep -q 'loop.sh` is ILLEGAL' || { ok=0; echo "  GENERATE binding not injected"; }
sed -i.bak 's/^CURRENT_HOP: GENERATE/CURRENT_HOP: EXECUTE/' "$R/docs/cascade/envelope.md"
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"
echo "$j" | grep -q 'class EXECUTE-BUILD' && echo "$j" | grep -q 'allowed this hop: test-driven-development' && echo "$j" | grep -q 'denied this hop: brainstorming' && echo "$j" | grep -q 'loop.sh` is legal' || { ok=0; echo "  EXECUTE-BUILD binding not injected"; }
sed -i.bak 's/^CURRENT_STAGE: 05b/CURRENT_STAGE: 03/' "$R/docs/cascade/envelope.md"
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"
echo "$j" | grep -q 'class EXECUTE-DESIGN' && echo "$j" | grep -q 'denied this hop: test-driven-development' || { ok=0; echo "  EXECUTE-DESIGN binding not injected"; }
sed -i.bak 's/^CURRENT_HOP: EXECUTE/CURRENT_HOP: NONE/' "$R/docs/cascade/envelope.md"
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"
[[ -z "$j" ]] || { ok=0; echo "  seam hook spoke while no cascade is running"; }
t T20 "$ok" "seam hook injects the per-hop skill allow/deny + precedence; silent when CURRENT_HOP is NONE"

# ---- T21  guards fail visibly, never open; CRLF envelopes still parse ----
R="$TMP/t21"; mkrepo "$R" GENERATE 05b 'D1 | law | test 1 = 1 | test 1 = 2'
ok=1
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/src/x.py","content":"x"}}' "$R" "$R" | CASCADE_HOOK_SELFTEST_RAISE=1 hook hop_guard.py)"
echo "$j" | grep -q '"ask"' || { ok=0; echo "  a crashing hop_guard did not surface as 'ask'"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | CASCADE_HOOK_SELFTEST_RAISE=1 hook bash_guard.py)"
echo "$j" | grep -q '"ask"' || { ok=0; echo "  a crashing bash_guard did not surface as 'ask'"; }
printf 'CURRENT_HOP: EXECUTE\r\nCURRENT_STAGE: 05b\r\n\r\nD1 | law | test 1 = 1 | test 1 = 2\r\n' > "$R/docs/cascade/envelope.md"
printf 'VALIDATOR: true\r\nVALIDATOR: test 1 = 1\r\n' > "$R/docs/cascade/goal.md"
out="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'LOOP 2/2' || { ok=0; echo "  CRLF envelope/goal broke loop.sh (rc=$rc): $(echo "$out" | tail -2 | tr '\n' ' ')"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/src/x.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard misread a CRLF EXECUTE hop as GENERATE"; }
t T21 "$ok" "a crashing guard returns 'ask' (never fails open); CRLF envelope and goal still parse"

# ---- T22  install manifest + drift check ----
I2="$TMP/t22"; mkdir -p "$I2"; ( cd "$I2" && git init -q )
if [[ -f "$ROOT/install.sh" ]]; then
  bash "$ROOT/install.sh" "$I2" >/dev/null 2>&1
  ok=0; bash "$ROOT/install.sh" --check "$I2" >"$TMP/chk" 2>&1 && grep -q 'no drift' "$TMP/chk" && ok=1
  echo '# softened' >> "$I2/.githooks/pre-commit"; rm -f "$I2/tests/loop.sh"
  bash "$ROOT/install.sh" --check "$I2" >"$TMP/chk" 2>&1; rc=$?
  [[ "$rc" -ne 0 ]] && grep -q 'DRIFTED  .githooks/pre-commit' "$TMP/chk" && grep -q 'MISSING  tests/loop.sh' "$TMP/chk" || { ok=0; echo "  drift check missed a softened hook / deleted script"; }
  t T22 "$ok" "install.sh --check: clean after install; reports a softened hook and a deleted script"
else
  echo "SKIP  T22  no install.sh here (installed product, not the pack)"
fi

# ---- T16  install.sh places Layer 2 where the agent actually loads it (found by probe P6) ----
# Tests the pack's installer, so it only runs in the pack repo. Installed products have no install.sh.
if [[ ! -f "$ROOT/install.sh" ]]; then
  echo "SKIP  T16  no install.sh here (installed product, not the pack)"
else
I="$TMP/t16"; mkdir -p "$I"; ( cd "$I" && git init -q )
bash "$ROOT/install.sh" "$I" >/dev/null 2>&1
ok=0; [[ -f "$I/.claude/skills/barbar/SKILL.md" && -f "$I/.claude/commands/barbar.md" && -f "$I/.claude/commands/loop.md" && -f "$I/.claude/hooks/hop_guard.py" && -f "$I/.claude/settings.json" && -x "$I/.githooks/pre-commit" ]] \
  && [[ "$(cd "$I" && git config core.hooksPath)" == ".githooks" ]] && ok=1
# The installed farm must be n/n in the product (Docker spike S1). Guarded: the nested farm skips this step.
if [[ -z "${CASCADE_ENFORCEMENT_NESTED:-}" ]]; then
  ( cd "$I" && CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >"$TMP/t16.farm" 2>&1 ) || { ok=0; echo "  installed farm red: $(grep -E '^FAIL' "$TMP/t16.farm" | head -3 | tr '\n' ' ')"; }
fi
t T16 "$ok" "install.sh puts skill + commands + hooks under .claude/, sets core.hooksPath; installed farm is n/n"
fi

if [[ "$fail" -ne 0 ]]; then exit 1; fi
echo "PASS: I18 T8–T22 enforced"
