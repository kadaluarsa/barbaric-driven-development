#!/usr/bin/env bash
# The divergence gate (t58). On GENERATE 05b of a brief tagged `[diverge]`, the spec is built on a design the
# human chose from N committed options — O1 the boring baseline — by filling the one empty <EDIT>CHOSEN:</EDIT>
# placeholder, a signed change. This scores completeness, distinctness a script can see, provenance and the
# pick; never which design is better. `DIVERGE k/n`, or `DIVERGE n/a` on any other hop or an untagged brief.
# Its red twins live in tests/ac/t58_divergence.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/cascade.sh
. "$ROOT/tests/lib/cascade.sh"
cd "$ROOT" || exit 1
python3 -B "$ROOT/tests/lib/diverge.py" "$ROOT" "$(cascade_hop)" "$(cascade_stage)" "$(cascade_slice)"
