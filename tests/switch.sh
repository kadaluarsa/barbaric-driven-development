#!/usr/bin/env bash
# The switch gate (t90). When more than one builder (host/model) worked an EXECUTE hop of 05b or 06–09, the accept
# edge and autopilot's edge wait for docs/cascade/<stage>-<slug>-switch-review.md: a fresh reviewer's rows over the diff
# since the switch, every row answered, committed after the LAST switch and with no product commit after it.
# Prints `SWITCH none (…)`, `SWITCH ok (a → b)`, `SWITCH n/a`, or FAIL lines and `SWITCH red` (exit 1).
# Its red twins live in tests/ac/t90_provenance_switch_audit.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/builders.py" "$ROOT" --gate
