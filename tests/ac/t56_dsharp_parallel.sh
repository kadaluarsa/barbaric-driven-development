#!/usr/bin/env bash
# AC tests for 05b t56-dsharp-parallel. dsharp_strength.sh gains an opt-in DSHARP_JOBS=N pool.
# AC2 is the RED TWIN: a parallel run MUST produce the identical report and k/n as a sequential one, and
# DSHARP_MUTANT=drop (a broken parallel collector) MUST make that equality fail — proving the check has teeth.
# Fixture laws are plain shell (true/false/sleep), never gradle: this proves the mechanism, not a toolchain (AC5).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
fail=0
t() { if [[ "$2" -eq 1 ]]; then echo "PASS  $1  $3"; else echo "FAIL  $1  $3"; fail=1; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
D="tests/dsharp_strength.sh"

# A mixed fixture: three GREEN (check passes, break fails), one RED (check fails). Declared order matters.
MIX="$TMP/mixed.md"
cat > "$MIX" <<'EOF'
### D101 — law A stays green
check:  sleep 0.2; true
break:  sleep 0.2; false
### D102 — law B stays green
check:  sleep 0.2; true
break:  sleep 0.2; false
### D103 — law C stays green
check:  sleep 0.2; true
break:  sleep 0.2; false
### D104 — a broken law is red
check:  false
break:  false
EOF

# An all-green fixture, for the exit-code checks.
GREENS="$TMP/greens.md"
cat > "$GREENS" <<'EOF'
### D201 — green one
check:  true
break:  false
### D202 — green two
check:  true
break:  false
EOF

run() {  # run() <env-file> [extra VAR=val ...] -> prints dsharp output; returns dsharp's exit code
  local env="$1"; shift
  env CASCADE_ENVELOPE="$env" "$@" bash "$D" --root "$ROOT" 2>/dev/null
}

base="$(run "$MIX" DSHARP_JOBS=1)"
par="$(run "$MIX" DSHARP_JOBS=4)"

# AC1 — the sequential baseline is what we expect (3 green, 1 red, in declared order).
ok=1
[[ "$(printf '%s\n' "$base" | tail -1)" == "DSHARP 3/4" ]] || ok=0
[[ "$(printf '%s\n' "$base" | sed -n '1p')" == GREEN*D101* ]] || ok=0
[[ "$(printf '%s\n' "$base" | sed -n '4p')" == RED*D104* ]] || ok=0
t AC1 "$ok" "sequential (JOBS=1) report is 3/4 in declared order"

# AC2 + AC3 — parallel output is byte-identical to sequential (same lines, same order, same k/n).
ok=1; [[ "$base" == "$par" ]] || ok=0
t AC2 "$ok" "DSHARP_JOBS=4 output identical to JOBS=1 (verdicts, order and k/n)"

# AC2 red twin — a broken parallel collector (drops a verdict) MUST make that equality fail.
twin="$(run "$MIX" DSHARP_MUTANT=drop DSHARP_JOBS=4)"
ok=1; [[ "$base" != "$twin" ]] || ok=0
t AC2 "$ok" "RED TWIN: DSHARP_MUTANT=drop breaks the equality (the check can fail)"

# AC4 — forcing some laws serial does not change any verdict.
ser="$(run "$MIX" DSHARP_SERIAL="D102 D104" DSHARP_JOBS=4)"
ok=1; [[ "$ser" == "$base" ]] || ok=0
t AC4 "$ok" "DSHARP_SERIAL laws produce the identical report"

# AC6 — exit code is preserved across JOBS: non-zero on a red set, zero on an all-green set.
run "$MIX" DSHARP_JOBS=1 >/dev/null 2>&1; r1=$?
run "$MIX" DSHARP_JOBS=4 >/dev/null 2>&1; r4=$?
ok=1; [[ "$r1" -eq "$r4" && "$r1" -ne 0 ]] || ok=0
t AC6 "$ok" "exit code non-zero and equal across JOBS on a red set (was $r1 vs $r4)"

run "$GREENS" DSHARP_JOBS=1 >/dev/null 2>&1; g1=$?
run "$GREENS" DSHARP_JOBS=4 >/dev/null 2>&1; g4=$?
gout="$(run "$GREENS" DSHARP_JOBS=4)"
ok=1; [[ "$g1" -eq 0 && "$g4" -eq 0 ]] || ok=0
[[ "$(printf '%s\n' "$gout" | tail -1)" == "DSHARP 2/2" ]] || ok=0
t AC6 "$ok" "exit code zero and equal across JOBS on an all-green set (2/2)"

echo
[[ "$fail" -eq 0 ]] && echo "t56 AC: all green" || echo "t56 AC: FAILURES above"
exit "$fail"
