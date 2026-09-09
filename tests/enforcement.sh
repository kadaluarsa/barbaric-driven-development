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
find "$P2/docs/cascade" -mindepth 1 -maxdepth 1 ! -name 'product-e2e-*.md' ! -name 'skill-binding.md' -exec rm -rf {} +
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
  ( cd "$I3" && CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >/dev/null 2>&1 ) || { ok=0; echo "  farm red after re-install"; }
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
j="$(printf '{"tool_name":"Bash","tool_input":{"command":"cat .git/cascade-sign-pending"}}' | hook bash_guard.py)"; echo "$j" | grep -q '"deny"' || { ok=0; echo "  bash_guard let the agent touch the pending file"; }
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
if [[ "$(git -C "$V" config core.bare)" != "true" || "$(cat "$V/.git/HEAD")" != "ref: refs/heads/main" ]]; then echo "  (note: this git does not redirect init/symbolic-ref via GIT_DIR — the leak is still guarded)"; fi
( cd "$V" && git config core.bare false && git symbolic-ref HEAD refs/heads/feature )
( cd "$TMP" && GIT_DIR="$V/.git" GIT_WORK_TREE="$V" CASCADE_ENFORCEMENT_NESTED=1 bash "$ROOT/tests/enforcement.sh" >/dev/null 2>&1 ) || true   # nested run (T16/T22/T32 skip inside); result irrelevant
[[ "$(git -C "$V" config core.bare)" == "false" && "$(cat "$V/.git/HEAD")" == "ref: refs/heads/feature" ]] || { ok=0; echo "  the farm mutated the repo named by an inherited GIT_DIR (bare=$(git -C "$V" config core.bare), HEAD=$(cat "$V/.git/HEAD"))"; }
t T32 "$ok" "an inherited GIT_DIR/GIT_WORK_TREE (as git sets for hooks) never reaches the farm's throwaway repos"
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
( cd "$P5" && CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >"$TMP/t35.farm" 2>&1 ) || { ok=0; echo "  plugin-mode repo cannot reach BARBAR n/n: $(grep -E '^FAIL' "$TMP/t35.farm" | head -3 | tr '\n' ' ')"; }
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
grep -q 'At most \*\*3\*\* punch rounds' "$ROOT/.claude/commands/barbar.md" || { ok=0; echo "  the punch list has no round cap"; }
grep -q 'EXECUTE-AUDIT' "$ROOT/docs/cascade/skill-binding.md" || { ok=0; echo "  docs/cascade/skill-binding.md is stale (no EXECUTE-AUDIT row) — re-run the pack's install.sh in this repo"; }
t T36 "$ok" "stage 10 can be signed onto the autopilot list and is gated by audit.sh (rows first, CLEAN to advance); stage 11 never can; the audit hop uses an independent reviewer and a capped punch list"

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
grep -q 'ROOT/\.git/' "$ROOT/.githooks/pre-commit" && { ok=0; echo "  pre-commit still hardcodes \$ROOT/.git instead of the resolved git dir"; }
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
CMD43="$(cascade_layer2_root)/.claude/commands/barbar.md"
if [[ ! -f "$CMD43" ]]; then
  echo "SKIP  T43  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI)."
else
ok=1
grep -q 'AskUserQuestion' "$CMD43" || { ok=0; echo "  /barbar auto never offers the human a choice — an unsigned list is a decision, not a procedure"; }
grep -qi 'ask, do not instruct' "$CMD43" || { ok=0; echo "  the unsigned-list path does not tell the agent to ask before halting"; }
grep -qi 'non-interactive' "$CMD43" || { ok=0; echo "  no fallback for a headless run, where there is nobody to ask"; }
grep -qi 'Never print a .sed' "$CMD43" || { ok=0; echo "  the agent is still free to hand the human a sed script for an edit it can make itself"; }
grep -qi 'Prefer a question to a halt' "$CMD43" || { ok=0; echo "  halts are not steered toward a question when the blocker is a decision"; }
# both copies say it, or plugin-mode users get the old behaviour (T38 is the general rule; this is the one that bit)
if [[ -f "$ROOT/commands/barbar.md" ]]; then
  grep -q 'AskUserQuestion' "$ROOT/commands/barbar.md" || { ok=0; echo "  the plugin copy of /barbar does not offer the picker"; }
fi
# laws are signed one at a time, read, not hand-copied in a block
grep -qi 'one question per candidate law' "$CMD43" || { ok=0; echo "  /barbar init still asks the human to hand-copy a block of laws instead of walking them one at a time"; }
grep -qi 'a law they did not read' "$CMD43" || { ok=0; echo "  nothing warns against signing unread laws"; }
# an accept edge offers the verdict, and a send-back leaves a machine signal (I11)
grep -qi 'At an accept edge, offer the verdict' "$CMD43" || { ok=0; echo "  the accept edge does not offer accept / send back / show the diff"; }
grep -q 'SENDBACK' "$CMD43" || { ok=0; echo "  a send-back leaves no recorded signal — I11 stays entirely invisible"; }
grep -qi 'never treat silence as acceptance' "$CMD43" || { ok=0; echo "  an unanswered accept question could be read as a yes"; }
t T43 "$ok" "decisions are asked, not dictated: the next slice, each proposed law one at a time, and the accept/send-back verdict all go through AskUserQuestion and are signed by the dialog; a send-back is recorded; headless still halts with the lines named"
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
grep -q '^\.cascade/loop-receipt$' "$ROOT/.gitignore" || { ok=0; echo "  the loop receipt is not gitignored"; }
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
grep -q '^\.cascade/decisions\.log$' "$ROOT/.gitignore" || { ok=0; echo "  the decision log is not gitignored — an autopilot run would dirty the tree it is auditing"; }
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
  ( cd "$I" && CASCADE_ENFORCEMENT_NESTED=1 bash tests/barbar.sh >"$TMP/t16.farm" 2>&1 ) || { ok=0; echo "  installed farm red: $(grep -E '^FAIL' "$TMP/t16.farm" | head -3 | tr '\n' ' ')"; }
fi
# The install itself must be committable without the key (found on a real product: the EDIT scan hit hook source and a .pyc).
( cd "$I" && git add -A && git commit -qm "cascade: install" >/dev/null 2>"$TMP/err" ) || { ok=0; echo "  fresh install could not be committed without the key: $(grep -m1 BLOCKED "$TMP/err")"; }
[[ -z "$(cd "$I" && git ls-files | grep -E '__pycache__|\.pyc$')" ]] || { ok=0; echo "  bytecode got committed"; }
t T16 "$ok" "install.sh puts skill + commands + hooks under .claude/, sets core.hooksPath; installed farm is n/n; the install commits without the key"
fi

if [[ "$fail" -ne 0 ]]; then exit 1; fi
echo "PASS: I18 T8–T45 enforced"
