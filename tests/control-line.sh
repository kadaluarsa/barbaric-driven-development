#!/usr/bin/env bash
# Pack eval for I15 + I16 + I17. Fails if /loop and /barbar are mixed or dropped.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRE="$ROOT/docs/cascade/product-e2e-gre-pipeline.md"
CAS="$ROOT/docs/cascade/product-e2e-cascade.md"
CL="$ROOT/CONTROL-LINE.md"
fail=0
need() {
  local file="$1" pat="$2" msg="$3"
  if ! grep -qE "$pat" "$file"; then
    echo "FAIL: $msg"
    fail=1
  fi
}
need "$GRE" 'I15 Control line' 'I15 missing from GRE conductor'
need "$GRE" 'I16 Two loops' 'I16 missing from GRE conductor'
need "$GRE" 'a conductor eval FAILS if GENERATE starts EXECUTE or stage N\+1' 'GENERATE→EXECUTE/N+1 is not an eval failure'
need "$GRE" '/loop` is illegal on 01–04' '/loop scope not illegal on 01–04'
need "$GRE" 'Auto-merge is illegal until CLEAN 10 \+ 11 READY' 'auto-merge gate missing'
need "$GRE" 'Do not execute' 'GENERATE hop does not say Do not execute'
need "$GRE" 'Never start stage N\+1 until execute N is accepted' 'N+1 gate missing'
need "$GRE" '/barbar` is the verify/CI eval farm' '/barbar not bound as her eval farm'
need "$GRE" '/barbar merge` is legal only after that bar' '/barbar merge not gated'
need "$CAS" 'Rule \(I15\)' 'I15 rule missing from spec pack'
need "$CAS" 'Rule \(I16\)' 'I16 rule missing from spec pack'
need "$CAS" 'conductor eval fails if it does' 'spec pack does not fail GENERATE that executes'
need "$CL" '/loop` \(ours, GRE\)' 'CONTROL-LINE missing /loop as ours'
need "$CL" '/barbar` \(hers, enhanced\)' 'CONTROL-LINE missing /barbar as hers'
need "$CL" '/barbar merge' '/barbar merge missing from CONTROL-LINE'
need "$GRE" 'I17 Dune bar' 'I17 missing from GRE conductor'
need "$CAS" 'Rule \(I17\)' 'I17 rule missing from spec pack'
need "$CL" 'T1–T7|T1' 'CONTROL-LINE missing T1–T7 Dune bar'
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: control line still encoded (I15 + I16 + I17 /loop vs /barbar)."
