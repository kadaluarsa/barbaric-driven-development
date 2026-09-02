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

R="$TMP/t13"; mkrepo "$R" EXECUTE 05b 'D1 | balance MUST NOT go negative | test 1 = 1'
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
for x in tests evals docs skills .github CONTROL-LINE.md; do cp -R "$ROOT/$x" "$P/$x"; done
rm -f "$P/tests/enforcement.sh"   # no recursion; farm skips it when absent
printf '# oneshot-not-barbar implemented-needs-evidence\nraise SystemExit(3)\n' > "$P/tests/score_hops.py"
out="$(bash "$P/tests/barbar.sh" 2>&1)"; rc=$?
ok=0; [[ "$rc" -ne 0 ]] && echo "$out" | grep -q 'FAIL  hop-scorer' && ok=1
out2="$(BARBAR_ROOT="$P/evals/fixtures/ready-product" bash "$P/tests/barbar.sh" merge 2>&1)"; rc2=$?
[[ "$rc2" -ne 0 ]] && echo "$out2" | grep -q 'farm is not n/n' || ok=0
t T14 "$ok" "farm is red when the scorer dies; merge runs the farm first"

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

if [[ "$fail" -ne 0 ]]; then exit 1; fi
echo "PASS: I18 T8–T15 enforced"
