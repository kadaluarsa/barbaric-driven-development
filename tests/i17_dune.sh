#!/usr/bin/env bash
# I17 evidence: T1–T7 must stay true or CI is red.
set -euo pipefail
# Git exports GIT_DIR/GIT_WORK_TREE to hooks. Inherited by a script that runs `git init` in a temp dir, they
# redirect it at the real repo (this once flipped a product to core.bare=true and re-pointed a worktree's HEAD).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRE="$ROOT/docs/cascade/product-e2e-gre-pipeline.md"
CAS="$ROOT/docs/cascade/product-e2e-cascade.md"
CL="$ROOT/CONTROL-LINE.md"
# shellcheck source=tests/lib/cascade.sh
. "$ROOT/tests/lib/cascade.sh"
# Layer 2 (hooks, commands, skill) lives in the repo for a standalone install and in the plugin otherwise.
# On a machine with neither — a plugin-mode repo checked out in CI — it is absent by design, not broken.
L2="$(cascade_layer2_root)"
SKILL="$L2/.claude/skills/cascade-farm/SKILL.md"
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

if [[ -z "$L2" ]]; then
  echo "SKIP  T1  Layer 2 is not on this machine (plugin-mode repo, plugin not installed — e.g. CI). Layers 0/1 still enforced."
else
  ok=0
  grep -q 'Hard stop' "$SKILL" && grep -q 'on A based on B using C' "$SKILL" && grep -q 'Do not implement features' "$SKILL" && ok=1
  t T1 "$ok" "skill hard-stops feature one-shots"
fi

# T2 and T4-T7 used to grep this pack's own source for strings — "exit 1" in barbar.sh, the names of two
# scorer rules, the existence of fixture files nothing ever scored. A grep proves a sentence is present, not
# that behaviour follows from it: T4 could not have failed if the farm had stopped exiting non-zero, and
# T6/T7 could not have failed if the scorer had stopped catching their fixtures. They run things now.
# T0, T1 and T3 stay presence checks on purpose — they guard against an instruction file or a CI job being
# deleted, which is exactly what a presence check is for, and is labelled as such in CONTROL-LINE.md.

ok=0
set +e                                   # a red scorer must be reported as FAIL, not kill the suite
hops_out="$(python3 -B "$ROOT/tests/score_hops.py" "$ROOT/evals/hops" 2>&1)"
set -e
if grep -qE 'PASS +fail-oneshot-feature' <<<"$hops_out" && grep -qE 'PASS +fail-implemented-without-evidence' <<<"$hops_out"; then ok=1; fi
t T2 "$ok" "the hop scorer actually catches a one-shot build and an IMPLEMENTED claim with no evidence"

ok=0
grep -q 'tests/barbar.sh' "$WF" && grep -q 'tests/i17_dune.sh' "$WF" && ! grep -q 'continue-on-error' "$WF" && grep -q 'pull_request' "$WF" && ok=1
t T3 "$ok" "CI runs farm + I17 on PRs, no continue-on-error (presence check: guards against the job being deleted)"

# The farm must exit non-zero when it is not n/n. Point it at a product whose D# is red: the gate fails,
# so the farm cannot be n/n, so it must exit non-zero. A grep for the string "exit 1" proved nothing.
ok=0
set +e
BARBAR_ROOT="$ROOT/evals/fixtures/dsharp-red-product" bash "$BARBAR" gate >/dev/null 2>&1
gate_rc=$?
set -e
[[ "$gate_rc" -ne 0 ]] && ok=1
t T4 "$ok" "the farm's gate exits non-zero on a product that is not n/n"

# The merge gate is the whole point of the bar: it must say ALLOWED for a READY product and REFUSED for a
# dirty one. These fixtures existed and were never scored.
ok=1
set +e
out_ready="$(BARBAR_ROOT="$ROOT/evals/fixtures/ready-product" bash "$BARBAR" gate 2>&1)"; rc_ready=$?
out_dirty="$(BARBAR_ROOT="$ROOT/evals/fixtures/dirty-product" bash "$BARBAR" gate 2>&1)"; rc_dirty=$?
set -e
{ [[ "$rc_ready" -eq 0 ]] && grep -q ALLOWED <<<"$out_ready"; } || { ok=0; echo "      a READY product was not ALLOWED: $(head -1 <<<"$out_ready")"; }
{ [[ "$rc_dirty" -ne 0 ]] && grep -q REFUSED <<<"$out_dirty"; } || { ok=0; echo "      a DIRTY product was not REFUSED: $(head -1 <<<"$out_dirty")"; }
t T5 "$ok" "the merge gate ALLOWS a READY product and REFUSES a dirty one, scored not asserted"

ok=0
grep -qE 'PASS +fail-implemented-without-evidence' <<<"$hops_out" && grep -qE 'PASS +pass-implemented-with-evidence' <<<"$hops_out" && ok=1
t T6 "$ok" "IMPLEMENTED without evidence is scored as a failure, and with evidence as a pass"

ok=0
grep -qE 'PASS +fail-generate-executed' <<<"$hops_out" && grep -qE 'PASS +fail-started-nplus1' <<<"$hops_out" && ok=1
t T7 "$ok" "a GENERATE hop that executed, and a hop that started N+1, are both scored as failures"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: I17 T1–T7 evidenced"
