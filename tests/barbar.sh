#!/usr/bin/env bash
# /barbar — her eval farm (I16/I17). Hill-climb control-line evals. No product stages.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE_ROOT="${BARBAR_ROOT:-$ROOT}"
cmd="${1:-run}"

merge_gate() {
  local audit="$GATE_ROOT/docs/cascade/10-audit.md"
  local prr="$GATE_ROOT/docs/cascade/11-prr.md"
  local clean=0 ready=0
  if [[ -f "$audit" ]] && grep -qE 'Audit verdict:[[:space:]]*CLEAN|^CLEAN$' "$audit"; then
    clean=1
  fi
  if [[ -f "$prr" ]] && grep -qE 'Verdict:[[:space:]]*READY( WITH WAIVERS)?' "$prr"; then
    ready=1
  fi
  if [[ "$clean" -eq 1 && "$ready" -eq 1 ]]; then
    echo "BARBAR merge ALLOWED: CLEAN 10 + 11 READY. In-force D# (if any) must be green."
    return 0
  fi
  echo "BARBAR merge REFUSED: need CLEAN stage 10 AND stage 11 READY. Human stays on the hop edge."
  return 2
}

if [[ "$cmd" == merge ]]; then
  merge_gate
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

if bash "$ROOT/tests/i17_dune.sh" >/tmp/barbar-i17.out 2>&1; then
  pass "i17-dune-bar"
else
  fail "i17-dune-bar"
  cat /tmp/barbar-i17.out
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
merge_out="$(BARBAR_ROOT="$ROOT" bash "$ROOT/tests/barbar.sh" merge 2>&1)"
merge_rc=$?
set -e
if [[ "$merge_rc" -ne 0 ]] && echo "$merge_out" | grep -q 'REFUSED'; then
  pass "merge-refused-without-prr"
else
  fail "merge-refused-without-prr (rc=$merge_rc)"
  echo "$merge_out"
fi

set +e
allow_out="$(BARBAR_ROOT="$ROOT/evals/fixtures/ready-product" bash "$ROOT/tests/barbar.sh" merge 2>&1)"
allow_rc=$?
set -e
if [[ "$allow_rc" -eq 0 ]] && echo "$allow_out" | grep -q 'ALLOWED'; then
  pass "merge-allowed-when-ready"
else
  fail "merge-allowed-when-ready (rc=$allow_rc)"
  echo "$allow_out"
fi

set +e
dirty_out="$(BARBAR_ROOT="$ROOT/evals/fixtures/dirty-product" bash "$ROOT/tests/barbar.sh" merge 2>&1)"
dirty_rc=$?
set -e
if [[ "$dirty_rc" -ne 0 ]] && echo "$dirty_out" | grep -q 'REFUSED'; then
  pass "merge-refused-when-dirty"
else
  fail "merge-refused-when-dirty (rc=$dirty_rc)"
  echo "$dirty_out"
fi

echo
echo "BARBAR $k/$n"
if [[ "$k" -eq "$n" && "$n" -gt 0 ]]; then
  exit 0
fi
echo "not n/n — do not /barbar merge."
exit 1
