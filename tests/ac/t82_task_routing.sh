#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bdd-t82.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

out="$(python3 -B "$ROOT/tests/score_hops.py" "$ROOT/evals/hops" 2>&1)" || score_rc=$?
score_rc="${score_rc:-0}"
ok=1
[[ "$score_rc" -eq 0 ]] || { ok=0; echo "$out" | grep -E '^(FAIL|HOPS)' | tail -8; }
for name in \
  t82-investigation t82-bug-fix t82-feature t82-refactor t82-verification \
  t82-precedence-explain-failure t82-precedence-fix-and-verify \
  t82-none-propose-edge t82-generate-spec-only t82-execute-accepted-plan \
  t82-law-conflict t82-human-state-change t82-reject-misroute t82-reject-scope-expansion; do
  grep -q "  PASS  $name.md " <<<"$out" || { ok=0; echo "  route eval did not pass: $name"; }
done
grep -q 't82-reject-misroute.*actual=fail' <<<"$out" \
  || { ok=0; echo "  wrong route was not scored as a failure case"; }
grep -q 't82-reject-scope-expansion.*actual=fail' <<<"$out" \
  || { ok=0; echo "  scope expansion was not scored as a failure case"; }
t AC1 "$ok" "route and boundary fixtures distinguish accepted choices from misroutes"

ok=1
[[ -f "$ROOT/skills/bdd-work/SKILL.md" ]] || { ok=0; echo "  plugin skill is missing"; }
[[ -f "$ROOT/.claude/skills/bdd-work/SKILL.md" ]] || { ok=0; echo "  standalone skill copy is missing"; }
if [[ -f "$ROOT/skills/bdd-work/SKILL.md" && -f "$ROOT/.claude/skills/bdd-work/SKILL.md" ]]; then
  cmp -s "$ROOT/skills/bdd-work/SKILL.md" "$ROOT/.claude/skills/bdd-work/SKILL.md" \
    || { ok=0; echo "  plugin and standalone skill files differ"; }
fi
grep -q '/bdd-work' "$ROOT/README.md" || { ok=0; echo "  README does not document /bdd-work"; }
t AC2 "$ok" "plugin and standalone skill copies match and the README documents the entry point"

ok=1
git -C "$TMP" init -q
git -C "$TMP" config user.email bdd-t82@example.invalid
git -C "$TMP" config user.name BDD-T82
bash "$ROOT/install.sh" --no-plugin "$TMP" >"$TMP/install.log" 2>&1 || {
  ok=0; echo "  standalone install failed: $(tail -5 "$TMP/install.log" | tr '\n' ' ')"
}
[[ -f "$TMP/.claude/skills/bdd-work/SKILL.md" ]] \
  || { ok=0; echo "  standalone installation did not place /bdd-work under .claude/skills"; }
if [[ -f "$TMP/.claude/skills/bdd-work/SKILL.md" ]]; then
  cmp -s "$ROOT/skills/bdd-work/SKILL.md" "$TMP/.claude/skills/bdd-work/SKILL.md" \
    || { ok=0; echo "  installed skill differs from plugin skill"; }
fi
t AC3 "$ok" "a standalone install exposes the same /bdd-work skill"

echo
[[ "$fail" -eq 0 ]] && echo "T82 AC all PASS" || echo "T82 AC FAILED"
exit "$fail"
