#!/usr/bin/env bash
# The spec-critic gate (t57). On a GENERATE 05b hop, the spec+plan reach the human only with a critique
# beside them: a fresh subagent's findings, committed verbatim, every one answered by the author. This
# scores the shape and the answers — never whether the critic was right (the critic only advises).
# Prints `CRITIQUE k/n`, or `CRITIQUE n/a` on any other hop. Its red twins live in tests/ac/t57_spec_critic.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/cascade.sh
. "$ROOT/tests/lib/cascade.sh"
cd "$ROOT" || exit 1
python3 -B "$ROOT/tests/lib/critique.py" "$ROOT" "$(cascade_hop)" "$(cascade_stage)" "$(cascade_slice)"
