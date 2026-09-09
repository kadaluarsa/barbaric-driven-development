#!/usr/bin/env bash
# I18 evidence: T8–T15. Each enforcement layer is exercised for real, in a throwaway
# git repo, the way an agent would hit it. Not greps. If one is red, that layer is prose.
set -uo pipefail
# Git exports GIT_DIR/GIT_WORK_TREE to hooks. Inherited by a script that runs `git init` in a temp dir, they
# redirect it at the real repo (this once flipped a product to core.bare=true and re-pointed a worktree's HEAD).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/cascade.sh
. "$ROOT/tests/lib/cascade.sh"
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
L2="$(cascade_layer2_root 2>/dev/null || true)"   # empty when Layer 2 is on neither the repo nor this machine
hook() { python3 -B "$L2/.claude/hooks/$1" 2>"$TMP/hook.err"; }
# A Layer 2 test cannot run where Layer 2 is not installed (a plugin-mode repo checked out in CI). Skip it —
# do not fail: Layers 0 and 1 are what CI enforces, and they are exercised by the other tests.
layer2() {
  [[ -n "$L2" ]] && return 0
  local where="this machine"; [[ -n "${GITHUB_ACTIONS:-}${CI:-}" ]] && where="this CI runner"
  echo "SKIP  $1  Layer 2 (agent hooks) is not installed on $where — plugin-mode repo. Layers 0/1 are still enforced here."
  return 1
}
# A signable change answers "ask" in an interactive session (the human's approval is the signature) and
# "deny" when permissions are bypassed (no human present). Tests pass permission_mode explicitly.
bypass() { python3 -c 'import sys,json; d=json.load(sys.stdin); d["permission_mode"]="bypassPermissions"; print(json.dumps(d))'; }

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
# Hermetic: keep only the pack's conductor docs. A product's PRD (FR-n), plans, specs, envelope and D#
# validators are its own state and must not leak into this fixture (found by the stress test: any
# product with a 03-prd.md made this self-test refuse, which turned the whole farm red).
printf '# 03 PRD\n\n- FR-7 something the product owns\n- FR-8 and another\n' > "$P2/docs/cascade/03-prd.md"   # simulate a product PRD
find "$P2/docs/cascade" -mindepth 1 -maxdepth 1 ! -name 'product-e2e-*.md' ! -name 'skill-binding.md' ! -name 'stages' -exec rm -rf {} +
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 11\n\nD1 | balance MUST NOT go negative | true | false\n' > "$P2/docs/cascade/envelope.md"
printf '| ID | claim | evidence | status |\n| FR-1 | envelope | path: docs/cascade/envelope.md test: true | IMPLEMENTED |\n| D1 | balance | validator | IMPLEMENTED |\n' > "$P2/docs/cascade/10-audit.md"
printf '# 11\n\n<EDIT>\n## Verdict: READY\n</EDIT>\n' > "$P2/docs/cascade/11-prr.md"
out3="$(bash "$P2/tests/barbar.sh" 2>&1)"; rc3=$?
[[ "$rc3" -eq 0 ]] && echo "$out3" | grep -qE 'BARBAR [0-9]+/[0-9]+' || { ok=0; echo "  farm went red inside a READY product: $(echo "$out3" | grep FAIL | head -2)"; }
out4="$(bash "$P2/tests/barbar.sh" merge 2>&1)"; rc4=$?
[[ "$rc4" -eq 0 ]] && echo "$out4" | grep -q ALLOWED || { ok=0; echo "  merge not ALLOWED in a READY product (rc=$rc4)"; }
t T14 "$ok" "farm is red when the scorer dies; merge runs the farm first; READY product still farms n/n and merges"

# ---- T15  Claude Code hooks ---------------------------------------------------
if layer2 T15; then
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
# A multi-line commit message that mentions forbidden commands is text, not a command (found while shipping T33).
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"fix: docs\\n\\ntests/sign.sh mints a token\\ngit push origin main is denied\\nCASCADE_HUMAN is the key\\n\\""}}' | hook bash_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  bash_guard denied a commit message that merely mentions the guarded commands"; }
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
# Closing an EXECUTE hop means the loop actually passed on this tree (I10, T41) — give it that receipt.
( cd "$R" && . tests/lib/cascade.sh && mkdir -p .cascade && printf 'EXECUTE 05b %s\n' "$(cascade_worktree_sha "$R")" > .cascade/loop-receipt )
printf '{"cwd":"%s","transcript_path":"%s","stop_hook_active":false}' "$R" "$tr" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 0 ]] || { ok=0; echo "  stop_guard blocked a closed hop"; }

j="$(printf '{"cwd":"%s","source":"compact"}' "$R" | hook preserve.py)"
echo "$j" | grep -q 'additionalContext' && echo "$j" | grep -q 'Current hop: EXECUTE' || { ok=0; echo "  preserve did not re-inject after compact"; }
j="$(printf '{"cwd":"%s","source":"startup"}' "$R" | hook preserve.py)"
[[ -z "$j" ]] || { ok=0; echo "  preserve fired on plain startup"; }
t T15 "$ok" "Claude hooks: deny product Write on GENERATE, deny ship escapes, block open hop, re-inject on compact"
fi

# ---- T17  hop state and D# lines are human-owned; CASCADE_HUMAN=1 is the human's key ----
if layer2 T17; then
R="$TMP/t17"; mkrepo "$R" GENERATE 05b 'D1 | balance MUST NOT go negative | test 1 = 1 | test 1 = 2'
( cd "$R" && sed -i.bak 's/^CURRENT_HOP: GENERATE/CURRENT_HOP: EXECUTE/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak \
    && git add -A && git commit -qm "agent flips hop" >/dev/null 2>"$TMP/err" ); rc_flip=$?
ok=0; [[ "$rc_flip" -ne 0 ]] && grep -q 'human-owned' "$TMP/err" && ok=1
( cd "$R" && CASCADE_HUMAN=1 git commit -qm "human: approved, execute 05b" >/dev/null 2>&1 ); [[ $? -eq 0 ]] || { ok=0; echo "  human could not commit the hop edge with the key"; }
( cd "$R" && sed -i.bak 's/| test 1 = 1 | test 1 = 2$/| true | false/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "agent softens D1" >/dev/null 2>"$TMP/err" ); [[ $? -ne 0 ]] && grep -q 'human-owned' "$TMP/err" || { ok=0; echo "  agent changed a D# validator"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_HOP: EXECUTE","new_string":"CURRENT_HOP: GENERATE"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j" | grep -q '"ask"' && echo "$j" | grep -q 'HUMAN SIGNATURE NEEDED' || { ok=0; echo "  hop_guard did not ask the human to sign a hop flip (interactive)"; }
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_HOP: EXECUTE","new_string":"CURRENT_HOP: GENERATE"}}' "$R" "$R" | bypass | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard let the agent flip the hop with permissions bypassed"; }
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_SLICE:","new_string":"CURRENT_SLICE:"}}' "$R" "$R" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard denied a no-op edit"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"CASCADE_HUMAN=1 git commit -m x"}}' | hook bash_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard let the agent use the human key"; }
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: mention CASCADE_HUMAN=1 in INTEGRATION\""}}' | hook bash_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  bash_guard denied merely mentioning the key in quotes"; }
t T17 "$ok" "agent cannot flip the hop or soften a D# (pre-commit + hop_guard); human can with the key; agent denied the key"
fi
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
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\n\nD1 | {{balance MUST NOT go negative}} | TODO | TODO\n# example: D9 | law | v | t\n' > "$R/docs/cascade/envelope.md"
printf 'VALIDATOR: true\n' > "$R/docs/cascade/goal.md"
out="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && echo "$out" | grep -q 'LOOP 1/1' || { ok=0; echo "  the template placeholder law blocked the loop (a fresh install could never run autopilot): $(echo "$out" | grep -m1 REFUSED)"; }
echo "$(bash "$ROOT/tests/dsharp_strength.sh" --root "$R" 2>&1)" | grep -q 'DSHARP 0/0' || { ok=0; echo "  placeholder counted as a declared law in dsharp_strength"; }
# A law with both commands named is IN FORCE: the loop runs it (red until the test exists) — it never refuses.
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\n\nD1 | balance MUST NOT go negative | test -f tests/inv/x.txt | test ! -f tests/inv/x.txt\n' > "$R/docs/cascade/envelope.md"
printf 'VALIDATOR: true\nVALIDATOR: test -f tests/inv/x.txt\n' > "$R/docs/cascade/goal.md"
out="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc=$?
[[ "$rc" -ne 3 ]] && echo "$out" | grep -qE '^LOOP [0-9]+/[0-9]+' || { ok=0; echo "  a signed law with named commands refused the hop instead of running as work"; }
# An undecided law (TODO commands) blocks — and the refusal says exactly what to do.
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\n\nD2 | tenant isolation | TODO | TODO\n' > "$R/docs/cascade/envelope.md"
out="$(cd "$R" && bash tests/loop.sh 2>&1)"; rc=$?
[[ "$rc" -eq 3 ]] || { ok=0; echo "  an undecided law did not block"; }
for k in BOTTLENECK "WHAT TO DO" "RESUME WITH"; do echo "$out" | grep -q "$k" || { ok=0; echo "  the refusal is missing its '$k' line"; }; done
t T18 "$ok" "red twin: THEATER is red; an undecided law blocks with BOTTLENECK/WHAT TO DO/RESUME; a law with named commands runs as work; a waiver lifts it; a {{placeholder}} is not a law"

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
if layer2 T20; then
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
echo "$j" | grep -q 'CASCADE IDLE' && ! echo "$j" | grep -q 'class ' || { ok=0; echo "  seam did not give the idle-flow instruction (draft brief, propose edge, human approves) with no hop running"; }
rm -f "$R/docs/cascade/envelope.md"
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"
[[ -z "$j" ]] || { ok=0; echo "  seam hook spoke in a repo with no envelope at all"; }
t T20 "$ok" "seam hook injects the per-hop skill allow/deny + precedence; idle-flow instruction when no hop runs; silent with no envelope"
fi

# ---- T21  guards fail visibly, never open; CRLF envelopes still parse ----
if layer2 T21; then
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
fi
# ---- T22  install manifest + drift check ----
I2="$TMP/t22"; mkdir -p "$I2"; ( cd "$I2" && git init -q )
if [[ -f "$ROOT/install.sh" ]]; then
  bash "$ROOT/install.sh" --no-plugin "$I2" >/dev/null 2>&1
  ok=0; bash "$ROOT/install.sh" --check "$I2" >"$TMP/chk" 2>&1 && grep -q 'no drift' "$TMP/chk" && ok=1
  echo '# softened' >> "$I2/.githooks/pre-commit"; rm -f "$I2/tests/loop.sh"
  bash "$ROOT/install.sh" --check "$I2" >"$TMP/chk" 2>&1; rc=$?
  [[ "$rc" -ne 0 ]] && grep -q 'DRIFTED  .githooks/pre-commit' "$TMP/chk" && grep -q 'MISSING  tests/loop.sh' "$TMP/chk" || { ok=0; echo "  drift check missed a softened hook / deleted script"; }
  t T22 "$ok" "install.sh --check: clean after install; reports a softened hook and a deleted script"
  # ---- T23  install.sh is idempotent: a second run nests nothing, leaves no drift, farm still n/n ----
  I3="$TMP/t23"; mkdir -p "$I3"; ( cd "$I3" && git init -q )
  bash "$ROOT/install.sh" --no-plugin "$I3" >/dev/null 2>&1; echo 'stale' > "$I3/tests/lib/stale.sh"
  bash "$ROOT/install.sh" --no-plugin "$I3" >/dev/null 2>&1
  ok=1
  nested="$(find "$I3" -path '*/.githooks/.githooks' -o -path '*/tests/lib/lib' -o -path '*/evals/hops/hops' -o -path '*/.claude/commands/commands' 2>/dev/null | head -3)"
  [[ -z "$nested" ]] || { ok=0; echo "  second install nested directories: $nested"; }
  [[ ! -e "$I3/tests/lib/stale.sh" ]] || { ok=0; echo "  stale file survived re-install"; }
  bash "$ROOT/install.sh" --check "$I3" >/dev/null 2>&1 || { ok=0; echo "  drift after a clean re-install"; }
  ( cd "$I3" && CASCADE_FAST=1 CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >/dev/null 2>&1 ) || { ok=0; echo "  farm red after re-install"; }
  # A git worktree (.git is a file) must install and --check like a normal checkout (found on a real product worktree).
  W="$TMP/t23w"; ( cd "$I3" && git worktree add -q "$W" -b t23-wt >/dev/null 2>&1 )
  if [[ -f "$W/.git" ]]; then
    bash "$ROOT/install.sh" --no-plugin "$W" >/dev/null 2>&1 && bash "$ROOT/install.sh" --check "$W" >/dev/null 2>&1 || { ok=0; echo "  install/--check refused a git worktree (.git file)"; }
  else ok=0; echo "  could not create a worktree fixture"; fi
  t T23 "$ok" "install.sh is idempotent: re-run nests nothing, drops stale files, no drift, farm n/n; works in a git worktree"
  # ---- T24  a real product: existing settings.json, CLAUDE.md, and a .gitignore that hides .claude/ ----
  I4="$TMP/t24"; mkdir -p "$I4/.claude"; ( cd "$I4" && git init -q )
  printf '{"permissions":{"allow":["Bash(npm test)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo theirs"}]}]}}\n' > "$I4/.claude/settings.json"
  printf '# My project\n\nRun npm test.\n' > "$I4/CLAUDE.md"
  printf '.claude/\n' > "$I4/.gitignore"
  out="$(bash "$ROOT/install.sh" --no-plugin "$I4" 2>&1)"
  ok=1
  python3 - "$I4/.claude/settings.json" <<'PYT' || { ok=0; echo "  settings merge lost theirs or missed ours"; }
import json,sys; d=json.load(open(sys.argv[1])); s=json.dumps(d)
assert d["permissions"]["allow"]==["Bash(npm test)"], "permissions lost"
assert "echo theirs" in s, "their hook lost"
for n in ("hop_guard.py","bash_guard.py","stop_guard.py","preserve.py","seam.py"): assert n in s, n+" missing"
PYT
  grep -q '^# My project' "$I4/CLAUDE.md" && grep -q '@AGENTS.md' "$I4/CLAUDE.md" || { ok=0; echo "  CLAUDE.md not appended with @AGENTS.md (or overwritten)"; }
  echo "$out" | grep -q 'IGNORED by .gitignore: .claude/hooks' || { ok=0; echo "  install did not warn that .claude/ is gitignored"; }
  bash "$ROOT/install.sh" --check "$I4" >"$TMP/chk4" 2>&1; rc=$?
  [[ "$rc" -ne 0 ]] && grep -q 'IGNORED  .claude/hooks' "$TMP/chk4" || { ok=0; echo "  --check did not flag the gitignored layer"; }
  : > "$I4/.gitignore"; bash "$ROOT/install.sh" --check "$I4" >"$TMP/chk4" 2>&1 && grep -q 'hooks wired' "$TMP/chk4" || { ok=0; echo "  --check not clean after un-ignoring: $(tail -1 "$TMP/chk4")"; }
  bash "$ROOT/install.sh" --no-plugin "$I4" >/dev/null 2>&1; n="$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['hooks']['PreToolUse']))" "$I4/.claude/settings.json")"
  [[ "$n" -eq 3 ]] || { ok=0; echo "  settings merge is not idempotent (PreToolUse entries: $n, want 3)"; }
  I5="$TMP/t24b"; mkdir -p "$I5"; ( cd "$I5" && git init -q ); bash "$ROOT/install.sh" --no-plugin "$I5" >/dev/null 2>&1
  echo '# my notes' >> "$I5/CLAUDE.md"; echo 'D9 | my law | true | false' >> "$I5/docs/cascade/envelope.md"
  bash "$ROOT/install.sh" --check "$I5" >/dev/null 2>&1 || { ok=0; echo "  editing product-owned CLAUDE.md/envelope.md counted as drift"; }
  t T24 "$ok" "real product: settings.json merged (theirs kept, ours added, idempotent), CLAUDE.md appended, gitignored layer flagged by install and --check, product-owned files never drift"
else
  echo "SKIP  T22  no install.sh here (installed product, not the pack)"
fi

# ---- T25  a law's test is the law: existing tests/inv/* are human-owned; new ones are welcome ----
if layer2 T25; then
R="$TMP/t25"; mkrepo "$R" EXECUTE 05b 'D1 | balance MUST NOT go negative | true | false'
( cd "$R" && mkdir -p tests/inv && echo 'def test_d1(): assert 1' > tests/inv/test_D1.py && git add -A && CASCADE_HUMAN=1 git commit -qm "human: D1 test" >/dev/null )
ok=1
rc="$(commit_try "$R" tests/inv/test_D1.py 'def test_d1(): assert True  # softened')"; [[ "$rc" -ne 0 ]] && grep -q 'existing D# tests are human-owned' "$TMP/err" || { ok=0; echo "  agent modified an existing law test"; }
( cd "$R" && git checkout -q HEAD -- tests/inv/test_D1.py && git rm -q --cached tests/inv/test_D1.py >/dev/null 2>&1; git checkout -q HEAD -- tests/inv/test_D1.py; git reset -q )
( cd "$R" && git rm -q tests/inv/test_D1.py && git commit -qm "agent deletes law test" >/dev/null 2>"$TMP/err" ); [[ $? -ne 0 ]] || { ok=0; echo "  agent deleted a law test"; }
( cd "$R" && git reset -q --hard HEAD )
rc="$(commit_try "$R" tests/inv/test_D9_new.py 'def test_d9(): assert 1')"; [[ "$rc" -eq 0 ]] || { ok=0; echo "  agent could not add a new law test"; }
( cd "$R" && echo 'def test_d1(): assert 2 > 1' > tests/inv/test_D1.py && git add -A && CASCADE_HUMAN=1 git commit -qm "human: accept test change" >/dev/null 2>&1 ) || { ok=0; echo "  human could not change a law test with the key"; }
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D1.py","old_string":"assert 2 > 1","new_string":"assert True"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j" | grep -q '"ask"' || { ok=0; echo "  hop_guard did not ask the human to sign a law-test edit"; }
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D1.py","old_string":"assert 2 > 1","new_string":"assert True"}}' "$R" "$R" | bypass | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard let the agent edit an existing law test with permissions bypassed"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D10.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard denied a new law test"; }
t T25 "$ok" "existing tests/inv/* are human-owned: agent cannot change or delete them (pre-commit + hop_guard), can add new ones; human can with the key"
fi
# ---- T26  a slice cannot carve an exception into a law: no new test under an existing D# id ----
if layer2 T26; then
R="$TMP/t26"; mkrepo "$R" EXECUTE 05b 'D1 | balance MUST NOT go negative | pytest -q tests/inv/test_D1_balance.py | INV_MUTANT=D1 pytest -q tests/inv/test_D1_balance.py'
ok=1
rc="$(commit_try "$R" tests/inv/test_D1_balance.py 'def test_d1(): assert 1')"; [[ "$rc" -eq 0 ]] || { ok=0; echo "  agent could not create the validator file the law names (UNPROVEN flow)"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D1_balance2.py","content":"x"}}' "$R" "$R" | bypass | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard let a second test under D1 through (bypass)"; }
rc="$(commit_try "$R" tests/inv/test_D1_vip_floor.py 'def test_vip(): assert 1')"; [[ "$rc" -ne 0 ]] && grep -q 'reuses declared D1' "$TMP/err" || { ok=0; echo "  agent added a test under existing D1"; }
( cd "$R" && git reset -q --hard HEAD && git clean -qfd )
rc="$(commit_try "$R" tests/inv/test_D7_new_law.py 'def test_d7(): assert 1')"; [[ "$rc" -eq 0 ]] || { ok=0; echo "  agent could not add a test for a new D# id"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D1_vip_floor.py","content":"x"}}' "$R" "$R" | bypass | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard let the agent add a test under existing D1 (bypass)"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D1_vip_floor.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j" | grep -q '"ask"' || { ok=0; echo "  hop_guard did not ask the human about a test under existing D1 (interactive)"; }
j="$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/tests/inv/test_D8_other.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard denied a new D# test"; }
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"; echo "$j" | grep -q 'admits no exceptions\|never carves an exception' || { ok=0; echo "  seam does not state that laws admit no exceptions"; }
t T26 "$ok" "no new test under an existing D# id except the file its law names (pre-commit + hop_guard); new D# ids fine; seam states laws admit no exceptions"
fi
# ---- T27  autopilot: pre-signed edges only, in order, with proof at each edge ----
if layer2 T27; then
R="$TMP/t27"; mkrepo "$R" NONE "" 'D1 | law | true | false'
printf 'CURRENT_HOP: NONE\nCURRENT_STAGE:\nCURRENT_SLICE:\nAUTOPILOT:\n\nD1 | law | true | false\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && git add -A && CASCADE_HUMAN=1 git commit -qm "human: full envelope" >/dev/null )
ap() { # ap <HOP> <STAGE> <SLICE>  -> commit rc as the agent (no key)
  ( cd "$R" && sed -i.bak "s/^CURRENT_HOP:.*/CURRENT_HOP: $1/; s/^CURRENT_STAGE:.*/CURRENT_STAGE: $2/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: $3/" docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak \
      && git add -A && git commit -qm "agent: $1 $2 $3" >/dev/null 2>"$TMP/err"; echo $? )
}
ok=1
[[ "$(ap GENERATE 05b checkout)" -ne 0 ]] && grep -q 'autopilot is off' "$TMP/err" || { ok=0; echo "  agent flipped the hop with autopilot off"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
( cd "$R" && sed -i.bak 's/^AUTOPILOT:.*/AUTOPILOT: 05b checkout, 05b refunds/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && CASCADE_HUMAN=1 git commit -qm "human: sign autopilot" >/dev/null )
[[ "$(ap GENERATE 05b refunds)" -ne 0 ]] && grep -q 'next allowed edge is GENERATE 05b checkout' "$TMP/err" || { ok=0; echo "  agent skipped ahead on the list"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
[[ "$(ap GENERATE 05b checkout)" -eq 0 ]] || { ok=0; echo "  first signed edge refused: $(tail -1 "$TMP/err")"; }
[[ "$(ap EXECUTE 05b checkout)" -ne 0 ]] && grep -q 'no spec doc' "$TMP/err" || { ok=0; echo "  GENERATE->EXECUTE allowed without a spec"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q && echo '# spec' > docs/cascade/05b-checkout.md && git add -A && git commit -qm "spec" >/dev/null )
[[ "$(ap EXECUTE 05b checkout)" -eq 0 ]] || { ok=0; echo "  GENERATE->EXECUTE refused with a spec present: $(tail -1 "$TMP/err")"; }
printf 'VALIDATOR: false\nVALIDATOR: true\n' > "$R/docs/cascade/goal.md"; ( cd "$R" && git add -A && git commit -qm goal >/dev/null )
[[ "$(ap GENERATE 05b refunds)" -ne 0 ]] && grep -q 'not n/n' "$TMP/err" || { ok=0; echo "  EXECUTE->next allowed with a red loop"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
printf 'VALIDATOR: true\n' > "$R/docs/cascade/goal.md"; ( cd "$R" && git add -A && git commit -qm goal >/dev/null )
[[ "$(ap GENERATE 05b refunds)" -eq 0 ]] || { ok=0; echo "  EXECUTE->next refused with a green loop: $(tail -1 "$TMP/err")"; }
( cd "$R" && echo '# spec' > docs/cascade/05b-refunds.md && git add -A && git commit -qm spec2 >/dev/null )
[[ "$(ap EXECUTE 05b refunds)" -eq 0 ]] || { ok=0; echo "  second slice execute refused"; }
[[ "$(ap GENERATE 10 audit)" -ne 0 ]] && grep -q 'end of the signed list' "$TMP/err" || { ok=0; echo "  agent advanced past the signed list"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
( cd "$R" && sed -i.bak 's/^AUTOPILOT:.*/AUTOPILOT: 05b checkout, 05b refunds, 05b extra/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "agent extends list" >/dev/null 2>"$TMP/err" ); [[ $? -ne 0 ]] && grep -q 'human-owned' "$TMP/err" || { ok=0; echo "  agent extended the AUTOPILOT list"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_HOP: EXECUTE","new_string":"CURRENT_HOP: GENERATE"}}' "$R" "$R" | bypass | hook hop_guard.py)"
echo "$j" | grep -q '"deny"' || { ok=0; echo "  hop_guard allowed an off-list flip under autopilot (bypass)"; }
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"; echo "$j" | grep -q 'AUTOPILOT is ON' || { ok=0; echo "  seam does not announce autopilot"; }
R2="$TMP/t27b"; mkrepo "$R2" NONE "" 'D1 | law | true | false'
printf '<EDIT>\nCURRENT_HOP: NONE\nCURRENT_STAGE:\nCURRENT_SLICE:\nAUTOPILOT: 05b checkout\n</EDIT>\n\nD1 | law | true | false\n' > "$R2/docs/cascade/envelope.md"
( cd "$R2" && git add -A && CASCADE_HUMAN=1 git commit -qm "human: envelope with hop lines inside EDIT" >/dev/null )
( cd "$R2" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/; s/^CURRENT_STAGE:.*/CURRENT_STAGE: 05b/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: checkout/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "agent: first edge" >/dev/null 2>"$TMP/err" ) || { ok=0; echo "  accepted edge re-blocked by the <EDIT> scan in pre-commit: $(grep -m1 BLOCKED "$TMP/err")"; }
( cd "$R2" && git checkout -q HEAD -- docs/cascade/envelope.md 2>/dev/null; git reset -q --hard HEAD >/dev/null )
printf '<EDIT>\nCURRENT_HOP: NONE\nCURRENT_STAGE:\nCURRENT_SLICE:\nAUTOPILOT: 05b checkout\n</EDIT>\n\nD1 | law | true | false\n' > "$R2/docs/cascade/envelope.md"
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_HOP: NONE\nCURRENT_STAGE:\nCURRENT_SLICE:","new_string":"CURRENT_HOP: GENERATE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: checkout"}}' "$R2" "$R2" | hook hop_guard.py)"
[[ -z "$j" ]] || { ok=0; echo "  hop_guard re-blocked an accepted edge inside <EDIT>: $(echo "$j" | cut -c1-120)"; }
t T27 "$ok" "autopilot: off by default; only the next signed edge; spec needed for EXECUTE; loop n/n needed to advance; list end and 10/11 are human; list is human-owned; an accepted edge is not re-blocked by the <EDIT> scan"
fi
# ---- T28  /barbar auto: the Stop hook keeps the session going while signed edges remain; bounded; HALT respected ----
if layer2 T28; then
R="$TMP/t28"; mkrepo "$R" EXECUTE 05b
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: checkout\nAUTOPILOT: 05b checkout, 05b refunds\n' > "$R/docs/cascade/envelope.md"
cp -R "$ROOT/tests/lib" "$R/tests/" 2>/dev/null || true
tr="$TMP/t28.jsonl"; printf '{"type":"assistant","message":{"content":[{"type":"text","text":"INVARIANTS held. STITCH NEEDED: accept execute for stage 05b, or send back."}]}}\n' > "$tr"
ok=1
printf '{"cwd":"%s","transcript_path":"%s","session_id":"t28","stop_hook_active":true}' "$R" "$tr" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 2 ]] && grep -q 'signed edges remain — next GENERATE 05b refunds' "$TMP/hook.err" || { ok=0; echo "  stop_guard let the session stop with signed edges remaining (rc=$rc)"; }
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"STITCH NEEDED: accept execute for stage 05b, or send back. AUTOPILOT HALT: D4 is RED and only a human can change it."}]}}\n' > "$tr"
printf '{"cwd":"%s","transcript_path":"%s","session_id":"t28","stop_hook_active":true}' "$R" "$tr" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 0 ]] || { ok=0; echo "  stop_guard ignored an explicit AUTOPILOT HALT (rc=$rc)"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: refunds\nAUTOPILOT: 05b checkout, 05b refunds\n' > "$R/docs/cascade/envelope.md"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"STITCH NEEDED: accept execute for stage 05b, or send back."}]}}\n' > "$tr"
printf '{"cwd":"%s","transcript_path":"%s","session_id":"t28","stop_hook_active":true}' "$R" "$tr" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 0 ]] || { ok=0; echo "  stop_guard kept going past the end of the signed list (rc=$rc)"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: checkout\nAUTOPILOT: 05b checkout, 05b refunds\n' > "$R/docs/cascade/envelope.md"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf '{"cwd":"%s","transcript_path":"%s","session_id":"t28cap","stop_hook_active":true}' "$R" "$tr" | hook stop_guard.py >/dev/null 2>&1; last_rc=$?; done
[[ "$last_rc" -eq 0 ]] || { ok=0; echo "  continuation cap did not stop the loop"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: checkout\nAUTOPILOT: 05b checkout, 05b refunds\n' > "$R/docs/cascade/envelope.md"
printf '{"cwd":"%s","session_id":"t28msg","stop_hook_active":false,"last_assistant_message":"STITCH NEEDED: accept execute for stage 05b, or send back"}' "$R" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 2 ]] || { ok=0; echo "  stop_guard ignored last_assistant_message (the field the real Stop event carries) rc=$rc"; }
printf '{"cwd":"%s","session_id":"t28msg2","stop_hook_active":false,"last_assistant_message":"Implemented it. Done."}' "$R" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 2 ]] && grep -q 'Hop not closed' "$TMP/hook.err" || { ok=0; echo "  stop_guard did not enforce the edge line from last_assistant_message"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: checkout\nAUTOPILOT: 05b checkout, 05b refunds\n' > "$R/docs/cascade/envelope.md"
printf '{"cwd":"%s","session_id":"t28halt","stop_hook_active":false,"last_assistant_message":"STITCH NEEDED: accept execute for stage 05b, or send back.\\nAUTOPILOT HALT: D4 is red."}' "$R" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 2 ]] && grep -q 'missing its instruction block' "$TMP/hook.err" || { ok=0; echo "  a HALT with no WHAT TO DO was accepted as an ending (rc=$rc)"; }
printf '{"cwd":"%s","session_id":"t28halt2","stop_hook_active":false,"last_assistant_message":"AUTOPILOT HALT: D4 is red.\\n  BOTTLENECK: x\\n  WHAT TO DO: bash tests/sign.sh\\n  RESUME WITH: /barbar auto\\n  DONE SO FAR: slice 1"}' "$R" | hook stop_guard.py; rc=$?
[[ "$rc" -eq 0 ]] || { ok=0; echo "  an actionable HALT was not accepted (rc=$rc)"; }
t T28 "$ok" "/barbar auto: Stop hook continues while signed edges remain, stops at list end, is capped, reads last_assistant_message, and refuses a HALT that does not say what to do"
fi
# ---- T29  first-knowledge discovery: nudge when no law is in force; /barbar init proposes, never signs ----
if layer2 T29; then
R="$TMP/t29"; mkrepo "$R" EXECUTE 05b 'D1 | {{balance MUST NOT go negative}} | TODO | TODO'
cp "$ROOT/tests/dsharp_strength.sh" "$R/tests/"; cp "$ROOT/docs/cascade/skill-binding.md" "$R/docs/cascade/" 2>/dev/null || true
ok=1
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"; echo "$j" | grep -q 'NO LAW IN FORCE' || { ok=0; echo "  seam did not nudge with no law in force"; }
j="$(printf '{"cwd":"%s","source":"resume"}' "$R" | hook preserve.py)"; echo "$j" | grep -q 'CASCADE NOT INITIALIZED' || { ok=0; echo "  preserve did not nudge with no law in force"; }
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\n\nD1 | balance MUST NOT go negative | true | false\n' > "$R/docs/cascade/envelope.md"
j="$(printf '{"cwd":"%s","prompt":"hi"}' "$R" | hook seam.py)"; echo "$j" | grep -q 'NO LAW IN FORCE' && { ok=0; echo "  seam nudged although a law is in force"; }
grep -q 'never write D# lines yourself\|Never write `docs/cascade/envelope.md`' "$ROOT/.claude/commands/barbar.md" || { ok=0; echo "  /barbar init does not forbid writing the envelope"; }
grep -q 'proposals.md' "$ROOT/.claude/commands/barbar.md" || { ok=0; echo "  /barbar init has no proposals file"; }
t T29 "$ok" "no law in force -> seam and preserve nudge toward /barbar init; silent once a law is GREEN; init proposes into proposals.md and never signs"
fi
# ---- T30  approve-to-sign: ask -> human approves -> sign_ok token -> pre-commit accepts once; agent cannot forge ----
if layer2 T30; then
R="$TMP/t30"; mkrepo "$R" NONE "" 'D1 | law | true | false'
printf 'CURRENT_HOP: NONE\nCURRENT_STAGE:\nCURRENT_SLICE:\nAUTOPILOT:\n\nD1 | law | true | false\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && git add -A && CASCADE_HUMAN=1 git commit -qm "human: envelope" >/dev/null )
ok=1; GD="$R/.git"
j="$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md","old_string":"CURRENT_HOP: NONE","new_string":"CURRENT_HOP: GENERATE"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j" | grep -q '"ask"' && [[ -s "$GD/cascade-sign-pending" ]] || { ok=0; echo "  ask did not record a pending signature"; }
# the human approved: the edit happens, then PostToolUse verifies and issues the token
sed -i.bak 's/^CURRENT_HOP: NONE/CURRENT_HOP: GENERATE/' "$R/docs/cascade/envelope.md"; rm -f "$R/docs/cascade/envelope.md.bak"
printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/docs/cascade/envelope.md"}}' "$R" "$R" | hook sign_ok.py
[[ -s "$GD/cascade-human-ok" ]] && grep -q 'docs/cascade/envelope.md' "$GD/cascade-human-ok" || { ok=0; echo "  sign_ok did not issue a token for the approved content"; }
( cd "$R" && git add -A && git commit -qm "agent commits the human-signed edge" >/dev/null 2>"$TMP/err" ) || { ok=0; echo "  pre-commit rejected a human-signed edge: $(grep -m1 BLOCKED "$TMP/err")"; }
[[ ! -s "$GD/cascade-human-ok" ]] || { ok=0; echo "  token was not consumed"; }
# no token now: the same kind of flip is blocked again
( cd "$R" && sed -i.bak 's/^CURRENT_HOP: GENERATE/CURRENT_HOP: EXECUTE/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "agent flips without a signature" >/dev/null 2>"$TMP/err" ) && { ok=0; echo "  flip committed without a token"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
# a token for different content does not sign this content
echo "0000000000000000000000000000000000000000000000000000000000000000 docs/cascade/envelope.md" > "$GD/cascade-human-ok"
( cd "$R" && sed -i.bak 's/^CURRENT_HOP: GENERATE/CURRENT_HOP: EXECUTE/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "wrong token" >/dev/null 2>"$TMP/err" ) && { ok=0; echo "  a mismatched token signed the content"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q ); rm -f "$GD/cascade-human-ok"
# the agent cannot mint tokens from the shell
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo x >> .git/cascade-human-ok"}}' | hook bash_guard.py)"; echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard let the agent write the token file"; }
# Minting requires a write. Reading the ledger is allowed on purpose: the human can open it in any editor,
# denying it bought nothing, and it made the guard fire on `ls`, `cat` and a grep for the filename — noise
# that teaches people to route around a guard. The Write/Edit path into the git dir is sealed by T46.
for w30 in "printf x > .git/cascade-sign-pending" "rm -f .git/cascade-human-ok" "mv .git/cascade-human-ok /tmp/x" "sed -i '' -e s/a/b/ .git/cascade-human-ok"; do
  j="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$w30" | hook bash_guard.py)"
  echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard let the agent write the ledger: $w30"; }
done
for r30 in "cat .git/cascade-sign-pending" "ls -la .git/cascade-human-ok" "wc -l .git/cascade-human-ok"; do
  j="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$r30" | hook bash_guard.py)"
  echo "$j" | grep -q '"deny"' && { ok=0; echo "  bash_guard denied a harmless read, which is how a guard becomes noise: $r30"; }
done
t T30 "$ok" "approve-to-sign: interactive ask records a pending hash, the approved write becomes a one-shot token, pre-commit accepts exactly that content once; mismatched or missing tokens fail; the agent cannot mint them"
fi

# ---- T31  plugin: manifest + hooks.json valid; plugin-mode install wires no project hooks; seam offers install ----
if layer2 T31; then
if [[ ! -f "$ROOT/.claude-plugin/plugin.json" ]]; then
  echo "SKIP  T31  no plugin manifest here (installed product, not the pack)"
else
ok=1
python3 -B - "$ROOT" <<'PY31' || { ok=0; echo "  plugin manifest / hooks.json invalid or referencing missing files"; }
import json,os,sys
root=sys.argv[1]
m=json.load(open(os.path.join(root,".claude-plugin","plugin.json"))); assert m["name"]=="bdd" and "hooks" not in m, "a hooks key in plugin.json makes the plugin fail to load; use the default hooks/hooks.json"
mk=json.load(open(os.path.join(root,".claude-plugin","marketplace.json"))); assert any(p["name"]=="bdd" for p in mk["plugins"])
v=open(os.path.join(root,"VERSION")).read().strip(); assert m["version"]==v and mk["plugins"][0]["version"]==v, f"plugin.json/marketplace.json must carry VERSION={v} — the updater compares it; a stale version means 'already latest'"
h=json.load(open(os.path.join(root,"hooks","hooks.json")))
for ev,entries in h["hooks"].items():
    for e in entries:
        for hk in e["hooks"]:
            cmd=hk["command"]; assert "${CLAUDE_PLUGIN_ROOT}" in cmd, cmd
            rel=cmd.split("${CLAUDE_PLUGIN_ROOT}/")[-1].split('"')[0]; assert os.path.exists(os.path.join(root,rel)), rel
            name=cmd.split()[-1]; assert os.path.exists(os.path.join(root,".claude","hooks",name+".py")), name
assert os.path.exists(os.path.join(root,"commands","barbar.md")) and os.path.exists(os.path.join(root,"skills","cascade-farm","SKILL.md"))
PY31
I6="$TMP/t31"; mkdir -p "$I6"; ( cd "$I6" && git init -q )
bash "$ROOT/install.sh" --plugin "$I6" >/dev/null 2>&1 || { ok=0; echo "  plugin-mode install failed"; }
[[ ! -e "$I6/.claude/hooks" ]] || { ok=0; echo "  plugin-mode install wired project hooks (the plugin provides them)"; }
[[ -f "$I6/.claude/commands/barbar.md" ]] || { ok=0; echo "  plugin-mode install left the repo without a plain /barbar (the plugin's own is namespaced /bdd:barbar)"; }
I7="$TMP/t31s"; mkdir -p "$I7"; ( cd "$I7" && git init -q ); bash "$ROOT/install.sh" --no-plugin "$I7" >/dev/null 2>&1; bash "$ROOT/install.sh" --plugin "$I7" >/dev/null 2>&1
python3 -B -c "import json,sys; d=json.load(open(sys.argv[1])); s=json.dumps(d.get('hooks',{})); sys.exit(1 if 'hop_guard' in s or 'seam.py' in s else 0)" "$I7/.claude/settings.json" 2>/dev/null || { ok=0; echo "  switching a standalone install to plugin mode left project hook entries behind"; }
[[ ! -e "$I7/.claude/hooks" ]] || { ok=0; echo "  switching to plugin mode left .claude/hooks behind"; }
grep -q '^mode plugin' "$I6/.cascade/manifest" || { ok=0; echo "  manifest does not record plugin mode"; }
bash "$ROOT/install.sh" --check "$I6" >"$TMP/c31" 2>&1 && grep -q 'from the plugin' "$TMP/c31" || { ok=0; echo "  --check wrong in plugin mode: $(tail -1 "$TMP/c31")"; }
[[ -x "$I6/.githooks/pre-commit" && -f "$I6/tests/barbar.sh" && -f "$I6/AGENTS.md" ]] || { ok=0; echo "  plugin-mode install lost the durable layers"; }
N="$TMP/t31n"; mkdir -p "$N"; ( cd "$N" && git init -q )   # a repo with no BDD at all, under the plugin
j="$(printf '{"cwd":"%s","prompt":"add a feature"}' "$N" | BDD_PLUGIN_ROOT="$ROOT" hook seam.py)"
echo "$j" | grep -q 'NOT INSTALLED IN THIS REPO' && echo "$j" | grep -q 'install.sh' || { ok=0; echo "  seam did not offer the install in a repo without BDD"; }
j="$(printf '{"cwd":"%s","prompt":"add a feature"}' "$N" | hook seam.py)"; [[ -z "$j" ]] || { ok=0; echo "  seam spoke in a non-BDD repo without the plugin"; }
R="$TMP/t31d"; mkrepo "$R" GENERATE 05b
j1="$(printf '{"tool_name":"Write","tool_use_id":"tu-1","cwd":"%s","tool_input":{"file_path":"%s/src/app.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
j2="$(printf '{"tool_name":"Write","tool_use_id":"tu-1","cwd":"%s","tool_input":{"file_path":"%s/src/app.py","content":"x"}}' "$R" "$R" | hook hop_guard.py)"
echo "$j1" | grep -q '"deny"' && [[ -z "$j2" ]] || { ok=0; echo "  the same tool call was judged twice (plugin + project hooks would double up)"; }
t T31 "$ok" "plugin: manifest, marketplace and hooks.json are valid; plugin-mode install wires no project hooks and --check knows; seam offers the install in a bare repo; a tool call is judged once"
fi
fi
# ---- T32  a hook-style GIT_DIR must never leak into the farm (it once flipped a real product to bare) ----
if [[ -n "${CASCADE_ENFORCEMENT_NESTED:-}" ]]; then echo "SKIP  T32  nested run"; else
V="$TMP/t32victim"; mkdir -p "$V"; ( cd "$V" && git init -q && git symbolic-ref HEAD refs/heads/feature && git commit -q --allow-empty -m init )
ok=1
( cd "$TMP" && GIT_DIR="$V/.git" GIT_WORK_TREE="$V" bash -c 'mkdir -p t32tmp && cd t32tmp && git init -q 2>/dev/null; git init -q --bare "$PWD/remote.git" 2>/dev/null; git symbolic-ref HEAD refs/heads/main 2>/dev/null; true' )
if [[ "$(git -C "$V" config core.bare)" != "true" || "$(cat "$V/.git/HEAD")" != "ref: refs/heads/main" ]]; then
  echo "  (note: this git does not redirect init/symbolic-ref via GIT_DIR, so the victim below cannot be"
  echo "   corrupted on this machine — which is why the environment check that follows is the real test)"
fi
( cd "$V" && git config core.bare false && git symbolic-ref HEAD refs/heads/feature )

# The victim check above is only as strong as the git in front of it: on a git that ignores GIT_DIR for
# `init`, it passes whether or not the scripts unset anything, which made it theatre here for its whole
# life. The property is simply "these scripts do not pass a hook's GIT_DIR to the git they invoke" — so
# observe it directly, with a git shim on PATH that records the environment it was called with.
SHIM="$TMP/t32shim"; mkdir -p "$SHIM"; T32_REALPATH="$PATH"; export T32_REALPATH
cat > "$SHIM/git" <<'SHIMEOF'
#!/usr/bin/env bash
echo "${GIT_DIR-<unset>}" >> "$T32_LOG"
exec /usr/bin/env -u T32_LOG PATH="$T32_REALPATH" git "$@"
SHIMEOF
chmod +x "$SHIM/git"
for script in barbar.sh loop.sh dsharp_strength.sh audit.sh; do
  [[ -f "$ROOT/tests/$script" ]] || continue
  : > "$TMP/t32.env"
  ( cd "$TMP" && GIT_DIR="$V/.git" GIT_WORK_TREE="$V" CASCADE_FAST=1 CASCADE_ENFORCEMENT_NESTED=1 \
      T32_LOG="$TMP/t32.env" PATH="$SHIM:$T32_REALPATH" \
      bash "$ROOT/tests/$script" >/dev/null 2>&1 ) || true
  if [[ -s "$TMP/t32.env" ]] && grep -qv '^<unset>$' "$TMP/t32.env"; then
    ok=0; echo "  tests/$script passed a hook's GIT_DIR through to git ($(grep -v '^<unset>$' "$TMP/t32.env" | head -1)) — its throwaway repos would target the real one"
  fi
done
t T32 "$ok" "an inherited GIT_DIR/GIT_WORK_TREE (as git sets for hooks) never reaches the git that loop.sh, the farm, audit.sh or dsharp_strength.sh invoke — observed at the call, not inferred from a victim repo this git refuses to corrupt"
fi

# ---- T34  version drift between the plugin and a repo is announced, with the fix command ----
if layer2 T34; then
R="$TMP/t34"; mkrepo "$R" EXECUTE 05b 'D1 | law | true | false'
mkdir -p "$R/.cascade" "$TMP/t34plug"
printf '9.9.9\n' > "$TMP/t34plug/VERSION"
printf 'version 0.0.1\nmode plugin\n' > "$R/.cascade/manifest"
ok=1
j="$(printf '{"cwd":"%s","source":"resume"}' "$R" | BDD_PLUGIN_ROOT="$TMP/t34plug" hook preserve.py)"
echo "$j" | grep -q 'BDD VERSION DRIFT' && echo "$j" | grep -q 'install.sh' || { ok=0; echo "  session start did not announce plugin/repo version drift"; }
printf 'version 9.9.9\nmode plugin\n' > "$R/.cascade/manifest"
j="$(printf '{"cwd":"%s","source":"resume"}' "$R" | BDD_PLUGIN_ROOT="$TMP/t34plug" hook preserve.py)"
echo "$j" | grep -q 'BDD VERSION DRIFT' && { ok=0; echo "  drift announced when versions match"; }
j="$(printf '{"cwd":"%s","source":"resume"}' "$R" | hook preserve.py)"
echo "$j" | grep -q 'BDD VERSION DRIFT' && { ok=0; echo "  drift announced with no plugin present"; }
t T34 "$ok" "a repo whose shipped scripts are older than the plugin is told at session start, with the refresh command; silent when in sync or plugin-less"
fi
# ---- T35  a plugin-mode repo farms n/n, and a product's own AGENTS.md receives the cascade rules ----
if [[ ! -f "$ROOT/install.sh" ]]; then
  echo "SKIP  T35  no install.sh here (installed product, not the pack)"
else
P5="$TMP/t35"; mkdir -p "$P5"; ( cd "$P5" && git init -q )
printf '# House rules\n\nUse tabs. Ship on Fridays.\n' > "$P5/AGENTS.md"
bash "$ROOT/install.sh" --plugin "$P5" >/dev/null 2>&1
ok=1
grep -q 'House rules' "$P5/AGENTS.md" && grep -q 'Barbaric Driven Development' "$P5/AGENTS.md" || { ok=0; echo "  a product's own AGENTS.md did not keep its rules and gain the cascade ones"; }
grep -q '^plugin_root ' "$P5/.cascade/manifest" || { ok=0; echo "  plugin mode did not record plugin_root for the tests to find Layer 2"; }
bash "$ROOT/install.sh" --check "$P5" >/dev/null 2>&1 || { ok=0; echo "  --check red right after a plugin-mode install"; }
( cd "$P5" && CASCADE_FAST=1 CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >"$TMP/t35.farm" 2>&1 ) || { ok=0; echo "  plugin-mode repo cannot reach BARBAR n/n: $(grep -E '^FAIL' "$TMP/t35.farm" | head -3 | tr '\n' ' ')"; }
t T35 "$ok" "plugin-mode repo: Layer 2 resolved from the plugin so the farm reaches n/n; an existing AGENTS.md keeps its rules and gains the cascade ones; --check clean"
fi

# ---- T36  stage 10 may be pre-signed and is gated by audit.sh; 11 and merge never can be ----
R="$TMP/t36"; mkrepo "$R" EXECUTE 05b
cp "$ROOT/tests/audit.sh" "$ROOT/tests/dsharp_strength.sh" "$R/tests/" 2>/dev/null || true
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\nAUTOPILOT: 05b a, 10 audit\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && git add -A && CASCADE_HUMAN=1 git commit -qm "human: sign list with stage 10" >/dev/null )
ok=1
printf 'VALIDATOR: true\n' > "$R/docs/cascade/goal.md"
[[ "$(cd "$R" && python3 -B tests/lib/autopilot.py --status .)" == "next GENERATE 10 audit" ]] || { ok=0; echo "  a signed '10 audit' entry is not offered as the next edge"; }
# GENERATE 10 -> EXECUTE 10 needs the audit doc
ap36() { ( cd "$R" && sed -i.bak "s/^CURRENT_HOP:.*/CURRENT_HOP: $1/; s/^CURRENT_STAGE:.*/CURRENT_STAGE: $2/; s/^CURRENT_SLICE:.*/CURRENT_SLICE: $3/" docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && git commit -qm "agent: $1 $2 $3" >/dev/null 2>"$TMP/err"; echo $? ); }
[[ "$(ap36 GENERATE 10 audit)" -eq 0 ]] || { ok=0; echo "  agent could not take the signed edge to GENERATE 10"; }
[[ "$(ap36 EXECUTE 10 audit)" -ne 0 ]] && grep -q '10-audit.md' "$TMP/err" || { ok=0; echo "  GENERATE 10 -> EXECUTE 10 allowed with no audit doc"; }
( cd "$R" && git checkout -q HEAD -- docs/cascade/envelope.md && git reset -q )
printf '| FR-1 | x | path: docs/cascade/envelope.md test: true | IMPLEMENTED |\n' > "$R/docs/cascade/10-audit.md"
( cd "$R" && git add -A && git commit -qm "audit rows" >/dev/null 2>&1 )
[[ "$(ap36 EXECUTE 10 audit)" -eq 0 ]] || { ok=0; echo "  GENERATE 10 -> EXECUTE 10 refused with the audit doc present: $(tail -1 "$TMP/err")"; }
# 11 can never be signed
( cd "$R" && sed -i.bak 's/^AUTOPILOT:.*/AUTOPILOT: 05b a, 11 prr/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak && git add -A && CASCADE_HUMAN=1 git commit -qm "human tries to sign 11" >/dev/null 2>&1 )
out="$(cd "$R" && python3 -B tests/lib/autopilot.py --status .)"
echo "$out" | grep -q "error:" && echo "$out" | grep -q "11" || { ok=0; echo "  stage 11 was accepted on the autopilot list ($out)"; }
grep -q 'independent auditor' "$ROOT/.claude/commands/barbar.md" || { ok=0; echo "  the audit hop does not dispatch an adversarial reviewer"; }
# The cap used to be a grep for the literal markdown "**3**" — reformatting broke the test, ignoring the
# instruction did not. It is a mechanism now: four DIRTY stage-10 rounds on one slice and the hop is refused.
if [[ -n "$L2" ]]; then
  P36="$TMP/t36-punch"; mkrepo "$P36" EXECUTE 10
  cp "$ROOT/tests/audit.sh" "$P36/tests/" 2>/dev/null || true
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 10\nCURRENT_SLICE: punchy\n' > "$P36/docs/cascade/hop-state.md"
  printf '| FR-1 | x | path: nope/missing.kt test: false | IMPLEMENTED |\n' > "$P36/docs/cascade/10-audit.md"
  sg36() { printf '{"cwd":"%s","session_id":"p%s","last_assistant_message":"STITCH NEEDED: accept execute for stage 10, or send back."}' "$P36" "$1" \
    | python3 -B "$L2/.claude/hooks/stop_guard.py" >/dev/null 2>"$TMP/err36"; echo $?; }
  for r in 1 2 3; do
    [[ "$(sg36 "$r")" -eq 2 ]] || { ok=0; echo "  a DIRTY stage 10 was allowed to ask for accept on round $r"; }
    grep -q 'rounds and the audit is still DIRTY' "$TMP/err36" && { ok=0; echo "  the cap fired on round $r, before the third"; }
  done
  [[ "$(sg36 4)" -eq 2 ]] || { ok=0; echo "  round 4 was allowed through"; }
  grep -q 'rounds and the audit is still DIRTY' "$TMP/err36" || { ok=0; echo "  a 4th punch round was not capped — an agent can grind at DIRTY rows all night: $(head -1 "$TMP/err36")"; }
  # a CLEAN audit resets the count, so the next slice starts fresh
  printf '| FR-1 | x | path: docs/cascade/10-audit.md test: true | IMPLEMENTED |\n' > "$P36/docs/cascade/10-audit.md"
  [[ "$(sg36 5)" -eq 0 ]] || { ok=0; echo "  a CLEAN stage 10 was still refused after the cap — the counter never resets"; }
  [[ ! -f "$P36/.cascade/punch-rounds" ]] || { ok=0; echo "  the round counter survived a CLEAN audit"; }
fi
# Was a grep for a row in skill-binding.md. What matters is whether the seam injects that class at stage 10.
if [[ -n "$L2" ]]; then
  B36="$TMP/t36-bind"; mkrepo "$B36" EXECUTE 10
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 10\nCURRENT_SLICE: audit\n' > "$B36/docs/cascade/hop-state.md"
  cp "$ROOT/docs/cascade/skill-binding.md" "$B36/docs/cascade/" 2>/dev/null || true
  printf '{"prompt":"go","cwd":"%s","prompt_id":"b36"}' "$B36" | python3 -B "$L2/.claude/hooks/seam.py" 2>/dev/null \
    | grep -q 'EXECUTE-AUDIT' || { ok=0; echo "  at stage 10 the seam does not bind the EXECUTE-AUDIT class — the audit hop gets the wrong tool list"; }
fi
t T36 "$ok" "stage 10 can be signed onto the autopilot list and is gated by audit.sh (rows first, CLEAN to advance); stage 11 never can; the audit hop uses an independent reviewer and a capped punch list"

# ---- T49  the hooks share one definition of each helper ----
# Five copies of "where does hop state live", four of the logger, three of the dedupe — the same defect
# consolidated in 1.2.2 (six law parsers, until a placeholder counted as a law), reintroduced by hand.
# seam.py carried the proof: `if "seam.py" == "preserve.py"`, a comparison that is always false.
if [[ -z "$L2" ]]; then
  echo "SKIP  T49  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
ok=1
[[ -f "$L2/.claude/hooks/_common.py" ]] || { ok=0; echo "  no shared module — every hook carries its own copy again"; }
for fn in repo_root git_dir already_handled already_event log hopstate guarded; do
  n=$(grep -l "^def $fn" "$L2"/.claude/hooks/*.py 2>/dev/null | wc -l | tr -d ' ')
  [[ "$n" == "1" ]] || { ok=0; echo "  '$fn' is defined $n times across the hooks — they will drift"; }
done
grep -q 'seam.py" == "preserve.py"' "$L2/.claude/hooks/seam.py" 2>/dev/null && { ok=0; echo "  the copy-paste fossil is back in seam.py"; }
# every hook still loads and answers when fed its event
R="$TMP/t49"; mkrepo "$R" GENERATE 05b
for h in hop_guard bash_guard sign_ok stop_guard preserve seam; do
  python3 -B "$L2/.claude/hooks/$h.py" >/dev/null 2>"$TMP/e49" <<<'{}' \
    || { ok=0; echo "  $h.py exits non-zero on a trivial event: $(tail -1 "$TMP/e49")"; }
  [[ -s "$TMP/e49" ]] && { ok=0; echo "  $h.py wrote to stderr on a trivial event: $(head -1 "$TMP/e49")"; }
done
# a PreToolUse guard that cannot load its module must ask, never fall through
out49="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/x.kt","content":"x"},"cwd":"%s","tool_use_id":"t49"}' "$R" "$R" \
  | CASCADE_HOOK_SELFTEST_RAISE=1 python3 -B "$L2/.claude/hooks/hop_guard.py" 2>/dev/null)"
grep -q '"ask"' <<<"$out49" || { ok=0; echo "  a crashing PreToolUse guard did not answer 'ask' — it would fail open"; }
t T49 "$ok" "every shared hook helper is defined once, in .claude/hooks/_common.py, and each hook still loads, answers a trivial event silently, and asks rather than failing open when the module cannot be used"
fi

# ---- T48  the local gate is fast, and fast never reaches main ----
# The suite also must not nest itself: three tests once ran a full farm — which runs this very file — inside
# a test of this file, ~70s each. The meta-suite is already running; it is the outer one.
[[ -z "$(grep -n 'CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh' "$ROOT/tests/enforcement.sh" | grep -v CASCADE_FAST)" ]] \
  || { ok=0; echo "  a nested farm runs the meta-suite inside a test of the meta-suite — minutes for nothing"; }
# A 7-minute push is a bar people route around with --no-verify, and a bar routed around protects nothing
# (I18). The local gate defers the pack's own multi-minute meta-suite to CI — but that split is only safe
# while the score says so, the merge gate refuses to be fast, and CI actually runs the full farm.
ok=1
out48="$(cd "$ROOT" && CASCADE_FAST=1 bash tests/barbar.sh 2>&1)"
grep -q 'DEFER i18-enforcement' <<<"$out48" || { ok=0; echo "  fast mode did not defer the meta-suite — the push gate is still minutes long"; }
grep -q 'not a full farm' <<<"$out48" || { ok=0; echo "  a fast farm reports a score that reads like a full one"; }
grep -qE '^BARBAR [0-9]+/[0-9]+ \(fast' <<<"$out48" || { ok=0; echo "  the fast score line is not machine-readable as fast"; }
# fast must still be able to FAIL: it is a gate, not a formality
grep -q 'PASS  lint' <<<"$out48" || { ok=0; echo "  fast mode skipped lint too — it is meant to defer one step, not most of them"; }
# Fast lint checks what this push changes, not the whole tree — but it must still catch a broken script.
L48="$TMP/t48-lint"; mkrepo "$L48" EXECUTE 05b
cp "$ROOT/tests/lint.sh" "$L48/tests/" 2>/dev/null || true
printf '\nif [ then\n' >> "$L48/tests/loop.sh"
( cd "$L48" && CASCADE_FAST=1 bash tests/lint.sh >"$TMP/l48" 2>&1 ) && { ok=0; echo "  fast lint passed a script with a syntax error — scoping it to changed files must not blind it"; }
grep -qE 'SYNTAX|SHELLCHECK|LINT red' "$TMP/l48" || { ok=0; echo "  fast lint did not report why it failed"; }
# the merge gate must ignore CASCADE_FAST entirely
grep -q 'unset CASCADE_FAST' "$ROOT/tests/barbar.sh" || { ok=0; echo "  'barbar merge' honours CASCADE_FAST — a merge could reach main with the pack's layers unchecked"; }
# pre-push asks for fast; CI must not
grep -q 'CASCADE_FAST=1' "$ROOT/.githooks/pre-push" || { ok=0; echo "  pre-push does not use the fast gate, so pushes stay slow enough to bypass"; }
[[ -z "$(grep -n 'CASCADE_FAST' "$ROOT/.github/workflows/control-line.yml" 2>/dev/null)" ]] \
  || { ok=0; echo "  CI sets CASCADE_FAST — nothing would ever run the deferred suite"; }
t T48 "$ok" "the pre-push gate defers the pack's own meta-suite to CI and says so in the score; lint and the hop scorer still run locally; 'barbar merge' unsets fast mode, and CI never sets it"

# ---- T47  Layer 1 guards do not fail open on a large commit, and cleanup cannot abort one ----
# Two bugs of one family, both invisible in review. (a) `echo "$staged" | grep -q …` under `set -o pipefail`
# returns 141 once grep exits early and the writer takes SIGPIPE, so the guard behind it is SKIPPED — on a
# commit with enough staged files the envelope's human-ownership check simply did not run. (b) a trailing
# `rm` in a `-e` script aborted a commit whose every check had passed, because `.git` is a file in a worktree.
R="$TMP/t47"; mkrepo "$R" EXECUTE 05b
ok=1
# (a) a big commit must not walk past the human-ownership guard
# The guard is skipped only when the staged list is big enough to fill the ~64KB pipe buffer *after* grep
# matches. Deep paths get there with few files, so this stays cheap — the suite runs on every push, and a
# slow gate is one people bypass. One commit, not two: mkrepo already put envelope.md in HEAD.
( cd "$R" && python3 -B -c '
import os, sys
deep = os.path.join(*(["a-directory-with-a-deliberately-long-name"] * 8))
d = os.path.join(sys.argv[1], "filler", deep); os.makedirs(d, exist_ok=True)
for i in range(200):
    open(os.path.join(d, f"padding-file-with-a-long-name-{i:04d}.md"), "w").write("x")
' "$R" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak \
  && git add -A && git commit -qm "agent flips the hop inside a large commit" >/dev/null 2>"$TMP/err47" ) \
  && { ok=0; echo "  a large commit walked past the human-ownership guard — the pipeline reported SIGPIPE and the check was skipped"; }
grep -q 'human-owned' "$TMP/err47" || { ok=0; echo "  the large commit was refused for the wrong reason: $(head -1 "$TMP/err47")"; }
# no pipeline may feed grep -q in a hook that runs under pipefail
[[ -z "$(grep -nE '\| *grep -q' "$ROOT/.githooks/pre-commit" "$ROOT/.githooks/pre-push" 2>/dev/null)" ]] \
  || { ok=0; echo "  a hook still pipes into grep -q under pipefail — that guard silently skips on a big input"; }
# (b) cleanup is the trap's job; no bare cleanup may decide the exit status
[[ -z "$(grep -nE '^\s*rm -f "\$before"' "$ROOT/.githooks/pre-commit" 2>/dev/null)" ]] \
  || { ok=0; echo "  pre-commit still unlinks scratch files inline — a failing rm aborts a passing commit"; }
grep -q 'trap cleanup EXIT' "$ROOT/.githooks/pre-commit" || { ok=0; echo "  pre-commit has no EXIT trap, so cleanup can still set the exit status"; }
t T47 "$ok" "Layer 1 does not fail open on a large commit (no pipeline feeds grep -q under pipefail) and cleanup runs from an EXIT trap, so an unlinkable scratch path can never abort a commit whose checks passed"

# ---- T46  the git dir is not writable by the agent, on any hop ----
# Found by an adversarial design review of the signing system: every defence around a signature guarded the
# *shell* — bash_guard denies CASCADE_HUMAN= and running tests/sign.sh — but the Write tool needs no shell.
# On an EXECUTE hop the agent could write "<sha> docs/cascade/envelope.md" straight into the token ledger and
# pre-commit would honour it as the human's signature. Approve-to-sign is only real if the ledger is sealed.
if [[ -z "$L2" ]]; then
  echo "SKIP  T46  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
R="$TMP/t46"; mkrepo "$R" EXECUTE 05b
ok=1
w46() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s/%s","content":"x"},"cwd":"%s","tool_use_id":"t46-%s"}' \
  "${2:-Write}" "$R" "$1" "$R" "$3" | python3 -B "$L2/.claude/hooks/hop_guard.py" 2>/dev/null; }
# the signature ledger and the pending list: writing either one mints a signature
for f in cascade-human-ok cascade-sign-pending; do
  w46 ".git/$f" Write "$f" | grep -q '"deny"' || { ok=0; echo "  the agent may write .git/$f — it can mint its own signature and every dialog becomes decorative"; }
done
# the rest of the git dir is not the agent's either: hooks, refs, config
for f in hooks/pre-commit config refs/heads/main; do
  w46 ".git/$f" Write "$(basename "$f")" | grep -q '"deny"' || { ok=0; echo "  the agent may write .git/$f"; }
done
# Edit is the same tool call by another name
w46 ".git/cascade-human-ok" Edit e1 | grep -q '"deny"' || { ok=0; echo "  Write is denied but Edit is not — the hole is still open"; }
# and the refusal must not swallow ordinary product work on an EXECUTE hop
[[ -z "$(w46 src/Ledger.kt Write p1)" ]] || { ok=0; echo "  a normal product write on EXECUTE was refused — the seal is too wide"; }
[[ -z "$(w46 docs/cascade/05b-briefs.md Write p2)" ]] || { ok=0; echo "  a normal doc write was refused"; }
t T46 "$ok" "the git dir is sealed against the agent on every hop — the signature ledger, the pending list, the hooks and the refs — so a signature can only come from a human approving a dialog or running tests/sign.sh; ordinary product writes are untouched"
fi

# ---- T45  the hooks work in a git worktree, where .git is a file ----
# Found while committing the hop-state split from a worktree: pre-commit wrote its scratch file to
# "$ROOT/.git/…", which is a *file* in a worktree, so the guard errored on every protected-line edit.
R45="$TMP/t45-main"; mkrepo "$R45" EXECUTE 05b
W45="$TMP/t45-wt"
ok=1
( cd "$R45" && git checkout -q -b slice-45 2>/dev/null; git worktree add -q "$W45" -b wt-45 >/dev/null 2>&1 )
if [[ ! -e "$W45/.git" ]]; then
  echo "  (note: this git cannot add a worktree here — skipping the worktree half)"
else
  [[ -f "$W45/.git" ]] || { ok=0; echo "  fixture is not a real worktree (.git is not a file) — the test proves nothing"; }
  ( cd "$W45" && sed -i.bak 's/^CURRENT_HOP:.*/CURRENT_HOP: GENERATE/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak       && git add -A && git commit -qm "agent flips the hop from a worktree" >/dev/null 2>"$TMP/err45" )     && { ok=0; echo "  a protected-line edit was committed from a worktree — the guard did not run"; }
  grep -q 'Not a directory' "$TMP/err45" && { ok=0; echo "  the guard wrote to \$ROOT/.git, which is a file in a worktree: $(grep -m1 'Not a directory' "$TMP/err45")"; }
  grep -q 'human-owned' "$TMP/err45" || { ok=0; echo "  the refusal from a worktree does not explain itself: $(head -1 "$TMP/err45")"; }
fi
t T45 "$ok" "the git hooks resolve the real git dir instead of assuming \$ROOT/.git, so every guard still runs — and still refuses — inside a worktree, where .git is a file"

# ---- T44  hop state is its own file, and pre-split repos keep working ----
# Hop state turns over 3-4 times per slice while the laws beside it change twice a year; one file made
# `git log envelope.md` unreadable — the record you most want in two years, buried under transitions.
R="$TMP/t44"; mkrepo "$R" EXECUTE 05b
ok=1
# A: no hop-state.md — everything still reads the envelope, exactly as before the split
( cd "$R" && printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: legacy\n\nAUTOPILOT: 05b legacy\n' > docs/cascade/envelope.md )
[[ "$( cd "$R" && . tests/lib/cascade.sh && cascade_hop )" == "EXECUTE" ]] || { ok=0; echo "  a pre-split repo lost its hop when the readers moved — every installed repo would break"; }
[[ "$( cd "$R" && . tests/lib/cascade.sh && cascade_stage )" == "05b" ]] || { ok=0; echo "  a pre-split repo lost its stage"; }
# B: hop-state.md present — it wins, and laws stay in the envelope
( cd "$R" && printf 'CURRENT_HOP: GENERATE\nCURRENT_STAGE: 06\nCURRENT_SLICE: split\n<EDIT>\nAUTOPILOT: 06 split\n</EDIT>\n' > docs/cascade/hop-state.md \
    && printf '### D1 — laws stay in the envelope\ncheck:  true\nbreak:  false\n' > docs/cascade/envelope.md )
[[ "$( cd "$R" && . tests/lib/cascade.sh && cascade_hop )" == "GENERATE" ]] || { ok=0; echo "  hop-state.md is present but the hop still came from the envelope"; }
[[ "$( cd "$R" && python3 -B tests/lib/autopilot.py --status . )" == "next EXECUTE 06 split" ]] || { ok=0; echo "  autopilot did not read the signed list from hop-state.md"; }
[[ -n "$( cd "$R" && python3 -B tests/lib/laws.py docs/cascade/envelope.md --in-force )" ]] || { ok=0; echo "  laws stopped being read from the envelope after the split"; }
# C: the new file is human-owned at Layer 1, exactly like the envelope
( cd "$R" && git add -A && CASCADE_HUMAN=1 git commit -qm "human: split" >/dev/null 2>&1 )
( cd "$R" && sed -i.bak 's/^CURRENT_HOP: GENERATE/CURRENT_HOP: EXECUTE/' docs/cascade/hop-state.md && rm -f docs/cascade/hop-state.md.bak && git add -A && git commit -qm "agent flips the hop" >/dev/null 2>"$TMP/err44" ) \
  && { ok=0; echo "  the agent flipped CURRENT_HOP in hop-state.md and pre-commit allowed it — the whole edge is unguarded"; }
grep -q 'hop-state.md' "$TMP/err44" || { ok=0; echo "  the refusal does not name hop-state.md: $(head -1 "$TMP/err44")"; }
# D: an installer must not create hop-state.md where the envelope still carries the hop — that resets a live hop
if [[ -f "$ROOT/install.sh" ]]; then
  L44="$TMP/t44-legacy"; mkdir -p "$L44/docs/cascade" && ( cd "$L44" && git init -q )
  printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: mid-slice\n' > "$L44/docs/cascade/envelope.md"
  bash "$ROOT/install.sh" --no-plugin "$L44" >/dev/null 2>&1
  [[ ! -f "$L44/docs/cascade/hop-state.md" ]] || { ok=0; echo "  install created hop-state.md in a repo mid-slice — its live hop silently reset to NONE"; }
  [[ "$( cd "$L44" && . tests/lib/cascade.sh && cascade_hop )" == "EXECUTE" ]] || { ok=0; echo "  installing over a pre-split repo lost its running hop"; }
fi
t T44 "$ok" "hop state lives in docs/cascade/hop-state.md — human-owned at Layer 1 like the envelope, read in preference to it, with laws staying in the envelope; a repo without the file still reads hop state from the envelope, and installing never creates it under a running hop"

# ---- T43  a decision is asked, not dictated ----
# Found in use: /barbar auto with an unsigned list printed a four-line `sed` plus a stitch-key commit for the
# human to retype — a procedure standing in for a question the agent could simply have asked.
#
# Most of this test used to grep the command file for sentences ("ask, do not instruct", "never treat silence
# as acceptance"). Those greps could not fail for the reason they claimed: reword the doc and they go red with
# nothing broken; ignore the doc entirely at runtime and they stay green. By this pack's own standard that is
# THEATER. What is mechanizable is asserted here; the conduct itself is scored as eval fixtures in
# evals/hops/, the way `oneshot-not-barbar` already is.
CMD43="$(cascade_layer2_root)/.claude/commands/barbar.md"
if [[ ! -f "$CMD43" ]]; then
  echo "SKIP  T43  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
ok=1
# The command file must at least offer the picker at all — deleting it wholesale is a real failure mode,
# and this is the one grep that catches something a behavioral test cannot see.
grep -q 'AskUserQuestion' "$CMD43" || { ok=0; echo "  /barbar auto never offers the human a choice — an unsigned list is a decision, not a procedure"; }
grep -qi 'non-interactive' "$CMD43" || { ok=0; echo "  no fallback for a headless run, where there is nobody to ask"; }
# A send-back must leave a machine signal, or I11 is invisible to everything downstream (this is the half
# of I11 that is real; whether the human actually rewound cannot be observed by any hook).
R43="$TMP/t43-sb"; mkrepo "$R43" EXECUTE 05b
( cd "$R43" && python3 -B tests/lib/decisions.py . human SENDBACK "05b checkout — the balance check is in the view, not the domain" >/dev/null 2>&1 )
grep -q 'human .*SENDBACK.*balance check' "$R43/.cascade/decisions.log" 2>/dev/null \
  || { ok=0; echo "  a send-back cannot be recorded — I11 leaves no trace at all"; }
# And the conduct fixtures must be scored, not merely present.
for fx in fail-halt-instead-of-asking fail-silence-as-acceptance; do
  [[ -f "$ROOT/evals/hops/$fx.md" ]] || { ok=0; echo "  no eval fixture for '$fx' — the conduct is prose again"; }
done
out43="$(python3 -B "$ROOT/tests/score_hops.py" "$ROOT/evals/hops" 2>&1)"
grep -qE 'PASS +fail-halt-instead-of-asking' <<<"$out43" || { ok=0; echo "  the scorer does not catch a halt that should have been a question: $(grep halt-instead <<<"$out43" | head -1)"; }
grep -qE 'PASS +fail-silence-as-acceptance' <<<"$out43" || { ok=0; echo "  the scorer does not catch silence read as acceptance: $(grep silence <<<"$out43" | head -1)"; }
t T43 "$ok" "an unsigned list is a decision the human is asked about, not a procedure they retype: the picker is offered, headless still halts, a send-back leaves a recorded signal, and the two conduct failures are scored as eval fixtures rather than asserted as sentences in a doc"
fi

# ---- T42  plugin-mode install must not strip Layer 2 from the pack itself ----
# Found on a real machine: running install.sh (plugin mode) inside the pack deleted .claude/hooks/*.py.
# Correct in a product, where the plugin supplies them; here those files ARE what gets packaged.
if [[ ! -f "$ROOT/install.sh" ]]; then
  echo "SKIP  T42  no install.sh here (installed product, not the pack)"
else
P42="$TMP/t42-pack"; mkdir -p "$P42"
( cd "$ROOT" && tar cf - install.sh VERSION tests .claude .githooks docs commands skills evals/hops evals/fixtures .claude-plugin 2>/dev/null ) | ( cd "$P42" && tar xf - )
( cd "$P42" && git init -q && git add -A && git commit -qm init >/dev/null 2>&1 )
ok=1
before="$(ls "$P42/.claude/hooks" 2>/dev/null | wc -l | tr -d ' ')"
[[ "$before" -gt 0 ]] || { ok=0; echo "  fixture built without hooks — the test proves nothing"; }
bash "$P42/install.sh" --plugin "$P42" >/dev/null 2>&1
after="$(ls "$P42/.claude/hooks" 2>/dev/null | wc -l | tr -d ' ')"
[[ "$after" == "$before" ]] || { ok=0; echo "  plugin-mode install deleted the pack's own Layer 2 ($before hooks -> $after) — the next release would ship none"; }
[[ -f "$P42/.claude/skills/cascade-farm/SKILL.md" ]] || { ok=0; echo "  plugin-mode install deleted the pack's own skill source"; }
# and it must still strip them in a real product
Q42="$TMP/t42-product"; mkdir -p "$Q42" && ( cd "$Q42" && git init -q )
bash "$ROOT/install.sh" --plugin "$Q42" >/dev/null 2>&1
[[ ! -d "$Q42/.claude/hooks" ]] || { ok=0; echo "  plugin-mode install left project hooks in a product — the same tool call is judged twice"; }
t T42 "$ok" "plugin-mode install strips Layer 2 from a product but never from the pack, whose .claude/hooks are the source that gets packaged"
fi

# ---- T41  I10: an EXECUTE hop cannot ask for accept with no loop behind it ----
# I10 was prose only: autopilot.py gated the *advance* on loop.sh, but an interactive hop could print
# "STITCH NEEDED: accept execute" having never run it, and the human was asked to accept unevidenced work.
if [[ -z "$L2" ]]; then
  echo "SKIP  T41  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
R="$TMP/t41"; mkrepo "$R" EXECUTE 05b
ok=1
MSG41='STITCH NEEDED: accept execute for stage 05b, or send back.'
sg41() { printf '{"cwd":"%s","session_id":"%s","last_assistant_message":"%s"}' "$R" "$1" "$2" \
  | python3 -B "$L2/.claude/hooks/stop_guard.py" >/dev/null 2>"$TMP/err41"; echo $?; }
# no receipt at all
[[ "$(sg41 n1 "$MSG41")" -eq 2 ]] || { ok=0; echo "  accept was asked for with no loop run at all"; }
grep -q 'bash tests/loop.sh' "$TMP/err41" || { ok=0; echo "  the refusal does not name the command that produces the evidence"; }
# a receipt for this hop and this tree
( cd "$R" && . tests/lib/cascade.sh && mkdir -p .cascade && printf 'EXECUTE 05b %s\n' "$(cascade_worktree_sha "$R")" > .cascade/loop-receipt )
[[ "$(sg41 n2 "$MSG41")" -eq 0 ]] || { ok=0; echo "  a hop with a valid loop receipt was still refused: $(head -1 "$TMP/err41")"; }
# the tree changed after the loop passed: the evidence no longer describes the code
echo "late edit" > "$R/late.txt"
[[ "$(sg41 n3 "$MSG41")" -eq 2 ]] || { ok=0; echo "  code edited after loop.sh passed still counted as evidence"; }
# a receipt from a different hop does not carry over
( cd "$R" && . tests/lib/cascade.sh && printf 'EXECUTE 06 %s\n' "$(cascade_worktree_sha "$R")" > .cascade/loop-receipt )
[[ "$(sg41 n4 "$MSG41")" -eq 2 ]] || { ok=0; echo "  a receipt from another stage was accepted for this one"; }
# loop.sh itself writes the receipt only when it reaches n/n, and clears it when it does not
( cd "$R" && rm -f .cascade/loop-receipt && printf 'VALIDATOR: false\n' > docs/cascade/goal.md && bash tests/loop.sh >/dev/null 2>&1 )
[[ ! -f "$R/.cascade/loop-receipt" ]] || { ok=0; echo "  a failing loop still wrote an accept receipt"; }
( cd "$R" && printf 'VALIDATOR: true\n' > docs/cascade/goal.md && bash tests/loop.sh >/dev/null 2>&1 )
[[ -f "$R/.cascade/loop-receipt" ]] || { ok=0; echo "  a passing loop wrote no receipt, so the accept edge can never be reached"; }
# and the receipt is never committed

# stage 10 is judged by audit.sh, not loop.sh — demanding a loop receipt there blocks a finished hop
cp "$ROOT/tests/audit.sh" "$R/tests/" 2>/dev/null || true
( cd "$R" && rm -f .cascade/loop-receipt && sed -i.bak 's/^CURRENT_STAGE:.*/CURRENT_STAGE: 10/' docs/cascade/envelope.md && rm -f docs/cascade/envelope.md.bak )
MSG41b='STITCH NEEDED: accept execute for stage 10, or send back.'
printf '| FR-1 | x | path: docs/cascade/envelope.md test: true | IMPLEMENTED |\n' > "$R/docs/cascade/10-audit.md"
[[ "$(sg41 n5 "$MSG41b")" -eq 0 ]] || { ok=0; echo "  a CLEAN stage 10 was refused for having no loop receipt — stage 10 is judged by audit.sh: $(head -1 "$TMP/err41")"; }
printf '| FR-1 | x | path: nope/missing.kt test: false | IMPLEMENTED |\n' > "$R/docs/cascade/10-audit.md"
[[ "$(sg41 n6 "$MSG41b")" -eq 2 ]] || { ok=0; echo "  a DIRTY stage 10 was allowed to ask for accept"; }
grep -q 'tests/audit.sh' "$TMP/err41" || { ok=0; echo "  the stage-10 refusal names loop.sh instead of audit.sh"; }
t T41 "$ok" "I10 is mechanical, and per stage: every hop but 10 needs a loop.sh receipt for this hop and this tree (none, stale or from another stage is refused, a failing loop writes none, the receipt is never committed); stage 10 is judged live by audit.sh"
fi

# ---- T40  every layer records its decisions, and a signed law is verified on the spot ----
# git records what succeeded. It does not record what was denied, what was signed, or which law went red
# at 3am — and that is exactly what the morning after an unattended run needs.
if [[ -z "$L2" ]]; then
  echo "SKIP  T40  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
R="$TMP/t40"; mkrepo "$R" GENERATE 05b
cp "$ROOT/tests/dsharp_strength.sh" "$R/tests/"
ok=1
LOG="$R/.cascade/decisions.log"
# a denied product write on a GENERATE hop is recorded
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/x.kt","content":"x"},"cwd":"%s","tool_use_id":"t40a"}' "$R" "$R" \
  | python3 -B "$L2/.claude/hooks/hop_guard.py" >/dev/null 2>&1
grep -q 'hop_guard.*DENY.*src/x.kt' "$LOG" 2>/dev/null || { ok=0; echo "  a denied product write left no record — the morning after cannot say what was refused"; }
# a blocked ship escape is recorded with the command that was tried
printf '{"tool_name":"Bash","tool_input":{"command":"git push --no-verify"},"cwd":"%s","tool_use_id":"t40b"}' "$R" \
  | python3 -B "$L2/.claude/hooks/bash_guard.py" >/dev/null 2>&1
grep -q 'bash_guard.*DENY.*no-verify' "$LOG" 2>/dev/null || { ok=0; echo "  a blocked ship escape left no record"; }
# a law that cannot fail is recorded as THEATER, with its id
printf '### D1 — cannot fail\ncheck:  true\nbreak:  true\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && bash tests/dsharp_strength.sh >/dev/null 2>&1 )
grep -q 'dsharp.*THEATER.*D1' "$LOG" 2>/dev/null || { ok=0; echo "  a law going THEATER left no record — an overnight halt cannot be reconstructed"; }
# the log never becomes a gate: removing it changes no verdict
rm -rf "$R/.cascade"
( cd "$R" && bash tests/dsharp_strength.sh >/dev/null 2>&1 ); rc_nolog=$?
printf '### D1 — cannot fail\ncheck:  true\nbreak:  true\n' > "$R/docs/cascade/envelope.md"
[[ "$rc_nolog" -eq 1 ]] || { ok=0; echo "  the verdict changed when the log was absent — logging must never be load-bearing"; }
# it must stay out of git: a run during a hop cannot dirty the tree

# a signed envelope is checked for strength on the spot, not at the next run
printf '### D1 — cannot fail\ncheck:  true\nbreak:  true\n' > "$R/docs/cascade/envelope.md"
sha="$(python3 -B -c 'import sys,hashlib;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/docs/cascade/envelope.md")"
printf '%s docs/cascade/envelope.md\n' "$sha" > "$R/.git/cascade-sign-pending"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/docs/cascade/envelope.md"},"cwd":"%s","tool_use_id":"t40c"}' "$R" "$R" \
  | python3 -B "$L2/.claude/hooks/sign_ok.py" >/dev/null 2>"$TMP/err40"
grep -q 'THEATER' "$TMP/err40" || { ok=0; echo "  signing a law that cannot fail said nothing — the human learns only at the next /barbar auto: $(head -2 "$TMP/err40" | tr '\n' ' ')"; }
# a halt is a line the agent issues, not one it quotes: explaining the format must not stop the session
py40="import sys; sys.path.insert(0, '$L2/.claude/hooks'); from stop_guard import halting; print(halting(sys.stdin.read()))"
printf 'The shape is:\n\n```\nAUTOPILOT HALT: D3 is THEATER\n  WHAT TO DO: fix it\n```\n\nThat is all.\n' \
  | python3 -B -c "$py40" | grep -q False || { ok=0; echo "  a halt quoted inside a code fence was treated as a real halt — explaining the format stops the session"; }
printf 'a reply ends with `AUTOPILOT HALT: <reason>` when it stops early.\n' \
  | python3 -B -c "$py40" | grep -q False || { ok=0; echo "  a halt named inside an inline code span was treated as a real halt"; }
printf 'Work stopped.\n\nAUTOPILOT HALT: D3 is THEATER\n  WHAT TO DO: add the escape\n' \
  | python3 -B -c "$py40" | grep -q True || { ok=0; echo "  a real halt on its own line was not recognised"; }
printf 'STITCH NEEDED: accept execute for stage 05b, or send back. AUTOPILOT HALT: D4 is RED.\n' \
  | python3 -B -c "$py40" | grep -q True || { ok=0; echo "  a real halt appended to an edge line was not recognised"; }
t T40 "$ok" "every layer appends its decisions to .cascade/decisions.log (denials, signatures, law verdicts, halts) without the log ever becoming a gate, and signing a law runs its strength check on the spot"
fi

# ---- T39  a fresh clone on a second machine is told that Layer 1 is off, and friendly laws are visible ----
# core.hooksPath is git config: per-clone, never committed. Clone a cascade repo on another machine and
# .githooks/ is on disk with git not calling it — every commit and push gate silently absent.
if [[ -z "$L2" ]]; then
  echo "SKIP  T39  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
R="$TMP/t39"; mkrepo "$R" EXECUTE 05b
ok=1
ctx39() { printf '{"source":"resume","cwd":"%s","session_id":"%s"}' "$R" "$1" \
  | python3 -B "$L2/.claude/hooks/preserve.py" 2>/dev/null; }
printf '### D1 — balance MUST NOT go negative\ncheck:  true\nbreak:  false\n\n### D2 — half a law\ncheck:  true\nbreak:\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && git config --unset core.hooksPath 2>/dev/null || true )
out="$(ctx39 s1)"
grep -q 'LAYER 1 IS OFF' <<<"$out" || { ok=0; echo "  a clone with no core.hooksPath was not told its commit and push gates are absent"; }
grep -q 'git config core.hooksPath .githooks' <<<"$out" || { ok=0; echo "  the warning does not give the one-line fix"; }
# friendly-format laws must reach session start (they were invisible to preserve.py's private parser)
grep -q 'D1' <<<"$out" && grep -q 'IN FORCE' <<<"$out" || { ok=0; echo "  a friendly-format law is invisible at session start — the agent starts blind to it"; }
grep -q 'NOT IN FORCE' <<<"$out" || { ok=0; echo "  a law missing its break is not reported as not-in-force"; }
# and it must go quiet once the clone is wired
( cd "$R" && git config core.hooksPath .githooks )
grep -q 'LAYER 1 IS OFF' <<<"$(ctx39 s2)" && { ok=0; echo "  the warning still fires on a correctly wired repo"; }
t T39 "$ok" "a fresh clone is told Layer 1 is off with the one-line fix and goes quiet once wired; friendly-format laws reach session start"
fi

# ---- T33  a human who edits by hand can sign from any git client ----
# Found on a real product: the only signature was an environment variable, which a GUI client cannot pass,
# so a hand-edited envelope was blocked in a loop with no way out that did not involve the terminal.
R="$TMP/t33"; mkrepo "$R" EXECUTE 05b
cp "$ROOT/tests/sign.sh" "$R/tests/sign.sh"
ok=1
# an unsigned hand-edit of a human-owned file is refused
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: hand-edited\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && git add -A && git commit -qm "human edit, unsigned" >/dev/null 2>"$TMP/err33" ) \
  && { ok=0; echo "  an unsigned hand-edit of the envelope was committed"; }
grep -qi 'sign' "$TMP/err33" || { ok=0; echo "  the refusal does not name the signing command, so the human is stuck: $(head -2 "$TMP/err33" | tr '\n' ' ')"; }
# sign.sh mints a token for it, and the same commit then lands with no env var set
( cd "$R" && bash tests/sign.sh >/dev/null 2>&1 )
( cd "$R" && git add -A && git commit -qm "human edit, signed" >/dev/null 2>"$TMP/err33" ) \
  || { ok=0; echo "  a signed hand-edit still could not be committed: $(head -2 "$TMP/err33" | tr '\n' ' ')"; }
# the token is one-shot: the next edit needs a new signature
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: edited-again\n' > "$R/docs/cascade/envelope.md"
( cd "$R" && git add -A && git commit -qm "second edit, unsigned" >/dev/null 2>&1 ) \
  && { ok=0; echo "  one signature covered a later, different edit — the token is not one-shot"; }
# and the agent may not run it (Layer 2)
if [[ -n "$L2" ]]; then
  for c in "bash tests/sign.sh" "bdd sign"; do
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$c" "$R" \
      | python3 -B "$L2/.claude/hooks/bash_guard.py" 2>/dev/null | grep -q '"deny"' \
      || { ok=0; echo "  the agent was allowed to run '$c' — it can sign as the human"; }
  done
fi
t T33 "$ok" "a human editing by hand can sign from any git client: tests/sign.sh mints a one-shot token pre-commit accepts for exactly that content, the refusal names it, and the agent is denied running it"

# ---- T38  the plugin ships what the repo runs: commands/ and skills/ are byte-identical to .claude/ ----
# Found in use: these were symlinks until 1.1.1 (the loader does not follow them), and the real files that
# replaced them froze. commands/barbar.md drifted 27 lines behind — a plugin-mode /barbar auto had no
# stage-10 auditor and no mandatory HALT block, silently, for four releases.
if [[ ! -d "$ROOT/commands" ]]; then
  echo "SKIP  T38  no plugin payload here (installed product, not the pack)"
else
ok=1
while IFS= read -r p; do
  [[ -f "$ROOT/.claude/$p" ]] || { ok=0; echo "  the plugin ships $p but .claude/ has no such file — nothing runs it in a standalone install"; continue; }
  cmp -s "$ROOT/$p" "$ROOT/.claude/$p" || { ok=0; echo "  $p differs from .claude/$p ($(wc -l < "$ROOT/$p") vs $(wc -l < "$ROOT/.claude/$p") lines) — plugin-mode repos run the stale copy"; }
done < <(cd "$ROOT" && git ls-files commands skills)
[[ -z "$(cd "$ROOT" && git ls-files -s commands skills | awk '$1 == "120000"')" ]] || { ok=0; echo "  a plugin payload file is a symlink — the plugin loader does not follow them"; }
t T38 "$ok" "every file the plugin ships under commands/ and skills/ is a real file and byte-identical to the .claude/ copy the repo runs"
fi

# ---- T37  an idle reply is not a hop: no edge line is demanded, and the prose says so ----
# Found in use: AGENTS.md asked for an edge line on *every* reply, so plain questions ended with
# "STITCH NEEDED: ... for stage N" — a placeholder stage, on a reply that closed no hop.
R="$TMP/t37"; mkrepo "$R" EXECUTE 05b
if [[ -z "$L2" ]]; then
  echo "SKIP  T37  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
ok=1
sg37() { ( cd "$R" && printf '{"cwd":"%s","transcript_path":"%s","session_id":"t37"}' "$R" "$TMP/t37.jsonl" \
  | python3 -B "$L2/.claude/hooks/stop_guard.py" >/dev/null 2>"$TMP/err37"; echo $? ); }
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Both, and here is why."}]}}\n' > "$TMP/t37.jsonl"
# idle envelope: no hop open -> the hook must stay silent
printf 'CURRENT_HOP:\nCURRENT_STAGE:\nCURRENT_SLICE:\n' > "$R/docs/cascade/envelope.md"
[[ "$(sg37)" -eq 0 ]] || { ok=0; echo "  the Stop hook demanded an edge line while no hop was running: $(head -1 "$TMP/err37")"; }
# hop open, no edge line -> it must still block (the boundary is a boundary, not a hole)
printf 'CURRENT_HOP: EXECUTE\nCURRENT_STAGE: 05b\nCURRENT_SLICE: a\n' > "$R/docs/cascade/envelope.md"
[[ "$(sg37)" -eq 2 ]] || { ok=0; echo "  the Stop hook let an EXECUTE hop end with no edge line"; }
grep -q 'for stage 05b' "$TMP/err37" || { ok=0; echo "  the hook's edge line says 'stage N' instead of the real stage"; }
# the prose must scope the ritual to hops, or the agent prints it over questions again
grep -q 'Ending a hop reply' "$ROOT/AGENTS.md" || { ok=0; echo "  AGENTS.md still asks for the edge line on every reply, not on hop replies"; }
grep -q 'When no hop is running' "$ROOT/AGENTS.md" || { ok=0; echo "  AGENTS.md does not say what an idle reply ends with"; }
t T37 "$ok" "the edge-line ritual is scoped to open hops in both layers: the Stop hook is silent when idle and names the real stage when not, and AGENTS.md says the same"
fi

# ---- T16  install.sh places Layer 2 where the agent actually loads it (found by probe P6) ----
# Tests the pack's installer, so it only runs in the pack repo. Installed products have no install.sh.
if [[ ! -f "$ROOT/install.sh" ]]; then
  echo "SKIP  T16  no install.sh here (installed product, not the pack)"
else
I="$TMP/t16"; mkdir -p "$I"; ( cd "$I" && git init -q )
bash "$ROOT/install.sh" --no-plugin "$I" >/dev/null 2>&1
ok=0; [[ -f "$I/.claude/skills/cascade-farm/SKILL.md" && -f "$I/.claude/commands/barbar.md" && -f "$I/.claude/commands/loop.md" && -f "$I/.claude/hooks/hop_guard.py" && -f "$I/.claude/settings.json" && -x "$I/.githooks/pre-commit" ]] \
  && [[ "$(cd "$I" && git config core.hooksPath)" == ".githooks" ]] && ok=1
# The installed farm must be n/n in the product (Docker spike S1). Guarded: the nested farm skips this step.
if [[ -z "${CASCADE_ENFORCEMENT_NESTED:-}" ]]; then
  ( cd "$I" && CASCADE_FAST=1 CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >"$TMP/t16.farm" 2>&1 ) || { ok=0; echo "  installed farm red: $(grep -E '^FAIL' "$TMP/t16.farm" | head -3 | tr '\n' ' ')"; }
fi
# The install itself must be committable without the key (found on a real product: the EDIT scan hit hook source and a .pyc).
( cd "$I" && git add -A && git commit -qm "cascade: install" >/dev/null 2>"$TMP/err" ) || { ok=0; echo "  fresh install could not be committed without the key: $(grep -m1 BLOCKED "$TMP/err")"; }
[[ -z "$(cd "$I" && git ls-files | grep -E '__pycache__|\.pyc$')" ]] || { ok=0; echo "  bytecode got committed"; }
# A run writes its receipt, its round counter and its decision log. If the install does not make those
# invisible to git, an autopilot night commits its own audit trail into the product (found when the log
# first appeared in a repo and pre-commit rejected it as product code on a GENERATE hop).
for gen in .cascade/decisions.log .cascade/loop-receipt .cascade/punch-rounds; do
  mkdir -p "$I/.cascade" && echo x > "$I/$gen"
  ( cd "$I" && git check-ignore -q "$gen" ) || { ok=0; echo "  install.sh leaves $gen visible to git — a run would dirty the product's tree"; }
done
[[ -z "$(cd "$I" && git status --porcelain 2>/dev/null)" ]] || { ok=0; echo "  a fresh install plus a run leaves the tree dirty: $(cd "$I" && git status --porcelain | head -1)"; }
t T16 "$ok" "install.sh puts skill + commands + hooks under .claude/, sets core.hooksPath; installed farm is n/n; the install commits without the key"
fi


# ---- T50  the git-dir seal holds inside a linked worktree ----
# T46 sealed $GIT_DIR against the agent, but only ever built a plain repo, where .git is a directory under
# the root. In a linked worktree $GIT_DIR is <main>/.git/worktrees/<name> — outside the worktree root — so
# hop_guard's "path is not under the root" early return fired before the seal was reached, and the agent
# could write its own signature token. Same blind spot class as T45, one layer up.
if layer2 T50; then
R="$TMP/t50"; mkrepo "$R" EXECUTE 05b
W="$TMP/t50wt"
( cd "$R" && git worktree add -q "$W" -b probe >/dev/null 2>&1 )
ok=1
if [[ ! -d "$W" ]]; then
  echo "  could not create a worktree to test with"; ok=0
else
GDW="$( cd "$W" && git rev-parse --absolute-git-dir )"
w50() { printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s","content":"x"},"tool_use_id":"t50-%s"}' \
  "${2:-Write}" "$W" "$1" "$3" | python3 -B "$L2/.claude/hooks/hop_guard.py" 2>/dev/null; }
for f in cascade-human-ok cascade-sign-pending; do
  w50 "$GDW/$f" Write "$f" | grep -q '"deny"' || { ok=0; echo "  from a worktree the agent may write \$GIT_DIR/$f — it mints its own signature and approve-to-sign is decorative"; }
done
w50 "$GDW/cascade-human-ok" Edit e50 | grep -q '"deny"' || { ok=0; echo "  Write is sealed in a worktree but Edit is not"; }
w50 "$GDW/hooks/pre-commit" Write h50 | grep -q '"deny"' || { ok=0; echo "  the agent may rewrite the hooks from a worktree"; }
# and ordinary product work inside the worktree is untouched
[[ -z "$(w50 "$W/src/Ledger.kt" Write p50)" ]] || { ok=0; echo "  a normal product write inside a worktree was refused — the seal is too wide"; }
fi
t T50 "$ok" "the git dir is sealed against the agent from inside a linked worktree too, where \$GIT_DIR lives outside the worktree root — ordinary product writes there are untouched"
fi

# ---- T51  quoting an argument does not defeat bash_guard ----
# 1.7.0 stopped the guard firing on reads by running every check over strip_quoted() text, so that a commit
# message naming a guarded command is read as prose. But that blanks quoted *arguments* too, and an argument
# in quotes is still that argument: one pair of quotes turned every denial below into an allow, including
# `git commit "--no-verify"`, which removes Layer 1 altogether.
if layer2 T51; then
ok=1
b51() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
  "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" | hook bash_guard.py; }
while IFS= read -r c51; do
  [[ -n "$c51" ]] || continue
  b51 "$c51" | grep -q '"deny"' || { ok=0; echo "  quoting defeats the guard: $c51"; }
done <<'Q51'
printf x > ".git/cascade-human-ok"
cp /tmp/tok '.git/cascade-human-ok'
python3 -c "open('.git/cascade-human-ok','w').write('x')"
bash "tests/sign.sh"
git commit "--no-verify" -m x
git push origin "main"
Q51
# the reads and the prose that 1.7.0 deliberately allowed must stay allowed — a guard that cries wolf is one
# people learn to route around, which is how the noise became a hole in the first place.
while IFS= read -r a51; do
  [[ -n "$a51" ]] || continue
  [[ -z "$(b51 "$a51")" ]] || { ok=0; echo "  a harmless command was denied: $a51"; }
done <<'A51'
cat ".git/cascade-human-ok"
grep -n cascade-human-ok .githooks/pre-commit
echo "the ledger lives at .git/cascade-human-ok"
git commit -m "docs: mention tests/sign.sh and CASCADE_HUMAN=1 in INTEGRATION"
git config core.hooksPath .githooks
A51
t T51 "$ok" "quoting an argument does not defeat bash_guard — the ledger, the signer, --no-verify and a push to main are denied quoted or bare, while reads and prose that merely name them stay allowed"
fi

# ---- T52  doctor reports a dead layer -----------------------------------------
# `install.sh --check` verifies the shipped files. A repo can pass it with every byte correct and still
# have a dead Layer 1: core.hooksPath is git config and does not travel with a clone. Doctor exists for
# exactly that gap, so the thing to prove is not that it prints a score — it is that each of its own
# checks goes red when the layer behind it dies. A green doctor on a broken repo would be worse than no
# doctor, because people would trust it.
ok=1
if [[ ! -f "$ROOT/tests/doctor.sh" ]]; then
  ok=0; echo "  tests/doctor.sh is missing"
else
  out52="$(cd "$ROOT" && DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"
  # NOT "doctor is clean here": that is a fact about the machine, not the code. A CI runner clones
  # fresh, so core.hooksPath — git config, which does not travel with a tree — is unset and doctor
  # correctly reports Layer 1 dead. The first cut of this test asserted the ambient repo was healthy,
  # passed on a developer box that had run an install, and could never pass in CI. Doctor was right;
  # the test was reading its environment. So: the score line must be well formed, and the direction of
  # each check is proven against repos this test builds.
  echo "$out52" | grep -qE '^DOCTOR [0-9]+/[0-9]+$' || {
    ok=0; echo "  doctor did not print a well-formed DOCTOR k/n"; }
  # Positive control: a repo whose hooksPath IS set must show that check green. With the hookspath
  # mutant below (which must go red) this pins both directions without either run consulting the
  # machine's own git config.
  P52="$TMP/t52-wired"; mkdir -p "$P52"
  for x in tests .githooks .github .claude docs commands VERSION install.sh CONTROL-LINE.md AGENTS.md; do
    [[ -e "$ROOT/$x" ]] && cp -R "$ROOT/$x" "$P52/$x"
  done
  ( cd "$P52" && git init -q . && git config core.hooksPath .githooks ) >/dev/null 2>&1
  wo="$(cd "$P52" && DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"
  echo "$wo" | grep -E 'hooksPath' | grep -q 'RED' && {
    ok=0; echo "  doctor called a correctly wired core.hooksPath red: $(echo "$wo" | grep hooksPath | head -1)"; }
  # And the same tree with it unset must go red there — the layer really is dead in a fresh clone.
  ( cd "$P52" && git config --unset core.hooksPath ) >/dev/null 2>&1
  uo="$(cd "$P52" && DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"
  echo "$uo" | grep -E 'hooksPath' | grep -q 'RED' || {
    ok=0; echo "  doctor stayed green with core.hooksPath unset — Layer 1 is dead and it said nothing"; }
  # A skipped check must never be counted as green: k/n covers only checks that ran.
  echo "$out52" | grep -q 'check(s) skipped — not counted either way' || {
    ok=0; echo "  doctor did not say its skipped checks are uncounted"; }
  # Branch protection cannot be read from the tree. Doctor must say so rather than implying it checked.
  echo "$out52" | grep -q 'branch protection is a GitHub setting' || {
    ok=0; echo "  doctor implied it verified branch protection"; }
  # Each new check needs a twin that fails, or the check is not in force (I13's rule, applied to doctor).
  for m52 in hookspath layer0 hopstate; do
    mo="$(cd "$ROOT" && DOCTOR_MUTANT="$m52" DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"; mrc=$?
    [[ "$mrc" -ne 0 ]] && echo "$mo" | grep -q 'RED' || {
      ok=0; echo "  DOCTOR_MUTANT=$m52 did not turn doctor red — that check is theater"; }
  done
  # A degraded repo is what doctor is for: it must diagnose, not crash.
  D52="$TMP/t52-bare"; mkdir -p "$D52/tests"; cp "$ROOT/tests/doctor.sh" "$D52/tests/doctor.sh"
  bo="$(cd "$D52" && DOCTOR_FAST=1 bash tests/doctor.sh 2>&1)"; brc=$?
  [[ "$brc" -ne 0 ]] && echo "$bo" | grep -q 'RED' || { ok=0; echo "  doctor in a bare repo did not report findings"; }
  echo "$bo" | grep -qi 'traceback\|command not found\|unbound variable' && {
    ok=0; echo "  doctor crashed in a bare repo instead of diagnosing it"; }
  # The command file ships to both places and must not drift (the T38 class).
  cmp -s "$ROOT/commands/doctor.md" "$ROOT/.claude/commands/doctor.md" || {
    ok=0; echo "  commands/doctor.md and .claude/commands/doctor.md differ"; }
fi
t T52 "$ok" "doctor goes red per dead layer (hooksPath, Layer 0 CI, hop state), never counts a skip as green, never claims to have checked branch protection, diagnoses a bare repo instead of crashing, and ships one command file to both trees"

if [[ "$fail" -ne 0 ]]; then exit 1; fi
echo "PASS: I18 T8–T52 enforced"
