#!/usr/bin/env bash
# /barbar — her eval farm (I16). Hill-climb control-line evals. No product stages.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cmd="${1:-run}"

merge_refuse() {
  local audit="$ROOT/docs/cascade/10-audit.md"
  local prr="$ROOT/docs/cascade/11-prr.md"
  local clean=0 ready=0
  if [[ -f "$audit" ]] && grep -qE 'Audit verdict:\s*CLEAN' "$audit"; then
    clean=1
  fi
  if [[ -f "$prr" ]] && grep -qE 'Verdict:\s*READY( WITH WAIVERS)?' "$prr"; then
    ready=1
  fi
  if [[ "$clean" -eq 1 && "$ready" -eq 1 ]]; then
    echo "BARBAR merge: CLEAN 10 + 11 READY are present."
    echo "REFUSED: this pack repo has no in-force product D# required checks to merge against."
    return 2
  fi
  echo "BARBAR merge REFUSED: need CLEAN stage 10 AND stage 11 READY. Human stays on the hop edge."
  return 2
}

if [[ "$cmd" == merge ]]; then
  merge_refuse
  exit $?
fi

if [[ "$cmd" != run ]]; then
  echo "usage: tests/barbar.sh [run|merge]" >&2
  exit 64
fi

k=0
n=0
pass() { k=$((k + 1)); n=$((n + 1)); echo "PASS  $1"; }
fail() { n=$((n + 1)); echo "FAIL  $1"; }

if bash "$ROOT/tests/control-line.sh" >/tmp/barbar-pack.out 2>&1; then
  pass "pack-law"
else
  fail "pack-law"
  cat /tmp/barbar-pack.out
fi

while IFS= read -r line; do
  [[ "$line" =~ ^HOPS ]] && continue
  [[ -z "$line" ]] && continue
  name="$(echo "$line" | awk '{print $2}')"
  if [[ "$line" =~ ^[[:space:]]*PASS ]]; then
    pass "hop:$name"
  else
    fail "hop:$name"
    echo "       $line"
  fi
done < <(python3 "$ROOT/tests/score_hops.py" "$ROOT/evals/hops")

set +e
merge_out="$(bash "$ROOT/tests/barbar.sh" merge 2>&1)"
merge_rc=$?
set -e
if [[ "$merge_rc" -ne 0 ]] && echo "$merge_out" | grep -q 'REFUSED'; then
  pass "merge-refused-without-prr"
else
  fail "merge-refused-without-prr (rc=$merge_rc)"
  echo "$merge_out"
fi

echo
echo "BARBAR $k/$n"
if [[ "$k" -eq "$n" && "$n" -gt 0 ]]; then
  exit 0
fi
echo "not n/n — do not /barbar merge."
exit 1
