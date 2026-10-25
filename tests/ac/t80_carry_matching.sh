#!/usr/bin/env bash
# AC tests for 05b t80-carry-matching, Plan A (spec v2, Ask 0: the matcher was measured — 0 of dream-camera's 63 lines
# change across 100 goal versions — and not built). What ships: the README explains the codes every screen shows,
# and USAGE §B16 records why carried lines still match exactly.
#   AC8  README.md has "Reading the codes": the stages and 05b, a slice id, GENERATE, EXECUTE, D#, LOOP k/n,
#        REGRESS k/n, STITCH NEEDED, AUTOPILOT HALT, and a worked line; each defined term links to its source.
#   AC9  USAGE.md §B16 says matching is exact and records the measurement behind not building filter matching.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

# ---- AC8  README: Reading the codes -------------------------------------------------------------------------------
ok=1
sec="$(awk '/^## Reading the codes/{on=1; print; next} /^## /{on=0} on' "$ROOT/README.md")"
[[ -n "$sec" ]] || { ok=0; echo "  README.md has no '## Reading the codes' section"; }
for term in '05b' 't80' 'GENERATE' 'EXECUTE' 'D#' 'LOOP k/n' 'REGRESS k/n' 'STITCH NEEDED' 'AUTOPILOT HALT' '00' '11'; do
  grep -qF -- "$term" <<<"$sec" || { ok=0; echo "  'Reading the codes' does not explain $term"; }
done
grep -qE 'GENERATE 05b t[0-9]+-[a-z-]+[`* ]+(means|=)' <<<"$sec" || { ok=0; echo "  no worked example line ('GENERATE 05b t80-… means …')"; }
for link in docs/cascade/product-e2e-cascade.md docs/cascade/hop-state.md CONTROL-LINE.md; do
  grep -qF "($link" <<<"$sec" || { ok=0; echo "  'Reading the codes' does not link $link"; }
done
t AC8 "$ok" "README.md explains the stages and 05b, a slice id, GENERATE/EXECUTE, D#, LOOP k/n, REGRESS k/n, STITCH NEEDED and AUTOPILOT HALT, with a worked line and links to their sources"

# ---- AC9  USAGE: matching is exact, and why ---------------------------------------------------------------------
ok=1
b16="$(awk '/^### B16\./{on=1; print; next} /^### B1[7-9]\./{on=0} on' "$ROOT/USAGE.md")"
grep -q 'exact' <<<"$b16" && grep -q '0 of 63' <<<"$b16" && grep -q 't80' <<<"$b16" \
  || { ok=0; echo "  USAGE §B16 does not say matching is exact and record t80's measurement (0 of 63)"; }
t AC9 "$ok" "USAGE §B16 says carried lines match exactly and records why filter matching was not built (t80: 0 of 63 lines)"

echo
[[ "$fail" -eq 0 ]] && echo "T80 AC all PASS" || echo "T80 AC FAILED"
exit "$fail"
