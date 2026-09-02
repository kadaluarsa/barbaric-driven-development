#!/usr/bin/env bash
# /barbar — her eval farm (I16/I17). Hill-climb control-line evals. No product stages.
#
# Fails closed:
#   * a scorer that dies is a FAIL, not zero hops (AUDIT §1)
#   * hop count must reach the number of fixtures on disk
#   * `merge` runs the farm first and refuses on k<n (AUDIT §3)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_ROOT="${BARBAR_ROOT:-$ROOT}"
cmd="${1:-run}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

k=0; n=0
pass() { k=$((k + 1)); n=$((n + 1)); echo "PASS  $1"; }
fail() { n=$((n + 1)); echo "FAIL  $1"; }

merge_gate() {
  local audit="$GATE_ROOT/docs/cascade/10-audit.md"
  local prr="$GATE_ROOT/docs/cascade/11-prr.md"
  local clean=0 ready=0 dsharp_red=0
  [[ -f "$audit" ]] && grep -qE 'Audit verdict:[[:space:]]*CLEAN|^CLEAN$' "$audit" && clean=1
  [[ -f "$prr" ]]   && grep -qE 'Verdict:[[:space:]]*READY( WITH WAIVERS)?' "$prr" && ready=1

  # In-force D# must be green (I13). Read from the gated tree's envelope.
  local env_file="$GATE_ROOT/docs/cascade/envelope.md"
  if [[ -f "$env_file" ]]; then
    while IFS='|' read -r id _law val; do
      val="$(echo "${val:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [[ -z "$val" || "$val" == "TODO" || "$val" == "none" ]] && continue
      if ! ( cd "$GATE_ROOT" && eval "$val" ) >/dev/null 2>&1; then
        echo "  D# RED: $(echo "$id" | tr -d '[:space:]') — $val"
        dsharp_red=1
      fi
    done < <(grep -E '^D[0-9]+[[:space:]]*\|' "$env_file" || true)
  fi

  if [[ "$clean" -eq 1 && "$ready" -eq 1 && "$dsharp_red" -eq 0 ]]; then
    echo "BARBAR merge ALLOWED: CLEAN 10 + 11 READY + in-force D# green."
    return 0
  fi
  echo "BARBAR merge REFUSED: need CLEAN stage 10 (=$clean) AND stage 11 READY (=$ready) AND in-force D# green (red=$dsharp_red). Human stays on the hop edge."
  return 2
}

run_farm() {
  if bash "$ROOT/tests/control-line.sh" >"$TMP/pack.out" 2>&1; then pass "pack-law"; else fail "pack-law"; cat "$TMP/pack.out"; fi
  if bash "$ROOT/tests/i17_dune.sh"   >"$TMP/i17.out"  2>&1; then pass "i17-dune-bar"; else fail "i17-dune-bar"; cat "$TMP/i17.out"; fi
  if [[ -f "$ROOT/tests/enforcement.sh" ]]; then
    if bash "$ROOT/tests/enforcement.sh" >"$TMP/enf.out" 2>&1; then pass "i18-enforcement"; else fail "i18-enforcement"; cat "$TMP/enf.out"; fi
  fi

  # Hop scorer: capture rc, never let a dead scorer read as zero hops.
  set +e
  python3 "$ROOT/tests/score_hops.py" "$ROOT/evals/hops" >"$TMP/hops.out" 2>"$TMP/hops.err"
  local rc=$?
  set -e
  local expected scored=0
  expected="$(find "$ROOT/evals/hops" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  while IFS= read -r line; do
    [[ "$line" =~ ^HOPS ]] && continue
    [[ -z "$line" ]] && continue
    scored=$((scored + 1))
    name="$(echo "$line" | awk '{print $2}')"
    if [[ "$line" =~ ^[[:space:]]*PASS ]]; then pass "hop:$name"; else fail "hop:$name"; echo "       $line"; fi
  done < "$TMP/hops.out"
  if [[ "$rc" -ne 0 && "$scored" -eq 0 ]]; then
    fail "hop-scorer (exit $rc, scored 0 of $expected fixtures)"; sed 's/^/       /' "$TMP/hops.err"
  elif [[ "$scored" -lt "$expected" ]]; then
    fail "hop-scorer (scored $scored of $expected fixtures)"
  else
    pass "hop-scorer ($scored/$expected fixtures)"
  fi

  local out rc2
  set +e; out="$(BARBAR_ROOT="$ROOT" bash "$ROOT/tests/barbar.sh" gate 2>&1)"; rc2=$?; set -e
  if [[ "$rc2" -ne 0 ]] && echo "$out" | grep -q REFUSED; then pass "merge-refused-without-prr"; else fail "merge-refused-without-prr (rc=$rc2)"; echo "$out"; fi

  set +e; out="$(BARBAR_ROOT="$ROOT/evals/fixtures/ready-product" bash "$ROOT/tests/barbar.sh" gate 2>&1)"; rc2=$?; set -e
  if [[ "$rc2" -eq 0 ]] && echo "$out" | grep -q ALLOWED; then pass "merge-allowed-when-ready"; else fail "merge-allowed-when-ready (rc=$rc2)"; echo "$out"; fi

  set +e; out="$(BARBAR_ROOT="$ROOT/evals/fixtures/dirty-product" bash "$ROOT/tests/barbar.sh" gate 2>&1)"; rc2=$?; set -e
  if [[ "$rc2" -ne 0 ]] && echo "$out" | grep -q REFUSED; then pass "merge-refused-when-dirty"; else fail "merge-refused-when-dirty (rc=$rc2)"; echo "$out"; fi

  set +e; out="$(BARBAR_ROOT="$ROOT/evals/fixtures/dsharp-red-product" bash "$ROOT/tests/barbar.sh" gate 2>&1)"; rc2=$?; set -e
  if [[ "$rc2" -ne 0 ]] && echo "$out" | grep -q 'D# RED'; then pass "merge-refused-when-dsharp-red"; else fail "merge-refused-when-dsharp-red (rc=$rc2)"; echo "$out"; fi

  echo
  echo "BARBAR $k/$n"
  if [[ "$k" -eq "$n" && "$n" -gt 0 ]]; then return 0; fi
  echo "not n/n — do not /barbar merge."
  return 1
}

case "$cmd" in
  run)  run_farm || exit 1; exit 0 ;;
  gate) merge_gate; exit $? ;;          # gate only — used by the farm's own fixtures
  merge)
    if ! run_farm >"$TMP/farm.out" 2>&1; then
      tail -3 "$TMP/farm.out"
      echo "BARBAR merge REFUSED: farm is not n/n. Fix the farm; do not write product code to fix it."
      exit 2
    fi
    tail -1 "$TMP/farm.out"
    merge_gate; exit $? ;;
  *) echo "usage: tests/barbar.sh [run|merge|gate]" >&2; exit 64 ;;
esac
