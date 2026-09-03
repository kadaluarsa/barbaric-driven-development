#!/usr/bin/env bash
# I17 evidence: T1–T7 must stay true or CI is red.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRE="$ROOT/docs/cascade/product-e2e-gre-pipeline.md"
CAS="$ROOT/docs/cascade/product-e2e-cascade.md"
CL="$ROOT/CONTROL-LINE.md"
SKILL="$ROOT/.claude/skills/cascade-farm/SKILL.md"
WF="$ROOT/.github/workflows/control-line.yml"
BARBAR="$ROOT/tests/barbar.sh"
fail=0
t() {
  local id="$1" ok="$2" msg="$3"
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS  $id  $msg"
  else
    echo "FAIL  $id  $msg"
    fail=1
  fi
}

ok=0
grep -q 'I17 Dune bar' "$GRE" && grep -q 'Rule (I17)' "$CAS" && grep -q 'T1' "$CL" && ok=1
t T0 "$ok" "I17 named in GRE, cascade, CONTROL-LINE"

ok=0
grep -q 'Hard stop' "$SKILL" && grep -q 'on A based on B using C' "$SKILL" && grep -q 'Do not implement features' "$SKILL" && ok=1
t T1 "$ok" "skill hard-stops feature one-shots"

ok=0
[[ -x "$ROOT/tests/score_hops.py" || -f "$ROOT/tests/score_hops.py" ]] && grep -q 'oneshot-not-barbar' "$ROOT/tests/score_hops.py" && grep -q 'implemented-needs-evidence' "$ROOT/tests/score_hops.py" && ok=1
t T2 "$ok" "hop evals score one-shots and tree evidence"

ok=0
grep -q 'tests/barbar.sh' "$WF" && grep -q 'tests/i17_dune.sh' "$WF" && ! grep -q 'continue-on-error' "$WF" && grep -q 'pull_request' "$WF" && ok=1
t T3 "$ok" "CI runs farm + I17 on PRs, no continue-on-error"

ok=0
grep -q 'BARBAR \$k/\$n' "$BARBAR" && grep -q 'not n/n' "$BARBAR" && grep -q 'exit 1' "$BARBAR" && ok=1
t T4 "$ok" "farm exits non-zero unless k=n"

ok=0
grep -q 'ALLOWED' "$BARBAR" && grep -q 'REFUSED' "$BARBAR" && [[ -f "$ROOT/evals/fixtures/ready-product/docs/cascade/10-audit.md" ]] && [[ -f "$ROOT/evals/fixtures/dirty-product/docs/cascade/10-audit.md" ]] && ok=1
t T5 "$ok" "merge gate has REFUSED and ALLOWED fixtures"

ok=0
[[ -f "$ROOT/evals/hops/fail-implemented-without-evidence.md" ]] && [[ -f "$ROOT/evals/hops/pass-implemented-with-evidence.md" ]] && ok=1
t T6 "$ok" "IMPLEMENTED without evidence has a failing fixture"

ok=0
[[ -f "$ROOT/evals/hops/fail-generate-executed.md" ]] && [[ -f "$ROOT/evals/hops/fail-started-nplus1.md" ]] && ok=1
t T7 "$ok" "GENERATE-execute and N+1 have failing fixtures"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: I17 T1–T7 evidenced"
