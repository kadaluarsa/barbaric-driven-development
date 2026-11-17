#!/usr/bin/env bash
# The briefs archive (t102). Closed briefs move, verbatim, from docs/cascade/05b-briefs.md to
# docs/cascade/05b-briefs-archive.md. A brief is closed when its spec exists and its slice is neither CURRENT_SLICE
# nor an AUTOPILOT entry (or it says `Absorbed by <slug>` and that slug has a spec). USAGE.md §B21.
#
# usage: tests/briefs.sh archive        move every closed brief; refuses (exit 1, no change) on uncommitted brief
#                                       files or a slug in both files. `tests/goal.sh reset` runs it.
#        tests/briefs.sh find <slug>    print <path>:<line> — the live file first, then the archive; exit 1 if none
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/lib/briefs.py" "$ROOT" "$@"
