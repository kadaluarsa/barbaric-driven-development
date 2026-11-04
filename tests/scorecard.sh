#!/usr/bin/env bash
# The delivery scorecard (t91): one card per slice, computed from the tree, the same bytes whoever runs it.
#   bash tests/scorecard.sh [slug] [--full]     --full also runs the regression suite (minutes)
# Exit 0 SCORECARD pass, 1 fail, 2 incomplete (a required field could not be proven). Its red twins live in
# tests/ac/t91_scorecard_routing.sh. Print it in every EXECUTE hop report; run --full before /barbar merge.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/scorecard.py" "$ROOT" "$@"
