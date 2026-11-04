#!/usr/bin/env bash
# The handover (t90): what any agent on any host needs at session start, in one command.
#   bash tests/handover.sh [--as <host>/<model>]
# --as records who you are (a `claimed` line in .cascade/builders — on a host without a Stop hook it is the only
# record). Then prints the hop, the recall index exactly as preserve.py injects it (t85), the oracle's state (t89),
# the builders of this hop, and the last decisions. Read-only otherwise; exit 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/tests/lib"
if [[ "${1:-}" == "--as" && -n "${2:-}" ]]; then
  host="${2%%/*}"; model="${2#*/}"; [[ "$model" == "$2" ]] && model=unknown
  python3 -B "$LIB/builders.py" "$ROOT" --record "$host" "$model" handover claimed 2>/dev/null || true
fi
HS="$ROOT/docs/cascade/hop-state.md"; [[ -f "$HS" ]] || HS="$ROOT/docs/cascade/envelope.md"
grep -E '^(CURRENT_HOP|CURRENT_STAGE|CURRENT_SLICE|AUTOPILOT):' "$HS" 2>/dev/null
hop="$(grep -m1 '^CURRENT_HOP:' "$HS" 2>/dev/null | sed 's/^CURRENT_HOP:[[:space:]]*//' | tr '[:lower:]' '[:upper:]')"
echo
idx="$(python3 -B "$LIB/recall.py" "$ROOT" 2>/dev/null)" || idx=""
if [[ -n "$idx" ]]; then
  echo "Recall index — pointers, not content; open what this hop needs (durable truth is these files):"
  printf '%s\n' "$idx" | sed 's/^/  /'
else
  echo "(no recall index: no hop running)"
fi
echo
if [[ ! -f "$ROOT/tests/oracle.sh" ]]; then
  echo "oracle: n/a"
elif [[ "$hop" == EXECUTE ]]; then
  out="$(bash "$ROOT/tests/oracle.sh" --loop 2>&1)" && echo "oracle: ok" || { echo "oracle: FAIL"; printf '%s\n' "$out" | sed 's/^/  /'; }
elif [[ "$hop" == GENERATE ]]; then
  out="$(bash "$ROOT/tests/oracle.sh" 2>&1)" && echo "oracle: ok ($(printf '%s\n' "$out" | tail -1))" \
    || { echo "oracle: FAIL"; printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/  /'; }
else
  echo "oracle: n/a"
fi
b="$(python3 -B "$LIB/builders.py" "$ROOT" --builders 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
echo "builders: ${b:-none recorded for this hop}"
if [[ -f "$ROOT/.cascade/decisions.log" ]]; then
  echo; echo "Last decisions (.cascade/decisions.log):"; tail -5 "$ROOT/.cascade/decisions.log" | sed 's/^/  /'
fi
exit 0
